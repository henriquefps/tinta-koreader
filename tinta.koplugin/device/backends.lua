-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (C) 2026 Tinta contributors
-- Tinta: picks the device backend once, from KOReader's Device (spec 11.1, 2.2). A backend is a module with
--   B.name, B.can_wake                 "kindle" | "kobo" | "generic"; whether the device can be woken by the Tinta
--   B.battery_read(opts) / B.battery_plugged(opts)    what device/battery.lua calls
--   B.sleep(env) -> controller         what device/sleep.lua drives (see its header)
-- Kindle is today's code, moved (backends/kindle.lua). Kobo is experimental, untested on hardware. Anything else
-- KOReader runs on (emulator, Android, Cervantes, Pocketbook, ...) gets the generic one.
local M = {}

local function flag(dev, name)
    local f = dev[name]
    if type(f) ~= "function" then return nil end
    local ok, v = pcall(f, dev)
    return ok and v == true
end

-- name of the backend for a KOReader Device table. A table without isKindle (a bare test fake, never a real
-- KOReader Device, whose Generic base always has it) is read as the Kindle it was written for.
function M.name(dev)
    if type(dev) ~= "table" or type(dev.isKindle) ~= "function" then return "kindle" end
    if flag(dev, "isKindle") then return "kindle" end
    if flag(dev, "isKobo") then return "kobo" end
    return "generic"
end

local selected   -- cache for the real Device (one decision per process)

function M.select(dev)
    local name = M.name(dev)
    if dev ~= nil and dev == (selected and selected.dev) then return selected.backend end
    local backend = require("device/backends/" .. name)
    if dev ~= nil then selected = { dev = dev, backend = backend } end
    return backend
end

-- the backend for the running KOReader (battery facade, host)
function M.current()
    local ok, Device = pcall(require, "device")
    return M.select(ok and type(Device) == "table" and Device or nil)
end

return M
