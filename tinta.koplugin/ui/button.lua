-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (C) 2026 Tinta contributors
-- Tinta: button (>= 64 px tall, 2 px border, 4 px corners). inv = selected / primary (black), disabled =
-- dashed border and regular weight (no grey: R-A3). sub: optional second line (central quick tiles).
local Draw = require("ui/draw")
local T = require("ui/theme")

local M = {}

-- opts = { label, w, h?, on_tap?, inv?, disabled?, sub?, size?, bold? }
function M.new(opts)
    local w = math.floor(opts.w)
    local h = math.floor(opts.h or T.BTN_H)
    local inv = opts.inv and not opts.disabled
    local fg = Draw.fg(inv)
    local size = opts.size or T.FONT_BODY
    local inner_w = w - 2 * T.BORDER - T.px(8)
    local label = Draw.text(opts.label, size, opts.bold ~= false and not opts.disabled, inner_w, fg)
    local child = label
    if opts.sub then
        child = Draw.vstack({ label, Draw.text(opts.sub, T.FONT_MIN, false, inner_w, fg) }, 0, "center")
    end
    return Draw.box{
        w = w, h = h, bg = Draw.bg(inv), border = T.BORDER, radius = T.RADIUS, dashed = opts.disabled or false,
        align = "center", valign = "center", child = child,
        on_tap = not opts.disabled and opts.on_tap or nil,
    }
end

-- width that fits the label
function M.width_for(label, size)
    return math.max(T.BTN_MIN_W, Draw.text_width(label, size or T.FONT_BODY, true) + T.px(32))
end

-- a row of buttons sharing width w: specs = { { label, on_tap, inv?, disabled? }, ... }
function M.row(specs, w, h)
    local Geom = require("ui/geom")
    local widths = Geom.share(w, #specs, T.GAP)
    local items = {}
    for i, s in ipairs(specs) do
        items[i] = M.new{ label = s[1], on_tap = s[2], inv = s.inv, disabled = s.disabled, w = widths[i], h = h }
    end
    return Draw.hstack(items, T.GAP)
end

return M
