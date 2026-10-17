-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (C) 2026 Tinta contributors
-- Bateria app: geometry of the discharge chart (10.3, the prototype's batteryChart and sparkline). Pure: it
-- turns log samples into pixel positions (axes, ticks, labels) and the polyline into spans { row, x, width },
-- the format ui/draw's Spans widget paints. Black only (R-A3): grid lines are dotted, not grey.
local Logic = require("apps/bateria/logic")

local M = {}

M.SPAN = 24 * 3600      -- s: the chart shows at most the last 24 h of the stretch
M.MIN_X = 600           -- s: smallest time range on the x axis
M.MIN_Y = 10            -- %: smallest range on the y axis
M.STEPS = { 900, 1800, 3600, 7200, 10800, 21600, 43200, 86400 }
M.MAX_XTICKS = 6

-- The samples to draw: the latest run of samples with the charging state of the newest one (suspend gaps do not
-- end it; they break the line), at most SPAN long. When that run has a single sample, the run before it joins,
-- so a freshly plugged or unplugged device still shows the recent discharge.
function M.recent(samples)
    local n = #(samples or {})
    if n == 0 then return {} end
    local chg = samples[n].chg
    local i = n
    while i > 1 and samples[i - 1].chg == chg and samples[i - 1].t <= samples[i].t do i = i - 1 end
    if i == n and n > 1 then
        local c2 = samples[n - 1].chg
        i = n - 1
        while i > 1 and samples[i - 1].chg == c2 and samples[i - 1].t <= samples[i].t do i = i - 1 end
    end
    local last_t = samples[n].t
    local out = {}
    for k = i, n do
        if samples[k].t >= last_t - M.SPAN then out[#out + 1] = samples[k] end
    end
    return out
end

-- y range: multiples of 5 around the data, at least MIN_Y wide, inside 0..100
function M.y_range(pmin, pmax)
    local y0 = math.max(0, math.floor((pmin - 1) / 5) * 5)
    local y1 = math.min(100, math.ceil((pmax + 1) / 5) * 5)
    while y1 - y0 < M.MIN_Y do
        if y0 > 0 then y0 = math.max(0, y0 - 5) else y1 = math.min(100, y1 + 5) end
        if y0 == 0 and y1 == 100 then break end
    end
    return y0, y1
end

function M.y_step(range)
    if range <= 15 then return 5 end
    if range <= 50 then return 10 end
    return 25
end

-- seconds east of UTC at t for `date` (os.date signature)
local function utc_offset(date, t)
    local l = date("*t", t)
    local u = date("!*t", t)
    local function secs(d) return d.hour * 3600 + d.min * 60 + d.sec end
    local off = (secs(l) - secs(u)) % 86400      -- time zones go from -12 h to +14 h
    if off > 14 * 3600 then off = off - 86400 end
    return off
end

-- time ticks between t0 and t1 at local-time multiples of the step: { { t, label } }
function M.x_ticks(t0, t1, max_ticks, date)
    date = date or os.date
    max_ticks = max_ticks or M.MAX_XTICKS
    local step = M.STEPS[#M.STEPS]
    for _, s in ipairs(M.STEPS) do
        if (t1 - t0) / s <= max_ticks then step = s; break end
    end
    local off = utc_offset(date, t0)
    local first = math.ceil((t0 + off) / step) * step - off
    local out = {}
    for t = first, t1, step do
        local label = step % 3600 == 0 and (date("%H", t):gsub("^0", "") .. "h") or date("%H:%M", t)
        out[#out + 1] = { t = t, label = label }
    end
    return out, step
end

-- opts = { w, h, left, right, top, bottom, date, max_xticks, k }, k = scale of the 600x800 design (default 1). Returns nil when there are fewer than 2 samples,
-- else { plot = { x, y, w, h }, y0, y1, t0, t1, yticks = { { y, label, pct } }, xticks = { { x, label } },
--        lines = { { {x, y}, ... }, ... } (one per gap-free run), last = { x, y }, from, to (samples) }
function M.build(samples, opts)
    opts = opts or {}
    local pts = M.recent(samples)
    if #pts < 2 then return nil end
    local W, H = opts.w, opts.h
    local L, R, T, B = opts.left or 0, opts.right or 0, opts.top or 0, opts.bottom or 0
    local pw, ph = W - L - R, H - T - B
    local min_plot = math.max(1, math.floor(10 * (opts.k or 1) + 0.5))   -- opts.k: scale of the screen (ui/theme T.s)
    if pw < min_plot or ph < min_plot then return nil end
    local pmin, pmax = 100, 0
    for _, s in ipairs(pts) do pmin, pmax = math.min(pmin, s.pct), math.max(pmax, s.pct) end
    local y0, y1 = M.y_range(pmin, pmax)
    local t0, t1 = pts[1].t, pts[#pts].t
    if t1 - t0 < M.MIN_X then t1 = t0 + M.MIN_X end
    local function X(t) return L + math.floor((t - t0) / (t1 - t0) * (pw - 1) + 0.5) end
    local function Y(p) return T + math.floor((y1 - p) / (y1 - y0) * (ph - 1) + 0.5) end
    local out = { plot = { x = L, y = T, w = pw, h = ph }, y0 = y0, y1 = y1, t0 = t0, t1 = t1,
        yticks = {}, xticks = {}, lines = {}, from = pts[1], to = pts[#pts] }
    local step = M.y_step(y1 - y0)
    for p = math.ceil(y0 / step) * step, y1, step do
        out.yticks[#out.yticks + 1] = { y = Y(p), label = p .. "%", pct = p }
    end
    for _, tk in ipairs((M.x_ticks(t0, t1, opts.max_xticks, opts.date))) do
        out.xticks[#out.xticks + 1] = { x = X(tk.t), label = tk.label, t = tk.t }
    end
    local cur
    for i, s in ipairs(pts) do
        if i == 1 or s.t - pts[i - 1].t > Logic.GAP_MAX then
            cur = {}
            out.lines[#out.lines + 1] = cur
        end
        cur[#cur + 1] = { X(s.t), Y(s.pct) }
    end
    out.last = { X(pts[#pts].t), Y(pts[#pts].pct) }
    return out
end

---------------------------------------------------------------- rasterizing into spans

-- a set of painted pixels, kept as rows of columns; spans() merges them into horizontal runs
local Canvas = {}
Canvas.__index = Canvas

function M.canvas(w, h) return setmetatable({ w = w, h = h, rows = {} }, Canvas) end

function Canvas:dot(x, y)
    if x < 0 or y < 0 or x >= self.w or y >= self.h then return end
    local row = self.rows[y]
    if not row then row = {}; self.rows[y] = row end
    row[x] = true
end

function Canvas:rect(x, y, w, h)
    for yy = y, y + h - 1 do for xx = x, x + w - 1 do self:dot(xx, yy) end end
end

-- line of thickness `th` (a th x th square stamped at each step along the major axis)
function Canvas:line(x0, y0, x1, y1, th)
    th = th or 1
    local half = math.floor((th - 1) / 2)
    local dx, dy = x1 - x0, y1 - y0
    local n = math.max(math.abs(dx), math.abs(dy))
    for i = 0, n do
        local x = n == 0 and x0 or math.floor(x0 + dx * i / n + 0.5)
        local y = n == 0 and y0 or math.floor(y0 + dy * i / n + 0.5)
        self:rect(x - half, y - half, th, th)
    end
end

function Canvas:polyline(pts, th)
    if #pts == 1 then self:line(pts[1][1], pts[1][2], pts[1][1], pts[1][2], th) end
    for i = 2, #pts do self:line(pts[i - 1][1], pts[i - 1][2], pts[i][1], pts[i][2], th) end
end

-- dotted horizontal line: `on` px painted, `off` px skipped
function Canvas:dotted_h(x0, x1, y, on, off)
    on, off = on or 2, off or 4
    local x = x0
    while x <= x1 do
        self:rect(x, y, math.min(on, x1 - x + 1), 1)
        x = x + on + off
    end
end

function Canvas:disc(cx, cy, r)
    for yy = -r, r do
        local half = math.floor(math.sqrt(r * r - yy * yy) + 0.5)
        self:rect(cx - half, cy + yy, 2 * half + 1, 1)
    end
end

-- { { row, x, width }, ... } sorted by row then x
function Canvas:spans()
    local out = {}
    local ys = {}
    for y in pairs(self.rows) do ys[#ys + 1] = y end
    table.sort(ys)
    for _, y in ipairs(ys) do
        local xs = {}
        for x in pairs(self.rows[y]) do xs[#xs + 1] = x end
        table.sort(xs)
        local start, prev = xs[1], xs[1]
        for i = 2, #xs + 1 do
            local x = xs[i]
            if x ~= prev + 1 then
                out[#out + 1] = { y, start, prev - start + 1 }
                start = x
            end
            prev = x
        end
    end
    return out
end

-- Spans of the full chart (screen): dotted grid at the y ticks, both axes (2 px), the line (4 px) and a dot on
-- the newest sample. Labels are not included (the view draws them as text at yticks / xticks).
-- k scales the strokes (2 px axes, 4 px line, dotted 2/4, dot of radius 6) with the screen; default 1 = the KT3.
function M.chart_spans(g, w, h, k)
    local function px(n) return math.max(1, math.floor(n * (k or 1) + 0.5)) end
    local cv = M.canvas(w, h)
    local p = g.plot
    local ax = px(2)
    for _, tk in ipairs(g.yticks) do cv:dotted_h(p.x, p.x + p.w - 1, tk.y, px(2), px(4)) end
    cv:rect(p.x - ax, p.y, ax, p.h + ax)               -- y axis, left of the plot
    cv:rect(p.x - ax, p.y + p.h, p.w + ax, ax)         -- x axis, below the plot
    for _, line in ipairs(g.lines) do cv:polyline(line, px(4)) end
    cv:disc(g.last[1], g.last[2], px(6))
    return cv:spans()
end

-- Spans of the small chart (4x2 widget): the line (3 px) and a base line (2 px)
function M.spark_spans(g, w, h, k)
    local function px(n) return math.max(1, math.floor(n * (k or 1) + 0.5)) end
    local cv = M.canvas(w, h)
    for _, line in ipairs(g.lines) do cv:polyline(line, px(3)) end
    cv:rect(0, h - px(2), w, px(2))
    return cv:spans()
end

return M
