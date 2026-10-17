-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (C) 2026 Tinta contributors
-- Tinta: menu sheet (6.5). Opens over the content, above the navigation bar; 60 px items. Tapping outside
-- closes it. Returns overlay layers for the window: backdrop first, then the sheet.
local Draw = require("ui/draw")
local Geom = require("ui/geom")
local T = require("ui/theme")

local M = {}

-- items = { { label, value?, on_tap }, ... }; on_close closes the sheet
function M.layers(regions, title, items, on_close)
    local r = Geom.sheet(regions, #items)
    local W = regions.W
    local pad = T.px(14)
    local backdrop = Draw.box{ w = W, h = regions.H, on_tap = on_close }
    local rows = {
        Draw.Fill:new{ w = W, h = T.SHEET_BORDER },
        Draw.box{ w = W, h = T.SHEET_TITLE_H - T.BORDER, pad_x = pad, valign = "center",
            child = Draw.text(title, T.FONT_BODY, true, W - 2 * pad) },
        Draw.Fill:new{ w = W, h = T.BORDER },
    }
    local n_fit = math.floor((r.h - T.SHEET_BORDER - T.SHEET_TITLE_H) / T.SHEET_ITEM_H)
    for i, it in ipairs(items) do
        if i > n_fit then break end
        local value = it[2] and Draw.text(it[2], T.FONT_BODY, true, math.floor(W * 0.4)) or nil
        local vw = value and value:getSize().w or 0
        local parts = { Draw.text(it[1], T.FONT_BODY, false, W - 2 * pad - vw - T.GAP) }
        if value then
            parts[2] = Draw.space(math.max(0, W - 2 * pad - parts[1]:getSize().w - vw), 1)
            parts[3] = value
        end
        local last = i == math.min(#items, n_fit)
        rows[#rows + 1] = Draw.box{ w = W, h = T.SHEET_ITEM_H - (last and 0 or T.BORDER), pad_x = pad, valign = "center",
            child = Draw.hstack(parts, 0), on_tap = it[3] }
        if not last then rows[#rows + 1] = Draw.Fill:new{ w = W, h = T.BORDER } end
    end
    local sheet = Draw.box{ w = W, h = r.h, bg = Draw.WHITE, child = Draw.vstack(rows, 0), on_tap = function() end }
    return { { widget = backdrop, x = 0, y = 0 }, { widget = sheet, x = r.x, y = r.y } }
end

return M
