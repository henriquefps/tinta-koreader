-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (C) 2026 Tinta contributors
-- the analog face: spans stay inside the box, the dial has its ticks, the hands point where the angles say
local T = ...
local check, eq = T.check, T.eq
local Face = require("apps/relogio/face")
local Logic = require("apps/relogio/logic")

local function grid(d, spans)
    local g = {}
    for y = 0, d - 1 do g[y] = {} end
    for _, s in ipairs(spans) do
        for x = s[2], s[2] + s[3] - 1 do g[s[1]][x] = true end
    end
    return g
end
local function inside(d, spans)
    for _, s in ipairs(spans) do
        if s[1] < 0 or s[1] >= d or s[2] < 0 or s[2] + s[3] > d or s[3] <= 0 then return false end
    end
    return true
end
local function on(g, d, dx, dy) return g[math.floor(d / 2 + dy)][math.floor(d / 2 + dx)] == true end

for _, d in ipairs({ 40, 76, 114, 164, 260 }) do
    local dial = Face.dial(d)
    check("dial " .. d .. ": has spans, inside the box", #dial > 0 and inside(d, dial))
    check("dial " .. d .. ": cached", Face.dial(d) == dial)
    local g = grid(d, dial)
    local R = d / 2 - 2
    check("dial " .. d .. ": ring at 12, 3, 6 and 9", on(g, d, 0, -R) and on(g, d, R, 0) and on(g, d, 0, R) and on(g, d, -R, 0))
    check("dial " .. d .. ": centre is empty", not on(g, d, 0, 0))
    check("dial " .. d .. ": outside the ring is empty", not g[0][0] and not g[d - 1][d - 1])
    local tick_at = math.floor(d / 2 - R * 0.9)
    check("dial " .. d .. ": 12 o'clock tick inside the ring", on(g, d, 0, -(d / 2 - 1 - (d >= 100 and 3 or 2) - 4)))
    for _, hd in ipairs({ { 0, 0 }, { 3, 0 }, { 6, 0 }, { 9, 0 }, { 12, 30 }, { 10, 10 }, { 23, 59 } }) do
        local hs = Face.hands(d, Logic.hands(hd[1], hd[2]))
        check(("hands %d at %d:%02d: inside the box"):format(d, hd[1], hd[2]), #hs > 0 and inside(d, hs))
    end
end

-- 3:00 on a 164 box: hour hand to the right, minute hand up, nothing to the left or below
local d = 164
local g = grid(d, Face.hands(d, Logic.hands(3, 0)))
check("3:00 hour hand points right", on(g, d, 20, 0) and on(g, d, 35, 0))
check("3:00 minute hand points up", on(g, d, 0, -30) and on(g, d, 0, -60))
check("3:00 nothing to the left", not on(g, d, -35, 0))
check("3:00 nothing straight down", not on(g, d, 0, 50))
check("hub is drawn", on(g, d, 0, 0))
-- 6:30: hour hand down (a little left of vertical), minute hand down
local g2 = grid(d, Face.hands(d, Logic.hands(6, 30)))
check("6:30 hands point down", on(g2, d, 0, 30) and on(g2, d, 0, 55))
check("6:30 nothing straight up", not on(g2, d, 0, -40))
-- the minute hand is longer than the hour hand
local g3 = grid(d, Face.hands(d, Logic.hands(12, 0)))
local g4 = grid(d, Face.hands(d, Logic.hands(3, 0)))
check("minute hand (up) is longer than the hour hand (right)", on(g3, d, 0, -60) and not on(g4, d, 60, 0))
-- the hands differ from minute to minute
local a, b = Face.hands(d, Logic.hands(10, 10)), Face.hands(d, Logic.hands(10, 11))
local same = #a == #b
if same then for i = 1, #a do if a[i][1] ~= b[i][1] or a[i][2] ~= b[i][2] or a[i][3] ~= b[i][3] then same = false; break end end end
check("a minute later the hands moved", not same)

-- scaled dial and hands (spec 6.1): k = 1 is the KT3; at k = 2 on a doubled box the ring and the hands are twice as thick
do
    local function count(spans) local n = 0; for _, s in ipairs(spans) do n = n + s[3] end return n end
    check("dial k=1 is the default and cached", Face.dial(164, 1) == Face.dial(164))
    local d1, d2 = Face.dial(164, 1), Face.dial(328, 2)
    check("dial k=2 inside its box", inside(328, d2))
    local ratio = count(d2) / count(d1)
    check("dial k=2 has about 4x the pixels", ratio > 3.5 and ratio < 4.5, ratio)
    local h1, h2 = Face.hands(164, Logic.hands(10, 10), 1), Face.hands(328, Logic.hands(10, 10), 2)
    check("hands k=2 inside their box", inside(328, h2))
    local hr = count(h2) / count(h1)
    check("hands k=2 have about 4x the pixels", hr > 3.3 and hr < 4.7, hr)
    -- the ring thickness at 12 o'clock: 3 px at d >= 100 (KT3), 6 px at k = 2
    local function ring_at_top(spans, d)
        local g = grid(d, spans); local n = 0
        for y = 0, d / 2 do if g[y][d / 2] then n = n + 1 else break end end
        return n
    end
    check("ring thickness doubles", ring_at_top(d2, 328) >= 2 * ring_at_top(d1, 164) - 1)
end
