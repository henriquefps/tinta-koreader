-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (C) 2026 Tinta contributors
-- Tinta: app header (6.4): app name (26 bold) on the left, state text on the right (bold when busy or in
-- error), 2 px bottom border.
local Draw = require("ui/draw")
local T = require("ui/theme")

local M = {}

-- returns the header widget (w x HEADER_H)
function M.new(w, title, meta, emphasis)
    local title_w = Draw.text(title, T.FONT_TITLE, true, math.floor(w * 0.62))
    local tw = title_w:getSize().w
    local parts = { title_w }
    if meta and meta ~= "" then
        local mw = w - tw - T.SB_GAP - T.px(8)
        local m = Draw.text(meta, T.FONT_MIN, emphasis ~= nil, math.max(T.px(10), mw))
        parts[2] = Draw.box{ w = math.max(T.px(10), mw) + T.SB_GAP, h = title_w:getSize().h, align = "right", valign = "center", child = m }
    end
    local line = Draw.box{ w = w, h = T.HEADER_H - T.BORDER, pad_x = T.px(4), valign = "center", child = Draw.hstack(parts, 0) }
    return Draw.vstack({ line, Draw.Fill:new{ w = w, h = T.BORDER } }, 0)
end

return M
