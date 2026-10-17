-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (C) 2026 Tinta contributors
-- Drawing: the widget and the screen, built only from ctx.ui, inside the box the Tinta gives (R-W1). Never write a
-- pixel number: use the theme (T.px(n) for design pixels, T.FONT_* for fonts, T.GAP, T.BTN_H). Never call getSize()
-- on a stack that still gets children (R-L1); ui.box with an explicit size is the safe way to place something.
local M = {}

-- 2x2 and 4x2 widgets (ui.basic stacks what fits in box.h: title, primary, secondary, then the lines)
function M.widget(ctx, size, box, vm, L)
    local spec = { title = vm.label, primary = vm.primary, secondary = vm.secondary }
    if box.cols >= 4 then
        spec.lines = { { L("line_source"), vm.host }, { L("line_limit"), vm.limit } }
    end
    return ctx.ui.basic(box, spec)
end

-- the main screen: the value, when it was read, where from, and the button that re-arms the alert
function M.screen(ctx, box, vm, act, L)
    local ui = ctx.ui
    local T = ui.theme
    local w = box.w
    local big = ui.text(vm.big, T.FONT_HUGE, true, w)
    return { title = L("screen_title"), body = ui.vstack({
        ui.box{ w = w, h = big:getSize().h + T.px(8), align = "center", valign = "center", child = big },
        ui.box{ w = w, h = T.FONT_BODY + T.px(14), align = "center", child = ui.text(vm.label, T.FONT_BODY, true, w) },
        ui.box{ w = w, h = T.FONT_BODY + T.px(14), align = "center", child = ui.text(vm.secondary .. " · " .. vm.host, T.FONT_BODY, false, w) },
        ui.button{ label = L("btn_rearm"), w = w, inv = true, on_tap = act.rearm },
    }, T.GAP, "center") }
end

return M
