-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (C) 2026 Tinta contributors
-- Tinta: organizer (7.3). Tabs "Início" / "Repouso" (R-O1), map of one page with a pager over ALL the pages of the
-- list (R-O2: opens on the page of the selected widget; the selection stays when another page is shown, and
-- "↑ Antes" / "↓ Depois" move the widget through the whole list, so it crosses page breaks), "Copiar do Início"
-- on the sleep tab (copies Home page 1, with confirmation),
-- "↑ Antes", "↓ Depois", "Tamanho ▸", "Ocultar"/"Tirar", "Pronto" (R-O3), hidden / addable apps (R-O4).
-- Every change is saved at once (R-O6). Landscape: map on the left, controls in a column on the right.
local Button = require("ui/button")
local Draw = require("ui/draw")
local G = require("ui/geom")
local Org = require("ui/orglogic")
local Pager = require("ui/pager")
local S = require("ui/strings")
local T = require("ui/theme")

local M = {}

local SLEEP_EXCLUDE = { sistema = true }

local function size_label(s) return (s or ""):gsub("x", "×") end

-- map of one packed page inside `box` (relative rect); returns widget
local function map_widget(win, regions, box, items, cols, rows, sel, on_select)
    local host = win.host
    local home_area = G.home_area(regions.inner, 1)
    local mrect, minner = G.map(box, home_area.w, home_area.h)
    local layers = Draw.Layers:new{ w = box.w, h = box.h }
    layers[1] = { widget = Draw.box{ w = mrect.w, h = mrect.h, border = T.BORDER, radius = T.RADIUS }, x = mrect.x - box.x, y = mrect.y - box.y }
    local origin = { x = 0, y = 0, w = minner.w, h = minner.h }
    for _, it in ipairs(items) do
        local r = G.tile_rect(it, origin, cols, rows, T.MAP_GAP)
        local m = host:app(it.app) or {}
        local short = m.short or m.name or it.app
        local selected = it.app == sel
        local fg = Draw.fg(selected)
        local label = it.w >= 2 and short or short:sub(1, 2)
        local lines = { Draw.text(label, T.FONT_MIN, true, r.w - T.px(6), fg) }
        if it.w >= 2 and it.h >= 2 then lines[2] = Draw.text(size_label(it.size), T.FONT_MIN, true, r.w - T.px(6), fg) end
        layers[#layers + 1] = {
            widget = Draw.box{ w = r.w, h = r.h, bg = Draw.bg(selected), border = T.BORDER, radius = T.px1(3),
                align = "center", valign = "center", child = Draw.vstack(lines, 0, "center"),
                on_tap = function() on_select(it.app) end },
            x = minner.x - box.x + r.x, y = minner.y - box.y + r.y,
        }
    end
    return layers
end

function M.build(win, regions, route)
    local host = win.host
    local mode = route.mode == "sleep" and "sleep" or "home"
    local known = host:knownSet()
    local list = host:layout(mode)
    route.sel = Org.selection(list, route.sel, known)
    local sel = route.sel
    local cols, rows = G.grid_dims(regions.W, regions.H)
    local pages = host:packList(list, cols, rows)
    -- page shown: the one the user turned to (route.view), else the page of the selection
    local sel_page = Org.page_of(pages, sel) or 1
    local pi = math.max(1, math.min(route.view or sel_page, #pages))
    route.view = pi ~= sel_page and pi or nil
    local function turn(d) route.view = math.max(1, math.min(#pages, pi + d)); win:render("partial") end
    local function switch(m) route.mode = m; route.sel = nil; route.view = nil; win:render("partial") end
    local box = win:bodyBox(regions)
    local landscape = box.landscape

    local function save(new_list)
        route.view = nil            -- follow the selection again
        host:saveLayout(mode, new_list)
        win:render("partial")
    end
    local function select(id) route.sel = id; route.view = nil; win:render("partial") end

    -- controls
    local ctrl_w = landscape and T.ORG_SIDE_W or box.w
    local _, sel_item = Org.find(list, sel)
    local vi, vn = Org.visible_index(list, sel, known)
    local m = sel and host:app(sel) or nil
    local sizes = m and m.sizes or {}
    local tabs = Button.row({
        { S.t("org_tab_home"), function() switch("home") end, inv = mode == "home" },
        { S.t("org_tab_sleep"), function() switch("sleep") end, inv = mode == "sleep" },
    }, ctrl_w)
    local info_text = S.t("org_no_widget")
    if sel_item then
        info_text = (#pages > 1 and Org.page_of(pages, sel))
            and S.t("org_info_page", host:appName(sel), size_label(sel_item.size), Org.page_of(pages, sel))
            or (host:appName(sel) .. " · " .. size_label(sel_item.size))
    end
    local info = Draw.text(info_text, T.FONT_BODY, true, ctrl_w)
    local row1, row2
    local b1 = {
        { S.t("org_before"), function() save(Org.move(list, sel, -1, known)) end, disabled = not vi or vi <= 1 },
        { S.t("org_after"), function() save(Org.move(list, sel, 1, known)) end, disabled = not vi or vi >= vn },
        { S.t("org_size"), function() save(Org.cycle_size(list, sel, sizes)) end, disabled = not sel_item or #sizes < 2 },
    }
    local b2 = {
        { mode == "sleep" and S.t("org_remove") or S.t("org_hide"), function()
            save(Org.hide(list, sel, mode))
            if sel == "sistema" and mode == "home" then win:showToast(S.t("toast_system_in_menu")) end
        end, disabled = not sel_item },
        { S.t("org_done"), function() win:back() end, inv = true },
    }
    -- sleep tab: replaces the sleep layout with Home page 1 (apps, sizes and order), after a confirmation
    local copy_btn
    if mode == "sleep" then
        copy_btn = { S.t("org_copy"), function()
            win:confirm{ title = S.t("org_copy_title"), text = S.t("org_copy_text"), ok_label = S.t("org_copy_ok"),
                on_ok = function()
                    local first = host:packedPages("home", cols, rows)[1] or {}
                    route.sel = nil
                    save(Org.from_home(first, SLEEP_EXCLUDE))
                    win:showToast(S.t("toast_copied"))
                end }
        end }
    end
    if landscape then
        -- one button per line in the side column
        local col = {}
        for _, b in ipairs(b1) do col[#col + 1] = Button.new{ label = b[1], on_tap = b[2], disabled = b.disabled, w = ctrl_w } end
        row1 = Draw.vstack(col, T.GAP)
        row2 = Button.row(b2, ctrl_w)
    else
        row1 = Button.row(b1, ctrl_w)
        row2 = Button.row(b2, ctrl_w)
    end
    local extras = Org.extras(list, host:appIds(), known, mode == "sleep" and SLEEP_EXCLUDE or nil)
    local extra_line
    if #extras == 0 then
        extra_line = Draw.text(S.t(mode == "sleep" and "org_none_add" or "org_none_hidden"), T.FONT_MIN, false, ctrl_w)
    else
        local items = { Draw.text(S.t(mode == "sleep" and "org_add" or "org_hidden"), T.FONT_MIN, false) }
        local used = items[1]:getSize().w + T.GAP
        for _, id in ipairs(extras) do
            local name = host:appName(id) or id
            local bw = math.min(Button.width_for(name, T.FONT_MIN), ctrl_w)
            if used + bw > ctrl_w then break end
            used = used + bw + T.GAP
            items[#items + 1] = Button.new{ label = name, w = bw, size = T.FONT_MIN, on_tap = function()
                local mm = host:app(id) or {}
                route.sel = id
                save(Org.unhide(list, id, (mm.sizes or {})[1] or "2x2"))
            end }
        end
        extra_line = Draw.hstack(items, T.GAP)
    end
    local parts = { info, row1, row2 }
    if copy_btn then parts[#parts + 1] = Button.row({ copy_btn }, ctrl_w) end
    parts[#parts + 1] = extra_line
    local controls = Draw.vstack(parts, T.GAP)
    local pager_h = #pages > 1 and (T.PAGER_H + T.GAP) or 0
    local function pager(w) return Pager.new(w, pi - 1, #pages, function() turn(-1) end, function() turn(1) end) end

    local body
    if landscape then
        local map_box = G.rect(0, 0, box.w - ctrl_w - T.GAP, box.h - T.BTN_H - T.GAP - pager_h)
        local map = map_widget(win, regions, map_box, pages[pi] or {}, cols, rows, sel, select)
        local left_parts = { Button.row({
            { S.t("org_tab_home"), function() switch("home") end, inv = mode == "home" },
            { S.t("org_tab_sleep"), function() switch("sleep") end, inv = mode == "sleep" },
        }, map_box.w), map }
        if pager_h > 0 then left_parts[3] = pager(map_box.w) end
        local left = Draw.vstack(left_parts, T.GAP)
        body = Draw.hstack({ left, controls }, T.GAP, "start")
        if tabs.free then tabs:free() end
    else
        local ch = controls:getSize().h
        local map_box = G.rect(0, 0, box.w, box.h - T.BTN_H - ch - 2 * T.GAP - pager_h)
        local map = map_widget(win, regions, map_box, pages[pi] or {}, cols, rows, sel, select)
        local col = { tabs, map }
        if pager_h > 0 then col[3] = pager(box.w) end
        col[#col + 1] = controls
        body = Draw.vstack(col, T.GAP)
    end
    local meta = #pages > 1 and S.t("org_page", pi, #pages) or S.t("org_one_page")
    if mode == "sleep" and #pages > 1 then meta = meta .. " · " .. S.t("org_sleep_extra") end
    return win:frameScreen(regions, S.t("org_title"), meta, nil, Draw.box{ w = box.w, h = box.h, child = body })
end

return M
