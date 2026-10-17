-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (C) 2026 Tinta contributors
-- Nota: widgets (2x2, 4x2, 2x4, 4x4) and the screen (the text and Editar / Limpar). Built from ctx.ui inside the box
-- the core gives (R-W1); the text box cuts at its height with "…". No KOReader group is measured (R-L1).
local Logic = require("apps/nota/logic")

local M = {}

-- vm: Logic.view; big: setting "Letra maior"
function M.widget(ctx, size, box, vm, big, L)
    local ui = ctx.ui
    local T = ui.theme
    local fg = ui.fg(box.inv)
    local fsize = big and T.fpx(24) or T.fpx(20)
    local title = ui.text(L("name"), T.FONT_WNAME, true, box.w, fg)
    local th = title:getSize().h
    local body_h = math.max(0, box.h - th - T.px(2))
    local text = ui.textbox(Logic.preview(vm.text), fsize, box.w, body_h, false, fg)
    return ui.vstack({ title, ui.box{ w = box.w, h = body_h, child = text } }, T.px(2), "start")
end

-- act = { edit(), clear() }
function M.screen(ctx, box, vm, big, act, L)
    local ui = ctx.ui
    local T = ui.theme
    local w, h = box.w, box.h
    local fsize = big and T.fpx(28) or T.fpx(24)
    local btn_h = T.BTN_H
    local meta_h = T.FONT_MIN + T.px(8)
    local frame_pad = T.px(10)
    local text_h = math.max(T.px(60), h - btn_h - meta_h - 2 * T.GAP)
    local inner_w, inner_h = w - 2 * (T.BORDER + frame_pad), text_h - 2 * (T.BORDER + frame_pad)
    local body = ui.textbox(Logic.preview(vm.empty and L("empty_screen") or vm.text, 1500), fsize, inner_w, inner_h)
    local frame = ui.box{ w = w, h = text_h, border = T.BORDER, radius = T.RADIUS, pad_x = frame_pad, pad_y = frame_pad,
        on_tap = act.edit, child = body }
    local meta = ui.box{ w = w, h = meta_h, align = "right",
        child = ui.text(vm.empty and "" or L("count", vm.count), T.FONT_MIN, false, w) }
    local specs = { { vm.empty and L("btn_write") or L("btn_edit"), act.edit, inv = true } }
    if not vm.empty then specs[2] = { L("btn_clear"), act.clear } end
    return { body = ui.vstack({ frame, meta, ui.button_row(specs, w) }, T.GAP) }
end

return M
