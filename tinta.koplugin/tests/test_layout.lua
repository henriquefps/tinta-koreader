-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (C) 2026 Tinta contributors
local T = ...
local L = require("core/layout")
local eq, same, check = T.eq, T.same, T.check

local function pos(pages)
    local out = {}
    for p, items in ipairs(pages) do
        for _, it in ipairs(items) do out[#out + 1] = string.format("%d:%s@%d,%d/%dx%d", p, it.app, it.x, it.y, it.w, it.h) end
    end
    return table.concat(out, " ")
end

eq("layout: grid portrait", select(1, L.grid_dims(false)) .. "x" .. select(2, L.grid_dims(false)), "6x8")
eq("layout: grid landscape", select(1, L.grid_dims(true)) .. "x" .. select(2, L.grid_dims(true)), "8x6")
local w, h = L.parse_size("2x4")
eq("layout: parse_size w", w, 2)
eq("layout: parse_size h", h, 4)
eq("layout: parse_size junk", L.parse_size("big"), nil)
eq("layout: parse_size zero", L.parse_size("0x2"), nil)
check("layout: valid sizes", L.valid_size("4x4") and L.valid_size("1x1") and not L.valid_size("3x3"))

-- R-G3: default layouts, exact positions
local P, Lc = { L.grid_dims(false) }, { L.grid_dims(true) }
eq("pack: home portrait", pos(L.pack(L.default("home"), P[1], P[2])),
    "1:bateria@0,0/2x2 1:notificacoes@2,0/2x2 1:sistema@4,0/1x1")
eq("pack: home landscape", pos(L.pack(L.default("home"), Lc[1], Lc[2])),
    "1:bateria@0,0/2x2 1:notificacoes@2,0/2x2 1:sistema@4,0/1x1")
eq("pack: sleep portrait", pos(L.pack(L.default("sleep"), P[1], P[2])),
    "1:bateria@0,0/2x2 1:notificacoes@2,0/4x2")
eq("pack: sleep landscape", pos(L.pack(L.default("sleep"), Lc[1], Lc[2])),
    "1:bateria@0,0/2x2 1:notificacoes@2,0/4x2")

-- apps place themselves with manifest.default_layout = { page = { size, order } }
local ext = {
    { id = "zeta", default_layout = { home = { size = "4x4", order = 10 }, sleep = { size = "2x2", order = 150 } } },
    { id = "bateria", default_layout = { home = { size = "1x1", order = 500 } } },   -- replaces the bundled entry
    { id = "bad", default_layout = { home = { size = "3x3", order = 1 } } },          -- invalid size: ignored
    { id = "none" },
}
local function ids(list) local o = {} for i, it in ipairs(list) do o[i] = it.app .. ":" .. it.size end return table.concat(o, " ") end
eq("default: no manifests = bundled", ids(L.default("home")), ids(L.DEFAULT.home))
eq("default: manifests merge by order", ids(L.default("home", ext)),
    "zeta:4x4 notificacoes:2x2 sistema:1x1 bateria:1x1")
eq("default: sleep order between bundled", ids(L.default("sleep", ext)),
    "bateria:2x2 zeta:2x2 notificacoes:4x2")
eq("default: unknown page", #L.default("nowhere", ext), 0)
local cp = L.default("home"); cp[1].size = "1x1"
eq("default: returns a copy", L.DEFAULT.home[1].size, "2x2")

-- every size alone, both orientations
for _, s in ipairs(L.SIZES) do
    local sw, sh = L.parse_size(s)
    eq("pack: " .. s .. " alone portrait", pos(L.pack({ { app = "a", size = s } }, 6, 8)), string.format("1:a@0,0/%dx%d", sw, sh))
    eq("pack: " .. s .. " alone landscape", pos(L.pack({ { app = "a", size = s } }, 8, 6)), string.format("1:a@0,0/%dx%d", sw, sh))
end
-- how many of each size fit one page
local per_page = { ["1x1"] = { 48, 48 }, ["2x2"] = { 12, 12 }, ["2x4"] = { 6, 4 }, ["4x2"] = { 4, 6 }, ["4x4"] = { 2, 2 } }
for s, n in pairs(per_page) do
    for o, dims in ipairs({ { 6, 8 }, { 8, 6 } }) do
        local list = {}
        for i = 1, n[o] + 1 do list[i] = { app = "a" .. i, size = s } end
        local pages = L.pack(list, dims[1], dims[2])
        eq("pack: " .. n[o] .. " x " .. s .. " fill page 1 " .. (o == 1 and "portrait" or "landscape"), #pages[1], n[o])
        eq("pack: next " .. s .. " goes to page 2 " .. (o == 1 and "portrait" or "landscape"), #pages[2], 1)
    end
end
-- 4x2 portrait leaves a 2-column strip: 4 of them, then 2x4 fill the strip
eq("pack: 4x2 portrait positions", pos(L.pack({ { app = "a", size = "4x2" }, { app = "b", size = "4x2" },
    { app = "c", size = "4x2" }, { app = "d", size = "4x2" }, { app = "e", size = "2x4" }, { app = "f", size = "2x4" } }, 6, 8)),
    "1:a@0,0/4x2 1:b@0,2/4x2 1:c@0,4/4x2 1:d@0,6/4x2 1:e@4,0/2x4 1:f@4,4/2x4")

-- item that does not fit goes to the next page; later smaller items fill holes on earlier pages
local list = { { app = "a", size = "4x4" }, { app = "b", size = "4x4" }, { app = "c", size = "4x4" }, { app = "d", size = "2x2" } }
eq("pack: overflow + hole fill portrait", pos(L.pack(list, 6, 8)),
    "1:a@0,0/4x4 1:b@0,4/4x4 1:d@4,0/2x2 2:c@0,0/4x4")
eq("pack: overflow landscape", pos(L.pack(list, 8, 6)),
    "1:a@0,0/4x4 1:b@4,0/4x4 1:d@0,4/2x2 2:c@0,0/4x4")
eq("pack: page count", #L.pack(list, 6, 8), 2)
-- three pages
local many = {}
for i = 1, 5 do many[i] = { app = "x" .. i, size = "4x4" } end
local pages = L.pack(many, 6, 8)
eq("pack: 5 x 4x4 portrait -> 3 pages", #pages, 3)
eq("pack: find_page", L.find_page(pages, "x5"), 3)
eq("pack: find_page missing", L.find_page(pages, "zz"), nil)

-- clamp, hidden, invalid, empty
eq("pack: larger than grid is clamped", pos(L.pack({ { app = "a", size = "9x9" } }, 6, 8)), "1:a@0,0/6x8")
eq("pack: wide clamp landscape", pos(L.pack({ { app = "a", size = "4x8" } }, 8, 6)), "1:a@0,0/4x6")
eq("pack: hidden skipped", pos(L.pack({ { app = "a", size = "2x2", hidden = true }, { app = "b", size = "2x2" } }, 6, 8)), "1:b@0,0/2x2")
eq("pack: bad size skipped", pos(L.pack({ { app = "a", size = "?" }, { app = "b", size = "1x1" } }, 6, 8)), "1:b@0,0/1x1")
same("pack: empty list = one empty page", L.pack({}, 6, 8), { {} })
same("pack: nil list = one empty page", L.pack(nil, 6, 8), { {} })
same("pack: all hidden = one empty page", L.pack({ { app = "a", size = "2x2", hidden = true } }, 6, 8), { {} })
check("pack: input not modified", L.default("home")[1].x == nil)

-- property: no overlap, inside the grid, every visible item placed once, deterministic
do
    local seed = 12345
    local function rnd(n) seed = (seed * 1103515245 + 12345) % 2147483648; return seed % n + 1 end
    local ok_all = true
    for trial = 1, 200 do
        local cols, rows = trial % 2 == 0 and 6 or 8, trial % 2 == 0 and 8 or 6
        local lst = {}
        for i = 1, rnd(14) do lst[i] = { app = "a" .. i, size = L.SIZES[rnd(#L.SIZES)], hidden = rnd(6) == 1 or nil } end
        local pg = L.pack(lst, cols, rows)
        local placed = 0
        for _, items in ipairs(pg) do
            local occ = {}
            for _, it in ipairs(items) do
                placed = placed + 1
                if it.x < 0 or it.y < 0 or it.x + it.w > cols or it.y + it.h > rows then ok_all = false end
                for y = it.y, it.y + it.h - 1 do
                    for x = it.x, it.x + it.w - 1 do
                        if occ[y * cols + x] then ok_all = false end
                        occ[y * cols + x] = true
                    end
                end
            end
        end
        local visible = 0
        for _, it in ipairs(lst) do if not it.hidden then visible = visible + 1 end end
        if placed ~= visible then ok_all = false end
        if pos(pg) ~= pos(L.pack(lst, cols, rows)) then ok_all = false end
    end
    check("pack: 200 random layouts: no overlap, in bounds, all placed, deterministic", ok_all)
end

-- R-G4 cell and box sizes
local cw, ch = L.cell_size(584, 664, 6, 8)
eq("cell: width (584 - 5*8)/6", cw, 90)
eq("cell: height (664 - 7*8)/8", ch, 76)
local cw2, ch2 = L.cell_size(784, 464, 8, 6)
eq("cell: landscape width (784 - 7*8)/8", cw2, 91)
eq("cell: landscape height (464 - 5*8)/6", ch2, 70)
same("box: 4x4 at 0,0", L.box({ x = 0, y = 0, w = 4, h = 4 }, 90, 76), { x = 0, y = 0, w = 384, h = 328 })
same("box: 2x4 at 4,0", L.box({ x = 4, y = 0, w = 2, h = 4 }, 90, 76), { x = 392, y = 0, w = 188, h = 328 })
same("box: 1x1 at 4,4", L.box({ x = 4, y = 4, w = 1, h = 1 }, 90, 76), { x = 392, y = 336, w = 90, h = 76 })

-- fixture lists for the organizer (independent of the bundled defaults)
local D1, D2 = "alfa", "beta"
local FIX_HOME = { { app = D1, size = "4x4" }, { app = D2, size = "2x4" }, { app = "bateria", size = "2x2" },
    { app = "notificacoes", size = "2x2" }, { app = "sistema", size = "1x1" } }
local FIX_SLEEP = { { app = D1, size = "4x4" }, { app = D2, size = "2x4" }, { app = "bateria", size = "2x2" },
    { app = "notificacoes", size = "4x2" } }
-- visible apps, normalize
same("visible_apps", L.visible_apps({ { app = "a" }, { app = "b", hidden = true }, { app = "a" }, { app = "c" } }), { "a", "c" })
local apps = { [D1] = { sizes = { "4x4", "2x2" } }, [D2] = { sizes = { "2x4" } } }
same("normalize: drops unknown, repeats, fixes size",
    L.normalize({ { app = D1, size = "1x1" }, { app = "zz", size = "2x2" }, { app = D2, size = "2x4", hidden = true },
        { app = D1, size = "4x4" }, "junk" }, apps),
    { { app = D1, size = "4x4" }, { app = D2, size = "2x4", hidden = true } })

-- organizer (7.3)
local home = L.copy(FIX_HOME)
local moved, ch1 = L.move(home, D2, -1)
eq("move: before", moved[1].app .. "," .. moved[2].app, D2 .. "," .. D1)
check("move: changed", ch1)
local _, ch2b = L.move(home, D1, -1)
check("move: first cannot go before", not ch2b)
local _, ch3 = L.move(home, "sistema", 1)
check("move: last cannot go after", not ch3)
local hid = L.hide(home, "bateria")
local m2 = L.move(hid, D2, 1)
eq("move: skips hidden", m2[2].app .. "," .. m2[3].app .. "," .. m2[4].app, "notificacoes,bateria," .. D2)
eq("move: original untouched", home[2].app, D2)
local cs = L.cycle_size(home, D1, { "4x4", "4x2", "2x2", "1x1" })
eq("cycle_size: next", cs[1].size, "4x2")
eq("cycle_size: wraps", L.cycle_size(L.cycle_size(L.cycle_size(cs, D1, { "4x4", "4x2", "2x2", "1x1" }), D1,
    { "4x4", "4x2", "2x2", "1x1" }), D1, { "4x4", "4x2", "2x2", "1x1" })[1].size, "4x4")
local _, chs = L.cycle_size(home, D2, { "2x4" })
check("cycle_size: single size no change", not chs)
eq("hide: hidden", L.hide(home, "sistema")[5].hidden, true)
local _, chh = L.hide(hid, "bateria")
check("hide: twice no change", not chh)
eq("remove: removed", #L.remove(L.copy(FIX_SLEEP), D2), 3)
local sh = L.show(hid, "bateria", "2x2")
eq("show: unhidden", sh[3].hidden, nil)
local sh2 = L.show(L.remove(L.copy(FIX_SLEEP), D2), D2, "2x4")
eq("show: appended", sh2[4].app .. "/" .. sh2[4].size, D2 .. "/2x4")
local _, chsh = L.show(home, D1, "4x4")
check("show: visible no change", not chsh)
same("outside: hidden and absent", L.outside(L.hide(L.copy(FIX_SLEEP), D1), { D1, D2, "bateria", "notificacoes", "sistema" }),
    { D1, "sistema" })

-- list paging (6.6)
local p, pages_, first, last = L.paginate(9, 4, 1)
eq("paginate: 9/4 page 1", table.concat({ p, pages_, first, last }, ","), "1,3,1,4")
p, pages_, first, last = L.paginate(9, 4, 3)
eq("paginate: 9/4 page 3", table.concat({ p, pages_, first, last }, ","), "3,3,9,9")
p, pages_, first, last = L.paginate(9, 4, 7)
eq("paginate: clamps high", table.concat({ p, pages_, first, last }, ","), "3,3,9,9")
p, pages_, first, last = L.paginate(0, 4, 1)
eq("paginate: empty = 1 page", table.concat({ p, pages_, first, last }, ","), "1,1,1,0")
p, pages_ = L.paginate(4, 2, 0)
eq("paginate: clamps low, landscape 2/page", p .. "," .. pages_, "1,2")
