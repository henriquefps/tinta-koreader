-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (C) 2026 Tinta contributors
-- Tinta: notification center (8.3). Four 72 px shortcuts (R-T8: Wi-Fi inverted when on, Sleep now, Rotate,
-- System), the list newest first, 4 per page in portrait and 2 in landscape (R-T9: unread = 4 px border,
-- high and unread = inverted), and "Marcar todas como lidas" / "Limpar" (R-T10, with confirmation).
-- Built as the main screen of the system app "notificacoes".
local Button = require("ui/button")
local Draw = require("ui/draw")
local G = require("ui/geom")
local Pager = require("ui/pager")
local S = require("ui/strings")
local T = require("ui/theme")

local M = {}

local function card(host, n, w, h, on_tap)
    local unread = n.read_at == nil
    local inv = unread and n.prio == "alta"
    local fg = Draw.fg(inv)
    local border = unread and T.BORDER_SEL or T.BORDER
    local pad_x, pad_y = T.px(12) - (border - T.BORDER), T.px(8) - (border - T.BORDER)
    local iw = w - 2 * (border + pad_x)
    local ih = h - 2 * (border + pad_y)
    local head_l = (host:appName(n.app) or n.app or "?") .. (n.prio == "alta" and S.t("central_high") or "")
    local time = Draw.text(host:hm(n.created_at), T.FONT_MIN, false, nil, fg)
    local tw = time:getSize().w
    local head = Draw.hstack({ Draw.box{ w = iw - tw, h = time:getSize().h, child = Draw.text(head_l, T.FONT_MIN, false, iw - tw - T.GAP, fg) }, time }, 0)
    local lines = { head, Draw.text(n.title or "", T.FONT_BODY, true, iw, fg) }
    if n.body and n.body ~= "" then lines[3] = Draw.text(n.body, T.FONT_MIN, false, iw, fg) end
    -- drop the body line when the card is too short
    local used = 0
    local keep = {}
    for i, l in ipairs(lines) do
        local lh = l:getSize().h
        if i > 2 and used + lh > ih then l:free() else keep[#keep + 1] = l; used = used + lh end
    end
    return Draw.box{ w = w, h = h, bg = Draw.bg(inv), border = border, radius = T.RADIUS, pad_x = pad_x, pad_y = pad_y,
        valign = "center", child = Draw.vstack(keep, 0), on_tap = on_tap }
end

-- returns { title, meta, body } for the app screen contract
function M.build(win, box)
    local host = win.host
    local route = win.building_route or win:current()
    local total = host:notificationCount()
    local unread = host:unreadCount()
    local landscape = box.landscape
    local per = landscape and T.CENTRAL_PER_PAGE_LANDSCAPE or T.CENTRAL_PER_PAGE_PORTRAIT
    local items, page, pages = host:notificationPage(route.page or 0, per)
    route.page = page
    local w = box.w

    local wifi_on = host:wifiState() ~= "off"
    local qw = G.share(w, 4, T.GAP)
    local quick = Draw.hstack({
        Button.new{ label = S.t("qt_wifi"), sub = S.t(wifi_on and "qt_on" or "qt_off"), w = qw[1], h = T.QUICK_H,
            size = T.FONT_MIN, inv = wifi_on, on_tap = function() host:toggleWifi() end },
        Button.new{ label = S.t("qt_sleep"), sub = S.t("qt_sleep_sub"), w = qw[2], h = T.QUICK_H, size = T.FONT_MIN,
            on_tap = function() host:sleepNow() end },
        Button.new{ label = S.t("qt_rotate"), sub = S.t(landscape and "qt_landscape" or "qt_portrait"), w = qw[3],
            h = T.QUICK_H, size = T.FONT_MIN, on_tap = function() host:rotate() end },
        Button.new{ label = S.t("qt_system"), sub = S.t("qt_system_sub"), w = qw[4], h = T.QUICK_H, size = T.FONT_MIN,
            on_tap = function() win:openApp("sistema") end },
    }, T.GAP)

    local footer = Button.row({
        { S.t("central_read_all"), function() host:markAllRead() end, disabled = unread == 0 },
        { S.t("central_clear"), function()
            win:confirm{ title = S.t("confirm_clear_title"), text = S.t("confirm_clear_text", total),
                ok_label = S.t("confirm_clear_ok"), on_ok = function() host:clearNotifications() end }
        end, disabled = total == 0 },
    }, w)

    local list_h = box.h - T.QUICK_H - T.BTN_H - 2 * T.GAP
    local parts = { quick }
    if total == 0 then
        parts[2] = Draw.box{ w = w, h = math.min(list_h, T.px(120)), border = T.BORDER, dashed = true, radius = T.RADIUS,
            align = "center", valign = "center", child = Draw.text(S.t("central_empty"), T.FONT_BODY, false, w - T.px(20)) }
        parts[3] = Draw.space(w, list_h - math.min(list_h, T.px(120)) - T.GAP)
    else
        local pager_h = pages > 1 and (T.PAGER_H + T.GAP) or 0
        local ch = math.floor((list_h - pager_h - (per - 1) * T.GAP) / per)
        local cards = {}
        for i, n in ipairs(items) do
            cards[i] = card(host, n, w, ch, function() host:openNotification(n) end)
        end
        local stack = Draw.vstack(cards, T.GAP)
        parts[2] = Draw.box{ w = w, h = list_h - pager_h, child = stack }
        if pages > 1 then
            parts[3] = Pager.new(w, page, pages, function() win:setPage(page - 1) end, function() win:setPage(page + 1) end)
        end
    end
    parts[#parts + 1] = footer
    return { title = S.t("central_title"), meta = S.t("central_unread", unread), body = Draw.vstack(parts, T.GAP) }
end

return M
