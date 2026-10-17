-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (C) 2026 Tinta contributors
-- luajit -bl on every file of the app (15.1), and R-A1: logic and strings require no KOReader module
local T = ...
local exe = arg and arg[-1] or "luajit"
for _, f in ipairs({ "init.lua", "logic.lua", "view.lua", "strings.lua" }) do
    local ok = os.execute(exe .. ' -bl "' .. T.plugin .. "/apps/repouso/" .. f .. '" > /dev/null 2>&1')
    T.check("syntax: apps/repouso/" .. f, ok == 0 or ok == true)
end
local bad = {}
for _, f in ipairs({ "logic.lua", "strings.lua" }) do
    local fh = assert(io.open(T.plugin .. "/apps/repouso/" .. f))
    local src = fh:read("*a"); fh:close()
    for mod in src:gmatch('require%(%s*"([^"]+)"%s*%)') do bad[#bad + 1] = f .. ":" .. mod end
end
T.eq("R-A1: logic and strings require nothing", table.concat(bad, ","), "")
