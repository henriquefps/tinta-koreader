-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (C) 2026 Tinta contributors
local T = ...
local I18n = require("core/i18n")
local eq, check, same = T.eq, T.check, T.same

eq("i18n: default lang pt (D7)", I18n.get_lang(), "pt")
eq("i18n: DEFAULT_LANG", I18n.DEFAULT_LANG, "pt")
eq("i18n: default text pt", I18n.t("busy"), "atualizando…")

-- every key in both languages, same specifiers, no empty strings (spec 13)
same("i18n: core tables consistent", I18n.check_tables(I18n.STRINGS), {})
local n = 0
for _ in pairs(I18n.STRINGS.pt) do n = n + 1 end
check("i18n: has keys", n > 60, n)

-- every I18n.t("key") / T("key") used in core/ exists
do
    local unknown = {}
    for _, f in ipairs({ "format", "registry", "notify", "power", "settings", "scheduler", "layout", "store" }) do
        local fh = io.open(T.here .. "/../core/" .. f .. ".lua")
        local src = fh:read("*a"); fh:close()
        for key in src:gmatch("I18n%.t%(\"([%w_]+)\"") do if not I18n.STRINGS.pt[key] then unknown[#unknown + 1] = key end end
        for key in src:gmatch("[^%w_]T%(\"([%w_]+)\"") do if not I18n.STRINGS.pt[key] then unknown[#unknown + 1] = key end end
    end
    eq("i18n: every key used in core exists", table.concat(unknown, ","), "")
end

eq("i18n: normalize pt", I18n.normalize_lang("pt"), "pt")
eq("i18n: normalize en", I18n.normalize_lang("en"), "en")
eq("i18n: normalize junk -> pt", I18n.normalize_lang("fr"), "pt")
eq("i18n: normalize nil -> pt", I18n.normalize_lang(nil), "pt")
eq("i18n: format args", I18n.t("ago_min", 3), "há 3 min")
eq("i18n: unknown key -> key", I18n.t("zzz_nope"), "zzz_nope")
eq("i18n: bad format args do not throw", I18n.t("ago_min", "x"), "há %d min")
I18n.set_lang("en")
eq("i18n: en", I18n.t("ago_min", 3), "3 min ago")
I18n.set_lang("xx")
eq("i18n: set invalid -> pt", I18n.get_lang(), "pt")

-- app translators
local tr = I18n.new({ pt = { hello = "olá %s" }, en = { hello = "hello %s" } })
eq("i18n: app key pt", tr.t("hello", "Ana"), "olá Ana")
eq("i18n: app falls back to core", tr.t("busy"), "atualizando…")
I18n.set_lang("en")
eq("i18n: app follows tinta lang", tr.t("hello", "Ana"), "hello Ana")
eq("i18n: app lang()", tr.lang(), "en")
local tr2 = I18n.new({ pt = { only_pt = "só pt" } })
eq("i18n: app missing in en -> pt", tr2.t("only_pt"), "só pt")
I18n.set_lang("pt")

-- check_tables finds problems
local probs = I18n.check_tables({ pt = { a = "%d x", b = "", c = "y" }, en = { a = "%s x", b = "b" } })
same("i18n: check_tables problems", probs, { "empty b", "missing en.c", "specifiers a" })

-- extend does not overwrite
I18n.extend({ pt = { busy = "OUTRO", ui_extra = "extra" }, en = { ui_extra = "extra en" } })
eq("i18n: extend keeps existing", I18n.t("busy"), "atualizando…")
eq("i18n: extend adds", I18n.t("ui_extra"), "extra")
I18n.STRINGS.pt.ui_extra, I18n.STRINGS.en.ui_extra = nil, nil
