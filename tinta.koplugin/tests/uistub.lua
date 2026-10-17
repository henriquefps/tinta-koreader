-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (C) 2026 Tinta contributors
-- Headless stand-ins for the KOReader widgets ui/kit needs (fixed-width fake text, like tests/tinta_ui_smoke.lua
-- and apps/bateria/tests/test_view.lua), so apps' widgets and screens can be built, painted and measured in plain
-- Lua. H = require("uistub").install(): H.kit (the real ui/kit), H.bb (fake blitbuffer), H.begin(w, h) (start
-- collecting inside a w x h area), H.oob (paints outside it), H.texts, H.has(text), H.cell(cols, rows, orient).
local M = {}

function M.install()
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

    local H = { oob = {}, texts = {} }
    local function paint_check(what, x, y, w, h)
        if w <= 0 or h <= 0 or not H.area then return end
        local a = H.area
        if x < a.x or y < a.y or x + w > a.x + a.w or y + h > a.y + a.h then
            H.oob[#H.oob + 1] = ("%s %d,%d %dx%d"):format(what, x, y, w, h)
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
    function TextWidget:paintTo(_, x, y) H.texts[#H.texts + 1] = self.text; paint_check("text '" .. self.text .. "'", x, y, self._w, self._h) end
    preload("ui/widget/textwidget", TextWidget)
    local TextBoxWidget = Widget:extend{}
    function TextBoxWidget:init()
        local per_line = math.max(1, math.floor(self.width / (self.face.size * 0.55)))
        local h = math.max(1, math.ceil(utf8len(self.text) / per_line)) * math.floor(self.face.size * 1.35)
        if self.height and h > self.height then h = self.height end
        self._h = h
    end
    function TextBoxWidget:getSize() return Geom:new{ w = self.width, h = self._h } end
    function TextBoxWidget:paintTo(_, x, y) H.texts[#H.texts + 1] = self.text; paint_check("textbox", x, y, self.width, self._h) end
    preload("ui/widget/textboxwidget", TextBoxWidget)

    H.kit = require("ui/kit")
    H.WidgetFrame = require("ui/widgetframe")
    H.bb = {
        paintRect = function(_, x, y, w, h) paint_check("rect", x, y, w, h) end,
        paintRoundedRect = function(_, x, y, w, h) paint_check("rrect", x, y, w, h) end,
        paintBorder = function(_, x, y, w, h) paint_check("border", x, y, w, h) end,
    }
    function H.begin(w, h) H.oob, H.texts = {}, {}; H.area = { x = 0, y = 0, w = w, h = h } end
    function H.has(text)
        for _, t in ipairs(H.texts) do if tostring(t):find(text, 1, true) then return true end end
        return false
    end
    -- widget box of a size as the grid gives it (cell 90.7 x 76 px portrait, 91 x 74 landscape)
    function H.cell(size, orient, inv)
        local cols, rows = size:match("(%d)x(%d)")
        cols, rows = tonumber(cols), tonumber(rows)
        local cw, ch = 90, 76
        if orient == "landscape" then cw, ch = 91, 74 end
        local w, h = math.floor(cols * cw + (cols - 1) * 8), math.floor(rows * ch + (rows - 1) * 8)
        return H.WidgetFrame.body_box(w, h, size, inv or false)
    end
    -- builds a widget and checks it paints inside its box (R-W1); returns the widget or nil
    function H.widget(T, name, fn, box)
        H.begin(box.w, box.h)
        local ok, wdg = pcall(fn)
        T.check(name .. ": builds", ok and wdg ~= nil, wdg)
        if not (ok and wdg) then return nil end
        local pok, perr = pcall(function() wdg:paintTo(H.bb, 0, 0) end)
        T.check(name .. ": paints", pok, perr)
        local s = wdg:getSize()
        T.check(name .. ": fits the box (R-W1)", s.w <= box.w and s.h <= box.h, s.w .. "x" .. s.h .. " in " .. box.w .. "x" .. box.h)
        T.check(name .. ": paints inside", #H.oob == 0, H.oob[1])
        return wdg
    end
    -- a screen result's body in portrait and landscape body boxes
    function H.screen(T, name, fn, b)
        H.begin(b.w, b.h)
        local ok, res = pcall(fn)
        T.check(name .. ": builds", ok and type(res) == "table" and res.body ~= nil, res)
        if not (ok and res) then return nil end
        local pok, perr = pcall(function() res.body:paintTo(H.bb, 0, 0) end)
        T.check(name .. ": paints", pok, perr)
        local s = res.body:getSize()
        T.check(name .. ": fits", s.w <= b.w and s.h <= b.h, s.w .. "x" .. s.h .. " in " .. b.w .. "x" .. b.h)
        T.check(name .. ": inside", #H.oob == 0, H.oob[1])
        return res
    end
    return H
end

return M
