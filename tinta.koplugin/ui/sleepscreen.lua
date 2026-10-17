-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (C) 2026 Tinta contributors
-- Tinta: sleep page (R-P5, R-T11): first page of the "Repouso" layout, no interaction, no navigation bar,
-- black strip on top with the unread notifications that fit the "Na tela de repouso" option, and the footer
-- "Em repouso. Aperte o botão de energia para usar a Tinta.". Entering and leaving sleep is stage 3
-- (device/sleep.lua); this module only draws.
local Draw = require("ui/draw")
local G = require("ui/geom")
local Home = require("ui/home")
local S = require("ui/strings")
local T = require("ui/theme")

local M = {}

function M.build(win, regions)
    local host = win.host
    local W = regions.content.w
    local inner = G.rect(T.MARGIN, T.MARGIN, regions.inner.w, regions.inner.h)
    local content = Draw.Layers:new{ w = W, h = regions.content.h }
    local y = inner.y
    local summary = host:sleepSummary()   -- R-T11, "Na tela de repouso" option
    if summary then
        local txt = summary.text
        local strip = Draw.box{ w = inner.w, h = T.px(44), bg = Draw.BLACK, radius = T.RADIUS_OVERLAY, pad_x = T.px(12), valign = "center",
            child = Draw.text(txt, T.FONT_BODY, true, inner.w - T.px(24), Draw.WHITE) }
        content[#content + 1] = { widget = strip, x = inner.x, y = y }
        y = y + T.px(44) + T.GAP
    end
    local note = Draw.text(S.t("sleep_footer"), T.FONT_MIN, false, inner.w)
    local note_h = note:getSize().h + T.px(8)
    local area = G.rect(inner.x, y, inner.w, inner.y + inner.h - y - note_h - T.GAP)
    local cols, rows = G.grid_dims(regions.W, regions.H)
    local pages = host:packedPages("sleep", cols, rows)
    content[#content + 1] = { widget = Home.grid(win, pages[1] or {}, area, cols, rows, false), x = area.x, y = area.y }
    content[#content + 1] = { widget = Draw.vstack({ Draw.Fill:new{ w = inner.w, h = T.BORDER },
        Draw.box{ w = inner.w, h = note_h - T.BORDER, align = "center", valign = "center", child = note } }, 0),
        x = inner.x, y = inner.y + inner.h - note_h }
    return content
end

return M
