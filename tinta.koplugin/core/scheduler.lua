-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (C) 2026 Tinta contributors
-- When to refresh each app (spec 9): interval (R-U1), per-app window (R-U2), global quiet hours (R-U3), the
-- 5 s tick that batches everything due in the next 2 min (R-U4), no Wi-Fi (R-U5), manual (R-U7).
-- Pure Lua (R-A1): no clock, no KOReader. `now` is passed in; local time comes from opts.date (os.date by
-- default). The scheduler only decides; the registry runs the refreshes and keeps one per app (R-U8).
--
-- An "app entry" is a plain table:
--   { id, interval (s; 0 = manual; nil = app has no refresh), net (bool), window ({from,to,weekdays,in_window}),
--     last_ok, last_err (timestamps), last (last attempt; defaults to max(last_ok, last_err)),
--     busy (bool), disabled (bool, R-E4 auto refresh off) }
local Format = require("core/format")

local M = {}

M.TICK = 5                -- seconds between ticks with the Tinta awake (R-U4)
M.BATCH_AHEAD = 120       -- apps due in the next 2 min go along (R-U4)
M.INTERVALS = { 30, 60, 300, 900, 1800, 3600, 0 }   -- R-U1; 0 = manual
M.QUIET_DEFAULT = { enabled = true, from = "23:00", to = "07:00" }   -- R-U3
M.MAX_LOOKAHEAD = 8 * 86400
M.STRIDE = 15 * 60         -- next_run: coarse step before the minute-by-minute search

function M.valid_interval(v)
    for _, x in ipairs(M.INTERVALS) do if x == v then return true end end
    return false
end

-- Next value in the R-U1 cycle (menu "Intervalo desta app", Sistema → Atualizações). Unknown values go to the
-- first one.
function M.cycle_interval(v)
    for i, x in ipairs(M.INTERVALS) do
        if x == v then return M.INTERVALS[i % #M.INTERVALS + 1] end
    end
    return M.INTERVALS[1]
end

-- Is minute-of-day `m` inside [from, to]? Inclusive at both ends; from > to wraps past midnight.
local function in_range(m, from, to, inclusive_end)
    if from == nil or to == nil then return true end
    if from <= to then
        if inclusive_end then return m >= from and m <= to end
        return m >= from and m < to
    end
    if inclusive_end then return m >= from or m <= to end
    return m >= from or m < to
end

-- R-U2: true when `now` is inside the app window. No window = always. A window may carry its own
-- in_window(now) (e.g. working days are known only by the app); an error there counts as inside.
-- weekdays = true limits to Monday..Friday.
function M.in_window(window, now, date)
    if not window then return true end
    if type(window.in_window) == "function" then
        local ok, res = pcall(window.in_window, now)
        if ok then return res and true or false end
        return true
    end
    date = date or os.date
    local d = date("*t", now)
    if window.weekdays and (d.wday == 1 or d.wday == 7) then return false end
    return in_range(d.hour * 60 + d.min, Format.parse_hm(window.from), Format.parse_hm(window.to), true)
end

-- R-U3: quiet hours, end exclusive (23:00–07:00 means 07:00 is no longer quiet).
function M.quiet_now(quiet, now, date)
    quiet = quiet or M.QUIET_DEFAULT
    if not quiet.enabled then return false end
    date = date or os.date
    return in_range(Format.minute_of_day(now, date), Format.parse_hm(quiet.from), Format.parse_hm(quiet.to), false)
end

local function last_attempt(a)
    if a.last then return a.last end
    local x, y = a.last_ok, a.last_err
    if x and y then return math.max(x, y) end
    return x or y
end
M.last_attempt = last_attempt

-- R-S5: the last refresh failed (there may or may not be older good data).
function M.failed(a)
    return a.last_err ~= nil and (a.last_ok == nil or a.last_err > a.last_ok)
end

-- Allowed to refresh automatically right now, ignoring the interval.
local function allowed(a, now, opts)
    if not a.interval or a.interval <= 0 then return false end
    if a.busy or a.disabled then return false end
    if a.net and opts.wifi == false then return false end                     -- R-U5
    if a.net and M.quiet_now(opts.quiet, now, opts.date) then return false end   -- R-U3
    return M.in_window(a.window, now, opts.date)                              -- R-U2
end

local function due_at(a)
    local last = last_attempt(a)
    if last == nil then return -math.huge end   -- never refreshed: due now
    return last + a.interval
end

-- The 5 s tick (R-U4): returns the list of app ids to refresh now, in input order: first the ones due
-- (last + interval <= now), then the ones that would be due within opts.ahead (default 2 min). Empty when
-- nothing is due. opts = { wifi = bool (default true), quiet = {enabled,from,to}, date = fn, ahead = s }.
-- Second result: number of network apps in the batch (they share one Wi-Fi connection, 11.2).
function M.pick(apps, now, opts)
    opts = opts or {}
    local ahead = opts.ahead or M.BATCH_AHEAD
    local due, soon, is_due = {}, {}, {}
    for _, a in ipairs(apps) do
        if allowed(a, now, opts) and due_at(a) <= now then
            due[#due + 1] = a; is_due[a] = true
        end
    end
    if #due == 0 then return {}, 0 end
    for _, a in ipairs(apps) do
        if not is_due[a] and allowed(a, now, opts) and due_at(a) <= now + ahead then soon[#soon + 1] = a end
    end
    local ids, nnet = {}, 0
    for _, list in ipairs({ due, soon }) do
        for _, a in ipairs(list) do
            ids[#ids + 1] = a.id
            if a.net then nnet = nnet + 1 end
        end
    end
    return ids, nnet
end

-- Manual refresh (R-U7): ignores interval, window, quiet and the R-E4 lock (the registry clears it). Without
-- Wi-Fi the network apps are skipped and returned separately (toast "Sem Wi-Fi: mostrando o último dado",
-- R-U5). Apps without refresh (interval nil) are never included. Returns ids, skipped_ids.
function M.manual(apps, opts)
    opts = opts or {}
    local ids, skipped = {}, {}
    for _, a in ipairs(apps) do
        if a.interval ~= nil then
            if a.net and opts.wifi == false then skipped[#skipped + 1] = a.id
            else ids[#ids + 1] = a.id end
        end
    end
    return ids, skipped
end

-- Wake-up from sleep (R-P6): the apps of the sleep page refresh regardless of the interval (the wake interval
-- already spaces them), but window and quiet hours still hold (it is automatic, not manual) and manual-only
-- apps stay out. Wi-Fi is being brought up for the batch, so it is not checked here (R-P3).
function M.wake(apps, now, opts)
    opts = opts or {}
    local ids = {}
    for _, a in ipairs(apps) do
        local o = { wifi = true, quiet = opts.quiet, date = opts.date }
        if allowed({ interval = a.interval, net = a.net, window = a.window, disabled = a.disabled }, now, o) then
            ids[#ids + 1] = a.id
        end
    end
    return ids
end

-- Timestamp of the next automatic refresh (Sistema → Atualizações), or nil when there is none (manual, no
-- refresh, R-E4 lock, nothing allowed in the next 8 days). Busy and Wi-Fi are not considered.
function M.next_run(a, now, opts)
    opts = opts or {}
    if not a.interval or a.interval <= 0 or a.disabled then return nil end
    local t = math.max(now, due_at(a))
    local o = { quiet = opts.quiet, date = opts.date }
    local probe = { interval = a.interval, net = a.net, window = a.window }
    local limit = now + M.MAX_LOOKAHEAD
    if allowed(probe, t, o) then return t end
    -- Coarse steps of M.STRIDE, then the minutes of the last step: the first allowed minute is found with
    -- ~800 checks instead of one per minute (11 520 for 8 days; each check can run the app's in_window). A
    -- window shorter than the stride can be skipped; windows and quiet hours are at least an hour (R-U2/R-U3).
    local function next_minute(x) return (math.floor(x / 60) + 1) * 60 end
    local prev = t
    local c = next_minute(t)
    while c <= limit do
        if allowed(probe, c, o) then
            local m = next_minute(prev)
            while m < c do
                if allowed(probe, m, o) then return m end
                m = m + 60
            end
            return c
        end
        prev = c
        c = c + M.STRIDE
    end
    return nil
end

-- "HH:MM" when automatic refresh comes back (footer "volta HH:MM"): the first allowed minute (window and quiet
-- hours), falling back to the window start.
local function resume_text(a, now, opts)
    local t = M.next_run({ interval = 60, net = a.net, window = a.window, last = now - 60 }, now, opts)
    if t then return Format.hm(t, opts.date) end
    return a.window and a.window.from or nil
end

-- Status of one app for the footer/header (format.footer / format.header):
--   kind = "none" (no refresh) | "busy" | "error" (R-E4) | "failed" (R-S5) | "paused" (out of window or, for
--   network apps, quiet hours) | "ok"; plus last_ok, interval, resume ("HH:MM", paused only).
-- Precedence follows R-W4: busy, failed, paused, ok; the R-E4 lock outranks them except busy.
function M.status(a, now, opts)
    opts = opts or {}
    local st = { last_ok = a.last_ok, interval = a.interval }
    if a.interval == nil then st.kind = "none"
    elseif a.busy then st.kind = "busy"
    elseif a.disabled then st.kind = "error"
    elseif M.failed(a) then st.kind = "failed"
    elseif a.interval > 0 and (not M.in_window(a.window, now, opts.date)
            or (a.net and M.quiet_now(opts.quiet, now, opts.date))) then
        st.kind = "paused"
        st.resume = resume_text(a, now, opts)
    else st.kind = "ok" end
    return st
end

return M
