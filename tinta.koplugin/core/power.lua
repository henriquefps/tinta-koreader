-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (C) 2026 Tinta contributors
-- Sleep rules (spec 11), pure: the wake schedule (11.4), the next wake-up, idle entry (R-P4), wake-up
-- classification (R-P11, R-P12), the repeated RTC request (R-P10) and the sleep status bar (R-S4).
-- The device side (lipc, powerd, Wi-Fi) lives in device/; this module never touches the device (R-A1, R-P1).
local Format = require("core/format")
local I18n = require("core/i18n")

local M = {}

-- The "wake" Tinta setting (10.5 Repouso → Atualizar a tela): seconds between wake-ups, "schedule" (the
-- fixed bands of 11.4) or "never".
M.WAKE = { 900, 1800, 3600, 7200, "schedule", "never" }
M.DEFAULT_WAKE = "schedule"
M.IDLE = { 2, 5, 10, 15 }               -- minutes without touch (R-P4); "never" is the mode, not a value
M.DEFAULT_IDLE = 5
M.IDLE_MODES = { "always", "battery", "never" }   -- the "idle_mode" Tinta setting (10.5)
M.DEFAULT_IDLE_MODE = "battery"
M.RTC_REPEAT = 2                        -- s between rtcWakeup requests while readyToSuspend (R-P10)
M.WAKE_TOLERANCE = 120                  -- s around the target that still counts as the scheduled wake-up
M.WIFI_TIMEOUT = 30                     -- s to wait for Wi-Fi on a scheduled wake-up (R-P3)

-- 11.4 (fixed bands in v1; only on/off is editable). every = minutes, nil = does not wake.
-- Bands are tried in order; the first that matches wins. weekdays: true = Mon..Fri only, false = Sat/Sun only.
M.SCHEDULE = {
    { from = "07:30", to = "18:30", weekdays = true, every = 30 },
    { from = "07:30", to = "18:30", weekdays = false, every = 60 },   -- outside working days
    { from = "18:30", to = "23:00", every = 60 },
    { from = "23:00", to = "07:30", every = nil },                    -- fixed screen
}

local function in_band(band, d)
    local m = d.hour * 60 + d.min
    local from, to = Format.parse_hm(band.from), Format.parse_hm(band.to)
    local weekend = d.wday == 1 or d.wday == 7
    if band.weekdays == true and weekend then return false end
    if band.weekdays == false and not weekend then return false end
    if from <= to then return m >= from and m < to end
    return m >= from or m < to
end

-- The band in force at `now`, or nil.
function M.band(now, schedule, date)
    local d = (date or os.date)("*t", now)
    for _, b in ipairs(schedule or M.SCHEDULE) do
        if in_band(b, d) then return b end
    end
    return nil
end

-- Wake interval in minutes at `now`, or nil when the device must not wake ("never", or the night band).
-- opts = { wake = the "wake" setting (default "schedule"), bands = list (default M.SCHEDULE), date = fn }
function M.wake_interval(now, opts)
    opts = opts or {}
    local wake = opts.wake
    if wake == nil then wake = M.DEFAULT_WAKE end
    if wake == "never" then return nil end
    if type(wake) == "number" then return wake / 60 end
    local b = M.band(now, opts.bands, opts.date)
    return b and b.every or nil
end

-- Timestamp of the next RTC wake-up after entering sleep (or after a wake-up) at `now`, or nil to never wake.
--   "never"            -> nil
--   a number (seconds) -> now + that, at any hour (the user chose it, the bands do not apply)
--   "schedule"         -> now + the interval of the current band; when that lands in a band that does not
--                         wake, the wake-up moves to the end of that band (the first minute that wakes
--                         again), so the night is one long sleep. In the night band itself, the first minute
--                         of the next waking band.
function M.next_wakeup(now, opts)
    opts = opts or {}
    local wake = opts.wake
    if wake == nil then wake = M.DEFAULT_WAKE end
    if wake == "never" then return nil end
    if type(wake) == "number" then return now + wake end
    local every = M.wake_interval(now, opts)
    local t = every and (now + every * 60) or now
    -- walk forward (minute steps) out of non-waking bands; at most 2 days
    local limit = t + 2 * 86400
    local function wakes(x) return M.wake_interval(x, opts) ~= nil end
    if not every or not wakes(t) then
        local x = (math.floor(t / 60) + 1) * 60
        while x <= limit and not wakes(x) do x = x + 60 end
        if x > limit then return nil end
        return x
    end
    return t
end

-- Seconds to request with rtcWakeup at `now` for the target (R-P10: requested again every 2 s with the
-- remaining time to the same target). Never below 1.
function M.rtc_seconds(target, now)
    return math.max(1, math.floor(target - now + 0.5))
end

-- R-P4: true when the Tinta should enter sleep after `idle` minutes without touch.
--   mode "always": whenever idle is due; "never": never; "battery" (default, also for an unknown mode): only
--   while the Kindle is not plugged in (USB/charger).
--   plugged: boolean, or a function returning one. The function is only called when the answer needs it (mode
--   "battery" and the idle time is due), so the 5 s tick does no device work in the common case.
function M.idle_due(last_touch, now, idle, mode, plugged)
    if not idle or idle <= 0 or not last_touch or mode == "never" then return false end
    if now - last_touch < idle * 60 then return false end
    if mode == "always" then return true end
    if type(plugged) == "function" then plugged = plugged() end
    return not plugged
end

-- R-P11/R-P12: why the device woke up.
--   powerd_state "active" -> "button" (R-P7: back to normal use)
--   otherwise, within tolerance of the scheduled target -> "scheduled" (R-P6: refresh, redraw, sleep again)
--   otherwise -> "unscheduled" (powerd's daily 06:10 and others: just sleep again)
function M.classify_wakeup(o)
    if o.powerd_state == "active" or o.reason == "button" then return "button" end
    if o.target and math.abs(o.now - o.target) <= (o.tolerance or M.WAKE_TOLERANCE) then return "scheduled" end
    return "unscheduled"
end

-- R-S4: "Repouso · atualizado HH:MM · próxima HH:MM" ("próxima" left out when it never wakes).
function M.sleep_bar(updated_at, next_at, date)
    if not next_at then return I18n.t("sleep_bar_no_next", Format.hm(updated_at, date)) end
    return I18n.t("sleep_bar", Format.hm(updated_at, date), Format.hm(next_at, date))
end

return M
