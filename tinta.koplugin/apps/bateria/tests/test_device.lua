-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (C) 2026 Tinta contributors
-- device/battery.lua: reads the bd7181x gauge by file (R-L3), with an injected file reader
local T = ...
local check, eq = T.check, T.eq
local Battery = require("device/battery")

eq("gauge dir", Battery.DIR, "/sys/class/power_supply/bd7181x_bat/")

-- files as the KT3 shows them (2026-10-14 power probe and the P4 suspend log)
local function fs(files)
    local read = {}
    return function(path)
        read[#read + 1] = path
        local name = path:match("([^/]+)$")
        local v = files[name]
        if v == "ERR" then error("EIO") end
        return v
    end, read
end
local KT3 = { capacity = "97", status = "Discharging", charging = "0", voltage_now = "4111", current_now = "-48",
    charge_now = "888", charge_full = "907", charge_full_design = "909", temp = "25" }
local rf, read = fs(KT3)
local r = Battery.read{ read_file = rf, powerd = false }
check("read: a reading", r ~= nil)
eq("read: pct", r.pct, 97)
eq("read: discharging", r.charging, false)
eq("read: not full", r.full, false)
eq("read: status", r.status, "Discharging")
eq("read: mV", r.mv, 4111)
eq("read: mA negative discharging", r.ma, -48)
eq("read: mAh", r.mah, 888)
eq("read: charge_full", r.full_mah, 907)
eq("read: design", r.design_mah, 909)
eq("read: temp", r.temp, 25)
local only_sys = true
for _, p in ipairs(read) do if not p:find("^/sys/class/power_supply/bd7181x_bat/") then only_sys = false end end
check("read: only gauge files, by path (R-L3)", only_sys and #read > 0)

-- charging (probe of 2026-10-14: 41 %, 97 mA in)
local rc = Battery.read{ read_file = fs{ capacity = "41\n", status = "Charging\n", charging = "1", current_now = "97",
    voltage_now = "3812", charge_now = "376", charge_full = "907", temp = "28" }, powerd = false }
eq("charging: pct with newline", rc.pct, 41)
eq("charging: flag", rc.charging, true)
eq("charging: positive current", rc.ma, 97)
-- Full: the charger is in, counts as charging, and full is set
local rf2 = Battery.read{ read_file = fs{ capacity = "100", status = "Full", charging = "0" }, powerd = false }
eq("full: charging", rf2.charging, true)
eq("full: full", rf2.full, true)
-- no charging file: the status decides
eq("status only: charging", Battery.read{ read_file = fs{ capacity = "50", status = "Charging" }, powerd = false }.charging, true)
eq("status only: discharging", Battery.read{ read_file = fs{ capacity = "50", status = "Discharging" }, powerd = false }.charging, false)
eq("status only: not charging", Battery.read{ read_file = fs{ capacity = "50", status = "Not charging" }, powerd = false }.charging, false)

-- micro-units and tenths of a degree (other kernels)
local ru = Battery.parse{ pct = "80", mv = "3921000", ma = "-187000", mah = "1020000", full_mah = "1020000", temp = "285" }
eq("micro: mV", ru.mv, 3921)
eq("micro: mA", ru.ma, -187)
eq("micro: mAh", ru.mah, 1020)
eq("tenths: temp", ru.temp, 28.5)
eq("milli kept: big current", Battery.parse{ ma = "-1500" }.ma, -1500)
eq("negative temp kept", Battery.parse{ temp = "-5" }.temp, -5)

-- missing / damaged files
local rm = Battery.read{ read_file = fs{ capacity = "70", status = "Discharging", current_now = "x", temp = "ERR" }, powerd = false }
eq("missing: pct still read", rm.pct, 70)
eq("missing: bad number nil", rm.ma, nil)
eq("missing: read error nil", rm.temp, nil)
eq("missing: no mah", rm.mah, nil)
eq("bad pct ignored", Battery.parse{ pct = "140" }.pct, nil)
eq("empty status", Battery.parse{ status = "  " }.status, nil)

-- no files at all: KOReader's power device fills pct and charging
local pd = { getCapacity = function() return 64 end, isCharging = function() return true end }
local rp = Battery.read{ read_file = fs{}, powerd = pd }
eq("powerd: pct", rp.pct, 64)
eq("powerd: charging", rp.charging, true)
eq("powerd: no gauge", rp.mah, nil)
local rp2 = Battery.read{ read_file = fs{ capacity = "55" }, powerd = { isCharging = function() return false end } }
eq("powerd: only charging from powerd", rp2.pct .. ":" .. tostring(rp2.charging), "55:false")
eq("powerd: throwing powerd", Battery.read{ read_file = fs{}, powerd = { getCapacity = function() error("x") end } }, nil)
eq("nothing: nil", Battery.read{ read_file = fs{}, powerd = false }, nil)
eq("no device module: nil", Battery.read{ read_file = fs{} }, nil)
-- the real reader on this machine (no /sys gauge): never raises
check("real read_file: missing file is nil", Battery.read_file("/nonexistent/capacity") == nil)

-- Battery.plugged: the idle sleep mode "só na bateria" (USB / charger, "plugged but full" counts as plugged)
local function plugged(files, pd) return Battery.plugged{ read_file = fs(files), powerd = pd } end
local PD = function(v) return { isCharging = function() return v end } end
check("plugged: discharging, powerd says no -> unplugged", plugged({ status = "Discharging", charging = "0" }, PD(false)) == false)
check("plugged: charging file 1", plugged({ status = "Discharging", charging = "1" }, PD(false)) == true)
check("plugged: status Charging", plugged({ status = "Charging" }, PD(false)) == true)
check("plugged: Full at 100 % on the cable (charging 0)", plugged({ status = "Full", charging = "0" }, PD(false)) == true)
check("plugged: gauge says no, powerd isCharging says yes", plugged({ status = "Discharging", charging = "0" }, PD(true)) == true)
check("plugged: no files, powerd no", plugged({}, PD(false)) == false)
check("plugged: no files, no powerd -> unplugged", plugged({}, nil) == false)
check("plugged: unreadable files, powerd yes", plugged({ status = "ERR", charging = "ERR" }, PD(true)) == true)
check("plugged: throwing powerd is not plugged", plugged({ status = "Discharging", charging = "0" }, { isCharging = function() error("lipc") end }) == false)
local _, pread = fs({})
local rf2, read2 = fs({ status = "Discharging", charging = "0" })
Battery.plugged{ read_file = rf2, powerd = false }
eq("plugged: reads only the two gauge files (cheap)", #read2, 2)
