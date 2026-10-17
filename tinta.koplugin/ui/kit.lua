-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (C) 2026 Tinta contributors
-- Tinta: the components of section 6 as the apps see them (ctx.ui). Apps build their widgets and screens with
-- these, inside the box the core gives them (R-W1). Everything here is KOReader-backed except `theme`.
local AppHeader = require("ui/appheader")
local Button = require("ui/button")
local Draw = require("ui/draw")
local G = require("ui/geom")
local Pager = require("ui/pager")
local Paging = require("ui/paging")
local Row = require("ui/row")
local T = require("ui/theme")
local WidgetFrame = require("ui/widgetframe")

local Kit = {
    theme = T,
    draw = Draw,
    button = Button.new,
    button_row = Button.row,
    button_width = Button.width_for,
    row = Row.new,
    pager = Pager.new,
    header = AppHeader.new,
    text = Draw.text,
    textbox = Draw.textbox,
    vstack = Draw.vstack,
    hstack = Draw.hstack,
    box = Draw.box,
    space = Draw.space,
    fill = function(w, h, inv) return Draw.Fill:new{ w = w, h = h, color = inv and Draw.WHITE or Draw.BLACK } end,
    fg = Draw.fg,
    bg = Draw.bg,
    -- standard widget inside: spec = { title, icon, primary, secondary, lines = { { l, r } }, number, short }
    basic = WidgetFrame.basic,
    icons = {
        wifi = Draw.icon_wifi, bell = Draw.icon_bell, gear = Draw.icon_gear,
        battery = function(pct, w, h, fg) return Draw.Battery:new{ pct = pct, w = w, h = h, fg = fg or Draw.BLACK } end,
    },
}

local function window()
    local ok, Host = pcall(require, "ui/host")
    return ok and Host.window or nil
end

-- route being built (holds the page of paged lists)
local function route()
    local win = window()
    if not win then return { page = 0 } end
    return win.building_route or win:current()
end

-- Paged list (6.6, never scrolling). items: any values; build(item, w, h) -> widget of w x h.
-- opts = { item_h = ROW_H, gap = ROW_GAP, cols = 1 (2 in landscape when opts.two_cols) }
-- Returns a widget of box size with a pager at the bottom when needed.
function Kit.paged(box, items, build, opts)
    opts = opts or {}
    local item_h = opts.item_h or T.ROW_H
    local gap = opts.gap or T.ROW_GAP
    local cols = (opts.two_cols and box.landscape) and 2 or 1
    local avail = box.h
    local per_col = Paging.fit(avail, item_h, gap)
    local per = per_col * cols
    if #items > per then
        avail = box.h - T.PAGER_H - T.GAP
        per_col = Paging.fit(avail, item_h, gap)
        per = per_col * cols
    end
    local r = route()
    local page_items, page, pages = Paging.slice(items, r.page or 0, per)
    r.page = page
    local col_w = G.share(box.w, cols, T.GAP)
    local columns = {}
    for c = 1, cols do
        local list = {}
        for i = 1, per_col do
            local it = page_items[(c - 1) * per_col + i]
            if it ~= nil then list[#list + 1] = build(it, col_w[c], item_h) end
        end
        columns[c] = Draw.vstack(list, gap)
    end
    local body = cols == 1 and columns[1] or Draw.hstack(columns, T.GAP, "start")
    local parts = { Draw.box{ w = box.w, h = avail, child = body } }
    if pages > 1 then
        local win = window()
        parts[2] = Pager.new(box.w, page, pages,
            function() if win then win:setPage(page - 1) end end,
            function() if win then win:setPage(page + 1) end end)
    end
    return Draw.vstack(parts, T.GAP)
end

-- rows = { { title, sub, right, inv, on_tap }, ... }: paged rows, two columns in landscape (10.5).
-- Two more kinds of entry, for screens that group their rows (Sistema → Repouso):
--   { section = "TEXT" }                  small bold label, kept with the row after it
--   { note = { "line", ... }, indent? }   small plain text lines, not tappable
-- With any of these the entries flow by height (Paging.flow) instead of a fixed row height.
function Kit.rows(box, rows, opts)
    opts = opts or {}
    local mixed = false
    for _, r in ipairs(rows) do if r.section or r.note then mixed = true; break end end
    if not mixed then
        return Kit.paged(box, rows, function(r, w, h)
            return Row.new{ w = w, h = h, title = r.title, sub = r.sub, right = r.right, inv = r.inv, dim = r.dim, on_tap = r.on_tap, on_hold = r.on_hold }
        end, { two_cols = opts.two_cols ~= false, item_h = opts.item_h })
    end
    local cols = (opts.two_cols ~= false and box.landscape) and 2 or 1
    local col_w = G.share(box.w, cols, T.GAP)
    local heights, keep = {}, {}
    for i, r in ipairs(rows) do
        if r.section then heights[i] = T.SECTION_H; keep[i] = true
        elseif r.note then
            local lines = type(r.note) == "table" and r.note or { r.note }
            heights[i] = #lines * T.NOTE_LINE_H + T.px(6)
        else heights[i] = opts.item_h or T.ROW_H end
    end
    local avail = box.h
    local pages = Paging.flow(heights, keep, avail, T.ROW_GAP, cols)
    if #pages > 1 then
        avail = box.h - T.PAGER_H - T.GAP
        pages = Paging.flow(heights, keep, avail, T.ROW_GAP, cols)
    end
    local r0 = route()
    local pn = Paging.clamp(r0.page or 0, #pages)
    r0.page = pn
    local columns = {}
    for c = 1, cols do
        local list = {}
        for _, i in ipairs(pages[pn + 1][c]) do
            local r = rows[i]
            if r.section then
                list[#list + 1] = Draw.box{ w = col_w[c], h = heights[i], valign = "bottom", pad_x = T.ROW_PAD_X,
                    child = Draw.text(r.section, T.FONT_MIN, true, col_w[c] - 2 * T.ROW_PAD_X) }
            elseif r.note then
                local lines = type(r.note) == "table" and r.note or { r.note }
                local indent = r.indent or (T.ROW_PAD_X + T.px(16))
                local texts = {}
                for k, line in ipairs(lines) do texts[k] = Draw.text(line, T.FONT_MIN, false, col_w[c] - indent - T.ROW_PAD_X) end
                list[#list + 1] = Draw.box{ w = col_w[c], h = heights[i], valign = "center", pad_x = indent, child = Draw.vstack(texts, 0) }
            else
                list[#list + 1] = Row.new{ w = col_w[c], h = heights[i], title = r.title, sub = r.sub, right = r.right,
                    inv = r.inv, dim = r.dim, on_tap = r.on_tap, on_hold = r.on_hold }
            end
        end
        columns[c] = Draw.vstack(list, T.ROW_GAP)
    end
    local body = cols == 1 and columns[1] or Draw.hstack(columns, T.GAP, "start")
    local parts = { Draw.box{ w = box.w, h = avail, child = body } }
    if #pages > 1 then
        local win = window()
        parts[2] = Pager.new(box.w, pn, #pages,
            function() if win then win:setPage(pn - 1) end end,
            function() if win then win:setPage(pn + 1) end end)
    end
    return Draw.vstack(parts, T.GAP)
end

-- box of the current screen body (same one the screen function receives)
function Kit.content_box()
    local win = window()
    if not win then return { w = T.px(584), h = T.px(608), landscape = false } end
    return win:bodyBox(win:regions())
end

return Kit
