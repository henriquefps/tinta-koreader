-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (C) 2026 Tinta contributors
-- Stubs of the KOReader widgets (fixed-width fake text, like tests/tinta_ui_smoke.lua) so the real ui/kit and the app
-- views run headless. Returns { check_area(x, y, w, h), set_area(a), reset(), texts, oob, has(text), bb }.
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

local S = { oob = {}, texts = {} }
local area
local function paint_check(what, x, y, w, h)
    if w <= 0 or h <= 0 then return end
    if x < area.x or y < area.y or x + w > area.x + area.w or y + h > area.y + area.h then
        S.oob[#S.oob + 1] = ("%s %d,%d %dx%d"):format(what, x, y, w, h)
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
function TextWidget:paintTo(_, x, y) S.texts[#S.texts + 1] = self.text; paint_check("text '" .. self.text .. "'", x, y, self._w, self._h) end
preload("ui/widget/textwidget", TextWidget)
local TextBoxWidget = Widget:extend{}
function TextBoxWidget:init()
    local per_line = math.max(1, math.floor(self.width / (self.face.size * 0.55)))
    local h = math.max(1, math.ceil(utf8len(self.text) / per_line)) * math.floor(self.face.size * 1.35)
    if self.height and h > self.height then h = self.height end
    self._h = h
end
function TextBoxWidget:getSize() return Geom:new{ w = self.width, h = self._h } end
function TextBoxWidget:paintTo(_, x, y) S.texts[#S.texts + 1] = self.text; paint_check("textbox", x, y, self.width, self._h) end
preload("ui/widget/textboxwidget", TextBoxWidget)


function S.set_area(a) area = a end
function S.reset() S.oob, S.texts = {}, {} end
function S.has(text)
    for _, t in ipairs(S.texts) do if tostring(t):find(text, 1, true) then return true end end
    return false
end
S.bb = {
    paintRect = function(_, x, y, w, h) paint_check("rect", x, y, w, h) end,
    paintRoundedRect = function(_, x, y, w, h) paint_check("rrect", x, y, w, h) end,
    paintBorder = function(_, x, y, w, h) paint_check("border", x, y, w, h) end,
}
return S
