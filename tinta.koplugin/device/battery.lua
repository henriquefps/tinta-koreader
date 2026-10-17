-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (C) 2026 Tinta contributors
-- Tinta: battery gauge reader (spec 4.1, 2.2): a facade over the device backend (device/backends). The backend
-- reads what its device offers: the Kindle's bd7181x gauge by plain file reads (R-L3: no process is spawned; mV, mA
-- negative while discharging, mAh, °C), a Kobo or other device only KOReader's power device (percentage and
-- charging, so the Bateria estimate falls back to the % path, D3). Thin on purpose: no estimate, no log (that is
-- apps/bateria). The file reader and the power device are injectable, so the tests run without a device.
local Backends = require("device/backends")
local Gauge = require("device/backends/gauge")
local Kindle = require("device/backends/kindle")

local M = {}

-- the KT3 gauge, as before the backends (the tests and the tools read these)
M.DIR = Kindle.DIR
M.FILES = Kindle.FILES
M.read_file = Gauge.read_file
M.parse = Gauge.parse

local function backend(opts)
    return (opts and opts.backend) or Backends.current()
end

-- Plugged in (USB cable or charger)? Used by the idle sleep mode "só na bateria". The backend decides how (Kindle:
-- gauge status + powerd isCharging; others: powerd isCharging). A failed read is false (the device may then sleep).
-- opts = { dir, read_file, powerd, backend } as in M.read.
function M.plugged(opts)
    return backend(opts).battery_plugged(opts)
end

-- opts = { dir = Kindle gauge dir, read_file = fn(path) -> string | nil, powerd = KOReader power device | false,
--          backend = a backends module (default: the one for this Device) }
-- Returns the reading { pct, charging, full, status, mv, ma, mah, full_mah, design_mah, temp } (nil fields where the
-- device has none); nil when no percentage is known at all.
function M.read(opts)
    return backend(opts).battery_read(opts)
end

return M
