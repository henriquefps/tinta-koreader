-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (C) 2026 Tinta contributors
-- Tinta: screen geometry (pure, no KOReader). Regions of the window, home grid cells (R-G4), navigation
-- buttons, organizer map, overlay boxes. Rectangles are { x, y, w, h } in integer pixels, relative to the content
-- box: the 3:4 area (4:3 landscape) centred on the screen at the scale of ui/theme (spec 6.1). The window paints
-- that box at (T.ox, T.oy) over a white letterbox, so on a 3:4 screen the box is the screen.
local T = require("ui/theme")

local M = {}

local floor = math.floor

local function rect(x, y, w, h) return { x = floor(x), y = floor(y), w = math.max(0, floor(w)), h = math.max(0, floor(h)) } end
M.rect = rect

function M.inside(r, x, y)
    return r ~= nil and x ~= nil and y ~= nil and x >= r.x and y >= r.y and x < r.x + r.w and y < r.y + r.h
end

function M.landscape(W, H) return W > H end

-- columns and rows of the home grid for this screen
function M.grid_dims(W, H)
    local g = M.landscape(W, H) and T.GRID_LANDSCAPE or T.GRID_PORTRAIT
    return g[1], g[2]
end

-- Window regions. nav_mode "bar" (default) or "gestures" (R-N2: no bar, a handle instead).
-- sleep = true: status bar only, no navigation (R-P5).
-- W, H: the screen; the regions (and r.W, r.H) are those of the content box inside it.
function M.regions(W, H, nav_mode, sleep)
    T.configure(W, H)
    local r = { SW = W, SH = H, ox = T.ox, oy = T.oy }
    W, H = T.BW, T.BH
    r.W, r.H = W, H
    r.status = rect(0, 0, W, T.SB_H)
    local bottom = H
    if not sleep and nav_mode ~= "gestures" then
        r.nav = rect(0, H - T.NAV_H, W, T.NAV_H)
        bottom = H - T.NAV_H
    elseif not sleep then
        r.handle = rect((W - T.HANDLE_W) / 2, H - T.HANDLE_BOTTOM - T.HANDLE_H, T.HANDLE_W, T.HANDLE_H)
    end
    r.content = rect(0, T.SB_H, W, bottom - T.SB_H)
    -- inner content (margins applied)
    r.inner = rect(T.MARGIN, T.SB_H + T.MARGIN, W - 2 * T.MARGIN, bottom - T.SB_H - 2 * T.MARGIN)
    return r
end

-- Edge (in px from the area origin) of grid line i of n cells sharing `size` with `gap` between cells.
-- Cell i spans [edge(i), edge(i + 1) - gap). Distributes the rounding so the grid fills the area exactly.
local function edge(i, n, size, gap)
    return floor(i * (size + gap) / n + 0.5)
end

-- cell size (R-G4): (area - (n - 1) * gap) / n, as a float
function M.cell(size, n, gap)
    return (size - (n - 1) * gap) / n
end

-- pixel rectangle of a packed item { x, y, w, h } (cells) inside an area { x, y, w, h }
function M.tile_rect(item, area, cols, rows, gap)
    gap = gap or T.GRID_GAP
    local x0 = edge(item.x, cols, area.w, gap)
    local x1 = edge(item.x + item.w, cols, area.w, gap) - gap
    local y0 = edge(item.y, rows, area.h, gap)
    local y1 = edge(item.y + item.h, rows, area.h, gap) - gap
    return rect(area.x + x0, area.y + y0, x1 - x0, y1 - y0)
end

-- Home grid area inside the inner content; a pager row (R: 6.6) takes the bottom when there is more than one page.
function M.home_area(inner, pages)
    if (pages or 1) > 1 then
        return rect(inner.x, inner.y, inner.w, inner.h - T.PAGER_H - T.GAP),
               rect(inner.x, inner.y + inner.h - T.PAGER_H, inner.w, T.PAGER_H)
    end
    return rect(inner.x, inner.y, inner.w, inner.h), nil
end

-- n equal buttons across width W, with dividers of `div` px between them (navigation bar).
-- Returns a list of { x, w } (the divider belongs to the left side of each button after the first).
function M.split(W, n, div)
    local out = {}
    for i = 0, n - 1 do
        local x0 = floor(i * W / n + 0.5)
        local x1 = floor((i + 1) * W / n + 0.5)
        local d = i > 0 and div or 0
        out[#out + 1] = { x = x0 + d, w = x1 - x0 - d }
    end
    return out
end

-- widths of n items sharing `w` with `gap` between them (button rows, stat blocks); sums exactly to w
function M.share(w, n, gap)
    local out = {}
    for i = 0, n - 1 do
        local x0 = edge(i, n, w, gap)
        local x1 = edge(i + 1, n, w, gap) - gap
        out[#out + 1] = x1 - x0
    end
    return out
end

-- dialog box centered on the screen
function M.dialog(W, H, h)
    local w = math.min(T.DIALOG_W, W - T.px(40))
    return rect((W - w) / 2, (H - h) / 2, w, h)
end

-- top banner (R-T5): right below the status bar, MARGIN from the edges
function M.banner(W, h)
    return rect(T.MARGIN, T.SB_H + T.MARGIN, W - 2 * T.MARGIN, h)
end

-- menu sheet: full width, bottom edge on top of the navigation bar (or the screen bottom)
function M.sheet(regions, n_items)
    local h = T.SHEET_BORDER + T.SHEET_TITLE_H + n_items * T.SHEET_ITEM_H
    local bottom = regions.nav and regions.nav.y or regions.H
    h = math.min(h, bottom - T.SB_H)
    return rect(0, bottom - h, regions.W, h)
end

-- toast box (R-K2): centered, TOAST_ABOVE_NAV above the navigation bar
function M.toast(regions, w, h)
    local bottom = regions.nav and regions.nav.y or regions.H
    w = math.min(w, regions.W - T.px(24))
    return rect((regions.W - w) / 2, bottom - T.TOAST_ABOVE_NAV - h, w, h)
end

-- Organizer map: the page grid in scale inside `box`, same aspect as the home grid area.
-- Returns the map rectangle (centered in box) and its inner area (border + padding removed).
function M.map(box, home_w, home_h)
    local k = math.min(box.w / home_w, box.h / home_h)
    local w, h = floor(home_w * k), floor(home_h * k)
    local r = rect(box.x + (box.w - w) / 2, box.y + (box.h - h) / 2, w, h)
    local p = T.BORDER + T.MAP_GAP
    return r, rect(r.x + p, r.y + p, r.w - 2 * p, r.h - 2 * p)
end

return M
