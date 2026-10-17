-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (C) 2026 Tinta contributors
-- Relógio app: the analog face as pixel spans (black only, no anti-alias: R-A3). Pure Lua over ui/shapes.from_pred.
-- The dial (ring and hour ticks) is cached per diameter; the hands are redrawn each minute. Spans are
-- { y, x, len } relative to the top-left corner of the d x d box, painted with ui.draw.Spans.
-- k (default 1 = the KT3) is the scale of the screen (ui/theme T.s): thicknesses and thresholds are design px x k.
local Shapes = require("ui/shapes")

local M = {}

local sqrt, sin, cos, atan2, pi, abs, floor = math.sqrt, math.sin, math.cos, math.atan2 or math.atan, math.pi, math.abs, math.floor

local function dial_pred(d, sc)
    local c, R = d / 2, d / 2 - sc
    local big = d >= 100 * sc
    local ring = (big and 3 or 2) * sc
    local major_len, minor_len = math.max(8 * sc, d * 0.13), math.max(5 * sc, d * 0.07)
    local with_minor = big
    return function(x, y)
        local dx, dy = x - c, y - c
        local r = sqrt(dx * dx + dy * dy)
        if r > R then return false end
        if r >= R - ring then return true end
        local ang = atan2(dx, -dy) * 180 / pi
        if ang < 0 then ang = ang + 360 end
        local k = floor(ang / 30 + 0.5)
        local delta = (ang - k * 30) * pi / 180
        local perp = r * abs(sin(delta))
        if cos(delta) <= 0 then return false end
        local major = k % 3 == 0
        if major then return r >= R - ring - major_len and perp <= (big and 2.2 or 1.6) * sc end
        return with_minor and r >= R - ring - minor_len and perp <= 1.2 * sc
    end
end

local cache = {}

-- ring and 12 ticks (longer and thicker at 12, 3, 6, 9) in a d x d box
function M.dial(d, k)
    k = k or 1
    local key = d .. "/" .. k
    local m = cache[key]
    if not m then m = Shapes.from_pred(d, d, dial_pred(d, k)); cache[key] = m end
    return m
end

-- distance from (px, py) to the segment (ax, ay)-(bx, by)
local function seg_dist(px, py, ax, ay, bx, by)
    local vx, vy = bx - ax, by - ay
    local len2 = vx * vx + vy * vy
    local t = len2 > 0 and ((px - ax) * vx + (py - ay) * vy) / len2 or 0
    if t < 0 then t = 0 elseif t > 1 then t = 1 end
    local qx, qy = ax + t * vx, ay + t * vy
    return sqrt((px - qx) ^ 2 + (py - qy) ^ 2)
end

-- the hands for angles { hour, min } (degrees from 12, clockwise: logic.hands) and the hub, in a d x d box
function M.hands(d, hands, k)
    k = k or 1
    local c, R = d / 2, d / 2 - k
    local function hand(deg, len, hw)
        local a = deg * pi / 180
        local ux, uy = sin(a), -cos(a)
        return { ax = c - ux * len * 0.12, ay = c - uy * len * 0.12, bx = c + ux * len, by = c + uy * len, hw = hw }
    end
    local h = hand(hands.hour, R * 0.5, math.max(2 * k, d * 0.022))
    local m = hand(hands.min, R * 0.8, math.max(1.5 * k, d * 0.014))
    local hub = math.max(3 * k, d * 0.035)
    return Shapes.from_pred(d, d, function(x, y)
        local dx, dy = x - c, y - c
        if dx * dx + dy * dy <= hub * hub then return true end
        if seg_dist(x, y, h.ax, h.ay, h.bx, h.by) <= h.hw then return true end
        return seg_dist(x, y, m.ax, m.ay, m.bx, m.by) <= m.hw
    end)
end

return M
