-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (C) 2026 Tinta contributors
-- Core texts in pt and en (spec 13). Default language pt (D7). Pure Lua (R-A1).
-- Every key exists in both languages with the same format specifiers (tested). Apps keep their own tables and
-- get a translator with I18n.new(strings) that follows the Tinta language; ui/ can add keys with I18n.extend.
local M = {}

M.DEFAULT_LANG = "pt"
M.LANGS = { "pt", "en" }

M.STRINGS = {
    pt = {
        -- time and intervals (format.lua)
        ago_now = "agora",
        ago_min = "há %d min",
        ago_h = "há %d h",
        ago_d = "há %d d",
        every_manual = "manual",
        every_s = "a cada %d s",
        every_min = "a cada %d min",
        every_h = "a cada %d h",
        window_weekdays = "dias úteis %s–%s",
        window_all = "%s–%s",
        -- widget footer and app header (R-W4, 6.4, R-S5, R-E4)
        busy = "atualizando…",
        no_response = "sem resposta",
        resume_at = "volta %s",
        paused_until = "pausado até %s",
        app_error = "erro na app",
        stale_header = "sem resposta · último dado %s",
        footer_settings = "configurações",
        widget_error = "%s · erro na app",
        screen_error = "A tela de %s falhou",
        -- settings (R-C2)
        token_set = "definido",
        token_unset = "não definido",
        bool_on = "ligado",
        bool_off = "desligado",
        -- notifications (8)
        prio_alta = "alta",
        prio_normal = "normal",
        pref_alta = "alta",
        pref_normal = "normal",
        pref_desligada = "desligada",
        sleep_shows_alta = "só alta",
        sleep_shows_todas = "todas",
        sleep_shows_nenhuma = "nenhuma",
        sleep_banner_one = "1 não lida: %s",
        sleep_banner_many = "%d não lidas · %s",
        sleep_banner_one_hidden = "1 não lida",
        sleep_banner_many_hidden = "%d não lidas",
        notif_unread_one = "1 nova",
        notif_unread_many = "%d novas",
        notif_none_new = "nada novo",
        notif_empty = "sem notificações",
        notif_total = "%d no total",
        mark_all_read = "Marcar todas como lidas",
        clear_all = "Limpar",
        clear_confirm_title = "Limpar notificações",
        clear_confirm_text = "Apagar todas as notificações?",
        log_notify_off = "notificação descartada (desligada) · %s · %s",
        log_notify_dup = "notificação repetida, ignorada · %s · %s",
        log_notify_first = "primeira leitura, sem notificação · %s · %s",
        log_notify_new = "notificação %s · %s · %s",
        -- Sistema server rules (8.6)
        source_down_title = "%s sem resposta",
        source_down_body = "%s não respondeu às 2 últimas atualizações",
        source_up_title = "%s voltou",
        source_up_body = "%s respondeu de novo",
        conn_ok = "ok %s · %d ms",
        conn_down = "sem resposta desde %s · último ok %s",
        -- toasts (R-K2)
        toast_updated = "Atualizado",
        toast_no_wifi = "Sem Wi-Fi: mostrando o último dado",
        toast_no_response = "%s sem resposta: mantive o último dado",
        toast_system_hidden = "Sistema continua no Menu",
        -- sleep (R-S4, R-P5)
        sleep_bar = "Repouso · atualizado %s · próxima %s",
        sleep_bar_no_next = "Repouso · atualizado %s",
        sleep_footer = "Em repouso. Aperte o botão de energia para usar a Tinta.",
        -- navigation, menu, dialogs (6.3, 6.5, 6.9)
        nav_home = "Início",
        nav_back = "Voltar",
        nav_refresh = "Atualizar",
        nav_menu = "Menu",
        cancel = "Cancelar",
        done = "Pronto",
        menu_refresh_app = "Atualizar %s agora",
        menu_interval_app = "Intervalo desta app: %s",
        menu_organize = "Organizar o início",
        menu_refresh_all = "Atualizar todas as apps",
        menu_central = "Central de notificações",
        menu_system = "Abrir Sistema",
        menu_sleep_now = "Entrar em repouso agora",
        -- organizer (7.3)
        org_tab_home = "Início",
        org_tab_sleep = "Repouso",
        org_before = "↑ Antes",
        org_after = "↓ Depois",
        org_size = "Tamanho ▸",
        org_hide = "Ocultar",
        org_remove = "Tirar",
        org_hidden = "Ocultas:",
        org_add = "Adicionar:",
        -- pager (6.6)
        pager = "%d/%d",
        -- languages
        lang_pt = "Português",
        lang_en = "English",
    },
    en = {
        ago_now = "now",
        ago_min = "%d min ago",
        ago_h = "%d h ago",
        ago_d = "%d d ago",
        every_manual = "manual",
        every_s = "every %d s",
        every_min = "every %d min",
        every_h = "every %d h",
        window_weekdays = "weekdays %s–%s",
        window_all = "%s–%s",
        busy = "updating…",
        no_response = "no response",
        resume_at = "back %s",
        paused_until = "paused until %s",
        app_error = "app error",
        stale_header = "no response · last data %s",
        footer_settings = "settings",
        widget_error = "%s · app error",
        screen_error = "The %s screen failed",
        token_set = "set",
        token_unset = "not set",
        bool_on = "on",
        bool_off = "off",
        prio_alta = "high",
        prio_normal = "normal",
        pref_alta = "high",
        pref_normal = "normal",
        pref_desligada = "off",
        sleep_shows_alta = "high only",
        sleep_shows_todas = "all",
        sleep_shows_nenhuma = "none",
        sleep_banner_one = "1 unread: %s",
        sleep_banner_many = "%d unread · %s",
        sleep_banner_one_hidden = "1 unread",
        sleep_banner_many_hidden = "%d unread",
        notif_unread_one = "1 new",
        notif_unread_many = "%d new",
        notif_none_new = "nothing new",
        notif_empty = "no notifications",
        notif_total = "%d in total",
        mark_all_read = "Mark all as read",
        clear_all = "Clear",
        clear_confirm_title = "Clear notifications",
        clear_confirm_text = "Delete all notifications?",
        log_notify_off = "notification dropped (off) · %s · %s",
        log_notify_dup = "repeated notification, ignored · %s · %s",
        log_notify_first = "first read, no notification · %s · %s",
        log_notify_new = "notification %s · %s · %s",
        source_down_title = "%s not responding",
        source_down_body = "%s did not answer the last 2 updates",
        source_up_title = "%s is back",
        source_up_body = "%s answered again",
        conn_ok = "ok %s · %d ms",
        conn_down = "no response since %s · last ok %s",
        toast_updated = "Updated",
        toast_no_wifi = "No Wi-Fi: showing the last data",
        toast_no_response = "%s not responding: kept the last data",
        toast_system_hidden = "System is still in the Menu",
        sleep_bar = "Sleep · updated %s · next %s",
        sleep_bar_no_next = "Sleep · updated %s",
        sleep_footer = "Sleeping. Press the power button to use the tinta.",
        nav_home = "Home",
        nav_back = "Back",
        nav_refresh = "Refresh",
        nav_menu = "Menu",
        cancel = "Cancel",
        done = "Done",
        menu_refresh_app = "Refresh %s now",
        menu_interval_app = "This app's interval: %s",
        menu_organize = "Organize home",
        menu_refresh_all = "Refresh all apps",
        menu_central = "Notification center",
        menu_system = "Open System",
        menu_sleep_now = "Sleep now",
        org_tab_home = "Home",
        org_tab_sleep = "Sleep",
        org_before = "↑ Before",
        org_after = "↓ After",
        org_size = "Size ▸",
        org_hide = "Hide",
        org_remove = "Remove",
        org_hidden = "Hidden:",
        org_add = "Add:",
        pager = "%d/%d",
        lang_pt = "Português",
        lang_en = "English",
    },
}

local current = M.DEFAULT_LANG

function M.normalize_lang(lang)
    for _, l in ipairs(M.LANGS) do if l == lang then return l end end
    return M.DEFAULT_LANG
end

function M.set_lang(lang) current = M.normalize_lang(lang) end
function M.get_lang() return current end

-- Translate with an explicit table set: strings[lang][key], falling back to the default language and then to
-- the key itself. Extra arguments go to string.format; a format error returns the raw text (never throws).
local function translate(strings, key, ...)
    local s = (strings[current] and strings[current][key]) or (strings[M.DEFAULT_LANG] and strings[M.DEFAULT_LANG][key])
    if s == nil then return key end
    if select("#", ...) == 0 then return s end
    local ok, out = pcall(string.format, s, ...)
    return ok and out or s
end

function M.t(key, ...) return translate(M.STRINGS, key, ...) end

-- Adds keys to the core tables (for ui/): extra = { pt = {...}, en = {...} }. Existing keys are not replaced.
function M.extend(extra)
    for lang, tbl in pairs(extra or {}) do
        M.STRINGS[lang] = M.STRINGS[lang] or {}
        for k, v in pairs(tbl) do
            if M.STRINGS[lang][k] == nil then M.STRINGS[lang][k] = v end
        end
    end
end

-- Translator for an app (ctx.i18n): follows the Tinta language. Missing keys fall back to the core tables.
function M.new(strings)
    strings = strings or {}
    local tr = { strings = strings }
    function tr.t(key, ...)
        local s = (strings[current] and strings[current][key]) or (strings[M.DEFAULT_LANG] and strings[M.DEFAULT_LANG][key])
        if s == nil then return M.t(key, ...) end
        return translate(strings, key, ...)
    end
    function tr.lang() return current end
    return tr
end

-- Checks a string table pair the way the test suite does (same keys, same specifiers, no empty strings).
-- Returns a list of problems (empty when fine). Apps' tests can call this on their own tables.
function M.check_tables(strings)
    local problems = {}
    local function specs(s) local o = {} for f in s:gmatch("%%[%-%d%.]*[dsfxq%%]") do o[#o + 1] = f end return table.concat(o, " ") end
    for _, a in ipairs(M.LANGS) do
        for _, b in ipairs(M.LANGS) do
            if a ~= b then
                for k in pairs(strings[a] or {}) do
                    if (strings[b] or {})[k] == nil then problems[#problems + 1] = "missing " .. b .. "." .. k end
                end
            end
        end
    end
    for k, v in pairs(strings[M.LANGS[1]] or {}) do
        local w = (strings[M.LANGS[2]] or {})[k]
        if v == "" or w == "" then problems[#problems + 1] = "empty " .. k end
        if w and specs(v) ~= specs(w) then problems[#problems + 1] = "specifiers " .. k end
    end
    table.sort(problems)
    return problems
end

return M
