-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (C) 2026 Tinta contributors
-- Tinta: home screen (7.1, 7.2): the visible layout items packed into the grid (core layout.pack), one page
-- at a time, with a pager when there is more than one page. Tap a widget opens the app's main screen; hold
-- opens the organizer with that widget selected (R-N3). Also the non-interactive grid of the sleep page.
local Draw = require("ui/draw")
local G = require("ui/geom")
local Pager = require("ui/pager")
local S = require("ui/strings")
local T = require("ui/theme")
local WidgetFrame = require("ui/widgetframe")

local M = {}

-- pages of the home layout for this window size
function M.pages(win, regions, page_name)
    local cols, rows = G.grid_dims(regions.W, regions.H)
    return win.host:packedPages(page_name or "home", cols, rows), cols, rows
end

-- sleep page, app set to "oculto" (8.5): the app is not called; a plain frame with its name only. No attention
-- inversion, no dashed border, no footer: nothing of the app's state shows.
function M.hidden_tile(host, it, rect)
    local box = WidgetFrame.body_box(rect.w, rect.h, it.size, false)
    local name = host:appName(it.app) or it.app
    local body
    if it.size == "1x1" then body = Draw.text(name, T.FONT_MIN, true, box.w)
    else body = Draw.textbox(name, T.FONT_WNAME, box.w, box.h, true) end
    return WidgetFrame.new{ w = rect.w, h = rect.h, size = it.size, body = body }
end

-- one tile: frame + the app's inside (protected) + footer
function M.tile(win, it, rect, interactive)
    local host = win.host
    if not interactive and host:sleepPlaceholder(it.app) then return M.hidden_tile(host, it, rect) end
    local inv = host:attention(it.app)
    local stale = host:isStale(it.app)
    local box = WidgetFrame.body_box(rect.w, rect.h, it.size, inv)
    local ok, body = host:callWidget(it.app, it.size, box)
    if not ok or type(body) ~= "table" or not body.paintTo then
        body = WidgetFrame.error_body(box, host:appName(it.app), S.t("widget_error", host:appName(it.app) or it.app))
    end
    local cols = select(1, require("ui/orglogic").parse_size(it.size)) or 2
    local fl, fr
    if interactive then
        fl, fr = host:widgetFooter(it.app, cols < 4)
    else
        -- sleep page: the awake interval ("a cada 30 s") is false while asleep; show the sleep refresh time or nothing
        local at = host.sleep_info and host.sleep_info.at
        fl = at and S.t("sleep_widget_updated", at) or nil
    end
    return WidgetFrame.new{
        w = rect.w, h = rect.h, size = it.size, inv = inv, stale = stale, body = body,
        footer_left = fl, footer_right = fr,
        on_tap = interactive and function() win:openApp(it.app) end or nil,
        on_hold = interactive and function() win:openOrganizer("home", it.app) end or nil,
    }
end

-- grid of `items` (packed page) inside `area` (absolute rect); returns a Layers widget of area size
function M.grid(win, items, area, cols, rows, interactive)
    local layers = Draw.Layers:new{ w = area.w, h = area.h }
    local origin = { x = 0, y = 0, w = area.w, h = area.h }
    for _, it in ipairs(items or {}) do
        local r = G.tile_rect(it, origin, cols, rows, T.GRID_GAP)
        layers[#layers + 1] = { widget = M.tile(win, it, r, interactive), x = r.x, y = r.y }
    end
    return layers
end

function M.build(win, regions)
    local route = win:current()
    local pages, cols, rows = M.pages(win, regions)
    route.page = math.max(0, math.min(route.page or 0, #pages - 1))
    local content = Draw.Layers:new{ w = regions.content.w, h = regions.content.h }
    -- inner rect relative to the content origin
    local inner = G.rect(T.MARGIN, T.MARGIN, regions.inner.w, regions.inner.h)
    local items = pages[route.page + 1] or {}
    if #pages == 1 and #items == 0 then
        content[1] = { widget = Draw.box{ w = inner.w, h = T.px(120), border = T.BORDER, dashed = true, radius = T.RADIUS,
            align = "center", valign = "center", child = Draw.textbox(S.t("home_empty"), T.FONT_BODY, inner.w - T.px(40), nil, false, nil, "center"),
            on_tap = function() win:openOrganizer("home") end }, x = inner.x, y = inner.y }
        return content
    end
    local area, pager = G.home_area(inner, #pages)
    content[#content + 1] = { widget = M.grid(win, items, area, cols, rows, true), x = area.x, y = area.y }
    if pager then
        content[#content + 1] = { widget = Pager.new(pager.w, route.page, #pages,
            function() M.turn(win, -1) end, function() M.turn(win, 1) end), x = pager.x, y = pager.y }
    end
    return content
end

-- page swipe / pager on home (full refresh, R-R1)
function M.turn(win, delta)
    if not win:isHome() then return end
    local regions = win:regions()
    local pages = M.pages(win, regions)
    local route = win:current()
    local n = math.max(0, math.min(#pages - 1, (route.page or 0) + delta))
    if n ~= (route.page or 0) then win:setPage(n) end
end

return M
