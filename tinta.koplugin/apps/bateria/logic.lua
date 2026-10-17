-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (C) 2026 Tinta contributors
-- Bateria app: pure logic (R-A1: no KOReader modules, no core/ either; clock, readings and the translator come in
-- by parameter). Ported from the standalone plugin this app replaces and adapted:
--
-- * Log lines: "unix_time,percent,charging,wifi,mv,ma,mah,temp_c", one per change of percentage or charging state
--   plus a heartbeat every 10 min (10.3). Older lines with only the first four columns still parse.
-- * Estimate: least squares over the current stretch of samples (same charging state, no suspend gap); with too
--   little data, the latest earlier stretch of the same kind calibrates ("saved"). D3: when the gauge exposes
--   charge_now (mAh), the slope is fitted on mAh instead of % (1 mAh steps instead of 1 % = ~9 mAh, and charge
--   is linear where the percentage is not). R-L4: a %-based calibration only comes from a stretch in the same
--   band of the battery (the percentage falls faster below ~65 %); mAh-based ones do not need that.
-- * Notification rules of 8.6 (below 20 % once per discharge, 100 % once per charge).
-- * Texts for the screen, the widgets and the status bar (R-S1), through a translator L(key, ...).
local M = {}

M.HEARTBEAT = 600       -- s: write a line even when nothing changed (keeps stretches gap-free while open)
M.GAP_MAX = 1500        -- s: a larger hole between samples means the device slept; it splits stretches
M.MAX_SAMPLES = 600     -- samples kept in memory for the estimate and the chart
M.WINDOW = 5400         -- s: only the last 90 min of a stretch feed the slope
M.MIN_SPAN = 900        -- s of data needed before the first estimate
M.MIN_DROP = 3          -- % lost (discharging) needed before the first %-based estimate
M.MIN_RISE = 2          -- % gained (charging) needed before the first %-based estimate
M.MIN_MOVE_MAH = 8      -- mAh moved (~1 %) needed before the first mAh-based estimate (D3)
M.MAX_ETA = 99 * 3600   -- s: beyond this the estimate means nothing
M.CAPACITY = 907        -- mAh: measured full charge of the KT3, when the gauge does not report charge_full
M.BAND_SPLIT = 65       -- % (R-L4): "high" band at or above, "low" band below
M.LOW = 20              -- % (8.6): low-battery notification threshold
M.REPLUG_JUMP = 3       -- %: a rise this big between two discharging readings means it charged in between

M.HEADER = "# unix_time,percent,charging,wifi,mv,ma,mah,temp_c,ev"

-- 9th column `ev` (appended; absent = a normal sample): why the sample was written outside the 1-min rhythm.
-- sleep and sched are the last sample before a suspend (sleep entry; end of a scheduled wake-up), so the hole
-- after them is a suspend stretch, not awake drain; button is the first sample after the power button woke it.
M.EV = { sleep = 1, sched = 2, button = 3 }
local function before_suspend(s) return s ~= nil and (s.ev == M.EV.sleep or s.ev == M.EV.sched) end

---------------------------------------------------------------- log lines

local function field(v)
    v = tonumber(v)
    if not v or v ~= v or v == math.huge or v == -math.huge then return "" end
    return string.format("%d", math.floor(v + 0.5))
end

-- extra: optional { mv, ma, mah, temp } gauge readings; ev: optional M.EV value (needs the 4 gauge columns, empty
-- when unknown)
function M.format_line(t, pct, charging, wifi, extra, ev)
    local line = string.format("%d,%d,%d,%d", t, pct, charging and 1 or 0, wifi and 1 or 0)
    if not extra and not ev then return line end
    extra = extra or {}
    line = line .. string.format(",%s,%s,%s,%s", field(extra.mv), field(extra.ma), field(extra.mah), field(extra.temp))
    if ev then line = line .. string.format(",%d", ev) end
    return line
end

-- "t,pct,c,w[,mv,ma,mah,temp[,ev]]" -> { t, pct, chg, wifi, mv, ma, mah, temp, ev }; nil for the header, blank or damaged lines
function M.parse_line(line)
    local t, p, c, w, rest = tostring(line):match("^(%d+),(%d+),([01]),([01])(.*)$")
    if not t then return nil end
    local pct = tonumber(p)
    if pct > 100 then return nil end
    local s = { t = tonumber(t), pct = pct, chg = c == "1", wifi = w == "1" }
    if rest ~= "" then
        local a, b, m, d, e = rest:match("^,(%-?%d*),(%-?%d*),(%-?%d*),(%-?%d*),?(%d*)$")
        if not a then return nil end
        s.mv, s.ma, s.mah, s.temp, s.ev = tonumber(a), tonumber(b), tonumber(m), tonumber(d), tonumber(e)
    end
    return s
end

-- last: the previous sample or nil
function M.should_log(last, now, pct, charging)
    if not last then return true end
    if now < last.t then return true end            -- the clock went back: start over
    if pct ~= last.pct or charging ~= last.chg then return true end
    return now - last.t >= M.HEARTBEAT
end

---------------------------------------------------------------- stretches and slopes

-- consecutive samples with the same charging state and no suspend gap (a hole over GAP_MAX, or a sample marked as
-- the last one before a suspend: wake-ups every 15 min leave holes smaller than GAP_MAX)
function M.segments(samples)
    local segs, cur = {}, nil
    for _, s in ipairs(samples) do
        local prev = cur and cur[#cur]
        if not prev or s.chg ~= prev.chg or s.t < prev.t or s.t - prev.t > M.GAP_MAX or before_suspend(prev) then
            cur = {}
            segs[#segs + 1] = cur
        end
        cur[#cur + 1] = s
    end
    return segs
end

-- least-squares slope of s[key] over time, in units per second, over the last WINDOW s of the stretch.
-- nil when the stretch is too short, moved too little, or went the wrong way for its charging state.
local function fit(seg, key, min_move_chg, min_move_dis)
    local last = seg[#seg]
    if not last then return nil end
    local pts = {}
    for _, s in ipairs(seg) do
        if s.t >= last.t - M.WINDOW and tonumber(s[key]) then pts[#pts + 1] = s end
    end
    if #pts < 2 then return nil end
    local first, final = pts[1], pts[#pts]
    if final.t - first.t < M.MIN_SPAN then return nil end
    local chg = last.chg
    local moved = chg and (final[key] - first[key]) or (first[key] - final[key])
    if moved < (chg and min_move_chg or min_move_dis) then return nil end
    local n, st, sv, stt, stv = #pts, 0, 0, 0, 0
    for _, s in ipairs(pts) do
        local x = s.t - first.t
        st, sv, stt, stv = st + x, sv + s[key], stt + x * x, stv + x * s[key]
    end
    local den = n * stt - st * st
    if den == 0 then return nil end
    local slope = (n * stv - st * sv) / den
    if chg and slope <= 0 or not chg and slope >= 0 then return nil end
    return slope
end

-- slope in %/s of one stretch (negative while discharging, positive while charging), or nil
function M.rate(seg) return fit(seg, "pct", M.MIN_RISE, M.MIN_DROP) end

-- slope in mAh/s of one stretch from the gauge's charge counter (D3), or nil
function M.rate_mah(seg) return fit(seg, "mah", M.MIN_MOVE_MAH, M.MIN_MOVE_MAH) end

-- R-L4: "high" at or above BAND_SPLIT %, "low" below
function M.band(pct) return (tonumber(pct) or 0) >= M.BAND_SPLIT and "high" or "low" end

-- whether a stretch spent its last part in `band` (its newest sample decides)
local function in_band(seg, band) return M.band(seg[#seg].pct) == band end

-- The rate to use: from the current stretch ("live") or the latest earlier one of the same kind ("saved").
-- rate_fn(seg) -> slope | nil; same_band: only earlier stretches in the band of `pct` count (R-L4).
local function pick_rate(segs, now, pct, charging, rate_fn, same_band)
    local n = #segs
    local cur = segs[n]
    if cur and cur[#cur].chg == charging and now >= cur[#cur].t and now - cur[#cur].t <= M.GAP_MAX
        and not before_suspend(cur[#cur]) then
        local r = rate_fn(cur)
        if r then return r, "live" end
        n = n - 1
    end
    local band = M.band(pct)
    for i = n, 1, -1 do
        local seg = segs[i]
        if seg[1].chg == charging and (not same_band or in_band(seg, band)) then
            local r = rate_fn(seg)
            if r then return r, "saved" end
        end
    end
    return nil
end

local function sane(secs)
    if not secs or secs ~= secs or secs <= 0 or secs > M.MAX_ETA then return nil end
    return secs
end

-- Seconds left (to empty while discharging, to 100 % while charging), or nil when there is not enough data.
-- Returns secs, kind ("live" | "saved"), basis ("mah" | "pct"), current in mA (the fitted slope; negative while
-- discharging). gauge = { mah = charge now, full = charge_full } (optional): with mah, the mAh slope is tried
-- first (D3) and the % slope is the fallback.
function M.estimate(samples, now, pct, charging, gauge)
    charging = charging == true
    pct = tonumber(pct)
    if not pct then return nil end
    if charging and pct >= 100 then return nil end
    if not charging and pct <= 0 then return nil end
    local segs = M.segments(samples or {})
    local mah = gauge and tonumber(gauge.mah)
    if mah then
        local rate, kind = pick_rate(segs, now, pct, charging, M.rate_mah, false)
        if rate then
            local full = gauge and tonumber(gauge.full) or M.CAPACITY
            local left = charging and math.max(0, full - mah) or mah
            local secs = sane(left / math.abs(rate))
            if secs then return secs, kind, "mah", rate * 3600 end
        end
    end
    local rate, kind = pick_rate(segs, now, pct, charging, M.rate, true)
    if not rate then return nil end
    local secs = sane(charging and (100 - pct) / rate or pct / -rate)
    if not secs then return nil end
    local full = gauge and tonumber(gauge.full) or M.CAPACITY
    return secs, kind, "pct", rate * 3600 * full / 100
end

-- Mean current (mA, absolute) of the current stretch from the gauge readings, over the last WINDOW s; nil without
-- readings. The screen and the widgets show it ("42 mA em média").
function M.mean_current(samples, now, charging)
    local segs = M.segments(samples or {})
    local cur = segs[#segs]
    if not cur or cur[#cur].chg ~= (charging == true) or now - cur[#cur].t > M.GAP_MAX or before_suspend(cur[#cur]) then
        return nil
    end
    local last = cur[#cur]
    local sum, n = 0, 0
    for _, s in ipairs(cur) do
        if s.t >= last.t - M.WINDOW and tonumber(s.ma) then sum, n = sum + math.abs(s.ma), n + 1 end
    end
    if n == 0 then return nil end
    return sum / n
end

---------------------------------------------------------------- 8.6 rules

-- Discharge / charge tracking, persisted between readings (ctx.data): { chg, since, pct, t }.
-- A new stretch starts on the first reading, when the charging state flips, and when the percentage jumped
-- the "wrong" way between two readings of the same state (it charged, or ran down, while the Tinta was closed).
function M.track(prev, now, pct, charging)
    charging = charging == true
    local new = { chg = charging, since = now, pct = pct, t = now }
    if type(prev) ~= "table" or prev.chg ~= charging or not prev.since then return new end
    local ppct = tonumber(prev.pct)
    if ppct and pct then
        if not charging and pct >= ppct + M.REPLUG_JUMP then return new end
        if charging and pct <= ppct - M.REPLUG_JUMP then return new end
    end
    return { chg = charging, since = prev.since, pct = pct, t = now }
end

-- Notifications due for this reading (8.6). The key carries the start of the stretch, so each fires once per
-- discharge / charge (R-T1 deduplicates). The first reading after opening is handled by core (it only records).
-- r = { pct, charging, full (gauge status "Full") }; eta_text: the estimate text or nil; L: translator.
function M.events(state, r, eta_text, L)
    local out = {}
    local pct = tonumber(r and r.pct)
    if not state or not pct then return out end
    if not r.charging and pct < M.LOW then
        out[#out + 1] = {
            key = "low:" .. tostring(state.since), type = "low", prio = "alta",
            title = L("n_low_title", math.floor(pct + 0.5)),
            body = eta_text and L("n_low_body", eta_text) or L("n_low_body_noeta"),
        }
    end
    if r.charging and (pct >= 100 or r.full) then
        out[#out + 1] = {
            key = "full:" .. tostring(state.since), type = "full", prio = "normal",
            title = L("n_full_title"), body = L("n_full_body"),
        }
    end
    return out
end

---------------------------------------------------------------- one refresh

-- The pure part of a refresh: log the reading (store = apps/bateria/csvlog store), estimate, track the stretch and
-- pick the notifications. r = device/battery reading (+ wifi); prev = the persisted tracking state.
-- Returns cache (what the widgets, the screen and the status bar read), the new tracking state, notifications.
function M.cycle(store, r, now, prev, L)
    local pct = math.max(0, math.min(100, math.floor(tonumber(r.pct) + 0.5)))
    local charging = r.charging == true
    store:sample(now, { pct = pct, charging = charging, wifi = r.wifi, mv = r.mv, ma = r.ma, mah = r.mah, temp = r.temp })
    local samples = store.samples or {}
    local secs, kind, basis, ma_fit = M.estimate(samples, now, pct, charging, { mah = r.mah, full = r.full_mah })
    local cache = {
        pct = pct, charging = charging, full = r.full == true, status = r.status,
        eta = secs, kind = kind, basis = basis, ma_fit = ma_fit,
        ma_mean = M.mean_current(samples, now, charging),
        ma = r.ma, mv = r.mv, mah = r.mah, full_mah = r.full_mah, temp = r.temp,
        samples = math.max(tonumber(store.nlines) or 0, #samples), at = now,
    }
    local state = M.track(prev, now, pct, charging)
    return cache, state, M.events(state, cache, M.eta_text(secs), L)
end

---------------------------------------------------------------- texts

-- "~25min", "~4h20", "~12h" (same rounding as core/format.eta, which apps do not require)
function M.eta_text(secs)
    secs = tonumber(secs)
    if not secs or secs ~= secs or secs < 0 then return nil end
    local min = math.floor(secs / 60 + 0.5)
    if min < 60 then return "~" .. math.max(5, math.floor(min / 5 + 0.5) * 5) .. "min" end
    local h, m = math.floor(min / 60), min % 60
    if h >= 10 then return "~" .. h .. "h" end
    return string.format("~%dh%02d", h, m)
end

-- "1.234" (pt) / "1,234" (en)
function M.thousands(n, lang)
    n = math.floor((tonumber(n) or 0) + 0.5)
    local s = tostring(math.abs(n))
    local sep = lang == "en" and "," or "."
    local out = s:reverse():gsub("(%d%d%d)", "%1" .. sep):reverse()
    if out:sub(1, 1) == sep then out = out:sub(2) end
    return (n < 0 and "-" or "") .. out
end

local function pct_text(pct) return tostring(math.floor((tonumber(pct) or 0) + 0.5)) .. "%" end

-- the view model of the last reading (ctx.cache), for the screen and the widgets.
-- c = { pct, charging, full, eta, kind, basis, ma_fit, ma_mean, ma, full_mah, temp, samples, at }
-- Returns { pct, pct_text, number (2x2 primary, "⚡" when charging), charging, line (screen), short (widget), stats = { {value, label} x4 }, ok }
function M.view(c, now, L, lang)
    if type(c) ~= "table" or not tonumber(c.pct) then
        return { ok = false, pct = 0, pct_text = "--%", number = "--", charging = false, line = L("no_reading"), short = L("no_reading"),
            stats = M.stats(c or {}, L, lang) }
    end
    local pct = math.max(0, math.min(100, tonumber(c.pct)))
    local eta = c.eta and M.eta_text(math.max(0, c.eta - math.max(0, (now or c.at or 0) - (c.at or now or 0)))) or nil
    local ma = c.ma_mean or (c.ma_fit and math.abs(c.ma_fit)) or (c.ma and math.abs(c.ma)) or nil
    local ma_text = ma and L("ma", math.floor(ma + 0.5)) or nil
    local line, short
    if c.charging then
        if pct >= 100 or c.full then
            line, short = L("charged"), L("charged")
        elseif eta then
            line, short = L("charging_eta", eta), L("charging_eta_short", eta)
        else
            line, short = L("charging_calibrating"), L("charging_calibrating")
        end
    else
        if eta then
            line = ma_text and L("left_ma", eta, ma_text) or L("left", eta)
            short = ma_text and (eta .. " · " .. ma_text) or eta
        else
            line, short = L("calibrating"), L("calibrating_short")
        end
    end
    local num = pct_text(pct)
    return {
        ok = true, pct = pct, pct_text = num, number = (c.charging and "⚡" or "") .. num,
        charging = c.charging == true,
        line = line, short = short, eta = eta, stats = M.stats(c, L, lang),
    }
end

-- the four blocks of the screen (10.3): mean current, full capacity, temperature, samples
function M.stats(c, L, lang)
    local ma = c.ma_mean or (c.ma_fit and math.abs(c.ma_fit)) or (c.ma and math.abs(c.ma)) or nil
    return {
        { ma and L("ma", math.floor(ma + 0.5)) or "--", L("stat_mean") },
        { c.full_mah and tostring(math.floor(c.full_mah + 0.5)) or "--", L("stat_full") },
        { c.temp and L("temp", math.floor(c.temp + 0.5)) or "--", L("stat_temp") },
        { c.samples and M.thousands(c.samples, lang) or "0", L("stat_samples") },
    }
end

-- status bar estimate (R-S1, Host.battery_eta): "~17h" for the reading b = { pct, charging } from KOReader,
-- from the last estimate when it is recent and of the same charging state; nil otherwise.
M.STATUS_MAX_AGE = 1800
function M.status_eta(last, b, now)
    if type(last) ~= "table" or type(b) ~= "table" or not last.eta or not last.at then return nil end
    if (b.charging == true) ~= (last.charging == true) then return nil end
    local age = (now or last.at) - last.at
    if age < 0 or age > M.STATUS_MAX_AGE then return nil end
    return M.eta_text(math.max(0, last.eta - age))
end

return M
