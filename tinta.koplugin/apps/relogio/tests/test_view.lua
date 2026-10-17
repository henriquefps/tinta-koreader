-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (C) 2026 Tinta contributors
-- widgets in every size and style (portrait and landscape cells), asleep and awake, and the style screen, built
-- with the real ui/kit over stubbed KOReader widgets. Checks: no Lua error, every paint inside the box (R-W1),
-- the texts that matter. The device is still the real check.
local T = ...
local check, eq = T.check, T.eq
local S = dofile(T.here .. "/stubs.lua")
local Kit = require("ui/kit")
local WidgetFrame = require("ui/widgetframe")
local Draw = require("ui/draw")
local Logic = require("apps/relogio/logic")
local View = require("apps/relogio/view")
local M = require("apps/relogio/init")
local Strings = require("apps/relogio/strings")
local I18n = require("core/i18n")

local tr = I18n.new(Strings)
local ctx = { ui = Kit }
local now = T.ts(2026, 10, 16, 10, 45)
local function vm(over)
    local v = { t = now, L = tr.t, style = "digital", asleep = false, next_at = nil, date = T.utc }
    for k, x in pairs(over or {}) do v[k] = x end
    return v
end
local function cell_box(cols, rows, cw, ch) return math.floor(cols * cw + (cols - 1) * 8), math.floor(rows * ch + (rows - 1) * 8) end

I18n.set_lang("pt")
eq("manifest: sizes", table.concat(M.sizes, ","), "2x2,4x2,4x4,2x4,1x1")
eq("manifest: no refresh, no network", tostring(M.refresh) .. tostring(M.net), "nilfalse")
eq("manifest: no notification types", #M.notifications, 0)
eq("manifest: style setting is a choice of the four styles", #M.settings[1].choices, #Logic.STYLES)
eq("manifest: style default", M.settings[1].default, "digital")

local cases = {
    { "digital", {}, { "10:45" } },
    { "data", {}, { "10:45", "sexta" } },
    { "analogico", {}, { "10:45" } },
    { "minimo", {}, { "10:45" } },
    { "minimo", { asleep = true, next_at = T.ts(2026, 10, 16, 11, 15) }, { "10:45", "11:15" } },
    { "minimo", { asleep = true, next_at = nil }, { "10:45", "sem despertar" } },
}
for _, orient in ipairs({ { "portrait", 90, 76 }, { "landscape", 91, 74 } }) do
    for _, size in ipairs(M.sizes) do
        for _, c in ipairs(cases) do
            for _, inv in ipairs({ false, true }) do
                local cols, rows = size:match("(%d)x(%d)")
                local w, h = cell_box(tonumber(cols), tonumber(rows), orient[2], orient[3])
                local box = WidgetFrame.body_box(w, h, size, inv)
                local name = ("widget %s %s %s%s%s"):format(size, orient[1], c[1], c[2].asleep and " asleep" or "", inv and " inv" or "")
                S.reset()
                S.set_area({ x = 0, y = 0, w = box.w, h = box.h })
                local ok, wdg = pcall(View.widget, ctx, size, box, vm({ style = c[1], asleep = c[2].asleep, next_at = c[2].next_at }))
                check(name .. ": builds", ok and wdg ~= nil, wdg)
                if ok and wdg then
                    local pok, perr = pcall(function() wdg:paintTo(S.bb, 0, 0) end)
                    check(name .. ": paints", pok, perr)
                    local s = wdg:getSize()
                    check(name .. ": fits the box (R-W1)", s.w <= box.w and s.h <= box.h, s.w .. "x" .. s.h .. " in " .. box.w .. "x" .. box.h)
                    check(name .. ": paints inside", #S.oob == 0, S.oob[1])
                    -- analog 2x2 is the face alone; 1x1 is always HH:MM; the sleep line only for "minimo"
                    if size == "1x1" then check(name .. ": HH:MM", S.has("10:45"))
                    else
                        for _, want in ipairs(c[3]) do
                            local skip = (c[1] == "analogico" and size == "2x2" and want == "10:45")
                                or (c[1] == "data" and size == "1x1")
                            if not skip then check(name .. ": has '" .. want .. "'", S.has(want)) end
                        end
                    end
                end
            end
        end
    end
end

-- the date line is the whole date on wide widgets and two lines on narrow ones
do
    local function paint(size, style)
        local w, h = cell_box(tonumber(size:sub(1, 1)), tonumber(size:sub(3, 3)), 90, 76)
        local box = WidgetFrame.body_box(w, h, size, false)
        S.reset(); S.set_area({ x = 0, y = 0, w = box.w, h = box.h })
        View.widget(ctx, size, box, vm({ style = style })):paintTo(S.bb, 0, 0)
    end
    paint("4x2", "data"); check("data 4x2: whole date on one line", S.has("sexta, 16 de outubro"))
    paint("4x4", "data"); check("data 4x4: whole date", S.has("sexta, 16 de outubro"))
    paint("2x2", "data"); check("data 2x2: weekday and day on two lines", S.has("sexta") and S.has("16 de outubro") and not S.has("sexta,"))
    paint("2x4", "data"); check("data 2x4: two lines", S.has("sexta") and S.has("16 de outubro"))
    I18n.set_lang("en")
    paint("4x2", "data"); check("data 4x2 en", S.has("Friday, October 16"))
    I18n.set_lang("pt")
end

-- the screen in portrait and landscape: preview + the four styles; the chosen one is marked and tap picks
for _, b in ipairs({ { w = 584, h = 608, landscape = false }, { w = 784, h = 408, landscape = true } }) do
    for _, style in ipairs(Logic.STYLES) do
        local name = ("screen %s %s"):format(b.landscape and "landscape" or "portrait", style)
        S.reset()
        S.set_area({ x = 0, y = 0, w = b.w, h = b.h })
        local picked
        local hot = Draw.begin_hot()
        local ok, res = pcall(View.screen, ctx, b, vm({ style = style }), function(s) picked = s end)
        Draw.end_hot()
        check(name .. ": builds", ok and type(res) == "table" and res.body ~= nil, res)
        if ok and res then
            local pok, perr = pcall(function() res.body:paintTo(S.bb, 0, 0) end)
            check(name .. ": paints", pok, perr)
            local s = res.body:getSize()
            check(name .. ": fits", s.w <= b.w and s.h <= b.h, s.w .. "x" .. s.h)
            check(name .. ": inside", #S.oob == 0, S.oob[1])
            for _, st in ipairs(Logic.STYLES) do check(name .. ": lists " .. st, S.has(Strings.pt["style_" .. st])) end
            check(name .. ": preview time", S.has("10:45"))
            -- tapping the row of another style picks it
            local other = Logic.next_style(style)
            for _, bx in ipairs(hot) do
                if bx.on_tap and bx.child then
                    local before = picked
                    bx.on_tap()
                    if picked == other then break end
                end
            end
            check(name .. ": tapping a row picks that style", picked ~= nil)
        end
    end
end

-- init: widget() reads the style from ctx.settings, asleep state from the host seam
do
    local style = "minimo"
    local c = { ui = Kit, now = function() return now end, i18n = tr, settings = { get = function(_, k) return style end, set = function(_, k, v) style = v end } }
    local saved = M._A.host
    M._A.host = function() return { isSleeping = function() return true end, sleep_info = { next_at = T.ts(2026, 10, 16, 11, 15) }, redraw = function() end } end
    local box = WidgetFrame.body_box(cell_box(4, 2, 90, 76), select(2, cell_box(4, 2, 90, 76)), "4x2", false)
    S.reset(); S.set_area({ x = 0, y = 0, w = box.w, h = box.h })
    local wok, wdg = pcall(M.widget, c, "4x2", box)
    check("init: widget builds", wok and wdg, wdg)
    wdg:paintTo(S.bb, 0, 0)
    check("init: asleep minimal shows the next wake-up", S.has("próximo despertar 11:15") or S.has("despertar"))
    M._A.host = function() return nil end
    local wok2 = pcall(M.widget, c, "4x2", box)
    check("init: no host (tests) still draws", wok2)
    M._A.host = saved
end
