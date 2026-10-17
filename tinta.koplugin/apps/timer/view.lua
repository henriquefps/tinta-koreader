-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (C) 2026 Tinta contributors
-- Timer: widgets (1x1, 2x2, 4x2) and the main screen, built only from ctx.ui inside the box the core gives
-- (R-W1). No KOReader group is measured (R-L1). `vm` is Logic.view(...); the actions are callbacks of init.lua.
local M = {}

local function icon_text(vm) return vm.mode == "idle" and "▶" or vm.number end

function M.widget(ctx, size, box, vm, L)
    local ui = ctx.ui
    if size == "1x1" then
        return ui.basic(box, { number = icon_text(vm), short = L("name") })
    end
    local spec = { title = L("name"), primary = vm.primary, secondary = vm.secondary }
    if box.cols >= 4 and box.rows >= 2 then
        spec.lines = { { vm.status } }
    end
    return ui.basic(box, spec)
end

-- act = { select(preset), custom(), start(), pause(), resume(), reset() }; sel = the selection in idle
function M.screen(ctx, box, vm, st, act, L)
    local ui = ctx.ui
    local T = ui.theme
    local w, land = box.w, box.landscape
    local big = ui.text(vm.primary, T.FONT_HUGE, true, w)
    local big_h = big:getSize().h
    local parts = {
        ui.box{ w = w, h = T.FONT_TITLE + T.px(12), align = "center", child = ui.text(vm.status, T.FONT_TITLE, true, w) },
        ui.box{ w = w, h = big_h + T.px(4), align = "center", valign = "center", child = big },
        ui.box{ w = w, h = T.FONT_BODY + T.px(14), align = "center", child = ui.text(vm.secondary, T.FONT_BODY, false, w) },
    }
    local function btn_row(specs) return ui.button_row(specs, w) end
    if st.mode == "idle" then
        local sel = st.sel or {}
        local specs = {}
        for _, id in ipairs({ "pomo", "m15", "m10", "m5" }) do
            local label
            if id == "pomo" then
                local pomo = st.pomo or { min = 25, brk = 5 }
                label = L("preset_pomo", pomo.min, pomo.brk)
            else
                label = L("preset_min", ({ m15 = 15, m10 = 10, m5 = 5 })[id])
            end
            specs[#specs + 1] = { label, function() act.select(id) end, inv = sel.id == id }
        end
        specs[#specs + 1] = { L("btn_custom"), act.custom, inv = sel.id == "custom" }
        parts[#parts + 1] = ui.space(w, T.px(land and 4 or 18))
        parts[#parts + 1] = btn_row(specs)
        parts[#parts + 1] = ui.button{ label = L("btn_start"), w = w, inv = true, on_tap = act.start }
        if sel.id == "pomo" then
            parts[#parts + 1] = ui.box{ w = w, h = T.FONT_MIN + T.px(10), align = "center", child = ui.text(L("pomo_note"), T.FONT_MIN, false, w) }
        end
    else
        parts[#parts + 1] = ui.space(w, T.px(land and 4 or 18))
        parts[#parts + 1] = btn_row({
            { st.mode == "paused" and L("btn_resume") or L("btn_pause"), st.mode == "paused" and act.resume or act.pause, inv = true },
            { L("btn_reset"), act.reset },
        })
    end
    return { body = ui.vstack(parts, T.GAP, "center") }
end

return M
