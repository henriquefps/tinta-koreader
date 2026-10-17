-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (C) 2026 Tinta contributors
-- Sistema (system app, 10.5): Wi-Fi, organizer, notification preferences, updates, sleep, connections,
-- screen and navigation, per-app settings (R-C1), data and log, exit. Widget 1x1 = icon, 2x2 = Wi-Fi state.
-- The only app without periodic refresh; its server rule (8.6) runs in ui/host after each refresh.
local Host = require("ui/host")
local S = require("ui/strings")
local Screens = require("apps/sistema/screens")
local SysStrings = require("apps/sistema/strings")

local L = S.make(SysStrings)

local VERSION = require("apps/sistema/logic").VERSION

return {
    id = "sistema",
    name = "Sistema",
    names = { pt = SysStrings.pt.name, en = SysStrings.en.name },
    short = "Sist.",
    version = 1,
    api = 1,                -- Tinta app API this app was written for (5.1)
    system = true,          -- no refresh (10.5)
    sizes = { "1x1", "2x2" },
    net = false,
    defaults = {},
    settings = {},
    notifications = {
        { type = "server_down", label = "servidor sem resposta" },
        { type = "server_up", label = "servidor de volta" },
    },

    widget = function(ctx, size, box)
        local ui = ctx.ui
        local fg = ui.fg(box.inv)
        if size == "1x1" then return ui.icons.gear(math.min(ui.theme.px(40), box.w, box.h), fg) end
        local w = Host:wifiState()
        return ui.basic(box, {
            title = Host:appName("sistema"),
            icon = ui.icons.gear(ui.theme.WIDGET_ICON, fg),
            primary = L(w == "on" and "wifi_connected" or w == "connecting" and "wifi_connecting" or "wifi_off"),
            secondary = L("version", VERSION),
        })
    end,

    footer = function()
        return L("apps_sub"), ""
    end,

    screens = Screens.screens,
    VERSION = VERSION,
}
