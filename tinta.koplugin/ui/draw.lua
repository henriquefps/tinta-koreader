-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (C) 2026 Tinta contributors
-- Tinta: drawing primitives over KOReader widgets. Black and white only (R-A3), no animations.
--
-- * Box: a fixed-size frame (background, solid or dashed border, rounded corners, padding, alignment) with an
--   optional child and optional tap / hold callbacks. Boxes with callbacks register themselves in the hot
--   list of the build in progress; the window hit-tests that list (last registered = topmost).
-- * Stack: vertical or horizontal list of children. It measures its children on every call and never caches
--   (R-L1: a KOReader HorizontalGroup/VerticalGroup caches its layout on getSize and crashes when children are
--   added after it; Stack has no such state).
-- * Layers: children at absolute positions, painted in order (overlays last).
-- * Spans: a pixel mask from ui/shapes (icons).
local Blitbuffer = require("ffi/blitbuffer")
local Font = require("ui/font")
local Geom = require("ui/geometry")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local Widget = require("ui/widget/widget")

local Shapes = require("ui/shapes")
local T = require("ui/theme")

local M = {}

local BLACK, WHITE = Blitbuffer.COLOR_BLACK, Blitbuffer.COLOR_WHITE
M.BLACK, M.WHITE = BLACK, WHITE

function M.fg(inv) return inv and WHITE or BLACK end
function M.bg(inv) return inv and BLACK or WHITE end

---------------------------------------------------------------- hot list (tap targets of the current build)

local hot = nil
local layer = 0

-- starts a new build; returns the list Boxes with callbacks will be added to
function M.begin_hot()
    hot = {}
    layer = 0
    return hot
end

function M.end_hot() hot = nil end

-- Boxes created from now on belong to overlay layer n (0 = screen). The window hit-tests the highest layer
-- first and, inside a layer, the smallest box (a button wins over the frame it sits in).
function M.set_layer(n) layer = n or 0 end

---------------------------------------------------------------- text

function M.face(size) return Font:getFace(T.FONT, size) end

-- one line, truncated with "…" at max_w
function M.text(str, size, bold, max_w, fg)
    return TextWidget:new{
        text = tostring(str or ""),
        face = M.face(size or T.FONT_BODY),
        bold = bold or false,
        fgcolor = fg or BLACK,
        max_width = max_w and math.max(1, math.floor(max_w)) or nil,
    }
end

-- several lines in w px; with h, cut at that height with "…"
function M.textbox(str, size, w, h, bold, fg, align)
    return TextBoxWidget:new{
        text = tostring(str or ""),
        face = M.face(size or T.FONT_BODY),
        bold = bold or false,
        fgcolor = fg or BLACK,
        width = math.max(1, math.floor(w)),
        height = h and math.max(1, math.floor(h)) or nil,
        height_overflow_show_ellipsis = h and true or nil,
        alignment = align or "left",
    }
end

-- text width without keeping the widget around
function M.text_width(str, size, bold)
    local w = M.text(str, size, bold)
    local tw = w:getSize().w
    w:free()
    return tw
end

---------------------------------------------------------------- Spacer and Fill

local Spacer = Widget:extend{ w = 0, h = 0 }
function Spacer:getSize() return Geom:new{ w = self.w, h = self.h } end
function Spacer:paintTo() end
M.Spacer = Spacer

function M.space(w, h) return Spacer:new{ w = math.max(0, math.floor(w or 0)), h = math.max(0, math.floor(h or 0)) } end

local Fill = Widget:extend{ w = 0, h = 0, color = BLACK, radius = nil }
function Fill:getSize() return Geom:new{ w = self.w, h = self.h } end
function Fill:paintTo(bb, x, y)
    if self.radius and self.radius > 0 then bb:paintRoundedRect(x, y, self.w, self.h, self.color, self.radius)
    else bb:paintRect(x, y, self.w, self.h, self.color) end
end
M.Fill = Fill

---------------------------------------------------------------- Spans (icons)

local Spans = Widget:extend{ w = 0, h = 0, spans = nil, color = BLACK }
function Spans:getSize() return Geom:new{ w = self.w, h = self.h } end
function Spans:paintTo(bb, x, y)
    local c = self.color
    for _, s in ipairs(self.spans or {}) do bb:paintRect(x + s[2], y + s[1], s[3], 1, c) end
end
M.Spans = Spans

-- icon sizes come from the theme (scaled); the masks scale their strokes with T.s
function M.icon_wifi(state, fg)
    local w, h = T.ICON_WIFI_W, T.ICON_WIFI_H
    return Spans:new{ w = w, h = h, spans = Shapes.wifi(w, h, state, T.s), color = fg or BLACK }
end
function M.icon_bell(fg, w, h)
    w, h = w or T.ICON_BELL_W, h or T.ICON_BELL_H
    return Spans:new{ w = w, h = h, spans = Shapes.bell(w, h, T.s), color = fg or BLACK }
end
function M.icon_gear(d, fg) d = d or T.ICON_GEAR; return Spans:new{ w = d, h = d, spans = Shapes.gear(d), color = fg or BLACK } end
function M.icon_house(fg)
    local w, h = T.ICON_HOUSE_W, T.ICON_HOUSE_H
    return Spans:new{ w = w, h = h, spans = Shapes.house(w, h, T.s), color = fg or BLACK }
end
function M.icon_bars(fg)
    local w, h = T.ICON_BARS_W, T.ICON_BARS_H
    return Spans:new{ w = w, h = h, spans = Shapes.bars(w, h, T.s), color = fg or BLACK }
end

-- battery: outlined body with a terminal nub, filled proportionally (same drawing as the earlier standalone plugin)
local Battery = Widget:extend{ pct = 0, w = nil, h = nil, fg = BLACK }   -- w, h default to T.BAT_W, T.BAT_H
function Battery:getSize() return Geom:new{ w = (self.w or T.BAT_W) + T.BAT_NUB, h = self.h or T.BAT_H } end
function Battery:paintTo(bb, x, y)
    local w, h, fg = self.w or T.BAT_W, self.h or T.BAT_H, self.fg
    local bg = fg == BLACK and WHITE or BLACK
    local b = math.max(T.px1(2), T.px(math.floor(h / T.s / 9 + 1e-6)))   -- 1/9 of the design height, scaled
    bb:paintRect(x, y, w, h, fg)
    bb:paintRect(x + b, y + b, w - 2 * b, h - 2 * b, bg)
    local nub = math.floor(h * 0.44)
    bb:paintRect(x + w, y + math.floor((h - nub) / 2), T.BAT_NUB, nub, fg)
    local inset = 2 * b
    local fill = math.floor((w - 2 * inset) * math.max(0, math.min(100, self.pct or 0)) / 100 + 0.5)
    if fill > 0 then bb:paintRect(x + inset, y + inset, fill, h - 2 * inset, fg) end
end
M.Battery = Battery

---------------------------------------------------------------- Stack

-- Stack{ dir = "v"|"h", gap = 0, align = "start"|"center"|"end", children... }
local Stack = Widget:extend{ dir = "v", gap = 0, align = "start" }

function Stack:getSize()
    local main, cross = 0, 0
    local n = 0
    for _, c in ipairs(self) do
        local s = c:getSize()
        n = n + 1
        if self.dir == "v" then main = main + s.h; cross = math.max(cross, s.w)
        else main = main + s.w; cross = math.max(cross, s.h) end
    end
    if n > 1 then main = main + (n - 1) * self.gap end
    if self.dir == "v" then return Geom:new{ w = cross, h = main } end
    return Geom:new{ w = main, h = cross }
end

function Stack:paintTo(bb, x, y)
    local size = self:getSize()
    local off = 0
    for _, c in ipairs(self) do
        local s = c:getSize()
        local cx, cy
        if self.dir == "v" then
            cx = x
            if self.align == "center" then cx = x + math.floor((size.w - s.w) / 2)
            elseif self.align == "end" then cx = x + size.w - s.w end
            cy = y + off
            off = off + s.h + self.gap
        else
            cy = y
            if self.align == "center" then cy = y + math.floor((size.h - s.h) / 2)
            elseif self.align == "end" then cy = y + size.h - s.h end
            cx = x + off
            off = off + s.w + self.gap
        end
        c:paintTo(bb, cx, cy)
    end
    self.dimen = Geom:new{ x = x, y = y, w = size.w, h = size.h }
end

function Stack:free()
    for _, c in ipairs(self) do if c.free then c:free() end end
end
M.Stack = Stack

function M.vstack(children, gap, align)
    local s = Stack:new{ dir = "v", gap = gap or 0, align = align or "start" }
    for i, c in ipairs(children) do s[i] = c end
    return s
end

function M.hstack(children, gap, align)
    local s = Stack:new{ dir = "h", gap = gap or 0, align = align or "center" }
    for i, c in ipairs(children) do s[i] = c end
    return s
end

---------------------------------------------------------------- Box

-- Box{ w, h, bg = WHITE|BLACK|nil (transparent), border = 0, border_color = BLACK, dashed = false, radius = 0,
--      pad_x = 0, pad_y = 0, align = "left"|"center"|"right", valign = "top"|"center"|"bottom",
--      on_tap = fn, on_hold = fn, child }
local Box = Widget:extend{
    w = 0, h = 0, bg = nil, border = 0, border_color = BLACK, dashed = false, radius = 0,
    pad_x = 0, pad_y = 0, align = "left", valign = "top", on_tap = nil, on_hold = nil, child = nil,
}

function Box:init()
    self.w, self.h = math.max(0, math.floor(self.w)), math.max(0, math.floor(self.h))
    self.dimen = Geom:new{ x = 0, y = 0, w = self.w, h = self.h }
    self.painted = false
    self.layer = layer
    if hot and (self.on_tap or self.on_hold) then hot[#hot + 1] = self end
end

function Box:getSize() return Geom:new{ w = self.w, h = self.h } end

-- inner size available for the child
function Box:inner()
    local b = self.border or 0
    return self.w - 2 * (b + self.pad_x), self.h - 2 * (b + self.pad_y)
end

function Box:paintTo(bb, x, y)
    self.dimen.x, self.dimen.y = x, y
    self.painted = true
    local w, h, r, b = self.w, self.h, self.radius or 0, self.border or 0
    if self.bg then
        if r > 0 then bb:paintRoundedRect(x, y, w, h, self.bg, r) else bb:paintRect(x, y, w, h, self.bg) end
    end
    if b > 0 then
        if self.dashed then
            for _, s in ipairs(Shapes.dashed_border(w, h, b, T.DASH, T.DASH_GAP)) do
                bb:paintRect(x + s[2], y + s[1], s[3], 1, self.border_color)
            end
        else
            bb:paintBorder(x, y, w, h, b, self.border_color, r > 0 and r or nil)
        end
    end
    local c = self.child
    if c then
        local s = c:getSize()
        local iw, ih = self:inner()
        local ox, oy = x + b + self.pad_x, y + b + self.pad_y
        if self.align == "center" then ox = ox + math.floor((iw - s.w) / 2)
        elseif self.align == "right" then ox = ox + iw - s.w end
        if self.valign == "center" then oy = oy + math.floor((ih - s.h) / 2)
        elseif self.valign == "bottom" then oy = oy + ih - s.h end
        c:paintTo(bb, ox, oy)
    end
end

function Box:free()
    if self.child and self.child.free then self.child:free() end
end
M.Box = Box

function M.box(opts) return Box:new(opts) end

-- an invisible tap area of w x h around an optional child (centered)
function M.tap(w, h, child, on_tap, on_hold, align)
    return Box:new{ w = w, h = h, child = child, on_tap = on_tap, on_hold = on_hold,
        align = align or "center", valign = "center" }
end

---------------------------------------------------------------- Layers

-- Layers{ w, h, { widget = w, x = 0, y = 0 }, ... }
local Layers = Widget:extend{ w = 0, h = 0 }
function Layers:getSize() return Geom:new{ w = self.w, h = self.h } end
function Layers:paintTo(bb, x, y)
    for _, l in ipairs(self) do l.widget:paintTo(bb, x + (l.x or 0), y + (l.y or 0)) end
end
function Layers:free()
    for _, l in ipairs(self) do if l.widget.free then l.widget:free() end end
end
M.Layers = Layers

return M
