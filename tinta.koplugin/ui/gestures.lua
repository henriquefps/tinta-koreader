-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (C) 2026 Tinta contributors
-- Tinta: gesture zones (R-N3), pure. Turns a KOReader swipe (start point, end point) into a Tinta action,
-- and holds the timing rules of the long press on a widget.
local T = require("ui/theme")

local M = {}

-- KOReader swipe directions -> unit vector (used when the event has no end point)
local DIR = {
    north = { 0, -1 }, south = { 0, 1 }, east = { 1, 0 }, west = { -1, 0 },
    northeast = { 0.7071, -0.7071 }, northwest = { -0.7071, -0.7071 },
    southeast = { 0.7071, 0.7071 }, southwest = { -0.7071, 0.7071 },
}

-- Displacement of a swipe: from end_pos when present, else from direction and distance.
function M.delta(ev)
    if ev.x1 and ev.y1 then return ev.x1 - ev.x0, ev.y1 - ev.y0 end
    local d = DIR[ev.direction or ""]
    if not d then return 0, 0 end
    local dist = ev.distance or 0
    return d[1] * dist, d[2] * dist
end

-- ev = { x0, y0, x1?, y1?, direction?, distance? }; screen = { W, H, home = bool }.
-- Returns "home" | "back" | "central" | "page_next" | "page_prev" | nil. Edges are tested first
-- (bottom, left, top); the page swipe only counts outside the edge zones and on the home screen.
function M.classify(ev, screen)
    if not ev or not ev.x0 or not ev.y0 then return nil end
    local dx, dy = M.delta(ev)
    local W, H = screen.W, screen.H
    local x0, y0 = ev.x0, ev.y0
    local in_bottom = y0 >= H - T.EDGE_BOTTOM
    local in_left = x0 <= T.EDGE_LEFT
    local in_top = y0 <= T.EDGE_TOP
    if in_bottom and -dy > T.SWIPE_MIN and -dy >= math.abs(dx) then return "home" end
    if in_left and dx > T.SWIPE_MIN and dx >= math.abs(dy) then return "back" end
    if in_top and dy > T.SWIPE_MIN and dy >= math.abs(dx) then return "central" end
    if screen.home and not in_bottom and not in_left and not in_top
        and math.abs(dx) > T.SWIPE_MIN and math.abs(dy) < T.SWIPE_MAX_CROSS then
        return dx < 0 and "page_next" or "page_prev"
    end
    return nil
end

-- KOReader already waited `hold_interval_ms` before sending "hold"; the Tinta waits the rest of HOLD_MS.
function M.hold_delay_ms(hold_interval_ms)
    return math.max(0, T.HOLD_MS - (hold_interval_ms or 0))
end

-- true when the finger moved too far from where the hold started (cancel the organizer)
function M.hold_moved(x0, y0, x, y)
    if not (x0 and y0 and x and y) then return false end
    return math.abs(x - x0) > T.HOLD_SLOP or math.abs(y - y0) > T.HOLD_SLOP
end

return M
