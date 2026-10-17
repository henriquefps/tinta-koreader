-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (C) 2026 Tinta contributors
-- Drawing: the widget and the screen, built only from ctx.ui, inside the box the Tinta gives (R-W1). Never write a
-- pixel number: use the theme (T.px(n) for design pixels, T.FONT_* for fonts, T.GAP). Never call getSize() on a stack
-- that still gets children (R-L1); ui.box with an explicit size is the safe way to place something.
local M = {}

-- 2x2 and 4x2 widgets (ui.basic stacks what fits in box.h: title, primary, secondary, then the lines)
function M.widget(ctx, size, box, vm, L)
    local spec = { title = vm.label, primary = vm.primary, secondary = vm.secondary }
    if box.cols >= 4 then
        spec.lines = { { L("line_rain"), vm.rain }, { L("line_next"), vm.next } }
    end
    return ctx.ui.basic(box, spec)
end

-- the main screen: the temperature, the sky, when it was read, and the list of the next hours
function M.screen(ctx, box, vm, L)
    local ui = ctx.ui
    local T = ui.theme
    local w = box.w
    local big = ui.text(vm.big, T.FONT_HUGE, true, w)
    local top = {
        ui.box{ w = w, h = big:getSize().h + T.px(8), align = "center", valign = "center", child = big },
        ui.box{ w = w, h = T.FONT_BODY + T.px(14), align = "center", child = ui.text(vm.secondary, T.FONT_BODY, true, w) },
        ui.box{ w = w, h = T.FONT_BODY + T.px(14), align = "center", child = ui.text(vm.rain .. " · " .. (vm.updated or ""), T.FONT_MIN, false, w) },
    }
    local top_h = big:getSize().h + T.px(8) + 2 * (T.FONT_BODY + T.px(14)) + 3 * T.GAP
    local rows = {}
    for i, h in ipairs(vm.hours) do rows[i] = { title = h.time, sub = h.desc, right = h.right } end
    local list_h = box.h - top_h
    local body = ui.vstack({
        ui.vstack(top, T.GAP, "center"),
        ui.box{ w = w, h = list_h, child = ui.rows({ w = w, h = list_h, landscape = box.landscape }, rows, { two_cols = false }) },
    }, T.GAP, "center")
    return { title = L("screen_title") .. (vm.units and (" · " .. vm.units) or ""), body = body }
end

return M
