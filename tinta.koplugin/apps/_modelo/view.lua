-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (C) 2026 Tinta contributors
-- Drawing: the widget and the screen, built only from ctx.ui, inside the box the Tinta gives (R-W1). Never write a
-- pixel number: use the theme (T.px(n) for design pixels, T.FONT_* for fonts, T.GAP, T.BTN_H). Never call getSize()
-- on a stack that still gets children (R-L1); ui.box with an explicit size is the safe way to place something.
local M = {}

-- 2x2 and 4x2 widgets. ui.basic stacks what fits in box.h: title, primary, secondary, then the lines.
function M.widget(ctx, size, box, vm, L)
    local spec = { title = L("name"), primary = vm.primary, secondary = vm.secondary }
    if box.cols >= 4 then
        spec.lines = { { L("line_limit"), L("line_limit_value", vm.limit) } }
    end
    return ctx.ui.basic(box, spec)
end

-- the main screen: a big number and a button. `box` is the body area under the app header; act.reset is a callback.
-- A screen returns a widget, or { body = widget, title = "…" } to name the header.
function M.screen(ctx, box, vm, act, L)
    local ui = ctx.ui
    local T = ui.theme
    local w = box.w
    local big = ui.text(tostring(vm.count), T.FONT_HUGE, true, w)
    return { body = ui.vstack({
        ui.box{ w = w, h = big:getSize().h + T.px(8), align = "center", valign = "center", child = big },
        ui.box{ w = w, h = T.FONT_BODY + T.px(14), align = "center", child = ui.text(vm.secondary, T.FONT_BODY, false, w) },
        ui.button{ label = L("btn_reset"), w = w, inv = true, on_tap = act.reset },
    }, T.GAP, "center") }
end

return M
