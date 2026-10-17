-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (C) 2026 Tinta contributors
-- same keys and specifiers in pt and en, every key the code uses exists, syntax and R-A1
local T = ...
local I18n = require("core/i18n")
local Strings = require("apps/_exemplo_json/strings")
T.eq("strings: check_tables", table.concat(I18n.check_tables(Strings), ", "), "")
local unknown = {}
for _, f in ipairs({ "init.lua", "logic.lua", "view.lua" }) do
    local fh = assert(io.open(T.plugin .. "/apps/_exemplo_json/" .. f, "r"))
    local src = fh:read("*a"); fh:close()
    for _, pat in ipairs({ 'L%("([%w_]+)"', 'i18n%.t%("([%w_]+)"', '%f[%w_]t%("([%w_]+)"' }) do
        for k in src:gmatch(pat) do if not Strings.pt[k] then unknown[#unknown + 1] = f .. ":" .. k end end
    end
end
T.eq("strings: every key used exists", table.concat(unknown, ","), "")
local exe = arg and arg[-1] or "luajit"
for _, f in ipairs({ "init.lua", "logic.lua", "view.lua", "strings.lua" }) do
    local ok = os.execute(exe .. ' -bl "' .. T.plugin .. "/apps/_exemplo_json/" .. f .. '" > /dev/null 2>&1')
    T.check("syntax: apps/_exemplo_json/" .. f, ok == 0 or ok == true)
end
local bad = {}
for _, f in ipairs({ "logic.lua", "strings.lua" }) do
    local fh = assert(io.open(T.plugin .. "/apps/_exemplo_json/" .. f))
    local src = fh:read("*a"); fh:close()
    for mod in src:gmatch('require%(%s*"([^"]+)"%s*%)') do bad[#bad + 1] = f .. ":" .. mod end
end
T.eq("R-A1: logic.lua and strings.lua require nothing", table.concat(bad, ","), "")
