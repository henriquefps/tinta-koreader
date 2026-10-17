-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (C) 2026 Tinta contributors
-- Tinta device backend: generic (any other device KOReader runs on: emulator, Android, Cervantes, PocketBook...).
-- No scheduled wake-up: sleep = draw the sleep page and let KOReader suspend (UIManager:suspend), so the page
-- shows no "next update" and never refreshes while asleep; the power button wakes the Tinta (Device:resume).
-- Battery: KOReader's power device (percentage, charging; Bateria uses the % estimate). Plugged: isCharging().
-- A device that cannot suspend (Device:canSuspend() false, e.g. the emulator) aborts back to the Tinta.
-- UNTESTED ON HARDWARE, like the Kobo one.
local B = { name = "generic", can_wake = false }

local Gauge = require("device/backends/gauge")
local Driven = require("device/backends/driven")

function B.battery_read(opts) return Gauge.from_powerd(Gauge.powerd(opts)) end
function B.battery_plugged(opts) return Gauge.powerd_plugged(opts) end

function B.sleep(env)
    return Driven.sleep(env, { name = B.name, can_wake = B.can_wake })
end

return B
