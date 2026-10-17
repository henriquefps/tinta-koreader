-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (C) 2026 Tinta contributors
-- Tinta: pixel masks of the drawn icons (Wi-Fi arcs, bell, gear, house, menu), pure.
-- A mask is a list of horizontal spans { y, x, len } relative to the icon's top-left corner, painted with
-- paintRect(x0 + x, y0 + y, len, 1). Black only (R-A3). Masks are cached per parameter set.
-- Sizes are the icon's w x h in px; k (default 1 = the KT3 design) is the scale of the strokes and offsets inside.
local M = {}

local floor, sqrt, atan2 = math.floor, math.sqrt, math.atan2 or math.atan

local cache = {}
local function cached(key, build)
    local m = cache[key]
    if not m then m = build(); cache[key] = m end
    return m
end

-- spans from a predicate inside a w x h box (pixel centers)
local function from_pred(w, h, pred)
    local spans = {}
    for y = 0, h - 1 do
        local start
        for x = 0, w do
            local on = x < w and pred(x + 0.5, y + 0.5)
            if on and not start then start = x
            elseif not on and start then
                spans[#spans + 1] = { y, start, x - start }
                start = nil
            end
        end
    end
    return spans
end
M.from_pred = from_pred

-- Wi-Fi icon w x h: three concentric arcs (90°, opening up) around the bottom center and a dot.
-- state "on": solid arcs + dot; "connecting": dashed arcs, no dot; "off": solid arcs, no dot, struck through.
function M.wifi(w, h, state, k)
    k = k or 1
    return cached("wifi" .. w .. "x" .. h .. state .. "/" .. k, function()
        local cx, cy = w / 2, h - 2 * k
        local stroke = 3 * k
        local radii = { h - 3 * k, (h - 3 * k) * 0.66, (h - 3 * k) * 0.33 }
        local dot_r = 2.2 * k
        return from_pred(w, h, function(x, y)
            local dx, dy = x - cx, y - cy
            local r = sqrt(dx * dx + dy * dy)
            if state == "on" and r <= dot_r then return true end
            if dy > -k then return false end
            local ang = atan2(dx, -dy)   -- 0 straight up, +/- to the sides
            if math.abs(ang) > 0.80 then
                -- strike: diagonal line from top-left to bottom-right
                if state == "off" then return math.abs((y - k) - (x - 2 * k) * (h - 2 * k) / (w - 4 * k)) < 1.8 * k end
                return false
            end
            for _, ra in ipairs(radii) do
                if math.abs(r - ra) <= stroke / 2 then
                    if state == "connecting" and floor((ang + 1) / 0.32) % 2 == 1 then return false end
                    return true
                end
            end
            if state == "off" then return math.abs((y - k) - (x - 2 * k) * (h - 2 * k) / (w - 4 * k)) < 1.8 * k end
            return false
        end)
    end)
end

-- bell w x h: dome (half disc ring), body, rim and clapper
function M.bell(w, h, k)
    k = k or 1
    return cached("bell" .. w .. "x" .. h .. "/" .. k, function()
        local cx = w / 2
        local rim_y = h * 0.76
        local dome_cy = h * 0.42
        local r_out = w * 0.33
        local stroke = math.max(2 * k, floor(w / 10))
        return from_pred(w, h, function(x, y)
            local dx = x - cx
            -- rim
            if y >= rim_y and y < rim_y + stroke and math.abs(dx) <= w * 0.46 then return true end
            -- clapper
            if y >= rim_y + stroke + k and y < h - 0.5 * k and math.abs(dx) <= w * 0.12 then return true end
            if y < rim_y then
                if y <= dome_cy then
                    local dy = y - dome_cy
                    local r = sqrt(dx * dx + dy * dy)
                    return r <= r_out and r >= r_out - stroke
                end
                -- walls widen a little toward the rim
                local t = (y - dome_cy) / (rim_y - dome_cy)
                local half = r_out + t * w * 0.08
                return math.abs(dx) <= half and math.abs(dx) >= half - stroke
            end
            return false
        end)
    end)
end

-- gear d x d: ring with 8 teeth and a hole
function M.gear(d)
    return cached("gear" .. d, function()
        local c = d / 2
        local r_body, r_teeth, r_hole = d * 0.36, d * 0.5, d * 0.16
        return from_pred(d, d, function(x, y)
            local dx, dy = x - c, y - c
            local r = sqrt(dx * dx + dy * dy)
            if r < r_hole then return false end
            if r <= r_body then return true end
            if r > r_teeth then return false end
            local a = (atan2(dy, dx) + math.pi) / (2 * math.pi) * 8
            local f = a - floor(a)
            return f > 0.3 and f < 0.7
        end)
    end)
end

-- house w x h (navigation "Início"): roof outline and walls with a door gap
function M.house(w, h, k)
    k = k or 1
    return cached("house" .. w .. "x" .. h .. "/" .. k, function()
        local s = 3 * k
        local roof_h = h * 0.45
        local cx = w / 2
        return from_pred(w, h, function(x, y)
            if y < roof_h then
                -- two slanted strokes from the apex
                local half = (y / roof_h) * (w / 2)
                local d = math.abs(math.abs(x - cx) - half)
                return d <= s * 0.8
            end
            local left, right = w * 0.16, w * 0.84
            if y >= h - s then return x >= left and x <= right and math.abs(x - cx) > w * 0.12 end
            if x >= left and x < left + s then return true end
            if x <= right and x > right - s then return true end
            return false
        end)
    end)
end

-- three bars w x h (navigation "Menu")
function M.bars(w, h, k)
    k = k or 1
    return cached("bars" .. w .. "x" .. h .. "/" .. k, function()
        local s = math.max(1, floor(3 * k + 0.5))
        local ys = { floor(k + 0.5), floor(h / 2) - floor(k + 0.5), h - s - floor(k + 0.5) }
        return from_pred(w, h, function(_, y)
            for _, y0 in ipairs(ys) do if y >= y0 and y < y0 + s then return true end end
            return false
        end)
    end)
end

-- dashed rectangle border (R-S5): spans for a w x h frame of thickness bw, dash and gap lengths in px
function M.dashed_border(w, h, bw, dash, gap)
    return cached(("dash%dx%d/%d/%d/%d"):format(w, h, bw, dash, gap), function()
        local spans = {}
        local period = dash + gap
        -- top and bottom: horizontal dashes
        for x = 0, w - 1, period do
            local len = math.min(dash, w - x)
            for k = 0, bw - 1 do
                spans[#spans + 1] = { k, x, len }
                spans[#spans + 1] = { h - 1 - k, x, len }
            end
        end
        -- left and right: vertical dashes as 1-row spans
        for y0 = 0, h - 1, period do
            for y = y0, math.min(h - 1, y0 + dash - 1) do
                if y >= bw and y < h - bw then
                    spans[#spans + 1] = { y, 0, bw }
                    spans[#spans + 1] = { y, w - bw, bw }
                end
            end
        end
        return spans
    end)
end

-- bounding check helper for tests
function M.bounds(spans)
    local minx, miny, maxx, maxy = math.huge, math.huge, -math.huge, -math.huge
    for _, s in ipairs(spans) do
        if s[2] < minx then minx = s[2] end
        if s[1] < miny then miny = s[1] end
        if s[2] + s[3] - 1 > maxx then maxx = s[2] + s[3] - 1 end
        if s[1] > maxy then maxy = s[1] end
    end
    return minx, miny, maxx, maxy
end

return M
