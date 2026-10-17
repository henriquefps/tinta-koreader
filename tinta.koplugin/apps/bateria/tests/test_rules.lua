-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (C) 2026 Tinta contributors
-- 8.6 Bateria rules: below 20 % discharging once per discharge (alta), 100 % charging once per charge (normal)
local T = ...
local check, eq = T.check, T.eq
local B = require("apps/bateria/logic")
local L = T.L

-- tracking of the discharge / charge stretch
local s1 = B.track(nil, 1000, 50, false)
eq("track: first reading starts a stretch", s1.since, 1000)
local s2 = B.track(s1, 1060, 49, false)
eq("track: same discharge keeps the start", s2.since, 1000)
eq("track: keeps the last pct", s2.pct, 49)
local s3 = B.track(s2, 1120, 49, true)
eq("track: plugged -> new start", s3.since .. ":" .. tostring(s3.chg), "1120:true")
local s4 = B.track(s3, 5000, 100, true)
eq("track: same charge", s4.since, 1120)
local s5 = B.track(s4, 5060, 100, false)
eq("track: unplugged -> new discharge", s5.since, 5060)
-- the Tinta was closed while it charged: two discharging readings, the second higher
local s6 = B.track({ chg = false, since = 100, pct = 30, t = 200 }, 90000, 95, false)
eq("track: charged while closed -> new discharge", s6.since, 90000)
local s7 = B.track({ chg = false, since = 100, pct = 30, t = 200 }, 300, 31, false)
eq("track: 1 % up is noise, same discharge", s7.since, 100)
local s8 = B.track({ chg = true, since = 100, pct = 90, t = 200 }, 90000, 40, true)
eq("track: ran down while closed -> new charge", s8.since, 90000)
eq("track: garbage prev", B.track("x", 10, 50, false).since, 10)
eq("track: prev without since", B.track({ chg = false }, 10, 50, false).since, 10)

-- events
local st = { chg = false, since = 1000 }
eq("events: 20 % is not low", #B.events(st, { pct = 20, charging = false }, nil, L), 0)
local e = B.events(st, { pct = 19, charging = false }, "~3h40", L)
eq("events: 19 % low", #e, 1)
eq("events: low key", e[1].key, "low:1000")
eq("events: low prio", e[1].prio, "alta")
eq("events: low type", e[1].type, "low")
eq("events: low title", e[1].title, "Bateria em 19%")
eq("events: low body", e[1].body, "~3h40 restantes com a Tinta aberta")
eq("events: no route (opens main)", e[1].route, nil)
eq("events: low body without estimate", B.events(st, { pct = 5, charging = false }, nil, L)[1].body, "conecte o carregador")
eq("events: low while charging = nothing", #B.events({ chg = true, since = 1 }, { pct = 10, charging = true }, nil, L), 0)
local f = B.events({ chg = true, since = 2000 }, { pct = 100, charging = true }, nil, L)
eq("events: full", #f, 1)
eq("events: full key", f[1].key, "full:2000")
eq("events: full prio", f[1].prio, "normal")
eq("events: full texts", f[1].title .. " / " .. f[1].body, "Carga completa / pode desconectar o cabo")
eq("events: gauge Full at 99 %", #B.events({ chg = true, since = 2000 }, { pct = 99, charging = true, full = true }, nil, L), 1)
eq("events: 100 % unplugged = nothing", #B.events({ chg = false, since = 1 }, { pct = 100, charging = false }, nil, L), 0)
eq("events: no state", #B.events(nil, { pct = 5 }, nil, L), 0)
eq("events: no pct", #B.events(st, {}, nil, L), 0)

-- a whole day through cycle(): one low per discharge, one full per charge
local Log = require("apps/bateria/csvlog")
local store = Log.open(nil)
local keys, state = {}, nil
local function step(t, pct, chg)
    local cache, ns, evs = B.cycle(store, { pct = pct, charging = chg }, t, state, L)
    state = ns
    for _, n in ipairs(evs) do keys[n.key] = (keys[n.key] or 0) + 1 end
    return cache
end
local t = 0
for p = 30, 10, -1 do t = t + 600; step(t, p, false) end          -- discharge 30 -> 10
local first_low = "low:600"
eq("day: one low key for the discharge", keys[first_low], 10)    -- emitted each reading below 20; core dedups (R-T1)
local n_low = 0
for k in pairs(keys) do if k:match("^low:") then n_low = n_low + 1 end end
eq("day: a single low key", n_low, 1)
for p = 10, 100, 5 do t = t + 600; step(t, p, true) end           -- charge to 100
t = t + 600; step(t, 100, true)
local n_full = 0
for k in pairs(keys) do if k:match("^full:") then n_full = n_full + 1 end end
eq("day: a single full key", n_full, 1)
for p = 100, 15, -5 do t = t + 600; step(t, p, false) end         -- second discharge
n_low = 0
for k in pairs(keys) do if k:match("^low:") then n_low = n_low + 1 end end
eq("day: second discharge, second low key", n_low, 2)
local c = step(t + 60, 15, false)
check("cycle: cache fields", c.pct == 15 and c.charging == false and c.at == t + 60 and c.samples >= 1)
