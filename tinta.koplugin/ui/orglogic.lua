-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (C) 2026 Tinta contributors
-- Tinta: organizer operations on a layout list (R-O1..R-O6), pure. A layout is an ordered list of
-- { app, size, hidden }. Every function returns a new list and never changes the one it gets.
-- known: optional set { [app_id] = manifest } of registered apps; items of apps that are not registered
-- (e.g. apps of a later stage) are kept in the list but never shown or touched.
local M = {}

local function copy(list)
    local out = {}
    for i, it in ipairs(list or {}) do out[i] = { app = it.app, size = it.size, hidden = it.hidden or nil } end
    return out
end
M.copy = copy

local function shown(it, known)
    return not it.hidden and (known == nil or known[it.app] ~= nil)
end

-- items shown on the page, in order (what goes to the packer)
function M.visible(list, known)
    local out = {}
    for _, it in ipairs(list or {}) do
        if shown(it, known) then out[#out + 1] = { app = it.app, size = it.size } end
    end
    return out
end

function M.find(list, app)
    for i, it in ipairs(list or {}) do if it.app == app then return i, it end end
    return nil
end

-- position of `app` among the visible items (1-based) and their count
function M.visible_index(list, app, known)
    local n, at = 0, nil
    for _, it in ipairs(list or {}) do
        if shown(it, known) then
            n = n + 1
            if it.app == app then at = n end
        end
    end
    return at, n
end

-- swaps `app` with the previous (delta = -1) or next (delta = 1) visible item ("↑ Antes" / "↓ Depois")
function M.move(list, app, delta, known)
    local out = copy(list)
    local i = M.find(out, app)
    if not i or not shown(out[i], known) then return out end
    local j = i + delta
    while j >= 1 and j <= #out and not shown(out[j], known) do j = j + delta end
    if j < 1 or j > #out then return out end
    out[i], out[j] = out[j], out[i]
    return out
end

-- next size of the app's declared sizes ("Tamanho ▸"); unknown current size -> first size
function M.cycle_size(list, app, sizes)
    local out = copy(list)
    local _, it = M.find(out, app)
    if not it or not sizes or #sizes == 0 then return out end
    local k = 0
    for n, s in ipairs(sizes) do if s == it.size then k = n end end
    it.size = sizes[k % #sizes + 1]
    return out
end

-- "Ocultar" (home: stays in the list, hidden) or "Tirar" (sleep: removed from the list)
function M.hide(list, app, mode)
    local out = copy(list)
    local i, it = M.find(out, app)
    if not i then return out end
    if mode == "sleep" then table.remove(out, i) else it.hidden = true end
    return out
end

-- brings an app back (hidden -> shown in place; absent -> appended at the end with `size`)
function M.unhide(list, app, size)
    local out = copy(list)
    local _, it = M.find(out, app)
    if it then it.hidden = nil
    else out[#out + 1] = { app = app, size = size } end
    return out
end

-- Apps for the "Ocultas:" (home) or "Adicionar:" (sleep) line, in registry order: hidden ones and
-- registered apps that are not in the list. order: list of registered app ids. exclude: set of ids never offered.
function M.extras(list, order, known, exclude)
    local out, in_list = {}, {}
    for _, it in ipairs(list or {}) do in_list[it.app] = it end
    for _, id in ipairs(order or {}) do
        local it = in_list[id]
        if (known == nil or known[id]) and not (exclude and exclude[id]) and (not it or it.hidden) then
            out[#out + 1] = id
        end
    end
    return out
end

-- Item to select after a change: keeps `sel` when it is still visible, else the first visible item.
function M.selection(list, sel, known)
    local first
    for _, it in ipairs(list or {}) do
        if shown(it, known) then
            if it.app == sel then return sel end
            first = first or it.app
        end
    end
    return first
end

-- 1-based page of `app` in packed pages (list of pages, each a list of { app, ... }); nil when not placed
function M.page_of(pages, app)
    for i, p in ipairs(pages or {}) do
        for _, it in ipairs(p) do if it.app == app then return i end end
    end
    return nil
end

-- "Copiar do Início": the sleep layout from the items of Home page 1 (packed items { app, size }), same
-- order and sizes, leaving out the apps in `exclude` (set; Sistema never goes on the sleep page).
function M.from_home(items, exclude)
    local out = {}
    for _, it in ipairs(items or {}) do
        if not (exclude and exclude[it.app]) then out[#out + 1] = { app = it.app, size = it.size } end
    end
    return out
end

-- Sizes as cells: "4x2" -> 4, 2 (nil for malformed)
function M.parse_size(s)
    local w, h = tostring(s or ""):match("^(%d+)x(%d+)$")
    if not w then return nil end
    return tonumber(w), tonumber(h)
end

-- the size to use for an item: its own when the app declares it, else the app's default (first) size
function M.effective_size(size, sizes)
    if not sizes or #sizes == 0 then return size end
    for _, s in ipairs(sizes) do if s == size then return size end end
    return sizes[1]
end

return M
