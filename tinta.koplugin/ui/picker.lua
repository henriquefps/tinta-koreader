-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (C) 2026 Tinta contributors
-- Tinta: choice popup (6.10, R-K4). The field title and one row per option, the current one inverted with a "●",
-- paged when the options do not fit (never scrolling). A tap on an option picks it; a tap outside (the backdrop
-- takes every tap, the navigation bar included) cancels. `footer` adds a closing button ("Pronto") for popups
-- that stay open after a pick. Modal like the dialog; returns overlay layers for the window.
local Button = require("ui/button")
local Draw = require("ui/draw")
local Geom = require("ui/geom")
local Logic = require("ui/picklogic")
local Pager = require("ui/pager")
local Row = require("ui/row")
local T = require("ui/theme")

local M = {}

-- p = { title, options (normalized), current, page (0-based, nil = the page of the current option), footer?, empty? }
-- cb = { on_pick(opt), on_cancel, on_page(delta), on_footer? }
-- Returns the layers and the page shown.
function M.layers(regions, p, cb)
    local W, H = regions.W, regions.H
    local bottom = regions.nav and regions.nav.y or H
    local w = math.min(T.DIALOG_W, W - T.px(40))
    local chrome = 2 * (T.BORDER_DIALOG + T.DIALOG_PAD)
    local inner = w - chrome
    local title = Draw.text(p.title or "", T.FONT_TITLE, true, inner)
    local footer_h = p.footer and (T.BTN_H + T.GAP) or 0
    local avail = bottom - T.SB_H - 2 * T.MARGIN - chrome - title:getSize().h - T.GAP - footer_h
    local n = #p.options
    local per = Logic.per_page(n, avail, T.ROW_H, T.ROW_GAP, T.PAGER_H + T.GAP)
    local page = p.page or Logic.start_page(p.options, p.current, per)
    local shown, pages
    shown, page, pages = Logic.page(p.options, page, per)

    local rows = {}
    for _, o in ipairs(shown) do
        local cur = Logic.is_current(o, p.current)
        rows[#rows + 1] = Row.new{ w = inner, title = o.label, sub = o.sub, right = cur and "●" or "", inv = cur,
            on_tap = function() cb.on_pick(o) end }
    end
    local list
    if #rows == 0 then
        list = Draw.box{ w = inner, h = T.ROW_H, valign = "center", pad_x = T.ROW_PAD_X,
            child = Draw.text(p.empty or "", T.FONT_BODY, false, inner - 2 * T.ROW_PAD_X) }
    else
        list = Draw.vstack(rows, T.ROW_GAP)
    end
    local parts = { title, list }
    if pages > 1 then
        parts[#parts + 1] = Pager.new(inner, page, pages, function() cb.on_page(-1) end, function() cb.on_page(1) end)
    end
    if p.footer then
        parts[#parts + 1] = Button.new{ label = p.footer, w = inner, inv = true, on_tap = cb.on_footer or cb.on_cancel }
    end
    local list_h = #rows == 0 and T.ROW_H or (#rows * T.ROW_H + (#rows - 1) * T.ROW_GAP)
    local h = chrome + title:getSize().h + T.GAP + list_h + (pages > 1 and (T.GAP + T.PAGER_H) or 0) + footer_h
    local r = Geom.popup(regions, w, h)
    local backdrop = Draw.box{ w = W, h = H, on_tap = cb.on_cancel }
    local box = Draw.box{ w = r.w, h = r.h, bg = Draw.WHITE, border = T.BORDER_DIALOG, radius = T.RADIUS_OVERLAY,
        pad_x = T.DIALOG_PAD, pad_y = T.DIALOG_PAD, on_tap = function() end,
        child = Draw.vstack(parts, T.GAP) }
    return { { widget = backdrop, x = 0, y = 0 }, { widget = box, x = r.x, y = r.y } }, page
end

return M
