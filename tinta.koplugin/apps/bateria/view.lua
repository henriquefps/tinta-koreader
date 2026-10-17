-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (C) 2026 Tinta contributors
-- Bateria app: widgets (1x1, 2x2, 4x2 with a small chart) and the main screen (10.3: big percentage, battery
-- drawing, estimate, chart of the recent discharge, stat blocks). Built only from ctx.ui (ui/kit), inside the
-- box the core gives (R-W1). Sizes are summed by hand; no KOReader group is measured (R-L1).
-- Every measure is a design px of the 600x800 layout scaled by ui.theme (T.px, T.s), spec 6.1.
local Chart = require("apps/bateria/chart")
local Logic = require("apps/bateria/logic")

local M = {}

-- 1x1 (~78 px wide inside the frame): battery drawing and the bare percentage. The "⚡" glyph is not used here
-- ("⚡100%" did not fit and showed "…"); charging is a "+" mark beside the battery. "100%" gets a smaller font.
M.ONE_FONT, M.ONE_FONT_WIDE = 26, 22   -- design sizes (scaled with T.px)
function M.widget_1x1(ctx, box, vm)
    local ui = ctx.ui
    local T = ui.theme
    local fg = ui.fg(box.inv)
    local text = vm.pct_text
    local size = T.fpx(#text >= 4 and M.ONE_FONT_WIDE or M.ONE_FONT)
    local row = ui.icons.battery(vm.pct, nil, nil, fg)
    if vm.charging then
        local d, bar, off = T.px(10), T.px1(3), T.px(3)
        local plus = ui.draw.Layers:new{ w = d, h = d }
        plus[1] = { widget = ui.fill(d, bar, box.inv), x = 0, y = off }
        plus[2] = { widget = ui.fill(bar, d, box.inv), x = off, y = 0 }
        row = ui.hstack({ plus, ui.space(T.px(5), 1), row }, 0, "center")
    end
    return ui.vstack({ row, ui.text(text, size, true, box.w, fg) }, T.px(2), "center")
end

-- vm: Logic.view(...); samples: the log samples in memory; L: translator
function M.widget(ctx, size, box, vm, samples, L)
    local ui = ctx.ui
    local T = ui.theme
    local fg = ui.fg(box.inv)
    if size == "1x1" then return M.widget_1x1(ctx, box, vm) end
    local spec = {
        title = L("name"),
        icon = ui.icons.battery(vm.pct, T.WIDGET_ICON - T.px(4), T.px(14), fg),
        primary = vm.number,
        secondary = vm.short,
    }
    if box.cols < 4 then return ui.basic(box, spec) end
    -- 4x2: text on the left, the small chart on the right
    local sw = math.min(T.px(170), math.floor(box.w * 0.45))
    local lw = box.w - sw - T.GAP
    local left = ui.basic({ w = lw, h = box.h, inv = box.inv, size = box.size, cols = 2, rows = box.rows, big = false }, spec)
    local sh = math.max(0, math.min(T.px(56), box.h - T.px(34)))
    local g = sh >= T.px(20) and Chart.build(samples, { w = sw, h = sh, left = T.px(2), right = T.px(2), top = T.px(3),
        bottom = T.px(4), k = T.s }) or nil
    local spark = g and ui.draw.Spans:new{ w = sw, h = sh, spans = Chart.spark_spans(g, sw, sh, T.s), color = fg }
        or ui.space(sw, sh)
    return ui.hstack({
        ui.box{ w = lw, h = box.h, child = left },
        ui.box{ w = sw, h = box.h, valign = "bottom", child = spark },
    }, T.GAP, "start")
end

---------------------------------------------------------------- screen

-- chart widget of w x h: spans (grid, axes, line, dot) and the axis labels as text, all inside the box
local function chart_widget(ui, g, w, h)
    local T = ui.theme
    local Draw = ui.draw
    local LABEL = T.FONT_MIN    -- chart label size (the minimum, 6.1)
    local layers = Draw.Layers:new{ w = w, h = h }
    layers[1] = { widget = Draw.Spans:new{ w = w, h = h, spans = Chart.chart_spans(g, w, h, T.s), color = Draw.BLACK }, x = 0, y = 0 }
    -- a label at (x, y), kept inside the chart box
    local function put(t, x, y)
        local s = t:getSize()
        layers[#layers + 1] = { widget = t, x = math.max(0, math.min(w - s.w, x)), y = math.max(0, math.min(h - s.h, y)) }
    end
    for _, tk in ipairs(g.yticks) do
        local t = ui.text(tk.label, LABEL, false, nil, Draw.BLACK)
        local s = t:getSize()
        put(t, g.plot.x - T.px(8) - s.w, tk.y - math.floor(s.h / 2))
    end
    local right_edge = -1
    for _, tk in ipairs(g.xticks) do
        local t = ui.text(tk.label, LABEL, false, nil, Draw.BLACK)
        local s = t:getSize()
        local x = math.max(0, math.min(w - s.w, tk.x - math.floor(s.w / 2)))
        if x > right_edge + T.GAP then
            put(t, x, h - s.h)
            right_edge = x + s.w
        else
            t:free()
        end
    end
    return layers
end

local function stat_block(ui, w, h, value, label)
    local T = ui.theme
    return ui.box{ w = w, h = h, border = T.BORDER, radius = T.RADIUS, align = "center", valign = "center",
        child = ui.vstack({ ui.text(value, T.fpx(30), true, w - T.px(8)), ui.text(label, T.FONT_MIN, false, w - T.px(8)) }, 0, "center") }
end

-- "15/10 11:17" and "15:46" (same day) for the chart note
local function span_text(from, to, date)
    date = date or os.date
    local same = date("%Y%m%d", from) == date("%Y%m%d", to)
    return date("%d/%m %H:%M", from), same and date("%H:%M", to) or date("%d/%m %H:%M", to)
end

-- c: the cache table (Logic.cycle); vm: Logic.view(c, ...)
function M.screen(ctx, box, vm, c, samples, L)
    local ui = ctx.ui
    local T = ui.theme
    local Draw = ui.draw
    local w, h, land = box.w, box.h, box.landscape
    -- top: big percentage, battery drawing, estimate line
    local pct = ui.text(vm.pct_text, T.FONT_HUGE, true)
    local ps = pct:getSize()
    local pw = ps.w
    local top_h = math.max(T.px(land and 80 or 96), ps.h)
    local bat_w = T.px(110)
    local bat = ui.icons.battery(vm.pct, bat_w, T.px(52), Draw.BLACK)
    local bw = bat_w + T.BAT_NUB
    local gap20 = T.px(20)
    local ew = math.max(T.px(40), w - pw - bw - 2 * gap20)
    local top = ui.hstack({
        ui.box{ w = pw, h = top_h, valign = "center", child = pct },
        ui.space(gap20, 1),
        ui.box{ w = bw, h = top_h, valign = "center", child = bat },
        ui.space(gap20, 1),
        ui.box{ w = ew, h = top_h, valign = "center", child = ui.textbox(vm.line, T.FONT_BODY, ew, top_h) },
    }, 0, "start")
    -- stat blocks
    local stats_h = T.px(84)
    local bwid = math.floor((w - 3 * T.GAP) / 4)
    local blocks = {}
    for i, s in ipairs(vm.stats) do
        local bw_i = i == 4 and (w - 3 * (bwid + T.GAP)) or bwid
        blocks[i] = stat_block(ui, bw_i, stats_h, s[1], s[2])
    end
    local stats = ui.hstack(blocks, T.GAP, "start")
    -- note: what the chart shows and where the estimate comes from
    local note_h = T.px(land and 28 or 56)
    -- the two estimates, labelled: real pace (sleep included) and awake with Wi-Fi; one per line in portrait, one
    -- line in landscape (nothing while charging or calibrating)
    local est, est_h = nil, 0
    local estimates = vm.estimates or {}
    if #estimates > 0 then
        local lines = land and { table.concat(estimates, " · ") } or estimates
        local rows = {}
        for i, t in ipairs(lines) do
            rows[i] = ui.text(t, T.FONT_BODY, i == 1, w)
            est_h = est_h + rows[i]:getSize().h
        end
        est = ui.box{ w = w, h = est_h, child = ui.vstack(rows, 0, "start") }
    end
    -- chart in a framed box, taking what is left
    local frame_pad = T.px(6)
    local est_room = est and (est_h + T.GAP) or 0
    local chart_h = math.max(T.px(90), math.min(T.px(300), h - top_h - stats_h - note_h - est_room - 3 * T.GAP))
    local cw, ch = w - 2 * (T.BORDER + frame_pad), chart_h - 2 * (T.BORDER + frame_pad)
    local g = Chart.build(samples, { w = cw, h = ch, left = T.px(56), right = T.px(10), top = T.px(12), bottom = T.px(30), k = T.s })
    local chart_child
    local note
    if g then
        chart_child = chart_widget(ui, g, cw, ch)
        local a, b = span_text(g.from.t, g.to.t)
        note = L("chart_note", a, b, g.from.pct, g.to.pct)
    else
        chart_child = ui.box{ w = cw, h = ch, align = "center", valign = "center",
            child = ui.textbox(L("chart_empty"), T.FONT_BODY, cw - T.px(16), nil, false, nil, "center") }
        note = ""
    end
    if c and c.basis then
        local b = c.eta_mix and c.mix_basis or c.basis
        local basis = not c.eta_mix and c.kind == "saved" and L("basis_saved") or L(b == "mah" and "basis_mah" or "basis_pct")
        note = (note ~= "" and (note .. " ") or "") .. basis
    end
    local chart = ui.box{ w = w, h = chart_h, border = T.BORDER, radius = T.RADIUS, pad_x = frame_pad, pad_y = frame_pad,
        child = chart_child }
    local note_w = land and ui.text(note, T.FONT_MIN, false, w) or ui.textbox(note, T.FONT_MIN, w, note_h)
    local parts = { top }
    if est then parts[#parts + 1] = est end
    parts[#parts + 1] = chart
    parts[#parts + 1] = stats
    parts[#parts + 1] = ui.box{ w = w, h = note_h, child = note_w }
    return {
        body = ui.vstack(parts, T.GAP),
    }
end

M.Logic = Logic
return M
