-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (C) 2026 Tinta contributors
-- Relógio app: the widget in every size and style, and the style screen with a preview. Built only from ctx.ui
-- (ui/kit) inside the box the core gives (R-W1); sizes are summed by hand, no group is measured (R-L1).
-- Measures and thresholds are design px of the 600x800 layout scaled by ui.theme (T.px), spec 6.1.
local Face = require("apps/relogio/face")
local Logic = require("apps/relogio/logic")

local M = {}

-- size (px) of `str` so that it fits w x h on one line: one measurement at 100 px, scaled (widths are linear)
local function fit_size(ui, str, w, h, bold, max_size, min_size)
    local tw = math.max(1, ui.draw.text_width(str, 100, bold))
    local by_w = math.floor(w * 100 / tw)
    local by_h = math.floor(h / 1.4)
    return math.max(min_size or ui.theme.FONT_MIN, math.min(max_size, by_w, by_h))
end

local function fitted(ui, str, w, h, bold, max_size, fg, min_size)
    local size = fit_size(ui, str, w, h, bold, max_size, min_size)
    return ui.text(str, size, bold, w, fg)
end

local function centered(ui, w, h, child)
    return ui.box{ w = w, h = h, align = "center", valign = "center", child = child }
end

-- the analog face of diameter d: dial + hands, one Layers widget
local function face(ui, d, hands, fg)
    local Draw = ui.draw
    local layers = Draw.Layers:new{ w = d, h = d }
    local k = ui.theme.s
    layers[1] = { widget = Draw.Spans:new{ w = d, h = d, spans = Face.dial(d, k), color = fg }, x = 0, y = 0 }
    layers[2] = { widget = Draw.Spans:new{ w = d, h = d, spans = Face.hands(d, hands, k), color = fg }, x = 0, y = 0 }
    return layers
end

-- vm = { t = now, L = translator, style, asleep = bool, next_at = timestamp | nil, date = os.date-like | nil }
function M.widget(ctx, size, box, vm)
    local ui = ctx.ui
    local T = ui.theme
    local fg = ui.fg(box.inv)
    local w, h = box.w, box.h
    local style = Logic.style_for(vm.style, size)
    local hm = Logic.hm(vm.t, vm.date)

    if size == "1x1" then
        return centered(ui, w, h, fitted(ui, hm, w, h, true, T.fpx(40), fg, T.fpx(16)))
    end

    if style == "digital" then
        return centered(ui, w, h, fitted(ui, hm, w, h, true, T.fpx(150), fg))
    end

    if style == "data" then
        if w >= T.px(300) then
            -- wide: time, then the whole date on one line
            local date_h = T.px(h >= T.px(200) and 40 or 30)
            local time = fitted(ui, hm, w, h - date_h - T.GAP, true, T.fpx(130), fg)
            local line = fitted(ui, Logic.date_text(vm.L, vm.t, vm.date), w, date_h, false, h >= T.px(200) and T.fpx(30) or T.FONT_BODY, fg)
            return centered(ui, w, h, ui.vstack({ time, line }, T.GAP, "center"))
        end
        -- narrow: time, weekday, "16 de outubro"
        local line_h = T.px(h >= T.px(200) and 34 or 26)
        local time = fitted(ui, hm, w, h - 2 * line_h - T.GAP, true, T.fpx(90), fg)
        local a, b = Logic.date_lines(vm.L, vm.t, vm.date)
        local max = h >= T.px(200) and T.fpx(28) or T.FONT_MIN
        return centered(ui, w, h, ui.vstack({ time, fitted(ui, a, w, line_h, false, max, fg), fitted(ui, b, w, line_h, false, max, fg) },
            T.px(2), "center"))
    end

    if style == "analogico" then
        local hands = Logic.hands_at(vm.t, vm.date)
        if box.rows >= 4 then
            -- tall: face on top, HH:MM under it
            local tw_h = T.px(48)
            local d = math.max(T.px(40), math.min(w, h - tw_h - T.GAP))
            return centered(ui, w, h, ui.vstack({ face(ui, d, hands, fg), fitted(ui, hm, w, tw_h, true, T.fpx(44), fg) }, T.GAP, "center"))
        end
        local d = math.max(T.px(40), math.min(w, h))
        if box.cols >= 4 then
            -- wide: face on the left, HH:MM on the right
            local tw = w - d - T.GAP
            return ui.hstack({ ui.box{ w = d, h = h, valign = "center", child = face(ui, d, hands, fg) },
                ui.space(T.GAP, 1), centered(ui, tw, h, fitted(ui, hm, tw, h, true, T.fpx(80), fg)) }, 0, "start")
        end
        return centered(ui, w, h, face(ui, d, hands, fg))
    end

    -- "minimo": HH:MM, and the next wake-up under it while the Tinta sleeps
    if vm.asleep then
        local line_h = T.px(box.cols >= 4 and 30 or 54)
        local time = fitted(ui, hm, w, h - line_h - T.GAP, true, T.fpx(130), fg)
        local text = Logic.wake_text(vm.L, vm.next_at, vm.t, vm.date)
        local line = box.cols >= 4 and ui.text(text, T.FONT_BODY, false, w, fg)
            or ui.textbox(text, T.FONT_MIN, w, line_h, false, fg, "center")
        return centered(ui, w, h, ui.vstack({ time, line }, T.GAP, "center"))
    end
    return centered(ui, w, h, fitted(ui, hm, w, h, true, T.fpx(150), fg))
end

-- the style screen: a 4x2 preview of the current style and the list of styles (tap = choose)
-- vm as in M.widget; pick(style) saves the choice and redraws.
function M.screen(ctx, box, vm, pick)
    local ui = ctx.ui
    local T = ui.theme
    local L = vm.L
    local land = box.landscape
    local pw = land and math.floor(box.w * 0.5) - T.GAP or box.w
    local ph = land and math.min(box.h, T.px(170)) or T.px(150)
    local pbox = { w = pw - 2 * (T.BORDER + T.px(8)), h = ph - 2 * (T.BORDER + T.px(6)), inv = false, size = "4x2", cols = 4, rows = 2, big = false }
    local preview = ui.box{ w = pw, h = ph, border = T.BORDER, radius = T.RADIUS, pad_x = T.px(8), pad_y = T.px(6), child = M.widget(ctx, "4x2", pbox, vm) }
    local rows = {}
    for _, s in ipairs(Logic.STYLES) do
        local sel = Logic.style_or_default(vm.style) == s
        rows[#rows + 1] = { title = L("style_" .. s), sub = L("style_" .. s .. "_sub"), right = sel and "●" or "", inv = sel,
            on_tap = function() pick(s) end }
    end
    if land then
        local lw = box.w - pw - T.GAP
        return { body = ui.hstack({ ui.box{ w = pw, h = box.h, valign = "top", child = preview },
            ui.space(T.GAP, 1), ui.rows({ w = lw, h = box.h, landscape = false }, rows, { two_cols = false }) }, 0, "start") }
    end
    local list_box = { w = box.w, h = box.h - ph - T.GAP, landscape = false }
    return { body = ui.vstack({ preview, ui.rows(list_box, rows, { two_cols = false }) }, T.GAP) }
end

return M
