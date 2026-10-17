-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (C) 2026 Tinta contributors
-- section 13: same keys and specifiers in pt and en, no empty strings; every key the code uses exists
local T = ...
local check, eq = T.check, T.eq
local I18n = require("core/i18n")
local Strings = require("apps/relogio/strings")

eq("strings: check_tables", table.concat(I18n.check_tables(Strings), ", "), "")
local unknown = {}
for _, f in ipairs({ "init.lua", "logic.lua", "view.lua" }) do
    local fh = assert(io.open(T.plugin .. "/apps/relogio/" .. f, "r"))
    local src = fh:read("*a")
    fh:close()
    for k in src:gmatch('L%("([%w_]+)"[,)]') do if not Strings.pt[k] then unknown[#unknown + 1] = f .. ":" .. k end end
    for k in src:gmatch('i18n%.t%("([%w_]+)"[,)]') do if not Strings.pt[k] then unknown[#unknown + 1] = f .. ":" .. k end end
end
eq("strings: every key used exists", table.concat(unknown, ","), "")
for _, s in ipairs(require("apps/relogio/logic").STYLES) do
    check("strings: style " .. s, Strings.pt["style_" .. s] and Strings.pt["style_" .. s .. "_sub"] and Strings.en["style_" .. s])
end
for i = 1, 7 do check("strings: weekday " .. i, Strings.pt["wd" .. i] and Strings.en["wd" .. i]) end
for i = 1, 12 do check("strings: month " .. i, Strings.pt["mo" .. i] and Strings.en["mo" .. i]) end
local tr = I18n.new(Strings)
I18n.set_lang("en")
eq("i18n en name", tr.t("name"), "Clock")
I18n.set_lang("pt")
eq("i18n pt name", tr.t("name"), "Relógio")
