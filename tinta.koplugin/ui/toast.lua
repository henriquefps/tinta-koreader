-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (C) 2026 Tinta contributors
-- Tinta: short notice (R-K2): black box above the navigation bar, 22 bold, for TOAST_MS. Not tappable.
local Draw = require("ui/draw")
local Geom = require("ui/geom")
local T = require("ui/theme")

local M = {}

function M.layers(regions, text)
    local max_w = regions.W - T.px(24) - 2 * T.TOAST_PAD_X
    local t = Draw.text(text, T.FONT_BODY, true, max_w, Draw.WHITE)
    local s = t:getSize()
    local r = Geom.toast(regions, s.w + 2 * T.TOAST_PAD_X, s.h + 2 * T.TOAST_PAD_Y)
    local box = Draw.box{ w = r.w, h = r.h, bg = Draw.BLACK, radius = T.RADIUS, align = "center", valign = "center", child = t }
    return { { widget = box, x = r.x, y = r.y } }
end

return M
