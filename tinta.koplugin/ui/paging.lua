-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (C) 2026 Tinta contributors
-- Tinta: list paging (6.6: lists that do not fit become pages, never scrolling), pure.
local M = {}

function M.count(n, per)
    if not per or per < 1 then return 1 end
    return math.max(1, math.ceil((n or 0) / per))
end

-- page (0-based) clamped to [0, pages - 1]
function M.clamp(page, pages)
    page = math.floor(tonumber(page) or 0)
    return math.max(0, math.min(page, (pages or 1) - 1))
end

-- items of page `page` (0-based), the clamped page and the page count
function M.slice(list, page, per)
    list = list or {}
    local pages = M.count(#list, per)
    page = M.clamp(page, pages)
    local out = {}
    for i = page * per + 1, math.min(#list, (page + 1) * per) do out[#out + 1] = list[i] end
    return out, page, pages
end

-- rows of `row_h` (plus `gap` between them) that fit in `avail` px, at least 1
function M.fit(avail, row_h, gap)
    gap = gap or 0
    return math.max(1, math.floor((avail + gap) / (row_h + gap)))
end

-- Items of different heights flowed into columns and pages (Sistema → Repouso has section labels, rows and
-- notes). heights[i] in px, keep[i] = true keeps item i on the same column as item i + 1 (a section label stays
-- with its first row). Returns pages: { { {i, ...}, ... one list of item indices per column }, ... }.
-- An item taller than `avail` sits alone in its column.
function M.flow(heights, keep, avail, gap, cols)
    gap = gap or 0
    cols = math.max(1, cols or 1)
    keep = keep or {}
    local pages, page, col, used = {}, nil, 0, 0
    local function new_page()
        page = {}
        for c = 1, cols do page[c] = {} end
        pages[#pages + 1] = page
        col, used = 1, 0
    end
    new_page()
    for i = 1, #heights do
        local need = heights[i]
        if keep[i] and heights[i + 1] then need = need + gap + heights[i + 1] end
        if used > 0 and used + gap + need > avail then
            if col < cols then col = col + 1; used = 0 else new_page() end
        end
        local list = page[col]
        list[#list + 1] = i
        used = used + (used > 0 and gap + heights[i] or heights[i])
    end
    return pages
end

return M
