-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (C) 2026 Tinta contributors
-- widgets 1x1, 2x2, 4x2 (portrait and landscape cells) and the screen, with the real ui/kit over stubbed KOReader
-- widgets; taps are found through the hot list like the window does. The state is a fake host with the same
-- settings Sistema → Repouso uses (no state of the app's own).
local T = ...
local check, eq = T.check, T.eq
local S = dofile(T.here .. "/stubs.lua")
local Kit = require("ui/kit")
local WidgetFrame = require("ui/widgetframe")
local Draw = require("ui/draw")
local M = require("apps/repouso/init")
local Strings = require("apps/repouso/strings")
local Settings = require("core/settings")
local I18n = require("core/i18n")

local tr = I18n.new(Strings)
I18n.set_lang("pt")

-- a fake host over the real Tinta defaults and choices
local tinta = { idle_sleep = 5, idle_mode = "battery" }
local calls = {}
local host = {
    get = function(_, k) return tinta[k] end,
    set = function(_, k, v) tinta[k] = v; calls[#calls + 1] = "set:" .. k; return true end,
    choices = function(_, k) return Settings.CHOICES[k] end,
    redraw = function() calls[#calls + 1] = "redraw" end,
    sleepNow = function() calls[#calls + 1] = "sleep" end,
}
M._A.host = function() return host end
local confirmed, chosen
local ctx = { ui = Kit, i18n = tr, confirm = function(title, text, ok, fn) confirmed = { title = title, ok = ok, fn = fn } end,
    choose = function(title, options, current, fn) chosen = { title = title, options = options, current = current, fn = fn } end }

local function cell_box(cols, rows, cw, ch) return math.floor(cols * cw + (cols - 1) * 8), math.floor(rows * ch + (rows - 1) * 8) end
eq("manifest: sizes", table.concat(M.sizes, ","), "2x2,4x2,1x1")
eq("manifest: no refresh, no network", tostring(M.refresh) .. tostring(M.net), "nilfalse")
eq("manifest: no notification types", #M.notifications, 0)
eq("manifest: no settings of its own", #M.settings, 0)

-- builds the widget and returns it with its tap boxes
local function build(size, orient, inv)
    local cols, rows = size:match("(%d)x(%d)")
    local w, h = cell_box(tonumber(cols), tonumber(rows), orient[2], orient[3])
    local box = WidgetFrame.body_box(w, h, size, inv or false)
    S.reset()
    S.set_area({ x = 0, y = 0, w = box.w, h = box.h })
    local hot = Draw.begin_hot()
    local ok, wdg = pcall(M.widget, ctx, size, box)
    Draw.end_hot()
    local name = ("widget %s %s%s"):format(size, orient[1], inv and " inv" or "")
    check(name .. ": builds", ok and wdg ~= nil, wdg)
    if not (ok and wdg) then return nil end
    local pok, perr = pcall(function() wdg:paintTo(S.bb, 0, 0) end)
    check(name .. ": paints", pok, perr)
    local s = wdg:getSize()
    check(name .. ": fits the box (R-W1)", s.w <= box.w and s.h <= box.h, s.w .. "x" .. s.h .. " in " .. box.w .. "x" .. box.h)
    check(name .. ": paints inside", #S.oob == 0, S.oob[1])
    return wdg, hot, box
end

for _, orient in ipairs({ { "portrait", 90, 76 }, { "landscape", 91, 74 } }) do
    for _, inv in ipairs({ false, true }) do
        for _, size in ipairs(M.sizes) do
            for _, v in ipairs({ { 5, "battery", "bateria" }, { 5, "never", "nunca" }, { 15, "always", "sempre" } }) do
                tinta.idle_sleep, tinta.idle_mode = v[1], v[2]
                local wdg = build(size, orient, inv)
                local mins = v[2] == "never" and "–" or (v[1] .. " min")
                if wdg and size == "2x2" then
                    check("2x2: minutes", S.has(mins))
                    check("2x2: mode", S.has(v[3]))
                end
                if wdg and size == "4x2" then
                    check("4x2: minutes button", S.has(mins))
                    check("4x2: mode and sleep buttons", S.has(v[3]) and S.has("Dormir"))
                end
            end
        end
    end
end
tinta.idle_sleep, tinta.idle_mode = 5, "battery"

-- 4x2: three buttons, each one at least 64 px tall (6.1) and wider than 64; each acts on the host
do
    local _, hot = build("4x2", { "portrait", 90, 76 })
    local buttons = {}
    for _, b in ipairs(hot) do if b.on_tap and b.border == Kit.theme.BORDER and b.w < 200 then buttons[#buttons + 1] = b end end
    eq("4x2: three tap buttons", #buttons, 3)
    for i, b in ipairs(buttons) do check("4x2: button " .. i .. " is a 64 px target", b.h >= 64 and b.w >= 64, b.w .. "x" .. b.h) end
    calls = {}
    buttons[1].on_tap()
    eq("4x2: first button cycles idle 5 -> 10", tinta.idle_sleep, 10)
    eq("4x2: and redraws", calls[#calls], "redraw")
    buttons[1].on_tap(); buttons[1].on_tap()
    eq("4x2: 10 -> 15 -> 2", tinta.idle_sleep, 2)
    tinta.idle_sleep = 5
    buttons[2].on_tap()
    eq("4x2: second button cycles the mode battery -> never", tinta.idle_mode, "never")
    buttons[2].on_tap()
    eq("4x2: never -> always", tinta.idle_mode, "always")
    buttons[2].on_tap()
    eq("4x2: always -> battery", tinta.idle_mode, "battery")
    tinta.idle_mode = "never"
    local _, hot2 = build("4x2", { "portrait", 90, 76 })
    local b2 = {}
    for _, b in ipairs(hot2) do if b.on_tap and b.border == Kit.theme.BORDER and b.w < 200 then b2[#b2 + 1] = b end end
    b2[1].on_tap()
    eq("4x2: minutes button does nothing while the mode is never", tinta.idle_sleep, 5)
    tinta.idle_mode = "battery"
    calls = {}
    buttons[3].on_tap()
    eq("4x2: third button sleeps now", calls[1], "sleep")
end

-- 1x1: the whole widget is one button; it asks first, then sleeps
do
    local _, hot = build("1x1", { "portrait", 90, 76 })
    local taps = {}
    for _, b in ipairs(hot) do if b.on_tap then taps[#taps + 1] = b end end
    eq("1x1: one tap box", #taps, 1)
    calls, confirmed = {}, nil
    taps[1].on_tap()
    check("1x1: asks for confirmation", confirmed ~= nil and confirmed.title == "Dormir agora?")
    eq("1x1: nothing slept before the answer", #calls, 0)
    confirmed.fn()
    eq("1x1: sleeps after OK", calls[1], "sleep")
end

-- 2x2 has no inner buttons: a tap anywhere opens the screen (the tile's own tap)
do
    local _, hot = build("2x2", { "portrait", 90, 76 })
    local n = 0
    for _, b in ipairs(hot) do if b.on_tap then n = n + 1 end end
    eq("2x2: no inner tap boxes (the tile opens the screen)", n, 0)
end

-- the screen: the three actions, the same settings
for _, b in ipairs({ { w = 584, h = 608, landscape = false }, { w = 784, h = 408, landscape = true } }) do
    local name = "screen " .. (b.landscape and "landscape" or "portrait")
    tinta.idle_sleep, tinta.idle_mode = 5, "battery"
    S.reset()
    S.set_area({ x = 0, y = 0, w = b.w, h = b.h })
    local hot = Draw.begin_hot()
    local ok, res = pcall(M.screens.main, ctx, nil, b)
    Draw.end_hot()
    check(name .. ": builds", ok and type(res) == "table" and res.body ~= nil, res)
    if ok and res then
        local pok, perr = pcall(function() res.body:paintTo(S.bb, 0, 0) end)
        check(name .. ": paints", pok, perr)
        local s = res.body:getSize()
        check(name .. ": fits", s.w <= b.w and s.h <= b.h, s.w .. "x" .. s.h)
        check(name .. ": inside", #S.oob == 0, S.oob[1])
        check(name .. ": the actions", S.has("Dormir sozinho") and S.has("Depois de") and S.has("Dormir agora"))
        check(name .. ": no expediente", not S.has("expediente"))
        check(name .. ": state", S.has("5 min") and S.has("só na bateria"))
        local taps = {}
        for _, bx in ipairs(hot) do if bx.on_tap then taps[#taps + 1] = bx end end
        eq(name .. ": three rows to tap", #taps, 3)
        table.sort(taps, function(a, c) return (a.dimen.y or 0) < (c.dimen.y or 0) end)
        calls, chosen = {}, nil
        taps[1].on_tap()
        check(name .. ": row 1 opens the mode popup", chosen and chosen.title == "Dormir sozinho" and #chosen.options == 3
            and chosen.current == "battery" and chosen.options[3].value == "never" and chosen.options[3].label == "nunca"
            and chosen.options[1].sub == "com ou sem o cabo ligado")
        eq(name .. ": opening the popup changes nothing", tinta.idle_mode, "battery")
        chosen.fn("never"); eq(name .. ": picking a mode saves it", tinta.idle_mode, "never")
        tinta.idle_mode = "battery"
        chosen = nil
        taps[2].on_tap()
        check(name .. ": row 2 opens the minutes popup", chosen and chosen.title == "Depois de" and #chosen.options == 4
            and chosen.current == 5 and chosen.options[2].label == "5 min")
        chosen.fn(15); eq(name .. ": picking minutes saves them", tinta.idle_sleep, 15)
        tinta.idle_sleep = 5
        taps[3].on_tap(); eq(name .. ": row 3 sleeps", calls[#calls], "sleep")
    end
    -- mode "nunca": the minutes row is gone
    tinta.idle_mode = "never"
    S.reset()
    S.set_area({ x = 0, y = 0, w = b.w, h = b.h })
    hot = Draw.begin_hot()
    ok, res = pcall(M.screens.main, ctx, nil, b)
    Draw.end_hot()
    if ok and res then
        res.body:paintTo(S.bb, 0, 0)
        check(name .. ": never hides the minutes", not S.has("Depois de") and S.has("nunca"))
        local n = 0
        for _, bx in ipairs(hot) do if bx.on_tap then n = n + 1 end end
        eq(name .. ": never has two rows", n, 2)
    end
end
M._A.host = function() return nil end
check("no host (tests): widget still draws", pcall(M.widget, ctx, "2x2", WidgetFrame.body_box(188, 160, "2x2", false)))
