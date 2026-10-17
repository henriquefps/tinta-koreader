-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (C) 2026 Tinta contributors
-- same keys and specifiers in pt and en, every key the code uses exists, syntax and R-A1
local T = ...
local I18n = require("core/i18n")
local Strings = require("apps/_exemplo_clima/strings")
T.eq("strings: check_tables", table.concat(I18n.check_tables(Strings), ", "), "")
local unknown = {}
for _, f in ipairs({ "init.lua", "logic.lua", "view.lua" }) do
    local fh = assert(io.open(T.plugin .. "/apps/_exemplo_clima/" .. f, "r"))
    local src = fh:read("*a"); fh:close()
    for _, pat in ipairs({ 'L%("([%w_]+)"', 'i18n%.t%("([%w_]+)"', '%f[%w_]t%("([%w_]+)"' }) do
        for k in src:gmatch(pat) do if not k:find("_$") and not Strings.pt[k] then unknown[#unknown + 1] = f .. ":" .. k end end
    end
end
T.eq("strings: every key used exists", table.concat(unknown, ","), "")
-- the weather kinds build their key at run time ("w_" .. kind): each kind must have its text
local Logic = require("apps/_exemplo_clima/logic")
local missing = {}
for _, code in ipairs({ 0, 2, 3, 45, 53, 63, 73, 81, 95, 1234 }) do
    if not Strings.pt["w_" .. Logic.kind(code)] or not Strings.en["w_" .. Logic.kind(code)] then missing[#missing + 1] = code end
end
T.eq("strings: every weather kind has a text", table.concat(missing, ","), "")
local exe = arg and arg[-1] or "luajit"
for _, f in ipairs({ "init.lua", "logic.lua", "view.lua", "strings.lua" }) do
    local ok = os.execute(exe .. ' -bl "' .. T.plugin .. "/apps/_exemplo_clima/" .. f .. '" > /dev/null 2>&1')
    T.check("syntax: apps/_exemplo_clima/" .. f, ok == 0 or ok == true)
end
local bad = {}
for _, f in ipairs({ "logic.lua", "strings.lua" }) do
    local fh = assert(io.open(T.plugin .. "/apps/_exemplo_clima/" .. f))
    local src = fh:read("*a"); fh:close()
    for mod in src:gmatch('require%(%s*"([^"]+)"%s*%)') do bad[#bad + 1] = f .. ":" .. mod end
end
T.eq("R-A1: logic.lua and strings.lua require nothing", table.concat(bad, ","), "")
