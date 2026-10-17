-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (C) 2026 Tinta contributors
-- Tinta: texts of the interface (ui/ and the system apps' shared parts), pt (default, D7) and en. Pure.
-- Same keys and same format specifiers in both languages (tests/tinta_ui_test.lua checks it).
local M = {}

M.LANGS = { "pt", "en" }

M.pt = {
    -- navigation bar (R-N1)
    nav_home = "Início",
    nav_back = "Voltar",
    nav_refresh = "Atualizar",
    nav_menu = "Menu",

    -- menu sheet (6.5)
    menu_apps = "Apps",
    launcher_title = "Apps",
    launcher_meta = "%d apps",
    launcher_mark_home = "no Início",
    launcher_mark_hidden = "oculta",
    launcher_added = "%s adicionada ao Início",
    launcher_already = "%s já está no Início",
    launcher_off = "desativada",
    launcher_turn_on = "Ativar",
    launcher_on = "%s ativada",
    launcher_on_failed = "Não foi possível ativar %s",
    menu_title_home = "Menu · Início",
    menu_title_app = "Menu · %s",
    menu_refresh_app = "Atualizar %s agora",
    menu_interval = "Intervalo desta app",
    menu_organize = "Organizar o início",
    menu_refresh_all = "Atualizar todas as apps",
    menu_central = "Central de notificações",
    menu_system = "Abrir Sistema",

    -- toasts (R-K2)
    toast_updated = "Atualizado",
    toast_no_wifi = "Sem Wi-Fi: mostrando o último dado",
    toast_server_down = "Servidor sem resposta: mantive o último dado",
    toast_app_error = "Erro na app %s",
    toast_system_in_menu = "Sistema continua no Menu",
    toast_sleep_later = "Repouso ainda não disponível nesta versão",
    toast_wifi_on = "Ligando o Wi-Fi…",
    toast_wifi_off = "Wi-Fi desligado",
    toast_nothing = "Nada para atualizar",

    -- dialogs (R-K1)
    btn_cancel = "Cancelar",
    btn_ok = "OK",
    btn_back = "Voltar",

    -- errors (R-E2)
    widget_error = "%s · erro na app",
    screen_error_title = "Erro na app",
    screen_error_text = "A tela \"%s\" de %s falhou. A Tinta continua funcionando; o erro foi para o log da Tinta.",
    app_missing = "App não encontrada: %s",

    -- home and sleep page
    home_empty = "Nenhum widget no Início. Menu → Organizar o início.",
    sleep_footer = "Em repouso. Aperte o botão de energia para usar a Tinta.",
    sleep_status = "Repouso · atualizado %s · próxima %s",
    sleep_widget_updated = "atualizado %s",

    -- first-run wizard (7.5)
    wz_title = "Primeiro uso",
    wz_step = "%d de %d",
    wz_next = "Próximo",
    wz_back = "Anterior",
    wz_skip = "Pular tudo",
    wz_finish = "Concluir",
    wz_welcome_text = "Bem-vindo à Tinta. Vamos configurar o essencial em poucos passos; dá para pular qualquer um e mudar tudo depois em Sistema.",
    wz_lang = "Idioma",
    wz_wifi_text = "O Wi-Fi atualiza os widgets e as notificações.",
    wz_wifi_state_on = "Wi-Fi ligado",
    wz_wifi_state_connecting = "Wi-Fi conectando…",
    wz_wifi_state_off = "Wi-Fi desligado",
    wz_wifi_turn_on = "Ligar o Wi-Fi",
    wz_wifi_turn_off = "Desligar",
    wz_apps_text = "Quais apps ficam no Início? Apps que usam um servidor pedem o endereço depois, em Sistema → Apps.",
    wz_app_on = "no Início",
    wz_app_off = "fora",
    wz_sleep_text = "Como o aparelho descansa e atualiza a tela.",
    wz_idle = "Dormir sozinho",
    wz_idle_always = "sempre",
    wz_idle_battery = "só na bateria",
    wz_idle_never = "nunca",
    wz_wake = "Atualizar a tela",
    wz_wake_900 = "a cada 15 min",
    wz_wake_1800 = "a cada 30 min",
    wz_wake_3600 = "a cada 1 h",
    wz_wake_7200 = "a cada 2 h",
    wz_wake_schedule = "pelo horário",
    wz_wake_never = "nunca",
    wz_done_toast = "Pronto. Tudo isso fica em Sistema.",

    -- central (8.3)
    central_title = "Central",
    central_unread = "%d não lidas",
    qt_wifi = "Wi-Fi",
    qt_on = "ligado",
    qt_off = "desligado",
    menu_sleep = "Dormir agora",
    qt_sleep = "Repouso",
    qt_sleep_sub = "agora",
    qt_rotate = "Girar",
    qt_portrait = "retrato",
    qt_landscape = "paisagem",
    qt_system = "Sistema",
    qt_system_sub = "ajustes",
    central_empty = "Nenhuma notificação.",
    central_high = " · alta",
    central_read_all = "Marcar todas como lidas",
    central_clear = "Limpar",
    confirm_clear_title = "Limpar as notificações?",
    confirm_clear_text = "Apaga as %d notificações, lidas e não lidas.",
    confirm_clear_ok = "Limpar",

    -- notification widget (10.4)
    notif_new_one = "1 nova",
    notif_new_many = "%d novas",
    notif_nothing = "nada novo",
    notif_none = "sem notificações",
    notif_total = "%d no total",
    notif_none_yet = "Nenhuma notificação ainda.",

    -- organizer (7.3)
    org_title = "Organizar",
    org_tab_home = "Início",
    org_tab_sleep = "Repouso",
    org_page = "página %d/%d",
    org_one_page = "1 página",
    org_before = "↑ Antes",
    org_after = "↓ Depois",
    org_size = "Tamanho ▸",
    org_hide = "Ocultar",
    org_remove = "Tirar",
    org_done = "Pronto",
    org_hidden = "Ocultas:",
    org_add = "Adicionar:",
    org_none_hidden = "Nenhuma app oculta.",
    org_info_page = "%s · %s · pág. %d",
    org_sleep_extra = "só a pág. 1 vai para o repouso",
    org_copy = "Copiar do Início",
    org_copy_title = "Copiar do Início?",
    org_copy_text = "Troca o layout do repouso pelos widgets, tamanhos e ordem da página 1 do Início (sem o Sistema).",
    org_copy_ok = "Copiar",
    toast_copied = "Repouso igual à página 1 do Início",
    org_none_add = "Nenhuma app para adicionar.",
    org_no_widget = "Nenhum widget",

}

M.en = {
    nav_home = "Home",
    nav_back = "Back",
    nav_refresh = "Refresh",
    nav_menu = "Menu",

    menu_apps = "Apps",
    launcher_title = "Apps",
    launcher_meta = "%d apps",
    launcher_mark_home = "on Home",
    launcher_mark_hidden = "hidden",
    launcher_added = "%s added to Home",
    launcher_already = "%s is already on Home",
    launcher_off = "turned off",
    launcher_turn_on = "Turn on",
    launcher_on = "%s turned on",
    launcher_on_failed = "Could not turn %s on",
    menu_title_home = "Menu · Home",
    menu_title_app = "Menu · %s",
    menu_refresh_app = "Refresh %s now",
    menu_interval = "Interval of this app",
    menu_organize = "Organize home",
    menu_refresh_all = "Refresh all apps",
    menu_central = "Notification center",
    menu_system = "Open System",

    toast_updated = "Updated",
    toast_no_wifi = "No Wi-Fi: showing the last data",
    toast_server_down = "Server not responding: kept the last data",
    toast_app_error = "App error: %s",
    toast_system_in_menu = "System is still in the Menu",
    toast_sleep_later = "Sleep mode is not available in this version yet",
    toast_wifi_on = "Turning Wi-Fi on…",
    toast_wifi_off = "Wi-Fi off",
    toast_nothing = "Nothing to refresh",

    btn_cancel = "Cancel",
    btn_ok = "OK",
    btn_back = "Back",

    widget_error = "%s · app error",
    screen_error_title = "App error",
    screen_error_text = "The \"%s\" screen of %s failed. Tinta keeps working; the error went to the Tinta log.",
    app_missing = "App not found: %s",

    home_empty = "No widgets on Home. Menu → Organize home.",
    sleep_footer = "Sleeping. Press the power button to use the tinta.",
    sleep_status = "Sleep · updated %s · next %s",
    sleep_widget_updated = "updated %s",

    -- first-run wizard (7.5)
    wz_title = "First use",
    wz_step = "%d of %d",
    wz_next = "Next",
    wz_back = "Previous",
    wz_skip = "Skip all",
    wz_finish = "Finish",
    wz_welcome_text = "Welcome to Tinta. Let's set up the essentials in a few steps; you can skip any of them and change everything later in Sistema.",
    wz_lang = "Language",
    wz_wifi_text = "Wi-Fi updates the widgets and the notifications.",
    wz_wifi_state_on = "Wi-Fi on",
    wz_wifi_state_connecting = "Wi-Fi connecting…",
    wz_wifi_state_off = "Wi-Fi off",
    wz_wifi_turn_on = "Turn Wi-Fi on",
    wz_wifi_turn_off = "Turn off",
    wz_apps_text = "Which apps go on Home? Apps that use a server ask for its address later, in Sistema → Apps.",
    wz_app_on = "on Home",
    wz_app_off = "off",
    wz_sleep_text = "How the device rests and refreshes the screen.",
    wz_idle = "Sleep by itself",
    wz_idle_always = "always",
    wz_idle_battery = "on battery only",
    wz_idle_never = "never",
    wz_wake = "Refresh the screen",
    wz_wake_900 = "every 15 min",
    wz_wake_1800 = "every 30 min",
    wz_wake_3600 = "every 1 h",
    wz_wake_7200 = "every 2 h",
    wz_wake_schedule = "by schedule",
    wz_wake_never = "never",
    wz_done_toast = "Done. All of this is in Sistema.",

    central_title = "Center",
    central_unread = "%d unread",
    qt_wifi = "Wi-Fi",
    qt_on = "on",
    qt_off = "off",
    menu_sleep = "Sleep now",
    qt_sleep = "Sleep",
    qt_sleep_sub = "now",
    qt_rotate = "Rotate",
    qt_portrait = "portrait",
    qt_landscape = "landscape",
    qt_system = "System",
    qt_system_sub = "settings",
    central_empty = "No notifications.",
    central_high = " · high",
    central_read_all = "Mark all as read",
    central_clear = "Clear",
    confirm_clear_title = "Clear the notifications?",
    confirm_clear_text = "Deletes the %d notifications, read and unread.",
    confirm_clear_ok = "Clear",

    notif_new_one = "1 new",
    notif_new_many = "%d new",
    notif_nothing = "nothing new",
    notif_none = "no notifications",
    notif_total = "%d in total",
    notif_none_yet = "No notifications yet.",

    org_title = "Organize",
    org_tab_home = "Home",
    org_tab_sleep = "Sleep",
    org_page = "page %d/%d",
    org_one_page = "1 page",
    org_before = "↑ Before",
    org_after = "↓ After",
    org_size = "Size ▸",
    org_hide = "Hide",
    org_remove = "Remove",
    org_done = "Done",
    org_hidden = "Hidden:",
    org_add = "Add:",
    org_none_hidden = "No hidden apps.",
    org_info_page = "%s · %s · p. %d",
    org_sleep_extra = "only p. 1 goes to the sleep page",
    org_copy = "Copy from Home",
    org_copy_title = "Copy from Home?",
    org_copy_text = "Replaces the sleep layout with the widgets, sizes and order of Home page 1 (without Sistema).",
    org_copy_ok = "Copy",
    toast_copied = "Sleep page now matches Home page 1",
    org_none_add = "No apps to add.",
    org_no_widget = "No widget",

}

M.LANG_NAMES = { pt = "Português", en = "English" }

local lang = "pt"

function M.set_lang(l) if M[l] and type(M[l]) == "table" and l ~= "LANGS" and l ~= "LANG_NAMES" then lang = l end end
function M.get_lang() return lang end

-- t(key, ...): text in the current language (pt as fallback, the key itself when missing)
function M.t(key, ...)
    local s = (M[lang] and M[lang][key]) or M.pt[key] or key
    if select("#", ...) > 0 then
        local ok, out = pcall(string.format, s, ...)
        if ok then return out end
    end
    return s
end

-- builds a t() for another table pair (system apps keep their own texts): tables = { pt = {...}, en = {...} }
function M.make(tables)
    return function(key, ...)
        local s = (tables[lang] and tables[lang][key]) or (tables.pt and tables.pt[key]) or M.t(key)
        if select("#", ...) > 0 then
            local ok, out = pcall(string.format, s, ...)
            if ok then return out end
        end
        return s
    end
end

return M
