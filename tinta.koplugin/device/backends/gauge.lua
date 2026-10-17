-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (C) 2026 Tinta contributors
-- Tinta: gauge helpers shared by the device backends (spec 11.1): plain file reads and the parse of a power_supply
-- sysfs directory (R-L3: no process is spawned). Moved unchanged from device/battery.lua; the Kindle backend
-- (bd7181x, mV / mA / mAh / °C) and the Kobo one (status + percentage) use the same parser.
local M = {}

-- first line of a file, or nil
function M.read_file(path)
    local fh = io.open(path, "r")
    if not fh then return nil end
    local s = fh:read("*l")
    fh:close()
    return s
end

function M.num(s)
    if s == nil then return nil end
    local v = tonumber((tostring(s):gsub("^%s+", ""):gsub("%s+$", "")))
    if not v or v ~= v or v == math.huge or v == -math.huge then return nil end
    return v
end

-- µV / µA / µAh -> milli when the value is too big to be milli (|v| >= limit)
function M.milli(v, limit)
    if v and math.abs(v) >= limit then return v / 1000 end
    return v
end

-- raw strings (key -> first line of the file) -> reading; nil fields when a file is missing or unreadable.
-- reading = { pct, charging, full, status, mv, ma, mah, full_mah, design_mah, temp }
function M.parse(raw)
    raw = raw or {}
    local r = {}
    local pct = M.num(raw.pct)
    if pct and pct >= 0 and pct <= 100 then r.pct = pct end
    local status = raw.status and tostring(raw.status):match("^%s*(.-)%s*$") or nil
    if status == "" then status = nil end
    r.status = status
    r.full = status == "Full"
    local chg = M.num(raw.charging)
    if chg ~= nil then
        r.charging = chg ~= 0 or status == "Full"
    elseif status then
        r.charging = status == "Charging" or status == "Full"
    end
    r.mv = M.milli(M.num(raw.mv), 100000)            -- 3812 mV, or 3812000 µV
    r.ma = M.milli(M.num(raw.ma), 20000)             -- -48 mA, or -48000 µA
    r.mah = M.milli(M.num(raw.mah), 100000)          -- 888 mAh, or 888000 µAh
    r.full_mah = M.milli(M.num(raw.full_mah), 100000)
    r.design_mah = M.milli(M.num(raw.design_mah), 100000)
    local temp = M.num(raw.temp)
    if temp and math.abs(temp) > 150 then temp = temp / 10 end   -- tenths of a degree
    r.temp = temp
    return r
end


-- KOReader's power device (Device:getPowerDevice()): `opts.powerd` when given (false = none), else the running one.
function M.powerd(opts)
    local pd = opts and opts.powerd
    if pd ~= nil then return pd or nil end
    local ok, Device = pcall(require, "device")
    if ok and type(Device) == "table" and Device.getPowerDevice then
        local pok, p = pcall(Device.getPowerDevice, Device)
        if pok and type(p) == "table" then return p end
    end
    return nil
end

-- A reading from KOReader's power device alone (Kobo and generic): percentage and charging, no gauge values, so the
-- Bateria estimate uses the % path. nil when no percentage is known. isCharging is true while charged and still
-- plugged in (Kobo: status ~= "Discharging"), which is what "plugged" means here.
function M.from_powerd(pd)
    if not pd then return nil end
    local r = {}
    if pd.getCapacity then
        local ok, v = pcall(pd.getCapacity, pd)
        v = ok and tonumber(v) or nil
        if v and v >= 0 and v <= 100 then r.pct = v end
    end
    if r.pct == nil then return nil end
    local ok, v = false, nil
    if pd.isCharging then ok, v = pcall(pd.isCharging, pd) end
    r.charging = ok and v == true
    if pd.isCharged then
        local cok, c = pcall(pd.isCharged, pd)
        r.full = cok and c == true
    else
        r.full = false
    end
    return r
end

function M.powerd_plugged(opts)
    local pd = M.powerd(opts)
    if pd and pd.isCharging then
        local ok, v = pcall(pd.isCharging, pd)
        if ok and v == true then return true end
    end
    return false
end

return M
