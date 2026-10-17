-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (C) 2026 Tinta contributors
-- log lines, stretches, estimate (ported from the standalone plugin's tests ("battery log and estimate")),
-- plus D3 (mAh), R-L4 (same band), mean current, texts and the status bar estimate.
local T = ...
local check, eq, near = T.check, T.eq, T.near
local B = require("apps/bateria/logic")
local function S(t, pct, chg) return { t = t, pct = pct, chg = chg or false, wifi = false } end

---------------------------------------------------------------- ported

eq("bat: format", B.format_line(1000, 82, true, false), "1000,82,1,0")
eq("bat: format extra", B.format_line(1000, 82, false, true, { mv = 3812, ma = -97.4, mah = 376, temp = 28 }),
    "1000,82,0,1,3812,-97,376,28")
eq("bat: format partial extra", B.format_line(1000, 82, false, true, { mv = 3812 }), "1000,82,0,1,3812,,,")
eq("bat: format NaN is empty", B.format_line(1000, 82, false, true, { mv = 0 / 0 }), "1000,82,0,1,,,,")
local px = B.parse_line("1000,82,0,1,3812,-97,376,28")
check("bat: parse extra", px and px.mv == 3812 and px.ma == -97 and px.mah == 376 and px.temp == 28)
local pe = B.parse_line("1000,82,0,1,3812,,,")
check("bat: parse empty extra", pe and pe.mv == 3812 and pe.ma == nil and pe.mah == nil)
eq("bat: parse half extra", B.parse_line("1000,82,0,1,3812,5"), nil)
local p = B.parse_line("1000,82,1,0")
check("bat: parse", p and p.t == 1000 and p.pct == 82 and p.chg == true and p.wifi == false)
eq("bat: parse header", B.parse_line(B.HEADER), nil)
eq("bat: parse damaged", B.parse_line("1000,xx,1,0"), nil)
eq("bat: parse pct > 100", B.parse_line("1000,101,0,0"), nil)
eq("bat: parse blank", B.parse_line(""), nil)
eq("bat: roundtrip", B.format_line(B.parse_line("1792089988,78,0,1,3943,-59,718,22").t, 78, false, true,
    B.parse_line("1792089988,78,0,1,3943,-59,718,22")), "1792089988,78,0,1,3943,-59,718,22")

eq("bat: log first", B.should_log(nil, 1, 50, false), true)
eq("bat: log pct change", B.should_log(S(1000, 50), 1010, 49, false), true)
eq("bat: log charging change", B.should_log(S(1000, 50), 1010, 50, true), true)
eq("bat: no log when nothing changed", B.should_log(S(1000, 50), 1060, 50, false), false)
eq("bat: heartbeat", B.should_log(S(1000, 50), 1000 + B.HEARTBEAT, 50, false), true)
eq("bat: clock went back", B.should_log(S(1000, 50), 900, 50, false), true)

-- 1% every 6 min from 90%: 10 samples = 54 min
local function drain(t0, pct0, n, step, per)
    local out = {}
    for i = 0, n - 1 do out[#out + 1] = S(t0 + i * per, pct0 - i * step) end
    return out
end
local d = drain(0, 90, 10, 1, 360)
eq("bat: one segment", #B.segments(d), 1)
local gap = drain(0, 90, 5, 1, 360)
for _, x in ipairs(drain(10000, 80, 3, 1, 360)) do gap[#gap + 1] = x end
eq("bat: gap splits", #B.segments(gap), 2)
local mixed = { S(0, 50), S(60, 50), S(120, 51, true), S(180, 52, true) }
eq("bat: charging splits", #B.segments(mixed), 2)
eq("bat: clock back splits", #B.segments({ S(1000, 50), S(500, 50) }), 2)

local secs, kind, basis = B.estimate(d, 54 * 60, 81, false)
check("bat: discharge estimate ~ 81% * 6 min", secs and math.abs(secs - 81 * 360) < 60, secs)
eq("bat: live", kind, "live")
eq("bat: basis pct without gauge", basis, "pct")
eq("bat: calibrating (too little)", B.estimate(drain(0, 90, 2, 1, 360), 400, 89, false), nil)
eq("bat: calibrating (no drop)", B.estimate({ S(0, 90), S(600, 90), S(1200, 90) }, 1200, 90, false), nil)

-- after a suspend the old stretch calibrates the new one ("saved")
local resumed = {}
for _, x in ipairs(d) do resumed[#resumed + 1] = x end
resumed[#resumed + 1] = S(20000, 70)
local s2, k2 = B.estimate(resumed, 20000, 70, false)
eq("bat: saved kind", k2, "saved")
check("bat: saved estimate", s2 and math.abs(s2 - 70 * 360) < 60, s2)

-- charging: 1% per 2 min
local c = {}
for i = 0, 9 do c[#c + 1] = S(i * 120, 40 + i, true) end
local cs, ck = B.estimate(c, 9 * 120, 49, true)
check("bat: charge estimate ~ 51% * 2 min", cs and math.abs(cs - 51 * 120) < 30, cs)
eq("bat: charge live", ck, "live")
eq("bat: full battery no eta", B.estimate(c, 9 * 120, 100, true), nil)
eq("bat: nothing at all", B.estimate({}, 0, 50, false), nil)
eq("bat: empty battery no eta", B.estimate(d, 54 * 60, 0, false), nil)
eq("bat: slow drain still estimated", B.estimate({ S(0, 90), S(1000, 90), S(2000, 89), S(3000, 89), S(4000, 88),
    S(5000, 88), S(6000, 87) }, 6000, 87, false) ~= nil, true)
eq("bat: stale stretch is not live", select(2, B.estimate(d, 54 * 60 + B.GAP_MAX + 1, 81, false)), "saved")
eq("bat: estimate nil pct", B.estimate(d, 100, nil, false), nil)

eq("eta: 25 min", B.eta_text(25 * 60), "~25min")
eq("eta: rounds to 5", B.eta_text(23 * 60), "~25min")
eq("eta: under 5 min", B.eta_text(60), "~5min")
eq("eta: 4h20", B.eta_text(4 * 3600 + 20 * 60), "~4h20")
eq("eta: 12h", B.eta_text(12 * 3600 + 600), "~12h")
eq("eta: 17h", B.eta_text(17.2 * 3600), "~17h")
eq("eta: nil", B.eta_text(nil), nil)
eq("eta: negative", B.eta_text(-5), nil)

---------------------------------------------------------------- D3: charge counter (mAh)

-- the KT3 awake with Wi-Fi: ~48 mA from 888 mAh (97 %), a sample every 10 min (heartbeat), % from the counter
local function gauge_drain(t0, mah0, ma, n, per)
    local out = {}
    for i = 0, n - 1 do
        local mah = mah0 - ma * i * per / 3600
        out[#out + 1] = { t = t0 + i * per, pct = math.floor(mah / 907 * 100), chg = false, wifi = true,
            mah = math.floor(mah + 0.5), ma = -ma }
    end
    return out
end
local g = gauge_drain(0, 888, 48, 4, 600)        -- 30 min
local gs, gk, gb, gma = B.estimate(g, 1800, g[#g].pct, false, { mah = g[#g].mah, full = 907 })
eq("D3: basis mah", gb, "mah")
eq("D3: live", gk, "live")
near("D3: ~ mah / 48 mA", gs, g[#g].mah / 48 * 3600, 600)
near("D3: fitted current ~ -48 mA", gma, -48, 1.5)
local hours = gs / 3600
check("D3: 18.5 h left from 864 mAh at 48 mA", hours > 17.5 and hours < 19.5, hours)
-- the same data without the gauge reading falls back to %, which has not moved 3 % yet in 30 min
eq("D3: % fallback still calibrating", B.estimate(g, 1800, g[#g].pct, false), nil)
-- mAh moved too little (< MIN_MOVE_MAH) -> nothing
local tiny = gauge_drain(0, 888, 8, 4, 600)
eq("D3: too little charge moved", B.estimate(tiny, 1800, tiny[#tiny].pct, false, { mah = tiny[#tiny].mah }), nil)
-- lines without mah (older log) next to the gauge reading: the % slope is used
local ps, _, pb = B.estimate(d, 54 * 60, 81, false, { mah = 730 })
eq("D3: no mah in samples -> pct", pb, "pct")
check("D3: pct estimate kept", ps ~= nil)
-- charging with the counter: 160 mA up from 400 mAh, to charge_full
local ch = {}
for i = 0, 6 do ch[#ch + 1] = { t = i * 300, pct = math.floor((400 + 160 * i * 300 / 3600) / 9.07), chg = true,
    mah = math.floor(400 + 160 * i * 300 / 3600 + 0.5) } end
local chs, _, chb, chma = B.estimate(ch, 1800, ch[#ch].pct, true, { mah = ch[#ch].mah, full = 907 })
eq("D3: charging basis mah", chb, "mah")
near("D3: charging to charge_full", chs, (907 - ch[#ch].mah) / 160 * 3600, 300)
near("D3: charging current", chma, 160, 3)
-- without charge_full the measured capacity (907) is used
local chs2 = B.estimate(ch, 1800, ch[#ch].pct, true, { mah = ch[#ch].mah })
near("D3: default capacity 907", chs2, chs, 1)
eq("D3: CAPACITY", B.CAPACITY, 907)

---------------------------------------------------------------- R-L4: same band

eq("band: 65 high", B.band(65), "high")
eq("band: 64 low", B.band(64), "low")
-- a fast high-band discharge, then the device slept; now at 50 % with no live data
local high = drain(0, 90, 10, 1, 360)                -- 90 -> 81
local now_low = {}
for _, x in ipairs(high) do now_low[#now_low + 1] = x end
now_low[#now_low + 1] = S(30000, 50)
eq("R-L4: % calibration from another band is not used", B.estimate(now_low, 30000, 50, false), nil)
-- with an earlier low-band stretch it is
local low = drain(10000, 60, 10, 1, 300)             -- 60 -> 51
local both = {}
for _, x in ipairs(high) do both[#both + 1] = x end
for _, x in ipairs(low) do both[#both + 1] = x end
both[#both + 1] = S(30000, 50)
local ls, lk = B.estimate(both, 30000, 50, false)
eq("R-L4: same-band calibration", lk, "saved")
near("R-L4: uses the low band rate (1 %/5 min)", ls, 50 * 300, 120)
-- the mAh counter does not depend on the band: a high-band mAh stretch calibrates a low-band reading
local gh = gauge_drain(0, 880, 48, 6, 600)
local gl = {}
for _, x in ipairs(gh) do gl[#gl + 1] = x end
gl[#gl + 1] = { t = 40000, pct = 50, chg = false, mah = 450 }
local mls, mlk, mlb = B.estimate(gl, 40000, 50, false, { mah = 450 })
eq("R-L4: mAh saved across bands", mlb .. ":" .. mlk, "mah:saved")
near("R-L4: 450 mAh at 48 mA", mls, 450 / 48 * 3600, 900)

---------------------------------------------------------------- mean current

near("mean: from ma readings", B.mean_current(g, 1800, false), 48, 0.01)
eq("mean: none without readings", B.mean_current(d, 54 * 60, false), nil)
eq("mean: other charging state", B.mean_current(g, 1800, true), nil)
eq("mean: stale", B.mean_current(g, 1800 + B.GAP_MAX + 1, false), nil)
eq("mean: empty", B.mean_current({}, 0, false), nil)

---------------------------------------------------------------- texts

eq("thousands pt", B.thousands(3120, "pt"), "3.120")
eq("thousands en", B.thousands(3120, "en"), "3,120")
eq("thousands small", B.thousands(42, "pt"), "42")
eq("thousands million", B.thousands(1234567, "pt"), "1.234.567")
eq("thousands negative", B.thousands(-1500, "pt"), "-1.500")

local L = T.L
local v = B.view({ pct = 82, charging = false, eta = 4 * 3600 + 20 * 60, ma_mean = 42.3, full_mah = 907, temp = 23,
    samples = 3120, at = 1000 }, 1000, L, "pt")
eq("view: pct", v.pct_text, "82%")
eq("view: number", v.number, "82%")
eq("view: line", v.line, "~4h20 restantes · 42 mA em média")
eq("view: short", v.short, "~4h20 · 42 mA")
eq("view: stat mean", v.stats[1][1], "42 mA")
eq("view: stat full", v.stats[2][1], "907")
eq("view: stat temp", v.stats[3][1], "23 °C")
eq("view: stat samples", v.stats[4][1], "3.120")
eq("view: stat labels", v.stats[1][2] .. "/" .. v.stats[2][2] .. "/" .. v.stats[3][2] .. "/" .. v.stats[4][2],
    "média/mAh cheia/temperatura/amostras")
local v2 = B.view({ pct = 82, eta = 4 * 3600 + 20 * 60, at = 1000 }, 1000 + 20 * 60, L, "pt")
eq("view: eta counts down since the reading", v2.eta, "~4h00")
eq("view: no current", v2.line, "~4h00 restantes")
local vc = B.view({ pct = 60, charging = true, eta = 40 * 60, at = 0 }, 0, L, "pt")
eq("view: charging", vc.line, "⚡ carregando · ~40min até 100%")
eq("view: charging short", vc.short, "⚡ ~40min até 100%")
eq("view: charging number", vc.number, "⚡60%")
eq("view: charging calibrating", B.view({ pct = 60, charging = true, at = 0 }, 0, L, "pt").line, "⚡ carregando · calibrando…")
eq("view: full", B.view({ pct = 100, charging = true, at = 0 }, 0, L, "pt").line, "⚡ carga completa")
eq("view: gauge says Full", B.view({ pct = 99, charging = true, full = true, at = 0 }, 0, L, "pt").short, "⚡ carga completa")
eq("view: calibrating", B.view({ pct = 70, at = 0 }, 0, L, "pt").line, "calibrando a estimativa…")
eq("view: calibrating short", B.view({ pct = 70, at = 0 }, 0, L, "pt").short, "calibrando…")
local vn = B.view(nil, 0, L, "pt")
eq("view: no reading", vn.ok, false)
eq("view: no reading text", vn.line, "sem leitura do medidor")
eq("view: no reading pct", vn.pct_text, "--%")
eq("view: no reading stats", vn.stats[1][1] .. vn.stats[4][1], "--0")
eq("view: clamps pct", B.view({ pct = 140, at = 0 }, 0, L, "pt").pct_text, "100%")
eq("view: fitted current when no readings", B.view({ pct = 50, eta = 3600, ma_fit = -47.6, at = 0 }, 0, L, "pt").stats[1][1], "48 mA")

---------------------------------------------------------------- status bar (R-S1, Host.battery_eta)

local last = { eta = 17 * 3600 + 600, charging = false, at = 1000 }
eq("status: eta", B.status_eta(last, { pct = 82, charging = false }, 1000), "~17h")
eq("status: counts down", B.status_eta(last, { pct = 82, charging = false }, 1000 + 1800), "~16h")
eq("status: other charging state", B.status_eta(last, { pct = 82, charging = true }, 1000), nil)
eq("status: too old", B.status_eta(last, { pct = 82, charging = false }, 1000 + B.STATUS_MAX_AGE + 1), nil)
eq("status: clock went back", B.status_eta(last, { pct = 82 }, 500), nil)
eq("status: no estimate", B.status_eta({ charging = false, at = 1 }, { pct = 82 }, 1), nil)
eq("status: nothing", B.status_eta(nil, { pct = 82 }, 1), nil)
eq("status: bad b", B.status_eta(last, nil, 1000), nil)
