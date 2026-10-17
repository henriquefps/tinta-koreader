-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (C) 2026 Tinta contributors
-- Repouso app: widgets (1x1 button, 2x2 state, 4x2 with three buttons) and the main screen with the three actions.
-- Built only from ctx.ui (ui/kit) inside the box the core gives (R-W1); sizes are summed by hand (R-L1).
-- Buttons are at least 64 px tall (6.1) and are the smallest tap boxes, so they win over the tile's own tap
-- (which opens the screen); acts = { cycle (minutes), cycle_mode, sleep, confirm_sleep } are callbacks of init.lua.
local Geom = require("ui/geom")
local Logic = require("apps/repouso/logic")

local M = {}

-- vm = { L, mode, idle }
function M.widget(ctx, size, box, vm, acts)
    local ui = ctx.ui
    local T = ui.theme
    local L = vm.L
    local fg = ui.fg(box.inv)
    local w, h = box.w, box.h

    if size == "1x1" then
        -- the whole widget is one button: confirm, then sleep (a stray tap on a 1x1 must not blank the screen)
        local label = ui.vstack({ ui.text(L("one_a"), T.FONT_MIN, true, w, fg), ui.text(L("one_b"), T.FONT_MIN, false, w, fg) }, 0, "center")
        return ui.box{ w = w, h = h, align = "center", valign = "center", child = label, on_tap = acts.confirm_sleep }
    end

    if box.cols >= 4 and h >= T.TOUCH + T.px(38) then
        local head = ui.text(L("name"), T.FONT_WNAME, true, w, fg)
        local specs = {
            { Logic.idle_text(L, vm.idle, vm.mode), Logic.sleeps_alone(vm.mode) and acts.cycle or function() end, sub = L("btn_idle_sub") },
            { Logic.mode_short(L, vm.mode), acts.cycle_mode, inv = Logic.sleeps_alone(vm.mode), sub = L("btn_mode_sub") },
            { L("btn_sleep"), acts.sleep, sub = L("btn_sleep_sub") },
        }
        local widths = Geom.share(w, #specs, T.GAP)
        local buttons = {}
        for i, s in ipairs(specs) do
            buttons[i] = ui.button{ label = s[1], sub = s.sub, w = widths[i], h = T.TOUCH, inv = s.inv, on_tap = s[2], size = T.FONT_BODY }
        end
        return ui.vstack({ head, ui.hstack(buttons, T.GAP, "start") }, T.GAP, "start")
    end

    return ui.basic(box, { title = L("name"), lines = Logic.lines(L, vm.mode, vm.idle) })
end

function M.screen(ctx, box, vm, acts)
    local L = vm.L
    local rows = {
        { title = L("idle"), sub = Logic.mode_sub(L, vm.mode), right = Logic.mode_text(L, vm.mode), on_tap = acts.cycle_mode },
    }
    if Logic.sleeps_alone(vm.mode) then
        rows[#rows + 1] = { title = L("idle_after"), sub = L("idle_after_sub"), right = Logic.idle_text(L, vm.idle, vm.mode), on_tap = acts.cycle }
    end
    rows[#rows + 1] = { title = L("sleep_now"), sub = L("sleep_now_sub"), right = "›", on_tap = acts.sleep }
    return { body = ctx.ui.rows(box, rows, { two_cols = false }) }
end

return M
