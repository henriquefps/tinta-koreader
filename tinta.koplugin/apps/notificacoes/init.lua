-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (C) 2026 Tinta contributors
-- Notificações (system app, 10.4): widget 2x2 ("N novas", newest title), 4x2 (2 newest), 4x4 (5 newest).
-- Tapping it opens the notification center (its main screen, ui/central). No refresh of its own.
local Host = require("ui/host")
local S = require("ui/strings")

local function new_text(n)
    if n == 0 then return S.t("notif_nothing") end
    if n == 1 then return S.t("notif_new_one") end
    return S.t("notif_new_many", n)
end

return {
    id = "notificacoes",
    name = "Notificações",
    names = { pt = "Notificações", en = "Notifications" },
    short = "Notif.",
    version = 1,
    api = 1,                -- Tinta app API this app was written for (5.1)
    system = true,          -- no refresh (10.4)
    sizes = { "2x2", "4x2", "4x4" },
    net = false,
    defaults = {},
    settings = {},
    notifications = {},

    widget = function(ctx, size, box)
        local ui = ctx.ui
        local list = Host:notifications{ limit = 5 }
        local unread = Host:unreadCount()
        local spec = {
            title = Host:appName("notificacoes"),
            icon = ui.icons.bell(ui.fg(box.inv)),
            primary = new_text(unread),
            number = unread > 0 and tostring(unread) or "",
        }
        if size == "2x2" then
            spec.secondary = list[1] and list[1].title or S.t("notif_none")
        else
            local k = box.rows >= 4 and 5 or 2
            spec.lines = {}
            for i = 1, math.min(k, #list) do
                local n = list[i]
                spec.lines[i] = { (n.read_at == nil and "● " or "") .. (n.title or ""), Host:hm(n.created_at) }
            end
            if #list == 0 then spec.secondary = S.t("notif_none_yet") end
        end
        return ui.basic(box, spec)
    end,

    footer = function(ctx)
        return S.t("notif_total", Host:notificationCount()), ""
    end,

    screens = {
        main = function(ctx, args, box)
            return require("ui/central").build(Host.window, box)
        end,
    },
}
