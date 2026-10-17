-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (C) 2026 Tinta contributors
-- Tinta: navigation bar (6.3, R-N1, R-N2): ⌂ Início, ‹ Voltar, ↻ Atualizar, ☰ Menu; 72 px, 4 equal buttons,
-- 2 px dividers and top border. Disabled buttons: regular weight, no icon (no grey, R-A3).
-- In "gestures only" mode the bar is replaced by a 120 x 6 handle (M.handle).
local Draw = require("ui/draw")
local Geom = require("ui/geom")
local S = require("ui/strings")
local T = require("ui/theme")

local M = {}

-- state = { home_enabled, back_enabled }; cb = { home, back, refresh, menu }
function M.new(W, state, cb)
    local inner_h = T.NAV_H - T.NAV_DIV
    local specs = {
        { S.t("nav_home"), cb.home, state.home_enabled, function() return Draw.icon_house() end },
        { S.t("nav_back"), cb.back, state.back_enabled, function() return Draw.text("‹", T.FONT_TITLE, true) end },
        { S.t("nav_refresh"), cb.refresh, true, function() return Draw.text("↻", T.FONT_TITLE, true) end },
        { S.t("nav_menu"), cb.menu, true, function() return Draw.icon_bars() end },
    }
    local cols = Geom.split(W, T.NAV_BUTTONS, T.NAV_DIV)
    local items = {}
    for i, s in ipairs(specs) do
        local enabled = s[3]
        local label = Draw.text(s[1], T.FONT_BODY, enabled, cols[i].w - T.px(44))
        local content = enabled and Draw.hstack({ s[4](), label }, T.px(8)) or label
        if i > 1 then items[#items + 1] = Draw.Fill:new{ w = T.NAV_DIV, h = inner_h } end
        items[#items + 1] = Draw.box{ w = cols[i].w, h = inner_h, align = "center", valign = "center",
            child = content, on_tap = enabled and s[2] or nil }
    end
    return Draw.vstack({ Draw.Fill:new{ w = W, h = T.NAV_DIV }, Draw.hstack(items, 0) }, 0)
end

-- the "gestures only" handle
function M.handle()
    return Draw.Fill:new{ w = T.HANDLE_W, h = T.HANDLE_H, radius = T.px1(3) }
end

return M
