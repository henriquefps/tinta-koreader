-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (C) 2026 Tinta contributors
-- same keys and specifiers in pt and en, every key the code uses exists, syntax and R-A1
local T = ...
local I18n = require("core/i18n")
local Strings = require("apps/timer/strings")
T.eq("strings: check_tables", table.concat(I18n.check_tables(Strings), ", "), "")
local unknown = {}
for _, f in ipairs({ "init.lua", "logic.lua", "view.lua" }) do
    local fh = assert(io.open(T.plugin .. "/apps/timer/" .. f, "r"))
    local src = fh:read("*a"); fh:close()
    for _, pat in ipairs({ 'L%("([%w_]+)"', 'i18n%.t%("([%w_]+)"', '%f[%w_]t%("([%w_]+)"', '%f[%w_]tt%("([%w_]+)"' }) do
        for k in src:gmatch(pat) do if not Strings.pt[k] then unknown[#unknown + 1] = f .. ":" .. k end end
    end
    for k in src:gmatch('t%(st%.kind == "break" and "([%w_]+)" or "([%w_]+)"') do
        if not Strings.pt[k] then unknown[#unknown + 1] = f .. ":" .. k end
    end
end
T.eq("strings: every key used exists", table.concat(unknown, ","), "")
T.eq("strings: the notification is the one of the spec", Strings.pt.n_done_title, "Tempo esgotado")
local exe = arg and arg[-1] or "luajit"
for _, f in ipairs({ "init.lua", "logic.lua", "view.lua", "strings.lua" }) do
    local ok = os.execute(exe .. ' -bl "' .. T.plugin .. "/apps/timer/" .. f .. '" > /dev/null 2>&1')
    T.check("syntax: apps/timer/" .. f, ok == 0 or ok == true)
end
local bad = {}
for _, f in ipairs({ "logic.lua", "strings.lua" }) do
    local fh = assert(io.open(T.plugin .. "/apps/timer/" .. f))
    local src = fh:read("*a"); fh:close()
    for mod in src:gmatch('require%(%s*"([^"]+)"%s*%)') do bad[#bad + 1] = f .. ":" .. mod end
end
T.eq("R-A1: logic.lua and strings.lua require nothing", table.concat(bad, ","), "")
