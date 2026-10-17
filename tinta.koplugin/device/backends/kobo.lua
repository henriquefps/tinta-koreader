-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (C) 2026 Tinta contributors
-- Tinta device backend: Kobo. EXPERIMENTAL, UNTESTED ON HARDWARE (the user owns no Kobo): written from KOReader
-- v2025.04 (frontend/device/kobo/device.lua, powerd.lua, wakeupmgr.lua, plugins/autosuspend.koplugin) and tested
-- against fakes modelled on those sources. See device/backends/driven.lua for how the Tinta cooperates with
-- KOReader's own suspend, WakeupMgr (RTC /dev/rtc0, dodgy_rtc chains handled by WakeupMgr itself), autosuspend and
-- USBMS prompt. Battery: KOReader's KoboPowerD (sysfs capacity and status): percentage and charging only. The
-- sysfs charge counter is not read: the node differs between Kobo kernels (mc13892, bd71827, "battery"), so the
-- Bateria estimate uses the % path (D3 fallback) rather than a mAh slope that could be wrong.
local B = { name = "kobo", can_wake = true }

local Gauge = require("device/backends/gauge")
local Driven = require("device/backends/driven")

function B.battery_read(opts) return Gauge.from_powerd(Gauge.powerd(opts)) end
function B.battery_plugged(opts) return Gauge.powerd_plugged(opts) end

-- Wi-Fi on a Kobo (NetworkMgr turnOnWifi + DHCP) is slower than the Kindle's: the wake-up batch waits longer
B.WIFI_TIMEOUT = 60

function B.sleep(env)
    return Driven.sleep(env, { name = B.name, can_wake = B.can_wake, wifi_timeout = B.WIFI_TIMEOUT })
end

return B
