-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (C) 2026 Tinta contributors
-- Tinta: confirmation dialog (6.9, R-K1): title, text, "Cancelar" / "<ação>". Modal: the backdrop takes
-- every tap outside the box. Returns overlay layers for the window.
local Button = require("ui/button")
local Draw = require("ui/draw")
local Geom = require("ui/geom")
local S = require("ui/strings")
local T = require("ui/theme")

local M = {}

-- d = { title, text, ok_label, on_ok, on_cancel }
function M.layers(regions, d)
    local W, H = regions.W, regions.H
    local w = math.min(T.DIALOG_W, W - T.px(40))
    local inner = w - 2 * (T.BORDER_DIALOG + T.DIALOG_PAD)
    local title = Draw.textbox(d.title or "", T.FONT_TITLE, inner, nil, true)
    local text = Draw.textbox(d.text or "", T.FONT_BODY, inner, math.floor(H * 0.45))
    local cancel_w = Button.width_for(S.t("btn_cancel"))
    local ok_w = Button.width_for(d.ok_label or S.t("btn_ok"))
    local buttons = Draw.hstack({
        Draw.space(math.max(0, inner - cancel_w - ok_w - T.GAP), 1),
        Button.new{ label = S.t("btn_cancel"), w = cancel_w, on_tap = d.on_cancel },
        Draw.space(T.GAP, 1),
        Button.new{ label = d.ok_label or S.t("btn_ok"), w = ok_w, inv = true, on_tap = d.on_ok },
    }, 0)
    local gap = T.px(14)
    local h = 2 * (T.BORDER_DIALOG + T.DIALOG_PAD) + title:getSize().h + gap + text:getSize().h + gap + T.BTN_H
    local r = Geom.dialog(W, H, h)
    local backdrop = Draw.box{ w = W, h = H, on_tap = function() end }
    local box = Draw.box{ w = r.w, h = r.h, bg = Draw.WHITE, border = T.BORDER_DIALOG, radius = T.RADIUS_OVERLAY,
        pad_x = T.DIALOG_PAD, pad_y = T.DIALOG_PAD, on_tap = function() end,
        child = Draw.vstack({ title, text, buttons }, gap) }
    return { { widget = backdrop, x = 0, y = 0 }, { widget = box, x = r.x, y = r.y } }
end

return M
