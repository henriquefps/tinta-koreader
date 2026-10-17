-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (C) 2026 Tinta contributors
-- Tinta: tests of the pure UI helpers (ui/geom, ui/gestures, ui/orglogic, ui/paging, ui/shapes,
-- ui/strings) and of the Sistema app rules. No KOReader. Run from the repo root:
--   luajit tests/tinta_ui_test.lua
-- Exits non-zero on failure; returns passed, failed when required by another runner.
package.path = "tinta.koplugin/?.lua;" .. package.path

local Geom = require("ui/geom")
local Gestures = require("ui/gestures")
local Org = require("ui/orglogic")
local Paging = require("ui/paging")
local Shapes = require("ui/shapes")
local Strings = require("ui/strings")
local Theme = require("ui/theme")
local Sys = require("apps/sistema/logic")

local passed, failed = 0, 0
local function check(name, cond, extra)
    if cond then passed = passed + 1
    else failed = failed + 1; print("FAIL - " .. name .. (extra and (" :: " .. tostring(extra)) or "")) end
end
local function eq(name, got, want) check(name, got == want, "got " .. tostring(got) .. ", want " .. tostring(want)) end

---------------------------------------------------------------- geom

do
    local r = Geom.regions(600, 800, "bar")
    eq("regions status h", r.status.h, 48)
    eq("regions nav y", r.nav.y, 728)
    eq("regions content y", r.content.y, 48)
    eq("regions content h", r.content.h, 680)
    eq("regions inner", r.inner.x .. "," .. r.inner.y .. "," .. r.inner.w .. "," .. r.inner.h, "8,56,584,664")
    check("regions bar: no handle", r.handle == nil)
    local g = Geom.regions(600, 800, "gestures")
    check("gestures: no nav", g.nav == nil)
    eq("gestures: handle x", g.handle.x, 240)
    eq("gestures: handle y", g.handle.y, 786)
    eq("gestures: content to bottom", g.content.h, 752)
    local s = Geom.regions(600, 800, "bar", true)
    check("sleep: no nav, no handle", s.nav == nil and s.handle == nil)

    local c, rr = Geom.grid_dims(600, 800)
    eq("grid portrait", c .. "x" .. rr, "6x8")
    c, rr = Geom.grid_dims(800, 600)
    eq("grid landscape", c .. "x" .. rr, "8x6")

    -- R-G4: (584 - 5*8) / 6 = 90.67 px per cell
    check("cell portrait", math.abs(Geom.cell(584, 6, 8) - 90.6667) < 0.01)
    local area = Geom.rect(8, 56, 584, 664)
    local full = Geom.tile_rect({ x = 0, y = 0, w = 6, h = 8 }, area, 6, 8, 8)
    eq("full tile fills area", full.x .. "," .. full.y .. "," .. full.w .. "," .. full.h, "8,56,584,664")
    local a = Geom.tile_rect({ x = 0, y = 0, w = 4, h = 4 }, area, 6, 8, 8)
    local b = Geom.tile_rect({ x = 4, y = 0, w = 2, h = 4 }, area, 6, 8, 8)
    eq("adjacent tiles keep the gap", b.x - (a.x + a.w), 8)
    eq("right tile ends at area edge", b.x + b.w, 592)
    -- widget of w cells = w*cell + (w-1)*gap (+-1 px rounding)
    check("4 cells width", math.abs(a.w - (4 * Geom.cell(584, 6, 8) + 3 * 8)) <= 1, a.w)
    -- every 1x1 cell of the grid: no overlap, gaps exactly 8
    local prev
    for x = 0, 5 do
        local t = Geom.tile_rect({ x = x, y = 0, w = 1, h = 1 }, area, 6, 8, 8)
        if prev then eq("gap col " .. x, t.x - (prev.x + prev.w), 8) end
        prev = t
    end

    local home, pager = Geom.home_area(area, 2)
    eq("home area with pager", home.h, 664 - 64 - 8)
    eq("pager at bottom", pager.y + pager.h, 56 + 664)
    local h1, p1 = Geom.home_area(area, 1)
    check("one page: no pager", p1 == nil and h1.h == 664)

    local sp = Geom.split(600, 4, 2)
    eq("split count", #sp, 4)
    eq("split first", sp[1].x .. "+" .. sp[1].w, "0+150")
    eq("split second has divider", sp[2].x .. "+" .. sp[2].w, "152+148")
    eq("split last ends", sp[4].x + sp[4].w, 600)

    local sh = Geom.share(584, 4, 8)
    local sum = 0
    for _, w in ipairs(sh) do sum = sum + w end
    eq("share sums with gaps", sum + 3 * 8, 584)

    local d = Geom.dialog(600, 800, 200)
    eq("dialog centered", d.x .. "," .. d.y .. "," .. d.w, "50,300,500")
    eq("dialog narrow screen", Geom.dialog(400, 800, 100).w, 360)
    local bn = Geom.banner(600, 70)
    eq("banner", bn.x .. "," .. bn.y .. "," .. bn.w, "8,56,584")
    local sheet = Geom.sheet(r, 5)
    eq("sheet bottom on nav", sheet.y + sheet.h, 728)
    eq("sheet height", sheet.h, 3 + 48 + 5 * 60)
    local sg = Geom.sheet(g, 3)
    eq("sheet bottom at screen bottom (gestures)", sg.y + sg.h, 800)
    local t = Geom.toast(r, 300, 50)
    eq("toast above nav", t.y + t.h, 728 - 12)
    eq("toast clipped", Geom.toast(r, 900, 50).w, 576)

    local m, inner = Geom.map(Geom.rect(0, 0, 300, 300), 584, 664)
    check("map keeps aspect", math.abs(m.w / m.h - 584 / 664) < 0.02, m.w .. "x" .. m.h)
    check("map inside box", m.x >= 0 and m.y >= 0 and m.x + m.w <= 300 and m.y + m.h <= 300)
    eq("map inner padding", inner.x - m.x, Theme.BORDER + Theme.MAP_GAP)

    check("inside", Geom.inside(Geom.rect(10, 10, 5, 5), 10, 14))
    check("outside right edge", not Geom.inside(Geom.rect(10, 10, 5, 5), 15, 12))
    check("inside nil", not Geom.inside(nil, 1, 1))
end

---------------------------------------------------------------- gestures (R-N3)

do
    local P = { W = 600, H = 800, home = false }
    local H = { W = 600, H = 800, home = true }
    local function sw(x0, y0, x1, y1, scr) return Gestures.classify({ x0 = x0, y0 = y0, x1 = x1, y1 = y1 }, scr or P) end
    eq("bottom edge up -> home", sw(300, 780, 300, 650), "home")
    eq("bottom edge up just 80 -> nothing", sw(300, 780, 300, 700), nil)
    eq("bottom edge up 81 -> home", sw(300, 780, 300, 699), "home")
    eq("start 51 px from bottom -> not home", sw(300, 749, 300, 600), nil)
    eq("start 50 px from bottom -> home", sw(300, 750, 300, 600), "home")
    eq("left edge right -> back", sw(20, 400, 200, 410), "back")
    eq("left edge right short -> nothing", sw(20, 400, 90, 400), nil)
    eq("left edge but moving down -> nothing", sw(20, 300, 60, 500), nil)
    eq("top edge down -> central", sw(300, 30, 300, 200), "central")
    eq("top edge 61 -> nothing", sw(300, 61, 300, 300), nil)
    eq("middle swipe off home -> nothing", sw(400, 400, 200, 400), nil)
    eq("home swipe left -> next page", sw(400, 400, 200, 410, H), "page_next")
    eq("home swipe right -> prev page", sw(200, 400, 400, 390, H), "page_prev")
    eq("home swipe too vertical -> nothing", sw(400, 300, 200, 370, H), nil)
    eq("home swipe short -> nothing", sw(400, 400, 330, 400, H), nil)
    eq("home: left edge still back", sw(10, 400, 300, 400, H), "back")
    eq("home: top edge right swipe is not page", sw(300, 20, 500, 20, H), nil)
    -- direction + distance (no end point)
    eq("direction north from bottom", Gestures.classify({ x0 = 300, y0 = 790, direction = "north", distance = 120 }, P), "home")
    eq("direction west on home", Gestures.classify({ x0 = 400, y0 = 400, direction = "west", distance = 150 }, H), "page_next")
    eq("unknown direction", Gestures.classify({ x0 = 400, y0 = 400, direction = "?", distance = 150 }, H), nil)
    eq("no event", Gestures.classify(nil, H), nil)
    -- landscape
    local L = { W = 800, H = 600, home = true }
    eq("landscape bottom up", sw(400, 590, 400, 450, L), "home")
    eq("hold delay after KOReader 500 ms", Gestures.hold_delay_ms(500), 150)
    eq("hold delay never negative", Gestures.hold_delay_ms(900), 0)
    check("hold moved 13 px", Gestures.hold_moved(100, 100, 113, 100))
    check("hold within 12 px", not Gestures.hold_moved(100, 100, 112, 88))
end

---------------------------------------------------------------- organizer list ops (R-O3, R-O4)

do
    local known = { alfa = {}, beta = {}, bateria = {}, notificacoes = {}, sistema = {} }
    local L = {
        { app = "alfa", size = "4x4" }, { app = "beta", size = "2x4" }, { app = "x_future", size = "2x2" },
        { app = "bateria", size = "2x2" }, { app = "notificacoes", size = "2x2", hidden = true }, { app = "sistema", size = "1x1" },
    }
    local function ids(list)
        local t = {}
        for _, it in ipairs(list) do t[#t + 1] = it.app .. (it.hidden and "-" or "") end
        return table.concat(t, ",")
    end
    eq("visible skips hidden and unknown", ids(Org.visible(L, known)), "alfa,beta,bateria,sistema")
    eq("visible without known keeps unknown", ids(Org.visible(L)), "alfa,beta,x_future,bateria,sistema")
    local m = Org.move(L, "bateria", -1, known)
    eq("move up skips unknown", ids(m), "alfa,bateria,x_future,beta,notificacoes-,sistema")
    eq("original untouched", ids(L), "alfa,beta,x_future,bateria,notificacoes-,sistema")
    eq("move down skips hidden", ids(Org.move(L, "bateria", 1, known)), "alfa,beta,x_future,sistema,notificacoes-,bateria")
    eq("move first up: no-op", ids(Org.move(L, "alfa", -1, known)), ids(L))
    eq("move last down: no-op", ids(Org.move(L, "sistema", 1, known)), ids(L))
    eq("move hidden: no-op", ids(Org.move(L, "notificacoes", 1, known)), ids(L))
    local vi, n = Org.visible_index(L, "bateria", known)
    eq("visible index", vi .. "/" .. n, "3/4")
    local c = Org.cycle_size(L, "alfa", { "4x4", "4x2", "2x2", "1x1" })
    eq("cycle size", c[1].size, "4x2")
    c = Org.cycle_size(Org.cycle_size(Org.cycle_size(c, "alfa", { "4x4", "4x2", "2x2", "1x1" }), "alfa", { "4x4", "4x2", "2x2", "1x1" }), "alfa", { "4x4", "4x2", "2x2", "1x1" })
    eq("cycle size wraps", c[1].size, "4x4")
    eq("cycle unknown size -> first", Org.cycle_size({ { app = "a", size = "3x3" } }, "a", { "2x2", "1x1" })[1].size, "2x2")
    eq("hide home keeps item", ids(Org.hide(L, "beta", "home")), "alfa,beta-,x_future,bateria,notificacoes-,sistema")
    eq("remove sleep drops item", ids(Org.hide(L, "beta", "sleep")), "alfa,x_future,bateria,notificacoes-,sistema")
    eq("unhide hidden in place", ids(Org.unhide(L, "notificacoes", "2x2")), "alfa,beta,x_future,bateria,notificacoes,sistema")
    local u = Org.unhide(L, "new", "2x2")
    eq("unhide absent appends", u[#u].app .. ":" .. u[#u].size, "new:2x2")
    local order = { "alfa", "beta", "bateria", "notificacoes", "sistema", "_test_ok" }
    known._test_ok = {}
    eq("extras: hidden + not in list", table.concat(Org.extras(L, order, known), ","), "notificacoes,_test_ok")
    eq("extras exclude", table.concat(Org.extras(L, order, known, { _test_ok = true }), ","), "notificacoes")
    eq("selection keeps visible", Org.selection(L, "bateria", known), "bateria")
    eq("selection falls back to first", Org.selection(L, "notificacoes", known), "alfa")
    eq("selection empty", Org.selection({}, "x", known), nil)
    local pg = { { { app = "alfa" }, { app = "beta" } }, { { app = "bateria" } } }
    eq("page_of", Org.page_of(pg, "bateria"), 2)
    eq("page_of absent", Org.page_of(pg, "x"), nil)
    local cp = Org.from_home({ { app = "alfa", size = "4x2", x = 0 }, { app = "sistema", size = "1x1" }, { app = "beta", size = "2x2" } }, { sistema = true })
    eq("from_home copies apps, sizes and order, minus excluded", ids(cp), "alfa,beta")
    eq("from_home sizes", cp[1].size .. cp[2].size, "4x22x2")
    eq("from_home empty", #Org.from_home(nil), 0)
    local w, h = Org.parse_size("4x2")
    eq("parse size", w .. "," .. h, "4,2")
    eq("parse bad size", Org.parse_size("big"), nil)
    eq("effective size kept", Org.effective_size("2x2", { "4x4", "2x2" }), "2x2")
    eq("effective size fallback", Org.effective_size("3x1", { "4x4", "2x2" }), "4x4")
end

---------------------------------------------------------------- paging (6.6)

do
    eq("pages of 0", Paging.count(0, 4), 1)
    eq("pages of 9 by 4", Paging.count(9, 4), 3)
    local items = {}
    for i = 1, 9 do items[i] = i end
    local s, p, n = Paging.slice(items, 2, 4)
    eq("last page", table.concat(s, ","), "9")
    eq("page/pages", p .. "/" .. n, "2/3")
    s, p = Paging.slice(items, 7, 4)
    eq("clamped page", p, 2)
    s, p = Paging.slice(items, -1, 4)
    eq("negative page", p .. ":" .. table.concat(s, ","), "0:1,2,3,4")
    eq("fit rows", Paging.fit(300, 64, 4), 4)
    eq("fit at least 1", Paging.fit(10, 64, 4), 1)
end

-- items of different heights (Sistema → Repouso)
do
    local function flat(pages)
        local out = {}
        for _, pg in ipairs(pages) do
            local cs = {}
            for _, col in ipairs(pg) do cs[#cs + 1] = table.concat(col, ",") end
            out[#out + 1] = table.concat(cs, "|")
        end
        return table.concat(out, ";")
    end
    -- header(30)+2 rows(64) in 200 px, gap 4: 30+4+64+4+64 = 166 fits
    eq("flow: all in one column", flat(Paging.flow({ 30, 64, 64 }, { true }, 200, 4, 1)), "1,2,3")
    eq("flow: overflow -> next page", flat(Paging.flow({ 30, 64, 64 }, { true }, 120, 4, 1)), "1,2;3")
    eq("flow: second column (landscape)", flat(Paging.flow({ 30, 64, 64 }, { true }, 120, 4, 2)), "1,2|3")
    eq("flow: header stays with its row", flat(Paging.flow({ 64, 30, 64 }, { false, true }, 110, 4, 1)), "1;2,3")
    eq("flow: header stays with its row (2 cols)", flat(Paging.flow({ 64, 30, 64 }, { false, true }, 110, 4, 2)), "1|2,3")
    eq("flow: oversize item sits alone", flat(Paging.flow({ 300, 64 }, nil, 100, 4, 1)), "1;2")
    eq("flow: empty", flat(Paging.flow({}, nil, 100, 4, 1)), "")
end

---------------------------------------------------------------- shapes

do
    for _, st in ipairs({ "on", "connecting", "off" }) do
        local m = Shapes.wifi(30, 26, st)
        check("wifi " .. st .. " not empty", #m > 0)
        local x0, y0, x1, y1 = Shapes.bounds(m)
        check("wifi " .. st .. " in box", x0 >= 0 and y0 >= 0 and x1 < 30 and y1 < 26, x0 .. "," .. y0 .. "," .. x1 .. "," .. y1)
    end
    local function px(m) local n = 0 for _, s in ipairs(m) do n = n + s[3] end return n end
    check("connecting has fewer pixels (dashes)", px(Shapes.wifi(30, 26, "connecting")) < px(Shapes.wifi(30, 26, "on")))
    check("off has the strike", px(Shapes.wifi(30, 26, "off")) > px(Shapes.wifi(30, 26, "connecting")))
    check("wifi cached", Shapes.wifi(30, 26, "on") == Shapes.wifi(30, 26, "on"))
    for name, m in pairs({ bell = Shapes.bell(24, 26), gear = Shapes.gear(30), house = Shapes.house(26, 24), bars = Shapes.bars(24, 20) }) do
        check(name .. " not empty", #m > 0)
    end
    local x0, y0, x1, y1 = Shapes.bounds(Shapes.gear(30))
    check("gear in box", x0 >= 0 and y0 >= 0 and x1 < 30 and y1 < 30)
    local d = Shapes.dashed_border(100, 60, 2, 8, 6)
    x0, y0, x1, y1 = Shapes.bounds(d)
    eq("dashed border bounds", x0 .. "," .. y0 .. "," .. x1 .. "," .. y1, "0,0,99,59")
    check("dashed border has gaps", px(d) < 2 * (100 + 60) * 2)
end

---------------------------------------------------------------- strings (same keys, same specifiers)

do
    local function specs(s)
        local t = {}
        for sp in s:gmatch("%%[%d%.]*[sdif]") do t[#t + 1] = sp end
        return table.concat(t, " ")
    end
    local function same(a, b, label)
        for k, v in pairs(a) do
            check(label .. ": en has " .. k, b[k] ~= nil)
            if b[k] then eq(label .. ": specifiers of " .. k, specs(b[k]), specs(v)) end
        end
        for k in pairs(b) do check(label .. ": pt has " .. k, a[k] ~= nil) end
    end
    same(Strings.pt, Strings.en, "ui")
    local SysStrings = require("apps/sistema/strings")
    same(SysStrings.pt, SysStrings.en, "sistema")
    Strings.set_lang("en")
    eq("t en", Strings.t("nav_home"), "Home")
    eq("t format", Strings.t("central_unread", 3), "3 unread")
    Strings.set_lang("xx")
    eq("bad lang ignored", Strings.get_lang(), "en")
    Strings.set_lang("pt")
    eq("t pt", Strings.t("nav_home"), "Início")
    eq("missing key -> key", Strings.t("nope_key"), "nope_key")
    local t2 = Strings.make({ pt = { a = "A %s" }, en = { a = "EN %s" } })
    eq("make pt", t2("a", "x"), "A x")
    eq("make falls back to ui strings", t2("nav_back"), "Voltar")
end

---------------------------------------------------------------- sistema rules (8.6)

do
    local src = Sys.sources({ { id = "alfa", source = { id = "alfa", name = "alfa-server" } }, { id = "x" },
        { id = "y", source = { id = "alfa" } }, { id = "beta", source = { id = "beta", name = "beta-server" } } })
    eq("sources grouped", #src .. ":" .. table.concat(src[1].apps, ","), "2:alfa,y")
    eq("host of url", Sys.host_of("http://192.0.2.101:4747/v1"), "192.0.2.101:4747")
    eq("host of non-url", Sys.host_of("abc"), nil)
    eq("cycle wraps", Sys.cycle({ "alta", "normal", "desligada" }, "desligada"), "alta")
    eq("cycle unknown -> first", Sys.cycle({ 15, 30 }, 7), 15)
    eq("size KB", Sys.size_text(217088), "212 KB")
    eq("size MB pt", Sys.size_text(1468006, "pt"), "1,4 MB")
    eq("size MB en", Sys.size_text(1468006, "en"), "1.4 MB")
end

---------------------------------------------------------------- launcher (6.5, 7.4)

do
    local L = require("ui/launchlogic")
    local apps = { { id = "sistema" }, { id = "alfa" }, { id = "relogio" }, { id = "beta" }, { id = "notificacoes" }, { id = "gone" } }
    local names = { sistema = "Sistema", alfa = "Orbital Plus", relogio = "Órbita", beta = "pilha", notificacoes = "Notificações", gone = "Orbital" }
    local home = { { app = "alfa", size = "4x4" }, { app = "beta", size = "2x2", hidden = true }, { app = "fora", size = "2x2" } }
    local e = L.entries(apps, function(id) return names[id] end, function(m) return m.id == "alfa" and "sub" or nil end, home)
    local order = {}
    for i, x in ipairs(e) do order[i] = x.id end
    eq("launcher lists every registered app, alphabetical (accents and case folded)", table.concat(order, ","),
        "notificacoes,relogio,gone,alfa,beta,sistema")
    eq("launcher mark: on Home", e[4].mark, "home")
    eq("launcher mark: hidden", e[5].mark, "hidden")
    eq("launcher mark: never added", e[1].mark, nil)
    eq("launcher subtitle from the manifest", e[4].sub, "sub")
    eq("launcher ignores layout items of unregistered apps", #e, 6)
    eq("sort key folds accents", L.sort_key("Órbita Çá"), "orbita ca")
    local list, changed = L.add_home(home, "beta", { "4x2", "2x2" })
    check("add_home brings a hidden app back in place", changed and list[2].app == "beta" and not list[2].hidden)
    list, changed = L.add_home(home, "sistema", { "2x4", "2x2" })
    check("add_home appends an absent app with its first size", changed and list[#list].app == "sistema" and list[#list].size == "2x4")
    list, changed = L.add_home(home, "alfa", { "4x4" })
    check("add_home leaves an app already on Home", not changed and #list == #home)
    check("add_home does not change its input", home[2].hidden == true and #home == 3)
    eq("add_home size fallback", select(1, L.add_home({}, "x", nil))[1].size, "2x2")
end

---------------------------------------------------------------- scale and content box (6.1)

do
    local sizes = { { 600, 800 }, { 758, 1024 }, { 1072, 1448 }, { 1264, 1680 }, { 1404, 1872 }, { 1860, 2480 },
        { 1200, 1600 }, { 1000, 800 }, { 480, 800 }, { 300, 400 } }
    local FIXED = { FONT = 1, DESIGN_W = 1, DESIGN_H = 1, NAV_BUTTONS = 1, GRID_PORTRAIT = 1, GRID_LANDSCAPE = 1,
        CENTRAL_PER_PAGE_PORTRAIT = 1, CENTRAL_PER_PAGE_LANDSCAPE = 1, TOAST_MS = 1, BANNER_MS = 1, TICK_S = 1,
        CLOCK_S = 1, FULL_EVERY = 1, HOLD_MS = 1 }

    -- the KT3: s = 1, the box is the screen, every measure is the design's (nothing may change there)
    for _, dims in ipairs({ { 600, 800 }, { 800, 600 } }) do
        local W, H = dims[1], dims[2]
        local s = Theme.configure(W, H)
        local tag = W .. "x" .. H
        eq(tag .. ": s = 1", s, 1)
        check(tag .. ": the box is the screen", Theme.ox == 0 and Theme.oy == 0 and Theme.BW == W and Theme.BH == H)
        local diff
        for k, v in pairs(Theme.BASE) do
            if type(v) == "number" and not FIXED[k] and Theme[k] ~= v then diff = k end
        end
        eq(tag .. ": every measure equals the design", diff, nil)
        eq(tag .. ": px is the identity", Theme.px(7) + Theme.px1(3) + Theme.fpx(26), 36)
    end
    -- the numbers of spec 6.1 on the KT3
    Theme.configure(600, 800)
    eq("6.1 SB_H", Theme.SB_H, 48); eq("6.1 NAV_H", Theme.NAV_H, 72); eq("6.1 FONT_BODY", Theme.FONT_BODY, 22)
    eq("6.1 TOUCH", Theme.TOUCH, 64); eq("6.1 BORDER", Theme.BORDER, 2); eq("6.1 DIALOG_W", Theme.DIALOG_W, 500)

    -- exact multiples
    Theme.configure(1200, 1600)
    eq("x2: s", Theme.s, 2); eq("x2: SB_H", Theme.SB_H, 96); eq("x2: FONT_BODY", Theme.FONT_BODY, 44)
    eq("x2: BORDER", Theme.BORDER, 4); eq("x2: GRID_GAP", Theme.GRID_GAP, 16); eq("x2: grid stays 6x8", Geom.grid_dims(1200, 1600), 6)
    eq("x2: gestures zone", Theme.EDGE_BOTTOM, 100); eq("x2: HOLD_MS is time, not px", Theme.HOLD_MS, 650)
    local sw = Gestures.classify({ x0 = 300, y0 = 1600 - 90, x1 = 300, y1 = 1600 - 90 - 200 }, { W = 1200, H = 1600 })
    eq("x2: bottom swipe from 90 px (inside the 100 px zone)", sw, "home")
    sw = Gestures.classify({ x0 = 300, y0 = 1600 - 190, x1 = 300, y1 = 1600 - 190 - 200 }, { W = 1200, H = 1600 })
    eq("x2: 190 px from the bottom is outside the zone", sw, nil)

    -- letterbox: not 3:4 -> the 3:4 box is centred, white around it
    Theme.configure(758, 1024)
    check("758x1024: s from the tighter side", math.abs(Theme.s - 758 / 600) < 1e-9, Theme.s)
    check("758x1024: box 758 x 1011, centred", Theme.BW == 758 and Theme.BH == 1011 and Theme.ox == 0 and Theme.oy == 6,
        Theme.BW .. "x" .. Theme.BH .. " @" .. Theme.ox .. "," .. Theme.oy)
    Theme.configure(1000, 800)
    check("1000x800 (wide for portrait... it is landscape): box 1000 x 750", Theme.land and Theme.BW == 1000 and Theme.BH == 750
        and Theme.ox == 0 and Theme.oy == 25, Theme.BW .. "x" .. Theme.BH .. " @" .. Theme.ox .. "," .. Theme.oy)
    Theme.configure(1000, 1000)
    check("square screen: portrait box, centred", not Theme.land and Theme.BH == 1000 and Theme.BW == 750 and Theme.ox == 125)
    Theme.configure(300, 400)
    check("half size: borders keep 1 px", Theme.BORDER == 1 and Theme.SB_BORDER == 1 and Theme.NAV_DIV == 1 and Theme.HANDLE_H >= 1)

    for _, d in ipairs(sizes) do
        for _, land in ipairs({ false, true }) do
            local W, H = d[1], d[2]
            if land then W, H = H, W end
            land = W > H
            local tag = W .. "x" .. H
            local r = Geom.regions(W, H, "bar")
            local s = Theme.s
            check(tag .. ": box inside the screen", Theme.ox >= 0 and Theme.oy >= 0 and Theme.ox + Theme.BW <= W and Theme.oy + Theme.BH <= H)
            check(tag .. ": box is centred (within 1 px)", math.abs((W - Theme.BW) - 2 * Theme.ox) <= 1 and math.abs((H - Theme.BH) - 2 * Theme.oy) <= 1)
            check(tag .. ": box keeps 3:4", math.abs(Theme.BW * (land and 3 or 4) - Theme.BH * (land and 4 or 3)) <= 4)
            check(tag .. ": regions are the box's", r.W == Theme.BW and r.H == Theme.BH and r.ox == Theme.ox and r.oy == Theme.oy and r.SW == W)
            eq(tag .. ": status + content + nav fill the box", r.status.h + r.content.h + r.nav.h, r.H)
            -- fonts never above design x s, borders at least 1, touch >= 64 x s
            check(tag .. ": fonts round down", Theme.FONT_BODY <= 22 * s + 1e-6 and Theme.FONT_BODY > 22 * s - 1 and Theme.FONT_MIN <= 20 * s + 1e-6, Theme.FONT_BODY)
            check(tag .. ": touch targets >= 64 x s", Theme.TOUCH >= math.floor(64 * s + 1e-6) and Theme.BTN_H == Theme.TOUCH and Theme.ROW_H >= math.floor(64 * s + 1e-6))
            check(tag .. ": borders >= 1 px", Theme.BORDER >= 1 and Theme.SB_BORDER >= 1 and Theme.NAV_DIV >= 1)
            -- the home grid: tiles inside the inner area, no overlap, gap exact
            local cols, rows = Geom.grid_dims(r.W, r.H)
            local area = Geom.home_area(r.inner, 1)
            local ok_in, ok_gap = true, true
            for y = 0, rows - 1 do
                for x = 0, cols - 1 do
                    local t = Geom.tile_rect({ x = x, y = y, w = 1, h = 1 }, area, cols, rows, Theme.GRID_GAP)
                    if t.x < area.x or t.y < area.y or t.x + t.w > area.x + area.w or t.y + t.h > area.y + area.h then ok_in = false end
                    if x > 0 then
                        local p = Geom.tile_rect({ x = x - 1, y = y, w = 1, h = 1 }, area, cols, rows, Theme.GRID_GAP)
                        if t.x - (p.x + p.w) ~= Theme.GRID_GAP then ok_gap = false end
                    end
                end
            end
            check(tag .. ": grid tiles inside the area, gap exact", ok_in and ok_gap)
            -- overlays inside the box
            local function inside_box(rc) return rc.x >= 0 and rc.y >= 0 and rc.x + rc.w <= r.W and rc.y + rc.h <= r.H end
            check(tag .. ": dialog, banner, sheet, toast inside the box",
                inside_box(Geom.dialog(r.W, r.H, Theme.px(300))) and inside_box(Geom.banner(r.W, Theme.px(60)))
                and inside_box(Geom.sheet(r, 5)) and inside_box(Geom.toast(r, Theme.px(200), Theme.px(48))))
            -- the fixed measures never change with the size
            eq(tag .. ": grid is 6x8 / 8x6", cols .. "x" .. rows, land and "8x6" or "6x8")
            eq(tag .. ": timings are not scaled", Theme.TOAST_MS + Theme.HOLD_MS + Theme.FULL_EVERY, 2600 + 650 + 10)
        end
    end
    Theme.configure(600, 800)
end

---------------------------------------------------------------- icons scale (6.1)

do
    for _, k in ipairs({ 1, 1.5, 2, 3.2 }) do
        local function r(n) return math.floor(n * k + 0.5) end
        local w, h = r(30), r(26)
        for _, state in ipairs({ "on", "connecting", "off" }) do
            local sp = Shapes.wifi(w, h, state, k)
            local x0, y0, x1, y1 = Shapes.bounds(sp)
            check(("wifi %s k=%s: has pixels inside the box"):format(state, k), #sp > 0 and x0 >= 0 and y0 >= 0 and x1 < w and y1 < h)
        end
        local bw, bh = r(24), r(26)
        local sp = Shapes.bell(bw, bh, k)
        local x0, y0, x1, y1 = Shapes.bounds(sp)
        check("bell k=" .. k .. ": inside the box", #sp > 0 and x0 >= 0 and y0 >= 0 and x1 < bw and y1 < bh)
        sp = Shapes.house(r(26), r(24), k)
        x0, y0, x1, y1 = Shapes.bounds(sp)
        check("house k=" .. k .. ": inside the box", #sp > 0 and x1 < r(26) and y1 < r(24))
        sp = Shapes.bars(r(24), r(20), k)
        x0, y0, x1, y1 = Shapes.bounds(sp)
        check("bars k=" .. k .. ": three bars inside the box", #sp > 0 and x1 < r(24) and y1 < r(20) and y0 >= 0)
        -- strokes grow with k: the number of painted pixels grows about with k^2
        local function area(spans) local n = 0; for _, q in ipairs(spans) do n = n + q[3] end return n end
        local a1, ak = area(Shapes.bars(24, 20, 1)), area(Shapes.bars(r(24), r(20), k))
        check("bars k=" .. k .. ": area follows the scale", math.abs(ak / a1 - k * k) < 0.35 * k * k, ak / a1)
    end
    -- k = 1 (default) is the KT3 mask, byte for byte
    local a, b = Shapes.wifi(30, 26, "on"), Shapes.wifi(30, 26, "on", 1)
    check("wifi default k is 1", a == b)
    check("masks of different k are different caches", Shapes.wifi(60, 52, "on", 2) ~= Shapes.wifi(60, 52, "on", 1))
end

---------------------------------------------------------------- text size factor (6.1)

do
    local T = Theme
    T.configure(600, 800)
    local base = {}
    for _, k in ipairs({ "FONT_BODY", "FONT_MIN", "FONT_TITLE", "FONT_STAT", "FONT_HUGE", "ROW_H", "BTN_H", "SB_H", "NAV_H", "MARGIN", "TOUCH", "WIDGET_FOOTER_H" }) do base[k] = T[k] end
    eq("text factor: starts at 1", T.text, 1)
    check("text factor: 1 changes nothing", T.set_text_factor(1) == false)
    check("text factor: 1.15 changes", T.set_text_factor(1.15) == true)
    eq("text factor: FONT_BODY 22 -> 25", T.FONT_BODY, 25)
    eq("text factor: FONT_MIN 20 -> 23", T.FONT_MIN, 23)
    eq("text factor: FONT_HUGE 72 -> 82", T.FONT_HUGE, 82)
    eq("text factor: T.fpx follows it", T.fpx(26), 29)
    check("text factor: rows, buttons and footers grow with their text", T.ROW_H > base.ROW_H and T.BTN_H > base.BTN_H and T.WIDGET_FOOTER_H > base.WIDGET_FOOTER_H)
    check("text factor: bars, margins and touch targets do not", T.SB_H == base.SB_H and T.NAV_H == base.NAV_H and T.MARGIN == base.MARGIN and T.TOUCH == base.TOUCH)
    T.configure(1200, 1600)
    eq("text factor: kept across a new screen size (x2: 44 * 1.15 = 50.6 -> 50)", T.FONT_BODY, 50)
    T.set_text_factor(1)
    eq("text factor: back to 1 at x2 gives the exact x2 sizes", T.FONT_BODY, 44)
    T.configure(600, 800)
    local same = true
    for k, v in pairs(base) do if T[k] ~= v then same = false end end
    check("text factor: normal again is the KT3 exactly", same)
    T.set_text_factor("nonsense"); eq("text factor: junk is 1", T.text, 1)
    T.set_text_factor(9); eq("text factor: absurd is 1", T.text, 1)
end

---------------------------------------------------------------- first-run wizard rules (7.5)

do
    local W = require("ui/wizlogic")
    local prot = function(id) return id == "sistema" or id == "notificacoes" end
    local apps = {
        { id = "bateria", sizes = { "2x2", "1x1" } }, { id = "notificacoes", sizes = { "2x2", "4x2" } },
        { id = "alfa", sizes = { "4x4", "2x2" } }, { id = "beta", sizes = { "2x4", "4x2", "2x2" } },
        { id = "relogio", sizes = { "2x2", "4x2" } }, { id = "sistema", sizes = { "1x1" } }, { id = "_test_ok", sizes = { "2x2" } },
        { id = "nota", sizes = { "2x2", "4x2" } },
    }
    local def_home = { { app = "alfa", size = "4x4" }, { app = "beta", size = "2x4" }, { app = "bateria", size = "2x2" },
        { app = "notificacoes", size = "2x2" }, { app = "sistema", size = "1x1" } }
    local def_sleep = { { app = "alfa", size = "4x4" }, { app = "beta", size = "2x4" }, { app = "bateria", size = "2x2" },
        { app = "notificacoes", size = "4x2" } }
    local cand = W.candidates(apps, prot)
    eq("wizard: candidates leave out Sistema, Notificações and test apps", table.concat(cand, ","), "bateria,alfa,beta,relogio,nota")
    local sel = W.initial(cand, def_home)
    check("wizard: initial = the default Home apps", sel.alfa and sel.beta and sel.bateria and not sel.relogio and not sel.nota)
    local function names(l) local o = {} for i, it in ipairs(l) do o[i] = it.app .. ":" .. it.size end return table.concat(o, ",") end
    local home, sleep = W.layouts(sel, apps, def_home, def_sleep, prot)
    eq("wizard: default choice gives the default layouts", names(home) .. "|" .. names(sleep),
        "alfa:4x4,beta:2x4,bateria:2x2,notificacoes:2x2,sistema:1x1|alfa:4x4,beta:2x4,bateria:2x2,notificacoes:4x2")
    sel.beta = nil; sel.relogio = true; sel.nota = true
    home, sleep = W.layouts(sel, apps, def_home, def_sleep, prot)
    eq("wizard: Home follows the choice, extras last at their first size", names(home),
        "alfa:4x4,bateria:2x2,notificacoes:2x2,sistema:1x1,relogio:2x2,nota:2x2")
    eq("wizard: the sleep page only takes the default's apps", names(sleep), "alfa:4x4,bateria:2x2,notificacoes:4x2")
    local empty_home = W.layouts({}, apps, def_home, def_sleep, prot)
    eq("wizard: nothing chosen still keeps Notificações and Sistema", names(empty_home), "notificacoes:2x2,sistema:1x1")
    local odd = W.layouts({ alfa = true }, { { id = "alfa", sizes = { "2x2" } } }, { { app = "alfa", size = "4x4" } }, {}, prot)
    eq("wizard: undeclared size -> the app's first", names(odd), "alfa:2x2")
    local valid = true
    for _, it in ipairs(home) do if not require("core/layout").valid_size(it.size) then valid = false end end
    check("wizard: every size is a layout size", valid)
    eq("wizard: four steps", #W.STEPS, 4)
end

print(("tinta ui: %d passed, %d failed"):format(passed, failed))
if ... == nil and failed > 0 then os.exit(1) end
return passed, failed
