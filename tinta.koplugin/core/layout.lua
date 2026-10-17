-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (C) 2026 Tinta contributors
-- Widget grid (spec 7): packing (R-G1, R-G2), cell sizes (R-G4), default layouts (7.2), organizer operations
-- (7.3) and list paging (6.6). Pure Lua (R-A1).
--
-- A layout is an ordered list of { app = "alfa", size = "4x4", hidden = bool } (R-G1). Sizes are "<w>x<h>" in
-- cells: "2x4" is 2 columns wide and 4 rows tall. Packed positions use 0-based cell coordinates (x = column,
-- y = row), like the prototype, so pixels are x * (cell + gap).
local M = {}

M.GAP = 8                                  -- 6.1: space between widgets
M.SIZES = { "1x1", "2x2", "2x4", "4x2", "4x4" }   -- Apêndice A item 14
M.PORTRAIT = { cols = 6, rows = 8 }        -- 6.1
M.LANDSCAPE = { cols = 8, rows = 6 }

-- 7.2: the bundled apps only. An app that wants a place in the default layouts declares it in its manifest:
-- default_layout = { home = { size = "4x2", order = 10 }, sleep = { size = "4x2", order = 10 } }. Entries below are
-- ordered 100, 200, ... so a manifest `order` under 100 goes first, between them or after them as it likes.
M.DEFAULT = {
    home = {
        { app = "bateria", size = "2x2" }, { app = "notificacoes", size = "2x2" }, { app = "sistema", size = "1x1" },
    },
    sleep = {
        { app = "bateria", size = "2x2" }, { app = "notificacoes", size = "4x2" },
    },
}

local function copy_list(list)
    local out = {}
    for i, it in ipairs(list or {}) do out[i] = { app = it.app, size = it.size, hidden = it.hidden and true or nil } end
    return out
end
M.copy = copy_list

-- The default list of a page: M.DEFAULT plus the apps of `manifests` (optional, any order) that declare
-- default_layout[page] = { size, order }. A declaring app replaces the bundled entry of the same id. Declarations
-- with a size that is not in M.SIZES are ignored.
function M.default(page, manifests)
    local items, seen = {}, {}
    for _, m in ipairs(manifests or {}) do
        local d = type(m) == "table" and type(m.default_layout) == "table" and m.default_layout[page]
        if type(d) == "table" and M.valid_size(d.size) and type(m.id) == "string" and not seen[m.id] then
            seen[m.id] = true
            items[#items + 1] = { app = m.id, size = d.size, key = tonumber(d.order) or 100 }
        end
    end
    for i, it in ipairs(M.DEFAULT[page] or {}) do
        if not seen[it.app] then items[#items + 1] = { app = it.app, size = it.size, key = i * 100 } end
    end
    for i, it in ipairs(items) do it.i = i end
    table.sort(items, function(a, b) if a.key ~= b.key then return a.key < b.key end return a.i < b.i end)
    return copy_list(items)
end

-- cols, rows for the orientation (6 x 8 portrait, 8 x 6 landscape).
function M.grid_dims(landscape)
    local g = landscape and M.LANDSCAPE or M.PORTRAIT
    return g.cols, g.rows
end

-- "4x2" -> 4, 2; nil for anything else.
function M.parse_size(s)
    if type(s) ~= "string" then return nil end
    local w, h = s:match("^(%d+)x(%d+)$")
    w, h = tonumber(w), tonumber(h)
    if not w or w < 1 or h < 1 then return nil end
    return w, h
end

function M.valid_size(s)
    for _, x in ipairs(M.SIZES) do if x == s then return true end end
    return false
end

-- R-G2: for each visible item, in order, the first page where it fits, at the first free position scanning
-- rows top to bottom and columns left to right. A size larger than the grid is clamped to the grid. Items
-- with an unparseable size are skipped. Returns a list of pages, each a list of
-- { app, size, x, y, w, h }; an empty layout gives one empty page (R-G3).
function M.pack(list, cols, rows)
    local pages = {}
    local function fits(occ, x, y, w, h)
        for j = y, y + h - 1 do
            for i = x, x + w - 1 do
                if occ[j * cols + i] then return false end
            end
        end
        return true
    end
    for _, it in ipairs(list or {}) do
        local w, h = M.parse_size(it.size)
        if w and not it.hidden then
            w, h = math.min(w, cols), math.min(h, rows)
            local placed = false
            local p = 1
            while not placed do
                pages[p] = pages[p] or { occ = {}, items = {} }
                local pg = pages[p]
                for y = 0, rows - h do
                    for x = 0, cols - w do
                        if fits(pg.occ, x, y, w, h) then
                            for j = y, y + h - 1 do
                                for i = x, x + w - 1 do pg.occ[j * cols + i] = true end
                            end
                            pg.items[#pg.items + 1] = { app = it.app, size = it.size, x = x, y = y, w = w, h = h }
                            placed = true
                            break
                        end
                    end
                    if placed then break end
                end
                p = p + 1
            end
        end
    end
    local out = {}
    for i, pg in ipairs(pages) do out[i] = pg.items end
    if #out == 0 then out[1] = {} end
    return out
end

-- Page index (1-based) that holds `app`, or nil.
function M.find_page(pages, app)
    for p, items in ipairs(pages) do
        for _, it in ipairs(items) do if it.app == app then return p end end
    end
    return nil
end

-- R-G4: cell width/height in px for an area, with `gap` px between cells (floored to whole pixels).
function M.cell_size(area_w, area_h, cols, rows, gap)
    gap = gap or M.GAP
    return math.floor((area_w - (cols - 1) * gap) / cols), math.floor((area_h - (rows - 1) * gap) / rows)
end

-- Pixel box of a packed item inside the grid area (origin at the area's top-left):
-- w cells measure w * cell + (w - 1) * gap (R-G4).
function M.box(item, cell_w, cell_h, gap)
    gap = gap or M.GAP
    return {
        x = item.x * (cell_w + gap),
        y = item.y * (cell_h + gap),
        w = item.w * cell_w + (item.w - 1) * gap,
        h = item.h * cell_h + (item.h - 1) * gap,
    }
end

-- Visible app ids in layout order, without repeats (the scheduler refreshes these, R-U4).
function M.visible_apps(list)
    local seen, out = {}, {}
    for _, it in ipairs(list or {}) do
        if not it.hidden and not seen[it.app] then seen[it.app] = true; out[#out + 1] = it.app end
    end
    return out
end

-- Cleans a stored layout against the known apps: drops unknown apps and repeats, replaces sizes the app does
-- not declare with its default (first) size. `apps` maps id -> manifest (or anything with .sizes).
function M.normalize(list, apps)
    local out, seen = {}, {}
    for _, it in ipairs(list or {}) do
        local m = type(it) == "table" and apps[it.app]
        if m and not seen[it.app] then
            seen[it.app] = true
            local size = it.size
            local ok = false
            for _, s in ipairs(m.sizes or {}) do if s == size then ok = true end end
            if not ok then size = (m.sizes or {})[1] end
            if size then out[#out + 1] = { app = it.app, size = size, hidden = it.hidden and true or nil } end
        end
    end
    return out
end

---------------------------------------------------------------- organizer (7.3); all return a new list

local function index_of(list, app)
    for i, it in ipairs(list) do if it.app == app then return i end end
end

-- R-O3 "↑ Antes" (delta -1) / "↓ Depois" (+1): swaps with the previous/next visible item. Returns the new
-- list and whether it changed.
function M.move(list, app, delta)
    local out = copy_list(list)
    local i = index_of(out, app)
    if not i or out[i].hidden then return out, false end
    local j = i + delta
    while out[j] and out[j].hidden do j = j + delta end
    if not out[j] then return out, false end
    out[i], out[j] = out[j], out[i]
    return out, true
end

-- R-O3 "Tamanho ▸": next size in the app's declared list (wraps).
function M.cycle_size(list, app, sizes)
    local out = copy_list(list)
    local i = index_of(out, app)
    if not i or not sizes or #sizes == 0 then return out, false end
    local cur, nxt = out[i].size, sizes[1]
    for k, s in ipairs(sizes) do
        if s == cur then nxt = sizes[k % #sizes + 1]; break end
    end
    if nxt == cur then return out, false end
    out[i].size = nxt
    return out, true
end

-- R-O3 "Ocultar" (Início): keeps the entry, hidden.
function M.hide(list, app)
    local out = copy_list(list)
    local i = index_of(out, app)
    if not i or out[i].hidden then return out, false end
    out[i].hidden = true
    return out, true
end

-- R-O3 "Tirar" (Repouso): removes the entry.
function M.remove(list, app)
    local out = copy_list(list)
    local i = index_of(out, app)
    if not i then return out, false end
    table.remove(out, i)
    return out, true
end

-- R-O4: brings an app back (unhides it, or appends it) in its default size.
function M.show(list, app, default_size)
    local out = copy_list(list)
    local i = index_of(out, app)
    if i then
        if not out[i].hidden then return out, false end
        out[i].hidden = nil
        out[i].size = default_size or out[i].size
        return out, true
    end
    out[#out + 1] = { app = app, size = default_size }
    return out, true
end

-- R-O4: apps out of the layout (hidden, or absent), in `all_ids` order.
function M.outside(list, all_ids)
    local visible = {}
    for _, it in ipairs(list or {}) do if not it.hidden then visible[it.app] = true end end
    local out = {}
    for _, id in ipairs(all_ids) do if not visible[id] then out[#out + 1] = id end end
    return out
end

---------------------------------------------------------------- list paging (6.6)

-- Paging of n items with per_page each: clamps `page` and returns page, pages, first, last (1-based, inclusive;
-- first > last when n == 0). There is always at least one page.
function M.paginate(n, per_page, page)
    per_page = math.max(1, per_page)
    local pages = math.max(1, math.ceil(n / per_page))
    page = math.max(1, math.min(page or 1, pages))
    local first = (page - 1) * per_page + 1
    return page, pages, first, math.min(n, first + per_page - 1)
end

return M
