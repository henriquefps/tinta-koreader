-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (C) 2026 Tinta contributors
-- 10.3 / 11.x: the battery log independent of the screen. The `ev` column (sleep / scheduled wake / button wake),
-- backwards-compatible parsing, forced marked samples without duplicates, suspend stretches that must not look like
-- awake drain in the estimate, and the manifest's background hook through the real core.
local T = ...
local check, eq = T.check, T.eq
local B = require("apps/bateria/logic")
local Log = require("apps/bateria/csvlog")
local C = require("ui/core")
local M = require("apps/bateria/init")
local A = M._A

local function S(t, pct, ev) return { t = t, pct = pct, chg = false, wifi = false, ev = ev } end

---------------------------------------------------------------- the ev column

eq("ev: header appends the column, order kept", B.HEADER, "# unix_time,percent,charging,wifi,mv,ma,mah,temp_c,ev")
eq("ev: format", B.format_line(1000, 80, false, true, { mv = 3800, ma = -40, mah = 700, temp = 25 }, B.EV.sleep),
    "1000,80,0,1,3800,-40,700,25,1")
eq("ev: format without gauge readings keeps the columns", B.format_line(1000, 80, false, false, nil, B.EV.button), "1000,80,0,0,,,,,3")
eq("ev: normal lines stay at 8 columns", B.format_line(1000, 80, false, true, { mv = 1, ma = 2, mah = 3, temp = 4 }),
    "1000,80,0,1,1,2,3,4")
eq("ev: parse", B.parse_line("1000,80,0,1,3800,-40,700,25,2").ev, B.EV.sched)
eq("ev: parse of a line without it", B.parse_line("1000,80,0,1,3800,-40,700,25").ev, nil)
eq("ev: parse of the old 4-column line", B.parse_line("1000,80,0,1").ev, nil)
eq("ev: marked row with empty gauge", B.parse_line("1000,80,0,0,,,,,3").ev, 3)
eq("ev: damaged tail", B.parse_line("1000,80,0,1,3800,-40,700,25,x"), nil)
eq("ev: parse keeps the gauge columns", B.parse_line("1000,80,0,1,3800,-40,700,25,1").mah, 700)

---------------------------------------------------------------- stretches

-- awake 1 % / 6 min for 36 min; sleep entry; 4 h asleep with wake-ups every 15 min (1 % per hour);
-- button wake; awake again
local function night()
    local out = {}
    for i = 0, 6 do out[#out + 1] = S(i * 360, 90 - i) end                    -- 90..84 % awake
    local t, pct = 6 * 360 + 30, 84
    out[#out + 1] = S(t, pct, B.EV.sleep)
    for k = 1, 16 do
        t = t + 900
        if k % 4 == 0 then pct = pct - 1 end
        out[#out + 1] = S(t, pct, B.EV.sched)                                 -- 15 min apart: < GAP_MAX
    end
    t = t + 900
    out[#out + 1] = S(t, pct, B.EV.button)
    for i = 1, 6 do out[#out + 1] = S(t + i * 360, pct - i) end
    return out, t, pct
end
local n, t_btn, pct_btn = night()
local segs = B.segments(n)
check("segments: the sleep row ends the awake stretch", #segs[1] == 8 and segs[1][#segs[1]].ev == B.EV.sleep, #segs[1])
eq("segments: each wake row is alone (suspend holes are not joined)", #segs[2], 1)
check("segments: the stretch after the button wake starts at the button row",
    segs[#segs][1].ev == B.EV.button and #segs[#segs] == 7, #segs[#segs])
local plain = {}
for _, s in ipairs(n) do plain[#plain + 1] = S(s.t, s.pct) end
eq("segments: the same rows unmarked would be ONE stretch (GAP_MAX does not catch 15 min wake-ups)", #B.segments(plain), 1)

-- the estimate right after the button wake: the awake stretches decide (6 min per %), not the 1 %/h suspend drain
local now = t_btn + 7 * 360
local secs, kind = B.estimate(n, now, pct_btn - 6, false)
check("estimate: from the awake rate (~6 min per %), not the suspend rate", secs and math.abs(secs - (pct_btn - 6) * 360) < 120, secs)
eq("estimate: live (the stretch after the wake has enough data)", kind, "live")
local pslope = B.estimate(plain, now, pct_btn - 6, false)
check("estimate: unmarked rows would have blended the suspend drain in", pslope == nil or math.abs(pslope - (pct_btn - 6) * 360) > 120, pslope)

-- right after the wake (one row after the suspend) the estimate uses the earlier awake stretch, never the suspend rows
local only_wake = {}
for i = 1, #n - 6 do only_wake[#only_wake + 1] = n[i] end
local secs2, kind2 = B.estimate(only_wake, t_btn + 5, pct_btn, false)
check("estimate: right after the wake it uses the saved awake stretch", secs2 and kind2 == "saved"
    and math.abs(secs2 - pct_btn * 360) < 300, tostring(secs2) .. " " .. tostring(kind2))
eq("estimate: a stretch ending at a suspend marker is only 'saved', never live", select(2, B.estimate({ S(0, 90), S(900, 89),
    S(1800, 88), S(2400, 87, B.EV.sleep) }, 2500, 87, false)), "saved")
eq("mean_current: not from a stretch that ended in a suspend", B.mean_current({ { t = 0, pct = 9, chg = false, ma = -40 },
    { t = 100, pct = 9, chg = false, ma = -40, ev = B.EV.sleep } }, 200, false), nil)

---------------------------------------------------------------- the store: forced marked samples

local path = T.tmp()
local st = Log.open(path)
local r = { pct = 80, charging = false, wifi = true, mv = 3800, ma = -40, mah = 700, temp = 25 }
check("store: first normal sample", st:sample(1000, r) ~= nil)
eq("store: same reading a minute later is not logged", st:sample(1060, r), nil)
check("store: a marked sample is written even when nothing changed", st:sample(1070, r, B.EV.sleep) ~= nil)
eq("store: the same marker twice in the same second is one sample", st:sample(1070, r, B.EV.sleep), nil)
check("store: another marker in the same second is its own sample", st:sample(1070, r, B.EV.sched) ~= nil)
eq("store: a normal reading right after a marked one still obeys should_log", st:sample(1075, r), nil)
local lines = T.lines(path)
eq("store: file has header + 3 lines", #lines, 4)
eq("store: marked line format", lines[3], "1070,80,0,1,3800,-40,700,25,1")
eq("store: normal line stays 8 columns", lines[2], "1000,80,0,1,3800,-40,700,25")
local again = Log.open(path)
eq("store: reopened keeps the markers", again.samples[2].ev .. "," .. again.samples[3].ev, "1,2")
os.remove(path)

-- an existing log with the old header is rewritten once, lines untouched
local oldp = T.tmp()
local fh = io.open(oldp, "w")
fh:write("# unix_time,percent,charging,wifi,mv,ma,mah,temp_c\n1000,90,0,1,4000,-48,816,25\n")
fh:close()
local o = Log.open(oldp)
eq("old header: sample kept", #o.samples, 1)
eq("old header: header migrated", T.lines(oldp)[1], B.HEADER)
eq("old header: line kept", T.lines(oldp)[2], "1000,90,0,1,4000,-48,816,25")
os.remove(oldp)

---------------------------------------------------------------- the manifest hook through core

eq("manifest: background is a function", type(M.background), "function")
check("manifest: still valid", (require("core/registry").validate(M)))
check("registry: a non-function background is refused", not (require("core/registry").validate({ id = "x", name = "X",
    sizes = { "1x1" }, widget = function() end, background = "no" })))

local dir = T.tmp()
os.execute('mkdir -p "' .. dir .. '"')
A.data_dir = function() return dir end
A.store, A.last = nil, nil
local gauge = { pct = 70, charging = false, mv = 3700, ma = -45, mah = 600, full_mah = 907, temp = 24 }
A.read = function() local x = {}; for k, v in pairs(gauge) do x[k] = v end; return x end
local clock = 5000
local c = C.open{ db_path = dir .. "/none/tinta.sqlite3", now = function() return clock end, log = function() end }
C.register(c, M)
C.register(c, { id = "plain", name = "Plain", sizes = { "1x1" }, widget = function() end })
C.register(c, { id = "thrower", name = "Thrower", sizes = { "1x1" }, widget = function() end,
    background = function() error("boom") end })
eq("core: ids of apps with a background hook", table.concat(C.background_ids(c), ","), "bateria,thrower")
local file = dir .. "/" .. Log.FILE
local ids = C.background_ids(c)
C.background(c, ids, clock, nil)
eq("hook: first call writes a sample (a throwing app does not stop it)", #T.lines(file), 2)
C.background(c, ids, clock + 60, nil)
eq("hook: a minute later, nothing changed: no line", #T.lines(file), 2)
gauge.pct = 69
C.background(c, ids, clock + 120, nil)
eq("hook: percentage changed: a line", #T.lines(file), 3)
A.last = nil
clock = clock + 125
local results = {}
C.refresh(c, "bateria", function(ok) results[#results + 1] = ok end, true)
eq("refresh after the hook in the same minute: no duplicate", #T.lines(file), 3)
C.background(c, ids, clock, "sleep")
C.background(c, ids, clock, "sleep")
eq("hook: the sleep marker takes the place of the unmarked row of the same moment (one row per wake)", #T.lines(file), 3)
eq("hook: marked line", T.lines(file)[3]:match(",1$"), ",1")
C.background(c, ids, clock + 3000, "button")
eq("hook: button marker", T.lines(file)[4]:match(",3$"), ",3")
gauge.charging = true
C.background(c, ids, clock + 3060, nil)
check("hook: charging change logged", T.lines(file)[5]:match("^%d+,69,1,") ~= nil, T.lines(file)[5])
A.read = function() return nil end
C.background(c, ids, clock + 4000, nil)
eq("hook: no gauge reading: nothing, no error", #T.lines(file), 5)
os.execute('rm -rf "' .. dir .. '"')
A.store, A.last = nil, nil
