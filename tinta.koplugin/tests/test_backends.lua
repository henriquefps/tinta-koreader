-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (C) 2026 Tinta contributors
-- device/backends: selection from KOReader's Device, and the battery facade (device/battery.lua) over each backend.
-- The Kindle rows pin what the KT3 had before the split; Kobo / generic fakes follow KOReader's KoboPowerD.
local T = ...
local Backends = require("device/backends")
local Battery = require("device/battery")
local eq, check = T.eq, T.check

local function device(flags, pd)
    local d = {}
    for k, v in pairs(flags) do d[k] = function() return v end end
    d.getPowerDevice = function() return pd end
    return d
end

eq("select: Kindle", Backends.name(device({ isKindle = true, isKobo = false })), "kindle")
eq("select: Kobo", Backends.name(device({ isKindle = false, isKobo = true })), "kobo")
eq("select: anything else is generic", Backends.name(device({ isKindle = false, isKobo = false })), "generic")
eq("select: a Device without the flags is the legacy Kindle (test fakes)", Backends.name({}), "kindle")
eq("select: no Device is the legacy Kindle", Backends.name(nil), "kindle")
eq("select: a failing flag counts as no", Backends.name({ isKindle = function() return false end,
    isKobo = function() error("boom") end }), "generic")
eq("select: the module of the name", Backends.select(device({ isKindle = false, isKobo = true })).name, "kobo")
check("select: the same Device gives the same backend",
    (function() local d = device({ isKindle = true }); return Backends.select(d) == Backends.select(d) end)())
check("backends: only the Kindle and the Kobo can be woken by the tinta",
    Backends.select(device({ isKindle = true })).can_wake and Backends.select(device({ isKobo = true, isKindle = false })).can_wake
    and not Backends.select(device({ isKindle = false, isKobo = false })).can_wake)

-- Kindle through the facade: the same readings as device/battery.lua always gave (bd7181x files)
local KT3 = { capacity = "97", status = "Discharging", charging = "0", voltage_now = "4111", current_now = "-48",
    charge_now = "888", charge_full = "907", charge_full_design = "909", temp = "25" }
local function rf(files) return function(path) return files[path:match("([^/]+)$")] end end
local kindle = device({ isKindle = true })
local r = Battery.read{ backend = Backends.select(kindle), read_file = rf(KT3), powerd = false }
eq("kindle facade: pct", r.pct, 97)
eq("kindle facade: mAh from the gauge", r.mah, 888)
eq("kindle facade: full mAh", r.full_mah, 907)
eq("kindle facade: mA", r.ma, -48)
eq("kindle facade: not plugged", Battery.plugged{ backend = Backends.select(kindle), read_file = rf(KT3), powerd = false }, false)
KT3.status, KT3.charging = "Charging", "1"
eq("kindle facade: plugged by the gauge", Battery.plugged{ backend = Backends.select(kindle), read_file = rf(KT3), powerd = false }, true)
eq("kindle facade: DIR kept", Battery.DIR, "/sys/class/power_supply/bd7181x_bat/")

-- Kobo / generic: KOReader's power device only
local function powerd(o)
    local calls = { cap = 0 }
    return setmetatable({ calls = calls,
        getCapacity = function() calls.cap = calls.cap + 1; return o.pct end,
        isCharging = function() return o.charging end,
        isCharged = function() return o.charged == true end }, { __index = o.extra })
end
for _, name in ipairs({ "kobo", "generic" }) do
    local be = require("device/backends/" .. name)
    local rk = Battery.read{ backend = be, powerd = powerd{ pct = 64, charging = false } }
    eq(name .. ": pct from powerd", rk.pct, 64)
    eq(name .. ": not charging", rk.charging, false)
    eq(name .. ": no mAh (the % estimate is used)", rk.mah, nil)
    eq(name .. ": no full mAh", rk.full_mah, nil)
    local rc = Battery.read{ backend = be, powerd = powerd{ pct = 100, charging = true, charged = true } }
    check(name .. ": charged and plugged", rc.charging == true and rc.full == true)
    eq(name .. ": no powerd -> no reading", Battery.read{ backend = be, powerd = false }, nil)
    eq(name .. ": a failing getCapacity -> no reading", Battery.read{ backend = be,
        powerd = { getCapacity = function() error("EIO") end } }, nil)
    eq(name .. ": plugged = powerd isCharging", Battery.plugged{ backend = be, powerd = powerd{ pct = 50, charging = true } }, true)
    eq(name .. ": unplugged", Battery.plugged{ backend = be, powerd = powerd{ pct = 50, charging = false } }, false)
    eq(name .. ": plugged while charged (still on the cable)", Battery.plugged{ backend = be,
        powerd = powerd{ pct = 100, charging = true, charged = true } }, true)
    eq(name .. ": no powerd -> not plugged", Battery.plugged{ backend = be, powerd = false }, false)
    eq(name .. ": a failing isCharging -> not plugged", Battery.plugged{ backend = be,
        powerd = { isCharging = function() error("EIO") end } }, false)
end

-- the estimate fallback: Bateria's logic with a Kobo reading (no mAh) uses the % basis (D3)
do
    local Logic = require("apps/bateria/logic")
    local samples = {}
    for i = 0, 20 do samples[#samples + 1] = { t = 1000 + i * 600, pct = 80 - i, chg = false } end
    local secs, _, basis = Logic.estimate(samples, 1000 + 20 * 600, 60, false, { mah = nil, full = nil })
    check("kobo reading: estimate on the % basis", secs ~= nil and basis == "pct", tostring(basis))
end
