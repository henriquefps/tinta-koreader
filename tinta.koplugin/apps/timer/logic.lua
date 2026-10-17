-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (C) 2026 Tinta contributors
-- Timer (10.6), pure (R-A1): the state machine of a countdown with pomodoro follow-up, the minute-resolution
-- text and the notification. State (kept in ctx.data "state", so it survives closing the Tinta):
--   { mode = "idle", sel = { min, brk? } }                                  idle, with the preset chosen
--   { mode = "running", kind = "focus"|"break", total, end_at, brk?, sel }  end_at: absolute time
--   { mode = "paused",  kind, total, left, brk?, sel }                      left: seconds when paused
-- Times are os.time() seconds; nothing here reads the clock or the store.
local M = {}

M.GRACE = 5             -- s: a refresh this much before end_at already counts as the end (RTC wake-up rounding)
M.MIN_MIN, M.MAX_MIN = 1, 600
M.CUSTOM_DEFAULT = 20

-- presets of the screen, in order; "pomo" takes its minutes from the settings (work_min / break_min)
M.PRESETS = { "pomo", "m15", "m10", "m5" }
M.FIXED = { m15 = 15, m10 = 10, m5 = 5 }

-- "45", " 45 ", "45 min" -> 45; nil outside 1..600 or not a whole number
function M.parse_minutes(v)
    if type(v) == "number" then
        return (v == math.floor(v) and v >= M.MIN_MIN and v <= M.MAX_MIN) and v or nil
    end
    if type(v) ~= "string" then return nil end
    local n = v:match("^%s*(%d+)%s*m?i?n?%s*$")
    n = tonumber(n)
    if not n or n < M.MIN_MIN or n > M.MAX_MIN then return nil end
    return n
end

-- the selection of a preset: { min, brk? }. cfg = { work_min, break_min, custom_min } (already validated numbers)
function M.selection(preset, cfg)
    cfg = cfg or {}
    if preset == "pomo" then return { min = cfg.work_min or 25, brk = cfg.break_min or 5, id = "pomo" } end
    if M.FIXED[preset] then return { min = M.FIXED[preset], id = preset } end
    return { min = M.parse_minutes(cfg.custom_min) or M.CUSTOM_DEFAULT, id = "custom" }
end

function M.idle(sel) return { mode = "idle", sel = sel } end

-- state read from the store: anything odd becomes idle (never throws)
function M.sanitize(raw, default_sel)
    local function sel_of(r)
        local s = type(r) == "table" and r.sel
        if type(s) == "table" and M.parse_minutes(s.min) then
            return { min = s.min, brk = M.parse_minutes(s.brk), id = type(s.id) == "string" and s.id or nil }
        end
        return default_sel
    end
    if type(raw) ~= "table" then return M.idle(default_sel) end
    local sel = sel_of(raw)
    local kind = raw.kind == "break" and "break" or "focus"
    local total = tonumber(raw.total)
    if raw.mode == "running" and tonumber(raw.end_at) and total and total > 0 then
        return { mode = "running", kind = kind, total = total, end_at = raw.end_at, brk = M.parse_minutes(raw.brk), sel = sel }
    end
    if raw.mode == "paused" and tonumber(raw.left) and total and total > 0 then
        return { mode = "paused", kind = kind, total = total, left = math.max(0, raw.left), brk = M.parse_minutes(raw.brk), sel = sel }
    end
    return M.idle(sel)
end

-- starts the selection: a focus run (with its break when the selection has one)
function M.start(sel, now)
    local secs = sel.min * 60
    return { mode = "running", kind = "focus", total = secs, end_at = now + secs, brk = sel.brk, sel = sel }
end

function M.remaining(st, now)
    if st.mode == "running" then return math.max(0, st.end_at - now) end
    if st.mode == "paused" then return st.left end
    return 0
end

function M.pause(st, now)
    if st.mode ~= "running" then return st end
    return { mode = "paused", kind = st.kind, total = st.total, left = M.remaining(st, now), brk = st.brk, sel = st.sel }
end

function M.resume(st, now)
    if st.mode ~= "paused" then return st end
    return { mode = "running", kind = st.kind, total = st.total, end_at = now + st.left, brk = st.brk, sel = st.sel }
end

function M.reset(st) return M.idle(st.sel) end

function M.is_due(st, now)
    return st.mode == "running" and now + M.GRACE >= st.end_at
end

-- the end of a run. Returns the new state and the event { kind, minutes, key }:
-- a finished focus run with a break and auto_break starts the break from `now`; anything else goes idle.
function M.finish(st, now, auto_break)
    local ev = { kind = st.kind, minutes = math.floor(st.total / 60 + 0.5), key = "timer:" .. tostring(math.floor(st.end_at)) }
    if st.kind == "focus" and st.brk and auto_break then
        local secs = st.brk * 60
        return { mode = "running", kind = "break", total = secs, end_at = now + secs, sel = st.sel }, ev
    end
    return M.idle(st.sel), ev
end

-- whole minutes left, rounded up (minute resolution on e-ink)
function M.minutes_left(secs) return math.ceil(math.max(0, secs) / 60) end

-- "12 min", "1 h 05", "< 1 min" -> text keys of the app's strings: t(key, ...)
function M.left_text(secs, t)
    local m = M.minutes_left(secs)
    if secs <= 0 then return t("left_zero") end
    if m < 1 then return t("left_lt1") end
    if m >= 60 then return t("left_h", math.floor(m / 60), m % 60) end
    return t("left_min", m)
end

-- what the widgets and the screen show. date = os.date-like (tests pass a fixed one)
function M.view(st, now, t, date)
    date = date or os.date
    local secs = M.remaining(st, now)
    local vm = { mode = st.mode, kind = st.kind, secs = secs, min = M.minutes_left(secs) }
    if st.mode == "idle" then
        local sel = st.sel or { min = 25 }
        vm.primary = t("left_min", sel.min)
        vm.secondary = sel.brk and t("idle_pomo", sel.min, sel.brk) or t("idle_tap")
        vm.status = t("st_idle")
        vm.number = nil
        return vm
    end
    vm.primary = M.left_text(secs, t)
    vm.status = st.mode == "paused" and t("st_paused") or t(st.kind == "break" and "st_break" or "st_focus")
    if st.mode == "paused" then
        vm.secondary = t("paused_note")
    else
        vm.secondary = t("until", date("%H:%M", st.end_at))
    end
    vm.number = tostring(vm.min)
    return vm
end

-- the notification of an ended run (8.6): prio alta
function M.notification(ev, t)
    local n = { key = ev.key, type = "done", prio = "alta", title = t("n_done_title") }
    n.body = ev.kind == "break" and t("n_break_body") or t("n_focus_body", ev.minutes)
    return n
end

-- timestamp the Tinta must be awake at for this state (ctx.wake_at), nil when none
function M.wake_time(st)
    return st.mode == "running" and st.end_at or nil
end

return M
