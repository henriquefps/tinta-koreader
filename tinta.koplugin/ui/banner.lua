-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (C) 2026 Tinta contributors
-- Tinta: top banner of a new notification (R-T5): black box right below the status bar, "App · HH:MM" and
-- the title, for BANNER_MS. Tapping opens the notification.
local Draw = require("ui/draw")
local Geom = require("ui/geom")
local T = require("ui/theme")

local M = {}

-- b = { head = "App · HH:MM", title }
function M.layers(regions, b, on_tap)
    local inner = regions.W - 2 * T.MARGIN - 2 * T.BANNER_PAD_X
    local content = Draw.vstack({
        Draw.text(b.head or "", T.FONT_MIN, false, inner, Draw.WHITE),
        Draw.text(b.title or "", T.FONT_BODY, true, inner, Draw.WHITE),
    }, T.px(2))
    local h = content:getSize().h + 2 * T.BANNER_PAD_Y
    local r = Geom.banner(regions.W, h)
    local box = Draw.box{ w = r.w, h = r.h, bg = Draw.BLACK, radius = T.RADIUS_OVERLAY,
        pad_x = T.BANNER_PAD_X, pad_y = T.BANNER_PAD_Y, valign = "center", child = content, on_tap = on_tap }
    return { { widget = box, x = r.x, y = r.y } }
end

return M
