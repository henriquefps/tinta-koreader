-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (C) 2026 Tinta contributors
-- section 13: same keys and specifiers in pt and en, no empty strings; every key the code uses exists
local T = ...
local check, eq = T.check, T.eq
local I18n = require("core/i18n")
local Strings = require("apps/bateria/strings")

eq("strings: check_tables", table.concat(I18n.check_tables(Strings), ", "), "")
local unknown = {}
for _, f in ipairs({ "init.lua", "logic.lua", "view.lua" }) do
    local fh = assert(io.open(T.plugin .. "/apps/bateria/" .. f, "r"))
    local src = fh:read("*a")
    fh:close()
    for k in src:gmatch('L%("([%w_]+)"') do if not Strings.pt[k] then unknown[#unknown + 1] = f .. ":" .. k end end
    for k in src:gmatch('i18n%.t%("([%w_]+)"') do if not Strings.pt[k] then unknown[#unknown + 1] = f .. ":" .. k end end
    for k in src:gmatch('L%(%s*[%w_.]+%s*and%s*"([%w_]+)"%s*or%s*"([%w_]+)"') do
        if not Strings.pt[k] then unknown[#unknown + 1] = f .. ":" .. k end
    end
end
eq("strings: every key used exists", table.concat(unknown, ","), "")
-- translated through core like ctx.i18n does
local tr = I18n.new(Strings)
I18n.set_lang("pt")
eq("i18n pt", tr.t("charging_eta", "~40min"), "⚡ carregando · ~40min até 100%")
I18n.set_lang("en")
eq("i18n en", tr.t("charging_eta", "~40min"), "⚡ charging · ~40min to 100%")
eq("i18n en name", tr.t("name"), "Battery")
I18n.set_lang("pt")
check("i18n: back to pt", tr.t("name") == "Bateria")
