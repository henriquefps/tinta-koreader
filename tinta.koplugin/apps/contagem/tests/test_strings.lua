-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (C) 2026 Tinta contributors
local T = ...
local I18n = require("core/i18n")
local Strings = require("apps/contagem/strings")
T.eq("strings: check_tables", table.concat(I18n.check_tables(Strings), ", "), "")
local unknown = {}
local keys_variable = { err_name_empty = 1, err_name_too_long = 1, err_date_format = 1, err_date_range = 1, err_full = 1, err_missing = 1 }
for _, f in ipairs({ "init.lua", "logic.lua", "view.lua" }) do
    local fh = assert(io.open(T.plugin .. "/apps/contagem/" .. f, "r"))
    local src = fh:read("*a"); fh:close()
    for _, pat in ipairs({ 'L%("([%w_]+)"[,)]', 'i18n%.t%("([%w_]+)"[,)]', '%f[%w_]t%("([%w_]+)"[,)]', 'L%(d%.kind == "past" and "([%w_]+)" or "([%w_]+)"',
            'L%(draft%.idx and "([%w_]+)" or "([%w_]+)"', 'n == 1 and "([%w_]+)" or "([%w_]+)"' }) do
        for a, b in src:gmatch(pat) do
            for _, k in ipairs({ a, b }) do if not Strings.pt[k] then unknown[#unknown + 1] = f .. ":" .. k end end
        end
    end
end
T.eq("strings: every key used exists", table.concat(unknown, ","), "")
for k in pairs(keys_variable) do T.check("strings: " .. k .. " (built from a reason) exists in both", Strings.pt[k] and Strings.en[k]) end
local exe = arg and arg[-1] or "luajit"
for _, f in ipairs({ "init.lua", "logic.lua", "view.lua", "strings.lua" }) do
    local ok = os.execute(exe .. ' -bl "' .. T.plugin .. "/apps/contagem/" .. f .. '" > /dev/null 2>&1')
    T.check("syntax: apps/contagem/" .. f, ok == 0 or ok == true)
end
local bad = {}
for _, f in ipairs({ "logic.lua", "strings.lua" }) do
    local fh = assert(io.open(T.plugin .. "/apps/contagem/" .. f))
    local src = fh:read("*a"); fh:close()
    for mod in src:gmatch('require%(%s*"([^"]+)"%s*%)') do bad[#bad + 1] = f .. ":" .. mod end
end
T.eq("R-A1: logic.lua and strings.lua require nothing", table.concat(bad, ","), "")
