-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (C) 2026 Tinta contributors
-- luajit -bl on every file of the app (15.1), and R-A1: logic, face and strings require no KOReader module
local T = ...
local exe = arg and arg[-1] or "luajit"
for _, f in ipairs({ "init.lua", "logic.lua", "face.lua", "view.lua", "strings.lua" }) do
    local ok = os.execute(exe .. ' -bl "' .. T.plugin .. "/apps/relogio/" .. f .. '" > /dev/null 2>&1')
    T.check("syntax: apps/relogio/" .. f, ok == 0 or ok == true)
end
local pure = { ["apps/relogio/logic"] = true, ["apps/relogio/strings"] = true, ["ui/shapes"] = true }
local bad = {}
for _, f in ipairs({ "logic.lua", "face.lua", "strings.lua" }) do
    local fh = assert(io.open(T.plugin .. "/apps/relogio/" .. f))
    local src = fh:read("*a"); fh:close()
    for mod in src:gmatch('require%(%s*"([^"]+)"%s*%)') do
        if not pure[mod] then bad[#bad + 1] = f .. ":" .. mod end
    end
end
T.eq("R-A1: logic, face and strings require only pure modules", table.concat(bad, ","), "")
