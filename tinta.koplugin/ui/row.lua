-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (C) 2026 Tinta contributors
-- Tinta: list row (>= 64 px): title (22 bold) and subtitle (20) on the left, a short value on the right
-- spanning both lines. inv = needs attention (black); static rows have no callback.
local Draw = require("ui/draw")
local T = require("ui/theme")

local M = {}

-- opts = { w, h?, title, sub?, right?, right_bold?, inv?, dim?, on_tap?, on_hold?, border? }
-- dim = turned off: dashed border and regular weight (no grey: R-A3)
function M.new(opts)
    local w = math.floor(opts.w)
    local h = math.floor(opts.h or T.ROW_H)
    local fg = Draw.fg(opts.inv)
    local border = opts.border or T.BORDER
    local inner = w - 2 * border - 2 * T.ROW_PAD_X
    local right_w = 0
    local right
    if opts.right and opts.right ~= "" then
        right = Draw.text(opts.right, T.FONT_MIN, opts.right_bold ~= false and not opts.dim, math.floor(inner * 0.45), fg)
        right_w = right:getSize().w + T.SB_GAP
    end
    local left_w = inner - right_w
    local lines = { Draw.text(opts.title, T.FONT_BODY, not opts.dim, left_w, fg) }
    if opts.sub and opts.sub ~= "" then lines[2] = Draw.text(opts.sub, T.FONT_MIN, false, left_w, fg) end
    local left = Draw.box{ w = left_w, h = h - 2 * border - T.px(4), valign = "center", child = Draw.vstack(lines, 0) }
    local parts = { left }
    if right then
        parts[2] = Draw.box{ w = right_w, h = h - 2 * border - T.px(4), align = "right", valign = "center", child = right }
    end
    return Draw.box{
        w = w, h = h, bg = Draw.bg(opts.inv), border = border, radius = T.RADIUS, dashed = opts.dim or false,
        pad_x = T.ROW_PAD_X, pad_y = T.px(2), valign = "center",
        child = Draw.hstack(parts, 0), on_tap = opts.on_tap, on_hold = opts.on_hold,
    }
end

return M
