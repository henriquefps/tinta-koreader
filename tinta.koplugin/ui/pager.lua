-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (C) 2026 Tinta contributors
-- Tinta: page control "‹  N/M  ›" with 64 px buttons (6.6). page is 0-based.
local Button = require("ui/button")
local Draw = require("ui/draw")
local T = require("ui/theme")

local M = {}

function M.new(w, page, pages, on_prev, on_next)
    local prev = Button.new{ label = "‹", w = T.TOUCH, h = T.PAGER_H, size = T.FONT_TITLE,
        disabled = page <= 0, on_tap = on_prev }
    local next = Button.new{ label = "›", w = T.TOUCH, h = T.PAGER_H, size = T.FONT_TITLE,
        disabled = page >= pages - 1, on_tap = on_next }
    local label = Draw.box{ w = T.px(120), h = T.PAGER_H, align = "center", valign = "center",
        child = Draw.text(("%d/%d"):format(page + 1, pages), T.FONT_BODY, false) }
    return Draw.box{ w = w, h = T.PAGER_H, align = "center", valign = "center",
        child = Draw.hstack({ prev, label, next }, T.px(16)) }
end

return M
