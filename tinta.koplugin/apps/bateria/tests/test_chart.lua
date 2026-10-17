-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (C) 2026 Tinta contributors
-- chart geometry: which samples, axis ranges, ticks, gaps, rasterized spans inside the box
local T = ...
local check, eq = T.check, T.eq
local Chart = require("apps/bateria/chart")
local function S(t, pct, chg) return { t = t, pct = pct, chg = chg or false } end

-- the prototype's data: 99 % at 11:17 to 78 % at 15:46 (UTC here)
local t0 = 11 * 3600 + 17 * 60
local data = {}
for i = 0, 21 do data[#data + 1] = S(t0 + math.floor(i * (4 * 3600 + 29 * 60) / 21), 99 - i) end

eq("recent: whole discharge", #Chart.recent(data), 22)
local plugged = { S(0, 50, true), S(600, 60, true) }
for _, s in ipairs(data) do plugged[#plugged + 1] = s end
eq("recent: only the latest run", #Chart.recent(plugged), 22)
local just_unplugged = { S(0, 50, true), S(600, 60, true), S(1200, 61, true), S(1300, 61, false) }
eq("recent: a single new sample takes the run before", #Chart.recent(just_unplugged), 4)
eq("recent: empty", #Chart.recent({}), 0)
local long = {}
for i = 0, 40 do long[#long + 1] = S(i * 3600, 100 - i) end
local rl = Chart.recent(long)
check("recent: at most 24 h", rl[#rl].t - rl[1].t <= Chart.SPAN, rl[#rl].t - rl[1].t)

local y0, y1 = Chart.y_range(78, 99)
eq("y range around 78..99", y0 .. ".." .. y1, "75..100")
eq("y range minimum width", table.concat({ Chart.y_range(50, 51) }, ".."), "45..55")
eq("y range at the top", table.concat({ Chart.y_range(99, 100) }, ".."), "90..100")
eq("y range at the bottom", table.concat({ Chart.y_range(0, 2) }, ".."), "0..10")
eq("y step 25 -> 10", Chart.y_step(25), 10)
eq("y step 10 -> 5", Chart.y_step(10), 5)
eq("y step 100 -> 25", Chart.y_step(100), 25)

local ticks, step = Chart.x_ticks(t0, t0 + 4 * 3600 + 29 * 60, 6, T.utc)
eq("x step 1 h", step, 3600)
eq("x ticks 12h..15h", ticks[1].label .. "," .. ticks[#ticks].label, "12h,15h")
eq("x ticks count", #ticks, 4)
local short = Chart.x_ticks(t0, t0 + 1800, 6, T.utc)
eq("x ticks short span: HH:MM", short[1].label, "11:30")
-- local time alignment: UTC-3 puts the ticks on local hours
local function utc_minus3(fmt, t)
    if fmt:sub(1, 1) == "!" then return os.date(fmt, t) end
    return os.date("!" .. fmt, t - 3 * 3600)
end
local lt = Chart.x_ticks(t0, t0 + 4 * 3600, 6, utc_minus3)
eq("x ticks in local time", lt[1].label, "9h")
eq("x ticks on the local hour", (lt[1].t - 3 * 3600) % 3600, 0)

local g = Chart.build(data, { w = 560, h = 210, left = 56, right = 10, top = 12, bottom = 30, date = T.utc })
check("build: chart", g ~= nil)
eq("build: plot", g.plot.x .. "," .. g.plot.y .. "," .. g.plot.w .. "," .. g.plot.h, "56,12,494,168")
eq("build: y labels", g.yticks[1].label .. " " .. g.yticks[2].label .. " " .. g.yticks[3].label, "80% 90% 100%")
eq("build: 100% at the top", g.yticks[3].y, 12)
eq("build: one line without gaps", #g.lines, 1)
eq("build: first point at the left", g.lines[1][1][1], 56)
eq("build: last point at the right", g.last[1], 56 + 494 - 1)
eq("build: from/to", g.from.pct .. "->" .. g.to.pct, "99->78")
local inside = true
for _, p in ipairs(g.lines[1]) do
    if p[1] < g.plot.x or p[1] >= g.plot.x + g.plot.w or p[2] < g.plot.y or p[2] >= g.plot.y + g.plot.h then inside = false end
end
check("build: points inside the plot", inside)
eq("build: fewer than 2 samples", Chart.build({ S(0, 50) }, { w = 100, h = 50 }), nil)
eq("build: box too small", Chart.build(data, { w = 20, h = 50, left = 15 }), nil)
-- a flat line over a short time still builds (minimum x and y ranges)
local flat = Chart.build({ S(0, 80), S(60, 80) }, { w = 200, h = 80 })
check("build: flat short line", flat and flat.t1 - flat.t0 == Chart.MIN_X and flat.y1 - flat.y0 >= 10)

-- a suspend gap breaks the line
local gapped = {}
for i = 0, 4 do gapped[#gapped + 1] = S(i * 600, 90 - i) end
for i = 0, 4 do gapped[#gapped + 1] = S(20000 + i * 600, 80 - i) end
local gg = Chart.build(gapped, { w = 300, h = 100 })
eq("gap: two lines", #gg.lines, 2)

-- spans stay inside the box and cover the line
local function bounded(spans, w, h)
    for _, s in ipairs(spans) do
        if s[1] < 0 or s[1] >= h or s[2] < 0 or s[3] < 1 or s[2] + s[3] > w then return false, table.concat(s, ",") end
    end
    return true
end
local sp = Chart.chart_spans(g, 560, 210)
check("spans: some", #sp > 100, #sp)
check("spans: inside the box", bounded(sp, 560, 210))
local row_has = function(spans, y, x)
    for _, s in ipairs(spans) do if s[1] == y and x >= s[2] and x < s[2] + s[3] then return true end end
    return false
end
check("spans: y axis painted", row_has(sp, 100, 55))
check("spans: x axis painted", row_has(sp, 12 + 168, 300))
check("spans: dot on the newest sample", row_has(sp, g.last[2], g.last[1]))
check("spans: line at the first point", row_has(sp, g.lines[1][1][2], g.lines[1][1][1]))
local sorted = true
for i = 2, #sp do
    if sp[i][1] < sp[i - 1][1] or (sp[i][1] == sp[i - 1][1] and sp[i][2] <= sp[i - 1][2] + sp[i - 1][3] - 1) then sorted = false end
end
check("spans: sorted and merged", sorted)
local gs = Chart.build(data, { w = 170, h = 56, left = 2, right = 2, top = 3, bottom = 4 })
local ss = Chart.spark_spans(gs, 170, 56)
check("spark: inside", bounded(ss, 170, 56))
check("spark: base line", row_has(ss, 55, 0) and row_has(ss, 55, 169))

-- canvas primitives
local cv = Chart.canvas(10, 10)
cv:line(0, 0, 9, 0, 1)
local s1 = cv:spans()
eq("canvas: horizontal line is one span", #s1 .. ":" .. s1[1][3], "1:10")
cv = Chart.canvas(10, 10)
cv:line(-5, -5, 20, 20, 3)
check("canvas: clipped", bounded(cv:spans(), 10, 10))
cv = Chart.canvas(20, 3)
cv:dotted_h(0, 19, 1, 2, 4)
eq("canvas: dotted", #cv:spans(), 4)
cv = Chart.canvas(20, 20)
cv:disc(10, 10, 6)
eq("canvas: disc rows", #cv:spans(), 13)

-- scaled strokes (spec 6.1): k = 1 is the KT3 byte for byte; at k = 2 the axes are 4 px, the line 8, the dot r 12
do
    local function same_spans(a, b)
        if #a ~= #b then return false end
        for i = 1, #a do if a[i][1] ~= b[i][1] or a[i][2] ~= b[i][2] or a[i][3] ~= b[i][3] then return false end end
        return true
    end
    check("chart_spans k=1 is the default", same_spans(Chart.chart_spans(g, 560, 210), Chart.chart_spans(g, 560, 210, 1)))
    check("spark_spans k=1 is the default", same_spans(Chart.spark_spans(gs, 170, 56), Chart.spark_spans(gs, 170, 56, 1)))
    local g2 = Chart.build(data, { w = 1120, h = 420, left = 112, right = 20, top = 24, bottom = 60, date = T.utc, k = 2 })
    check("build at k=2 works", g2 ~= nil and g2.plot.w == 1120 - 132)
    local sp2 = Chart.chart_spans(g2, 1120, 420, 2)
    check("k=2 spans inside the box", bounded(sp2, 1120, 420))
    local y_axis = 0
    for _, s in ipairs(sp2) do if s[1] == 200 and s[2] == g2.plot.x - 4 then y_axis = s[3] end end
    check("k=2: the y axis is 4 px wide", y_axis >= 4, y_axis)
    eq("k=2 disc rows", (function() local c = Chart.canvas(40, 40); c:disc(20, 20, 12); return #c:spans() end)(), 25)
    check("min plot scales with k", Chart.build(data, { w = 30, h = 30, k = 4 }) == nil and Chart.build(data, { w = 30, h = 30 }) ~= nil)
end
