-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (C) 2026 Tinta contributors
-- luajit -bl on every file of the app and on device/battery.lua (15.1), and R-A1: the pure modules require only
-- each other (no KOReader, no core/)
local T = ...
local exe = arg and arg[-1] or "luajit"
local files = { "init.lua", "logic.lua", "csvlog.lua", "chart.lua", "view.lua", "strings.lua" }
for _, f in ipairs(files) do
    local ok = os.execute(exe .. ' -bl "' .. T.plugin .. "/apps/bateria/" .. f .. '" > /dev/null 2>&1')
    T.check("syntax: apps/bateria/" .. f, ok == 0 or ok == true)
end
local ok = os.execute(exe .. ' -bl "' .. T.plugin .. '/device/battery.lua" > /dev/null 2>&1')
T.check("syntax: device/battery.lua", ok == 0 or ok == true)
local pure = { ["apps/bateria/logic"] = true, ["apps/bateria/chart"] = true, ["apps/bateria/csvlog"] = true }
local bad = {}
for _, f in ipairs({ "logic.lua", "csvlog.lua", "chart.lua", "view.lua", "strings.lua" }) do
    local fh = assert(io.open(T.plugin .. "/apps/bateria/" .. f))
    local src = fh:read("*a"); fh:close()
    for mod in src:gmatch('require%(%s*"([^"]+)"%s*%)') do
        if not pure[mod] then bad[#bad + 1] = f .. ":" .. mod end
    end
end
T.eq("R-A1: logic, csvlog, chart and view require only the app's pure modules", table.concat(bad, ","), "")
