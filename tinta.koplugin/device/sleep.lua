-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (C) 2026 Tinta contributors
-- Tinta device side of sleep (spec 11, R-P1: only this module and device/net.lua turn the Wi-Fi on/off, suspend
-- the Kindle and program the wake-up). The decisions are core/power's (next wake-up, classification, idle);
-- they reach this module through the host (ui/host -> ui/core), so nothing here requires core/.
--
--   Sleep.attach(host, opts)  Tinta opened: remember preventScreenSaver, hold it at 1 (R-P9, awake)
--   Sleep.detach()            Tinta closed: stop everything, restore the remembered preventScreenSaver
--   Sleep.enter(reason)       R-P5: close menus/dialogs, draw the sleep page, Wi-Fi off, wake-up target, suspend
--   Sleep.earliest(a, b)      min of two optional timestamps (schedule vs. wake requests, 11.7)
--   Sleep.active()            true while the sleep page is up (also during a scheduled wake-up)
--   opts = { log_path = <text log of every sleep and wake-up, with charge_now>, measure_path = <file whose
--            content is a number of seconds: scheduled wake-ups every N s instead of the 11.4 bands> }
--
-- How it works on the KT3 (11.5, measured with small RTC and suspend test scripts):
--   * preventScreenSaver is set to 0 and powerButton 1 is sent (R-P9), then every 2 s, while powerd is in
--     readyToSuspend, rtcWakeup is requested again with the seconds left to the same target (R-P10);
--   * a wake-up is classified (R-P11/R-P12): the power button (powerd active, OutOfSS) goes back to the previous
--     screen; the scheduled one refreshes the sleep-page apps over Wi-Fi, redraws and lets powerd suspend again
--     (it is not touched: no new button press); anything else (powerd's daily 06:10) is ignored;
--   * KOReader's own screensaver never draws over the sleep page: intoScreenSaver is wrapped while sleeping.
--   * USB: with a cable connected powerd stays in screenSaver and never reaches readyToSuspend (measured 2026-10-16: 22 min,
--     no suspend, no RTC wake-up). After USB_WAIT_S in screenSaver the scheduled wake-ups are driven by a UIManager timer at
--     the same target (schedule or wake request, whichever is first): the same batch (Wi-Fi, refresh, redraw, Wi-Fi off)
--     runs without a suspend, logged as "sleep mode=awake-usb". If powerd later reaches readyToSuspend (cable removed) the
--     RTC pump takes over again.
-- lipc goes through KOReader's liblipclua when it loads, else through lipc-get-prop / lipc-set-prop.
--
-- Device specifics live in device/backends/{kindle,kobo,generic}.lua, chosen once at attach from KOReader's Device
-- (backends.select). The Kindle text above describes backends/kindle.lua, where that code now is (moved, not
-- rewritten). This module keeps what is common: the sleep page, Wi-Fi, the wake-up batch, the button, the log.
-- A backend (sleep controller) offers: name, can_wake, wifi_timeout, charge(), attach() -> text, detach(), stop(),
-- state(), suspend(), restore(), retarget(), batch_done(); see backends/kobo.lua for the KOReader-driven kind.
-- Every KOReader dependency can be replaced with Sleep._set_deps{...} (tests run without a Kindle).
local Backends = require("device/backends")

local M = {}

M.SETTLE_S = 2             -- after drawing the sleep page, before Wi-Fi off + suspend (e-ink needs to finish)
M.PUMP_S = 2               -- R-P10: rtcWakeup is requested again every 2 s while readyToSuspend
M.CLASSIFY_S = 3           -- after WakeupFromSuspend, before reading powerd's state
M.WAKE_GAP_S = 12          -- a pump tick this late means the device was suspended in between
M.ABORT_S = 25             -- powerd still active this long after the power button: give up, back to the Tinta
M.USB_WAIT_S = 90          -- powerd stuck in screenSaver this long (USB cable: it never suspends): awake-usb mode
M.WIFI_POLL_S = 1
M.MEASURE_MIN = 60         -- the measure file is clamped to this many seconds at least
M.LOG_MAX = 64 * 1024

local deps = nil
function M._set_deps(d) deps = d end

local function dep(name)
    if deps then return deps[name] end
    if name == "ui" then return require("ui/uimanager") end
    if name == "network" then
        local ok, nm = pcall(require, "ui/network/manager")
        return ok and nm or nil
    end
    if name == "device" then
        local ok, d = pcall(require, "device")
        return ok and d or nil
    end
    if name == "pluginshare" then
        local ok, p = pcall(require, "pluginshare")
        return ok and type(p) == "table" and p or nil
    end
    if name == "screensaver" then
        local ok, sc = pcall(require, "ui/screensaver")
        return ok and type(sc) == "table" and sc or nil
    end
    if name == "logger" then
        local ok, l = pcall(require, "logger")
        return ok and l or nil
    end
    if name == "lipc_lib" then
        local ok, l = pcall(require, "liblipclua")
        return ok and l or nil
    end
    if name == "clock" then return os.time end
    if name == "read_file" then
        return function(path)
            local fh = io.open(path, "r")
            if not fh then return nil end
            local s = fh:read("*l")
            fh:close()
            return s
        end
    end
    if name == "exec" then
        return function(cmd)
            local p = io.popen(cmd .. " 2>/dev/null")
            if not p then return nil end
            local out = p:read("*a")
            p:close()
            return out
        end
    end
    return nil
end

local S = nil      -- state of the attached Tinta (nil = not attached)

local function now() return dep("clock")() end

local function log(msg)
    local lg = dep("logger")
    if lg and lg.info then lg.info("Tinta sleep:", msg) end
    if S and S.host and S.host.log then pcall(S.host.log, S.host, "sleep", "info", msg) end
end

---------------------------------------------------------------- measurement log

local function charge()
    return S and S.backend and S.backend.charge() or nil
end

local function hms(t) return os.date("%H:%M:%S", t) end

-- one line in the text log: key=value pairs (the coordinator reads this after a device test)
local function record(kind, fields)
    if not S.log_path then return end
    local parts = { "t=" .. hms(now()), kind }
    for _, kv in ipairs(fields or {}) do parts[#parts + 1] = kv[1] .. "=" .. tostring(kv[2]) end
    local fh = io.open(S.log_path, "a")
    if not fh then return end
    fh:write(table.concat(parts, " "), "\n")
    fh:close()
end

local function trim_log(path)
    local fh = io.open(path, "r")
    if not fh then return end
    local size = fh:seek("end")
    if size and size > M.LOG_MAX then
        fh:seek("set", size - M.LOG_MAX / 2)
        fh:read("*l")
        local rest = fh:read("*a")
        fh:close()
        local out = io.open(path, "w")
        if out then out:write(rest); out:close() end
    else
        fh:close()
    end
end

-- measurement mode: a file with a number of seconds makes every scheduled wake-up that many seconds apart
local function measure_seconds()
    if not S.measure_path then return nil end
    local rf = dep("read_file")
    local v = rf and rf(S.measure_path)
    v = v and tonumber((v:gsub("%s+", "")))
    if not v then return nil end
    return math.max(M.MEASURE_MIN, math.floor(v))
end

-- earliest of two optional timestamps
function M.earliest(a, b)
    if a and b then return math.min(a, b) end
    return a or b
end

-- the next RTC target: the schedule's (or the measure file's) wake-up, or the earliest wake request an app made
-- (ctx.wake_at: the Timer) when that comes first. Requests only ever bring the wake-up forward.
local function next_target(from)
    if not S.backend.can_wake then return nil end        -- generic: nothing to wake the device, so no target
    local m = measure_seconds()
    local sched = m and (from + m) or S.host:wakeTarget(from)
    local req = S.host.nextWakeRequest and S.host:nextWakeRequest(from) or nil
    return M.earliest(sched, req)
end

---------------------------------------------------------------- attach / detach

function M.attach(host, opts)
    opts = opts or {}
    if S then M.detach() end
    S = { host = host, log_path = opts.log_path, measure_path = opts.measure_path, sleeping = false }
    if S.log_path then trim_log(S.log_path) end
    S.backend = Backends.select(dep("device")).sleep{ M = M, S = S, dep = dep, now = now, log = log, record = record }
    local what = S.backend.attach()
    host.enter_sleep = function(reason) return M.enter(reason) end
    log("attached (" .. S.backend.name .. "), " .. tostring(what))
end

function M.detach()
    if not S then return end
    local st = S
    st.backend.stop()
    if st.sleeping then
        -- the Tinta closed while asleep (it should not happen): leave powerd the way KOReader had it
        st.host.sleeping = false
    end
    st.backend.detach()
    st.host.enter_sleep = nil
    S = nil
end

function M.active() return S ~= nil and S.sleeping == true end

---------------------------------------------------------------- Wi-Fi (R-P1, R-P3)

local function wifi_on()
    local nm = dep("network")
    if not nm then return false end
    local ok, v = pcall(function() return nm:isWifiOn() == true end)
    return ok and v
end

local function wifi_connected()
    local nm = dep("network")
    if not nm then return false end
    local ok, v = pcall(function() return nm:isWifiOn() == true and nm:isConnected() == true end)
    return ok and v
end

local function wifi_off()
    local nm = dep("network")
    if not nm then return end
    pcall(function() nm:disableWifi(nil, false) end)
end

local function wifi_start()
    local nm = dep("network")
    if not nm then return false end
    local ok = pcall(function() nm:enableWifi(nil, false) end)
    return ok
end

-- turns Wi-Fi on and waits (polling every second) for a connection, at most `limit` seconds.
-- done(true, seconds) | done(false, seconds)
local function wifi_up(limit, done)
    local ui = dep("ui")
    local t0 = now()
    if wifi_connected() then return done(true, 0) end
    wifi_start()
    local function poll()
        if not S or not S.sleeping then return end        -- the button woke the Tinta meanwhile
        local waited = now() - t0
        if wifi_connected() then return done(true, waited) end
        if waited >= limit then return done(false, waited) end
        ui:scheduleIn(M.WIFI_POLL_S, poll)
    end
    ui:scheduleIn(M.WIFI_POLL_S, poll)
end

---------------------------------------------------------------- enter (R-P4, R-P5)

-- battery log hook (10.3): the host asks the apps that declare `background` for a sample marked with `kind`
-- ("sleep" | "sched" | "button", or "plain" = forced, unmarked); a failure never stops sleeping or waking
local function sample(host, kind)
    if host.background then pcall(host.background, host, kind) end
end

-- reason: "now" | "idle" (only for the log)
function M.enter(reason)
    if not S then return false, "detached" end
    if S.sleeping then return false, "already" end
    local host, ui = S.host, dep("ui")
    host:beforeSleep()                                   -- menus, dialogs, hold timers
    sample(host, "sleep")                                -- battery log: last sample before the suspend (10.3)
    S.wifi_was_on = wifi_on()
    local t = now()
    S.sleeping = true
    S.busy = false
    S.left_active = false
    S.pressed_at = nil
    S.wake_at = nil
    S.updated_at = t
    S.awake_mode, S.ss_since = false, nil
    S.target = next_target(t)
    S.backend.retarget()
    S.reason = reason
    host:setSleepInfo(S.updated_at, S.target)
    host.sleeping = true
    host:drawSleep()                                     -- sleep page, full refresh
    pcall(ui.forceRePaint, ui)
    log("entering (" .. tostring(reason) .. "), next wake-up " .. (S.target and hms(S.target) or "never"))
    record("sleep", { { "reason", reason }, { "target", S.target and hms(S.target) or "never" },
        { "charge", charge() }, { "wifi_was_on", tostring(S.wifi_was_on) }, { "measure", measure_seconds() or "-" } })
    S.settle_cb = function()
        S.settle_cb = nil
        if not S or not S.sleeping then return end
        if wifi_on() then wifi_off() end                 -- R-P5
        S.backend.suspend()                              -- Kindle: R-P9 hooks, powerButton, pump; others: KOReader suspends
    end
    ui:scheduleIn(M.SETTLE_S, S.settle_cb)
    return true
end

---------------------------------------------------------------- wake-ups (R-P7, R-P11, R-P12)

-- the process ran again after a suspend: wait a moment for powerd to settle, then classify
-- kind = "scheduled" when the backend already knows what woke the device (Kobo: KOReader's WakeupMgr ran our task),
-- which skips the wait and the classification
function M._woke(source, kind)
    if not S or not S.sleeping then return end
    local t = now()
    if S.wake_at and t - S.wake_at < M.CLASSIFY_S + 10 then return end   -- hook and gap both saw the same wake-up
    if S.busy then return end
    S.wake_at = t
    S.ss_since = nil
    S.wake_charge = charge()
    S.r2s_seen = false
    S.rtc_requests = 0
    log("woke (" .. tostring(source) .. ")")
    if kind == "scheduled" then return M._scheduled(nil) end
    local ui = dep("ui")
    if S.classify_cb then ui:unschedule(S.classify_cb) end
    S.classify_cb = function()
        S.classify_cb = nil
        if not S or not S.sleeping then return end
        local state = S.backend.state()
        local kind = S.host:classifyWakeup{ powerd_state = state, target = S.target, now = now() }
        log("wake-up is " .. kind .. " (powerd " .. tostring(state) .. ")")
        if kind == "button" then return M._button("classified") end
        if kind == "scheduled" then return M._scheduled(state) end
        return M._unscheduled(state)
    end
    ui:scheduleIn(M.CLASSIFY_S, S.classify_cb)
end

-- R-P12: powerd's own wake-up (06:10) or one we did not ask for: back to sleep, nothing else. A target in the
-- past (the scheduled wake-up never came) is moved forward, or rtcWakeup would fire again at once.
function M._unscheduled(state)
    local t = now()
    if S.target and S.target <= t then S.target = next_target(t); S.backend.retarget() end
    record("wake", { { "kind", "unscheduled" }, { "powerd", state }, { "charge", S.wake_charge },
        { "target", S.target and hms(S.target) or "never" } })
    S.wake_at = S.wake_at or t
end

-- R-P6, R-P3: Wi-Fi on, wait (30 s), refresh the sleep-page apps, redraw, Wi-Fi off; powerd suspends again by
-- itself and the pump requests the next wake-up when it reaches readyToSuspend.
function M._scheduled(state)
    local host = S.host
    local t0 = now()
    S.busy = true
    local ids, need_net = host:wakePlan(t0)
    local wifi_ok, wifi_s, opened = nil, 0, false
    local function finish()
        if not S or not S.sleeping then return end
        if opened then wifi_off() end
        -- awake-usb mode never suspends: a plain forced sample, not a suspend marker
        sample(host, S.awake_mode and "plain" or "sched")  -- battery log: end of this wake-up, before suspending again
        local t = now()
        S.updated_at = t
        S.target = next_target(t)
        S.backend.retarget()
        host:setSleepInfo(S.updated_at, S.target)
        host:drawSleep()                                 -- the redraw, full refresh
        pcall(dep("ui").forceRePaint, dep("ui"))
        S.busy = false
        S.last_tick = now()
        S.ss_since = nil
        S.backend.batch_done()
        record("wake", { { "kind", "scheduled" }, { "mode", S.awake_mode and "awake-usb" or "rtc" }, { "powerd_start", state }, { "apps", #ids },
            { "wifi", wifi_ok == nil and "not-needed" or (wifi_ok and "ok" or "timeout") }, { "wifi_s", wifi_s },
            { "work_s", t - t0 }, { "charge_wake", S.wake_charge }, { "charge_done", charge() },
            { "powerd_end", S.backend.state() }, { "next", S.target and hms(S.target) or "never" } })
        if wifi_ok == false then log("wifi did not connect in " .. wifi_s .. " s: sleep page redrawn with the old data") end
    end
    local function batch()
        if #ids == 0 then return finish() end
        host:sleepRefresh(ids, finish)
    end
    if need_net then
        opened = true
        wifi_up(math.max(host:wifiTimeout(), S.backend.wifi_timeout or 0), function(ok, waited)
            wifi_ok, wifi_s = ok, waited
            if ok then batch() else finish() end         -- fallback: old data, sleep again
        end)
    else
        batch()
    end
end

-- the power button (R-P7): back to the screen the Tinta had, normal use, preventScreenSaver restored (R-P9)
function M._button(source)
    if not S or not S.sleeping then return end
    local host = S.host
    log("button wake (" .. tostring(source) .. ")")
    S.backend.stop()
    S.sleeping = false
    S.busy = false
    S.backend.restore()
    record("wake", { { "kind", "button" }, { "source", source }, { "charge", charge() } })
    host.sleeping = false
    sample(host, "button")                               -- battery log: first sample after the button wake
    host:afterWake(S.wifi_was_on)
end

-- the Kindle never went to sleep: show the Tinta again (touch would otherwise be ignored on the sleep page)
function M._abort(why)
    if not S or not S.sleeping then return end
    log("abort: " .. why)
    record("abort", { { "why", why }, { "charge", charge() } })
    M._button("abort")
end

---------------------------------------------------------------- state for the tests

function M._state() return S end

return M
