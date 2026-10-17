-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (C) 2026 Tinta contributors
-- widgets in every declared size and the screen in portrait and landscape, built with the real ui/kit over stubbed
-- KOReader widgets (fixed-width fake text, like tests/tinta_ui_smoke.lua). Checks: no Lua error, every paint
-- inside the box the core gave (R-W1), the texts that matter are there. The device is still the real check.
local T = ...
local check, eq = T.check, T.eq

local function preload(name, mod) package.preload[name] = function() return mod end end
local Geom = {}
Geom.__index = Geom
function Geom:new(o) o = o or {}; o.x, o.y, o.w, o.h = o.x or 0, o.y or 0, o.w or 0, o.h or 0; return setmetatable(o, Geom) end
preload("ui/geometry", Geom)
local Widget = {}
function Widget:extend(o) o = o or {}; setmetatable(o, self); self.__index = self; return o end
function Widget:new(o) o = self:extend(o); if o.init then o:init() end; return o end
function Widget:getSize() return self.dimen or Geom:new{} end
function Widget:paintTo() end
function Widget:free() end
preload("ui/widget/widget", Widget)
preload("ffi/blitbuffer", { COLOR_BLACK = "B", COLOR_WHITE = "W", COLOR_DARK_GRAY = "G" })
preload("ui/font", { getFace = function(_, name, size) return { name = name, size = size } end })

local oob, texts = {}, {}
local area
local function paint_check(what, x, y, w, h)
    if w <= 0 or h <= 0 then return end
    if x < area.x or y < area.y or x + w > area.x + area.w or y + h > area.y + area.h then
        oob[#oob + 1] = ("%s %d,%d %dx%d"):format(what, x, y, w, h)
    end
end
local function utf8len(s) local _, n = tostring(s):gsub("[^\128-\191]", ""); return n end
local TextWidget = Widget:extend{}
function TextWidget:init()
    local w = math.floor(utf8len(self.text) * self.face.size * 0.55)
    if self.max_width and w > self.max_width then w = self.max_width end
    self._w, self._h = w, math.floor(self.face.size * 1.35)
end
function TextWidget:getSize() return Geom:new{ w = self._w, h = self._h } end
function TextWidget:paintTo(_, x, y) texts[#texts + 1] = self.text; paint_check("text '" .. self.text .. "'", x, y, self._w, self._h) end
preload("ui/widget/textwidget", TextWidget)
local TextBoxWidget = Widget:extend{}
function TextBoxWidget:init()
    local per_line = math.max(1, math.floor(self.width / (self.face.size * 0.55)))
    local h = math.max(1, math.ceil(utf8len(self.text) / per_line)) * math.floor(self.face.size * 1.35)
    if self.height and h > self.height then h = self.height end
    self._h = h
end
function TextBoxWidget:getSize() return Geom:new{ w = self.width, h = self._h } end
function TextBoxWidget:paintTo(_, x, y) texts[#texts + 1] = self.text; paint_check("textbox", x, y, self.width, self._h) end
preload("ui/widget/textboxwidget", TextBoxWidget)

local Kit = require("ui/kit")
local WidgetFrame = require("ui/widgetframe")
local Strings = require("apps/bateria/strings")
local Log = require("apps/bateria/csvlog")
local M = require("apps/bateria/init")
local A = M._A

local bb = {
    paintRect = function(_, x, y, w, h) paint_check("rect", x, y, w, h) end,
    paintRoundedRect = function(_, x, y, w, h) paint_check("rrect", x, y, w, h) end,
    paintBorder = function(_, x, y, w, h) paint_check("border", x, y, w, h) end,
}
local function has(text)
    for _, t in ipairs(texts) do if tostring(t):find(text, 1, true) then return true end end
    return false
end

-- a ctx like ui/host builds (ui = kit), over a log with the prototype's discharge (99 % -> 78 %)
local store = Log.open(nil)
local t0 = 1792000000
for i = 0, 40 do store:sample(t0 + i * 400, { pct = 99 - math.floor(i / 2), charging = false, wifi = true, ma = -48, mah = 890 - i * 5 }) end
A.store = store
local now = t0 + 40 * 400
A.last = { pct = 79, charging = false, eta = 15 * 3600, kind = "live", basis = "mah", ma_mean = 47.6, full_mah = 907,
    temp = 23, samples = 3120, at = now }
local cache = {}
local ctx = { ui = Kit, now = function() return now end,
    i18n = require("core/i18n").new(Strings),
    cache = { get = function() return cache.v end, put = function(_, v) cache.v = v end } }

-- widget sizes as the grid gives them in portrait (cell 90.7 x 76 px) and landscape
local function cell_box(cols, rows, cw, ch) return math.floor(cols * cw + (cols - 1) * 8), math.floor(rows * ch + (rows - 1) * 8) end
for _, orient in ipairs({ { "portrait", 90, 76 }, { "landscape", 91, 74 } }) do
    for _, size in ipairs(M.sizes) do
        for _, inv in ipairs({ false, true }) do
            local cols, rows = size:match("(%d)x(%d)")
            local w, h = cell_box(tonumber(cols), tonumber(rows), orient[2], orient[3])
            local box = WidgetFrame.body_box(w, h, size, inv)
            local name = ("widget %s %s%s"):format(size, orient[1], inv and " inverted" or "")
            oob, texts = {}, {}
            area = { x = 0, y = 0, w = box.w, h = box.h }
            local ok, wdg = pcall(M.widget, ctx, size, box)
            check(name .. ": builds", ok and wdg ~= nil, wdg)
            if ok and wdg then
                local pok, perr = pcall(function() wdg:paintTo(bb, 0, 0) end)
                check(name .. ": paints", pok, perr)
                local s = wdg:getSize()
                check(name .. ": fits the box (R-W1)", s.w <= box.w and s.h <= box.h, s.w .. "x" .. s.h .. " in " .. box.w .. "x" .. box.h)
                check(name .. ": paints inside", #oob == 0, oob[1])
                check(name .. ": percentage", has("79%"))
                if size ~= "1x1" then check(name .. ": estimate", has("~15h · 48 mA")) end
            end
        end
    end
end

-- screen in portrait and landscape (body boxes of ui/screen: 584 x 608 and 784 x 408)
for _, b in ipairs({ { w = 584, h = 608, landscape = false }, { w = 784, h = 408, landscape = true } }) do
    local name = "screen " .. (b.landscape and "landscape" or "portrait")
    oob, texts = {}, {}
    area = { x = 0, y = 0, w = b.w, h = b.h }
    local ok, res = pcall(M.screens.main, ctx, nil, b)
    check(name .. ": builds", ok and type(res) == "table" and res.body ~= nil, res)
    if ok and res then
        local pok, perr = pcall(function() res.body:paintTo(bb, 0, 0) end)
        check(name .. ": paints", pok, perr)
        local s = res.body:getSize()
        check(name .. ": fits", s.w <= b.w and s.h <= b.h, s.w .. "x" .. s.h)
        check(name .. ": inside", #oob == 0, oob[1])
        check(name .. ": big percentage", has("79%"))
        check(name .. ": estimate line", has("~15h restantes · 48 mA em média"))
        check(name .. ": y labels", has("80%") and has("90%"))
        check(name .. ": x labels (hours)", (function() for _, t in ipairs(texts) do if tostring(t):match("^%d+h$") then return true end end end)())
        check(name .. ": stat blocks", has("48 mA") and has("907") and has("23 °C") and has("3.120") and has("amostras"))
        check(name .. ": chart note", has("Gráfico:") and has("99% a 79%"))
        check(name .. ": basis", has("contador de carga"))
    end
end

-- nothing logged yet and no reading: still draws
A.store, A.last = Log.open(nil), nil
cache.v = nil
oob, texts = {}, {}
area = { x = 0, y = 0, w = 584, h = 608 }
local ok, res = pcall(M.screens.main, ctx, nil, { w = 584, h = 608, landscape = false })
check("empty screen: builds", ok and res and res.body, res)
if ok and res then
    check("empty screen: paints", pcall(function() res.body:paintTo(bb, 0, 0) end))
    check("empty screen: inside", #oob == 0, oob[1])
    check("empty screen: no reading text", has("sem leitura do medidor"))
    check("empty screen: chart placeholder", has("ainda sem amostras"))
end
for _, size in ipairs(M.sizes) do
    local bw, bh = cell_box(tonumber(size:sub(1, 1)), tonumber(size:sub(3, 3)), 90, 76)
    local box = WidgetFrame.body_box(bw, bh, size, false)
    oob, texts = {}, {}
    area = { x = 0, y = 0, w = box.w, h = box.h }
    local wok, wdg = pcall(M.widget, ctx, size, box)
    check("empty widget " .. size .. ": builds and paints", wok and wdg and pcall(function() wdg:paintTo(bb, 0, 0) end), wdg)
    check("empty widget " .. size .. ": inside", #oob == 0, oob[1])
end
-- charging state text in the widget
A.last = { pct = 60, charging = true, eta = 40 * 60, at = now }
local cw2, ch2 = cell_box(2, 2, 90, 76)
local box = WidgetFrame.body_box(cw2, ch2, "2x2", false)
texts = {}
area = { x = 0, y = 0, w = box.w, h = box.h }
M.widget(ctx, "2x2", box):paintTo(bb, 0, 0)
check("charging widget: number", has("⚡60%"))
-- 1x1: every value 0-100, charging or not, normal and inverted. The stub text measures 0.55 em per char and
-- clamps to max_width (the real "…"), so also check with a pessimistic bold metric (digits 0.62 em, "%" 1.0 em)
-- that the text fits the 1x1 body box. The real font is a device check.
local Vm, View = require("apps/bateria/logic"), require("apps/bateria/view")
local b1w, b1h = cell_box(1, 1, 90, 76)
local box1 = WidgetFrame.body_box(b1w, b1h, "1x1", false)
local worst = 0
for pct = 0, 100 do
    for _, chg in ipairs({ false, true }) do
        for _, inv in ipairs({ false, true }) do
            local vm = Vm.view({ pct = pct, charging = chg, at = now }, now, T.L, "pt")
            local b = WidgetFrame.body_box(b1w, b1h, "1x1", inv)
            oob, texts = {}, {}
            area = { x = 0, y = 0, w = b.w, h = b.h }
            local wdg = View.widget_1x1(ctx, b, vm)
            wdg:paintTo(bb, 0, 0)
            local sz = wdg:getSize()
            local label = ("1x1 %d%%%s%s"):format(pct, chg and " charging" or "", inv and " inv" or "")
            if sz.w > b.w or sz.h > b.h or #oob > 0 or not has(pct .. "%") or has("⚡") then
                check(label .. ": fits, no glyph", false, sz.w .. "x" .. sz.h .. " in " .. b.w .. "x" .. b.h .. " " .. tostring(oob[1]))
            end
            local text = pct .. "%"
            local font = #text >= 4 and View.ONE_FONT_WIDE or View.ONE_FONT
            local est = 0
            for ch in text:gmatch(".") do est = est + (ch == "%" and 1.0 or 0.62) * font end
            worst = math.max(worst, est)
        end
    end
end
check("1x1: all values 0-100, charging or not, fit and have no glyph", true)
check("1x1: pessimistic text width (" .. math.floor(worst) .. " px) fits the body box (" .. box1.w .. " px)", worst <= box1.w, worst)
A.store, A.last = nil, nil
