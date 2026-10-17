-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (C) 2026 Tinta contributors
-- the real-pace estimate (sleep included), recorded-like logs: an overnight sleep/wake log, an awake log, a mixed
-- day, a charge in the middle, a gauge without mAh; the headline vs the awake estimate; days in the texts; one row
-- per wake-up in the store.
local T = ...
local check, eq, near = T.check, T.eq, T.near
local B = require("apps/bateria/logic")
local Log = require("apps/bateria/csvlog")
local L = T.L
local H = 3600

-- one row; mah/pct follow the charge (907 mAh full: 1 % = 9.07 mAh)
local function row(t, mah, ev, chg)
    return { t = t, pct = math.floor(mah / 9.07 + 0.5), chg = chg or false, wifi = false, mah = mah, ev = ev }
end

-- overnight like the one recorded on the KT3: a scheduled wake every 15 min, ev=2 on each row, ~6 mA on average
-- (1.5 mAh per 15 min), 801 mAh at 20:00
local function overnight(t0, mah0, hours, per_cycle)
    local out = {}
    for i = 0, hours * 4 do out[#out + 1] = row(t0 + i * 900, mah0 - i * per_cycle, B.EV.sched) end
    return out
end

-- awake: one row a minute at ~55 mA (0.9167 mAh/min), Wi-Fi on
local function awake(t0, mah0, minutes, rows)
    rows = rows or {}
    for i = 0, minutes do rows[#rows + 1] = row(t0 + i * 60, mah0 - i * 55 / 60) end
    return rows
end

---------------------------------------------------------------- overnight: a multi-day estimate

local on = overnight(0, 801, 6.75, 1.5)           -- 6 h 45 min, 801 -> 760.5 mAh (about what was measured)
local last = on[#on]
local now = last.t
local secs, basis, ma = B.estimate_mix(on, now, last.pct, { mah = last.mah })
eq("mix overnight: from the mAh counter", basis, "mah")
near("mix overnight: ~6 mA average", ma, 6, 0.5)
check("mix overnight: days, not hours", secs and secs > 4 * 86400 and secs < 7 * 86400, secs)
near("mix overnight: remaining / rate", secs, last.mah / (1.5 / 900), 60)
eq("mix overnight: the awake estimate has nothing to fit (every stretch ends at a suspend)",
    B.estimate(on, now, last.pct, false, { mah = last.mah }), nil)

-- the same night on % only (no mAh column): 93 -> 83 % in ~11 h
local pct_log = {}
for i = 0, 44 do   -- 11 h of 15-min rows
    pct_log[#pct_log + 1] = { t = i * 900, pct = 93 - math.floor(i * 10 / 44), chg = false, wifi = false, ev = B.EV.sched }
end
local pl = pct_log[#pct_log]
local psecs, pbasis, pma = B.estimate_mix(pct_log, pl.t, pl.pct, {})
eq("mix pct: basis", pbasis, "pct")
check("mix pct: ~3.7 days at 10 %% per 11 h", psecs and math.abs(psecs - 83 / (10 / 11) * H) < 3 * H, psecs)
near("mix pct: current from the % slope (~8 mA)", pma, 10 / 11 * 9.07, 0.6)
eq("mix pct: no gauge table at all behaves the same", select(2, B.estimate_mix(pct_log, pl.t, pl.pct, nil)), "pct")

---------------------------------------------------------------- awake: matches today's awake estimate

local aw = awake(0, 800, 240)                  -- 4 h awake
local al = aw[#aw]
local mix_a = B.estimate_mix(aw, al.t, al.pct, { mah = al.mah })
local awake_a = B.estimate(aw, al.t, al.pct, false, { mah = al.mah })
check("mix awake: both estimates exist", mix_a ~= nil and awake_a ~= nil)
check("mix awake: within 3 % of the awake estimate", math.abs(mix_a - awake_a) / awake_a < 0.03, tostring(mix_a) .. " vs " .. tostring(awake_a))

---------------------------------------------------------------- mixed day: awake bursts + sleep cycles

local mixed = awake(0, 800, 30)                                  -- 30 min of reading
local m = mixed[#mixed]
for i = 1, 40 do mixed[#mixed + 1] = row(m.t + i * 900, m.mah - i * 1.5, B.EV.sched) end   -- 10 h asleep
m = mixed[#mixed]
awake(m.t + 60, m.mah - 1, 30, mixed)                            -- 30 min more
local ml = mixed[#mixed]
local msecs = B.estimate_mix(mixed, ml.t, ml.pct, { mah = ml.mah })
local drop_per_s = (800 - ml.mah) / (ml.t - 0)
near("mix mixed: remaining / average over the whole span", msecs, ml.mah / drop_per_s, 120)
local awake_m = B.estimate(mixed, ml.t, ml.pct, false, { mah = ml.mah })
check("mix mixed: far longer than the awake estimate", awake_m and msecs > 3 * awake_m, tostring(msecs) .. " vs " .. tostring(awake_m))

---------------------------------------------------------------- charging in the middle resets the window

local ch = overnight(0, 700, 5, 1.5)                             -- 5 h of discharge from 700
local cl = ch[#ch]
for i = 1, 4 do ch[#ch + 1] = row(cl.t + i * 900, cl.mah + i * 10, nil, true) end   -- an hour on the charger
local base = ch[#ch].t
for i = 1, 8 do ch[#ch + 1] = row(base + i * 900, 800 - i * 3) end                   -- 2 h after unplugging: too short
local c8 = ch[#ch]
eq("mix charge: too little since the charger -> nil (falls back)", B.estimate_mix(ch, c8.t, c8.pct, { mah = c8.mah }), nil)
for i = 9, 20 do ch[#ch + 1] = row(base + i * 900, 800 - i * 3) end                  -- 5 h since the charger
local c20 = ch[#ch]
local csecs, _, cma = B.estimate_mix(ch, c20.t, c20.pct, { mah = c20.mah })
near("mix charge: only the discharge after the charger counts (12 mA)", cma, 12, 0.5)
near("mix charge: remaining / its rate", csecs, c20.mah / (3 / 900), 60)
eq("mix charge: charging now -> nil", B.estimate_mix({ row(0, 700, nil, true) }, 0, 70, {}), nil)
-- a rise of the charge without a charging row (recharged while the Tinta was closed) cuts the window as well
local jump = overnight(0, 500, 4, 1.5)
local jl = jump[#jump]
for i = 1, 16 do jump[#jump + 1] = row(jl.t + i * 900, 800 - i * 1.5) end
local jj = jump[#jump]
local jsecs = B.estimate_mix(jump, jj.t, jj.pct, { mah = jj.mah })
near("mix jump: window starts at the rise", jsecs, jj.mah / (1.5 / 900), 60)

---------------------------------------------------------------- limits and fallbacks

eq("mix: too short a span", B.estimate_mix(overnight(0, 800, 2, 1.5), 2 * H, 85, { mah = 797 }), nil)
eq("mix: too small a drop (mAh) and too small in % -> nil", B.estimate_mix(overnight(0, 800, 5, 0.1), 5 * H, 88, { mah = 798 }), nil)
eq("mix: no samples", B.estimate_mix({}, 0, 50, {}), nil)
eq("mix: nil samples", B.estimate_mix(nil, 0, 50, {}), nil)
eq("mix: empty battery", B.estimate_mix(on, now, 0, { mah = 0 }), nil)
eq("mix: clock went back", B.estimate_mix(on, now - 10 * H, last.pct, { mah = last.mah }), nil)
-- older than the window is ignored: 40 h of log, the last 24 h count
local long = overnight(0, 900, 40, 1.5)
local ll = long[#long]
local lsecs = B.estimate_mix(long, ll.t, ll.pct, { mah = ll.mah })
near("mix window: same pace either way", lsecs, ll.mah / (1.5 / 900), 60)
-- the mAh counter missing in the window: % path
local nomah = {}
for _, s in ipairs(on) do nomah[#nomah + 1] = { t = s.t, pct = s.pct, chg = false, wifi = false, ev = s.ev } end
eq("mix: rows without mAh use %", select(2, B.estimate_mix(nomah, now, last.pct, { mah = last.mah })), "pct")

---------------------------------------------------------------- cycle: the headline and the awake estimate

local store = Log.open(nil)
local out
for i = 0, 27 do   -- 7 h of 15-min wakes, marked, 1.5 mAh each
    local t = 1000000 + i * 900
    store:sample(t, { pct = math.floor((800 - i * 1.5) / 9.07 + 0.5), charging = false, wifi = false, mah = 800 - i * 1.5,
        mv = 3800, ma = -6, temp = 22 }, B.EV.sched)
end
local tnow = 1000000 + 27 * 900
local r = { pct = 84, charging = false, mah = 759.5, full_mah = 907, ma = -55, mv = 3800, temp = 22 }
local cache, _, events = B.cycle(store, r, tnow + 120, nil, L)
check("cycle: headline is the real pace", cache.eta_mix ~= nil and cache.eta == cache.eta_mix)
check("cycle: days", cache.eta > 4 * 86400, cache.eta)
eq("cycle: mix basis", cache.mix_basis, "mah")
near("cycle: average current is the real pace", cache.ma_mix, 6, 0.6)
local v = B.view(cache, tnow + 120, L, "pt")
check("view: headline in days", v.line:match("^~%d+ d restantes · %d+ mA em média$") ~= nil, v.line)
eq("view: short", v.short:match("^~%d+ d · %d+ mA$") ~= nil, true)
check("view: the real pace first", v.estimates[1] and v.estimates[1]:match("^no ritmo atual ~%d+ d$") ~= nil, tostring(v.estimates[1]))
eq("view: stat mean shows the same current", v.stats[1][1], B.view(cache, tnow + 120, L, "pt").stats[1][1])
check("view: stat mean is the pace, not the awake 55 mA", tonumber(v.stats[1][1]:match("%d+")) < 10, v.stats[1][1])
local ve = B.view(cache, tnow + 120, T.L, "en")
check("view: english labels exist", #ve.estimates >= 1)

-- both estimates when the awake stretch has data too: 40 awake minutes after the last wake
for i = 1, 40 do
    store:sample(tnow + 200 + i * 60, { pct = 84, charging = false, wifi = true, mah = 759 - i * 55 / 60, ma = -55 })
end
local t2 = tnow + 200 + 40 * 60
local c2 = B.cycle(store, { pct = 82, charging = false, mah = 759 - 40 * 55 / 60, full_mah = 907, ma = -55 }, t2, nil, L)
check("cycle: awake estimate present", c2.eta_awake ~= nil, tostring(c2.eta_awake))
check("cycle: awake in hours", c2.eta_awake and c2.eta_awake < 20 * H, c2.eta_awake)
check("cycle: headline stays the real pace", c2.eta_mix and c2.eta == c2.eta_mix)
local v2 = B.view(c2, t2, L, "pt")
eq("view: two labelled estimates", #v2.estimates, 2)
check("view: awake label", v2.estimates[2]:match("^acordado com Wi%-Fi ~%d+h%d*$") ~= nil, v2.estimates[2])
eq("view: charging has no labelled estimates", #B.view({ pct = 50, charging = true, eta = 3600, at = 0 }, 0, L, "pt").estimates, 0)

-- without a real pace (a fresh unplug) the awake estimate is the headline, labelled
local fresh = Log.open(nil)
for i = 0, 40 do fresh:sample(i * 60, { pct = 100 - math.floor(i / 10), charging = false, wifi = true, mah = 900 - i * 55 / 60 }) end
local cf = B.cycle(fresh, { pct = 96, charging = false, mah = 900 - 40 * 55 / 60, full_mah = 907 }, 40 * 60, nil, L)
eq("cycle fresh: no real pace yet", cf.eta_mix, nil)
check("cycle fresh: headline = awake", cf.eta ~= nil and cf.eta == cf.eta_awake)
local vf = B.view(cf, 40 * 60, L, "pt")
eq("view fresh: one labelled estimate", #vf.estimates, 1)
check("view fresh: it is the awake one", vf.estimates[1]:match("^acordado") ~= nil, vf.estimates[1])

---------------------------------------------------------------- texts: days

eq("eta text: no translator keeps hours", B.eta_text(3 * 86400), "~72h")
eq("eta text: 47 h stays in hours", B.eta_text(47 * H, L), "~47h")
eq("eta text: 2 days", B.eta_text(48 * H, L), "~2 d")
eq("eta text: 5 days pt", B.eta_text(5 * 86400 + 3 * H, L), "~5 d")
eq("eta text: rounds to the nearest day", B.eta_text(5.6 * 86400, L), "~6 d")
local Strings = require("apps/bateria/strings")
eq("eta text: en", B.eta_text(5 * 86400, function(k, ...) return string.format(Strings.en[k], ...) end), "~5 days")
eq("status: days", B.status_eta({ eta = 5 * 86400, charging = false, at = 1000 }, { pct = 80 }, 1000, L), "~5 d")
eq("status: hours when under 2 days", B.status_eta({ eta = 20 * H, charging = false, at = 1000 }, { pct = 80 }, 1000, L), "~20h")
eq("events: low body in days", B.events({ since = 1 }, { pct = 10, charging = false }, "~3 d", L)[1].body, "~3 d restantes")

---------------------------------------------------------------- the store: one row per wake-up

local path = T.tmp()
local st = Log.open(path)
local g = { pct = 80, charging = false, wifi = true, mv = 3800, ma = -40, mah = 700, temp = 25 }
-- scheduled wake: the refresh of the Bateria (unmarked) and then the hook (ev=2) in the same second
check("dup: refresh row written", st:sample(1000, g) ~= nil)
g.wifi = false
check("dup: the marked row replaces it", st:sample(1000, g, B.EV.sched) ~= nil)
eq("dup: one data row in the file", #T.lines(path), 2)
eq("dup: it is the marked one", T.lines(path)[2], "1000,80,0,0,3800,-40,700,25,2")
eq("dup: memory too", #st.samples, 1)
eq("dup: memory row is marked", st.samples[1].ev, 2)
eq("dup: nlines", st.nlines, 1)
-- a few seconds apart still counts as the same wake-up
st:sample(2000, g)
st:sample(2003, g, B.EV.sched)
eq("dup: a few seconds apart: still one row", #T.lines(path), 3)
-- the hook first, then an unmarked sample of the same moment (button wake, then a refresh): dropped
st:sample(3000, g, B.EV.button)
eq("dup: unmarked right after a marked row is dropped", st:sample(3001, { pct = 79, charging = false, mah = 690 }), nil)
eq("dup: file unchanged", #T.lines(path), 4)
-- far apart: separate rows (the 60 s background row, then a sleep entry half a minute later)
st:sample(4000, g)
st:sample(4030, g, B.EV.sleep)
eq("dup: 30 s apart are two rows", #T.lines(path), 6)
-- a different charging state is never merged
st:sample(5000, g)
st:sample(5000, { pct = 80, charging = true, mah = 700 }, B.EV.sleep)
eq("dup: charging state differs: two rows", #T.lines(path), 8)
-- the same marker twice is still one row; after a reopen the replaced row is intact
eq("dup: same marker twice", st:sample(5000, { pct = 80, charging = true, mah = 700 }, B.EV.sleep), nil)
local re = Log.open(path)
eq("dup: reopen keeps one per wake", #re.samples, 7)
eq("dup: reopen first row", re.samples[1].t .. "/" .. tostring(re.samples[1].ev), "1000/2")
-- a row from an old 4-column file cannot be swapped in place: appended (nothing is lost)
local oldp = T.tmp()
local fh = io.open(oldp, "w")
fh:write(B.HEADER, "\n", "1000,90,0,1\n")
fh:close()
local so = Log.open(oldp)
so:sample(1001, { pct = 90, charging = false, wifi = false }, B.EV.sched)
eq("dup: 4-column row: marked row still lands", T.lines(oldp)[#T.lines(oldp)], "1001,90,0,0,,,,,2")
eq("dup: memory has one", #so.samples, 1)
os.remove(oldp)
os.remove(path)
