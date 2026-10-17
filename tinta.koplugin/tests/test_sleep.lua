-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (C) 2026 Tinta contributors
-- device/sleep.lua with fakes for lipc, powerd, the UIManager scheduler, the clock, the network manager and the
-- host (no Kindle): entering sleep (R-P5, R-P9), the repeated rtcWakeup (R-P10), the three kinds of wake-up
-- (R-P11, R-P12, R-P3 fallback), the power button (R-P7), the abort and the lipc-set-prop fallback.
local T = ...
local Sleep = require("device/sleep")
local Power = require("core/power")
local eq, check = T.eq, T.check

local T0 = T.utc(2026, 10, 16, 10, 0)

-- a world: clock, scheduler, powerd, devices
local function world(opts)
    opts = opts or {}
    local W = { t = T0, tasks = {}, calls = {}, props = { preventScreenSaver = "0", state = "active" },
        orig_calls = {}, wifi = { on = false, connected = false, enable_calls = 0, disable_calls = 0 },
        host_calls = {}, files = {} }
    W.ui = {
        scheduleIn = function(_, d, fn) W.tasks[#W.tasks + 1] = { at = W.t + d, fn = fn } end,
        unschedule = function(_, fn)
            for i = #W.tasks, 1, -1 do if W.tasks[i].fn == fn then table.remove(W.tasks, i) end end
        end,
        forceRePaint = function() W.host_calls[#W.host_calls + 1] = "repaint" end,
    }
    function W.run_due()
        local progressed = true
        while progressed do
            progressed = false
            table.sort(W.tasks, function(a, b) return a.at < b.at end)
            if W.tasks[1] and W.tasks[1].at <= W.t then
                local task = table.remove(W.tasks, 1)
                task.fn()
                progressed = true
            end
        end
    end
    function W.advance(s)
        for _ = 1, s do
            W.t = W.t + 1
            if W.on_second then W.on_second(W.t) end
            W.run_due()
        end
    end
    -- powerd: state script
    W.handle = {
        get_string_property = function(_, _, prop) return W.props[prop] end,
        set_int_property = function(_, _, prop, v)
            W.calls[#W.calls + 1] = { prop, v }
            if prop == "powerButton" and W.props.state == "active" then
                W.props.state = "screenSaver"
                W.suspend_pressed_at = W.t
            end
            if prop == "rtcWakeup" then W.last_rtc = { at = W.t, secs = v } end
            return true
        end,
        set_string_property = function(_, _, prop, v)
            W.calls[#W.calls + 1] = { prop, v, "string" }
            W.props[prop] = tostring(v)
            return true
        end,
        close = function() W.handle_closed = true end,
    }
    if not opts.no_lipc then W.lipc_lib = { init = function() return W.handle end } end
    W.device = {
        screen_saver_mode = false,
        powerd = { beforeSuspend = function() W.orig_calls[#W.orig_calls + 1] = "beforeSuspend" end },
        intoScreenSaver = function(self) W.orig_calls[#W.orig_calls + 1] = "into"; self.screen_saver_mode = true end,
        outofScreenSaver = function(self) W.orig_calls[#W.orig_calls + 1] = "outof"; self.screen_saver_mode = false end,
        wakeupFromSuspend = function() W.orig_calls[#W.orig_calls + 1] = "wakeupFromSuspend" end,
    }
    W.network = {
        isWifiOn = function() return W.wifi.on end,
        isConnected = function() return W.wifi.connected end,
        enableWifi = function() W.wifi.enable_calls = W.wifi.enable_calls + 1; W.wifi.on = true
            if W.wifi.connect_after then W.wifi.connect_at = W.t + W.wifi.connect_after end end,
        disableWifi = function() W.wifi.disable_calls = W.wifi.disable_calls + 1; W.wifi.on = false; W.wifi.connected = false end,
    }
    W.shell = {}
    W.host = {
        sleeping = false,
        log = function() end,
        beforeSleep = function() W.host_calls[#W.host_calls + 1] = "beforeSleep" end,
        setSleepInfo = function(_, u, n) W.sleep_info = { u, n } end,
        drawSleep = function() W.host_calls[#W.host_calls + 1] = "draw" end,
        wakeTarget = function(_, from) if opts.never then return nil end return from + 1800 end,
        rtcSeconds = function(_, target, from) return Power.rtc_seconds(target, from) end,
        classifyWakeup = function(_, o) return Power.classify_wakeup(o) end,
        wakePlan = function() W.request = nil; return opts.plan_ids or { "alfa" }, opts.need_net ~= false end,
        nextWakeRequest = function(_, from) if W.request and W.request > from then return W.request end end,
        sleepRefresh = function(_, ids, done) W.refreshed = ids; W.host_calls[#W.host_calls + 1] = "refresh"; done() end,
        background = function(_, kind) W.bg = W.bg or {}; W.bg[#W.bg + 1] = kind end,
        wifiTimeout = function() return 30 end,
        afterWake = function(_, wifi) W.after_wake = { wifi = wifi }; W.host_calls[#W.host_calls + 1] = "afterWake" end,
    }
    W.log_path = os.tmpname()
    W.measure_path = os.tmpname()
    os.remove(W.measure_path)
    Sleep._set_deps({
        ui = W.ui, clock = function() return W.t end, lipc_lib = W.lipc_lib, device = W.device, network = W.network,
        logger = { info = function() end },
        read_file = function(path)
            if path:match("charge_now$") then return tostring(W.charge or 880) end
            local fh = io.open(path, "r")
            if not fh then return nil end
            local s = fh:read("*l"); fh:close(); return s
        end,
        exec = function(cmd)
            W.shell[#W.shell + 1] = cmd
            local prop = cmd:match("lipc%-get%-prop %S+ (%S+)")
            if prop then return (W.props[prop] or "") .. "\n" end
            local p, v = cmd:match("lipc%-set%-prop %-?i? ?%S+ (%S+) '([^']*)'")
            if p then
                W.props[p] = v
                if p == "powerButton" and W.props.state == "active" then
                    W.props.state = "screenSaver"; W.suspend_pressed_at = W.t
                end
                if p == "rtcWakeup" then W.last_rtc = { at = W.t, secs = tonumber(v) } end
            end
            return ""
        end,
    })
    return W
end

local function calls_of(W, prop)
    local out = {}
    for _, c in ipairs(W.calls) do if c[1] == prop then out[#out + 1] = c[2] end end
    return out
end
local function count(list, name) local n = 0; for _, v in ipairs(list) do if v == name then n = n + 1 end end; return n end
local function slurp(path) local fh = io.open(path); if not fh then return "" end; local s = fh:read("*a"); fh:close(); return s end

-- the Kindle "suspends" 4 s after readyToSuspend with an rtcWakeup in place, and wakes at target - 6 s (R-P10)
local function install_powerd(W)
    W.on_second = function(t)
        if W.props.state == "screenSaver" and not W.usb and W.suspend_pressed_at and t - W.suspend_pressed_at >= 3 then
            W.props.state = "readyToSuspend"
            W.r2s_at = t
        end
        if W.props.state == "readyToSuspend" and W.r2s_at and t - W.r2s_at >= 6 and not W.suspended then
            -- suspend: the clock jumps to the requested wake-up
            if W.last_rtc then
                W.suspended = true
                W.suspend_log = { from = t, secs = W.last_rtc.secs, at = W.last_rtc.at }
                W.t = W.last_rtc.at + W.last_rtc.secs - 6
                W.props.state = "screenSaver"
                W.suspended = false
                W.r2s_at = nil
                W.suspend_pressed_at = W.resuspend and W.t or nil     -- powerd goes back to suspend by itself
                W.woke_count = (W.woke_count or 0) + 1
                W.last_rtc = nil
                W.device:wakeupFromSuspend()
            end
        end
        if W.wifi.connect_at and W.t >= W.wifi.connect_at and W.wifi.on then W.wifi.connected = true; W.wifi.connect_at = nil end
    end
end

---------------------------------------------------------------- attach / detach (R-P9)

do
    local W = world()
    Sleep.attach(W.host, { log_path = W.log_path })
    eq("attach: preventScreenSaver held at 1 while awake", W.props.preventScreenSaver, "1")
    check("attach: set through liblipclua (string property)", W.calls[1] and W.calls[1][1] == "preventScreenSaver" and W.calls[1][3] == "string")
    check("attach: sets Host.enter_sleep", type(W.host.enter_sleep) == "function")
    Sleep.detach()
    eq("detach: the remembered value is restored", W.props.preventScreenSaver, "0")
    eq("detach: enter_sleep removed", W.host.enter_sleep, nil)
    check("detach: lipc handle closed", W.handle_closed == true)
    check("detach: state cleared", Sleep._state() == nil)
end

---------------------------------------------------------------- enter (R-P5, R-P9)

do
    local W = world()
    W.wifi.on, W.wifi.connected = true, true
    Sleep.attach(W.host, { log_path = W.log_path })
    local ok = Sleep.enter("now")
    check("enter: ok", ok == true)
    check("enter: menus and dialogs closed first", W.host_calls[1] == "beforeSleep")
    check("enter: sleep page drawn", count(W.host_calls, "draw") == 1 and W.host.sleeping == true)
    eq("enter: status bar info (updated, next)", W.sleep_info[2] - W.sleep_info[1], 1800)
    check("enter: active", Sleep.active())
    eq("enter: twice is ignored", select(2, Sleep.enter("now")), "already")
    eq("enter: nothing happens before the page settled", #calls_of(W, "powerButton"), 0)
    W.advance(Sleep.SETTLE_S)
    eq("enter: Wi-Fi turned off (R-P5)", W.wifi.disable_calls, 1)
    eq("enter: preventScreenSaver 0 (R-P9)", W.props.preventScreenSaver, "0")
    eq("enter: powerButton 1 sent once", table.concat(calls_of(W, "powerButton"), ","), "1")
    check("enter: KOReader's screensaver is wrapped", W.device.intoScreenSaver ~= nil and rawget(W.device, "intoScreenSaver") ~= nil)
    W.device:intoScreenSaver()
    check("enter: intoScreenSaver does not draw the screensaver while sleeping",
        count(W.orig_calls, "into") == 0 and count(W.orig_calls, "beforeSuspend") == 1 and W.device.screen_saver_mode == true)
    check("enter: log has the sleep line", slurp(W.log_path):match("sleep reason=now") ~= nil)
    Sleep.detach()
end

---------------------------------------------------------------- R-P10: rtcWakeup repeated

do
    local W = world()
    install_powerd(W)
    Sleep.attach(W.host, { log_path = W.log_path })
    Sleep.enter("now")
    local target = Sleep._state().target
    W.advance(Sleep.SETTLE_S + 3)
    eq("rtc: not before readyToSuspend", #calls_of(W, "rtcWakeup"), 0)
    W.props.state = "readyToSuspend"; W.r2s_at = W.t
    W.advance(Sleep.PUMP_S * 3 - 1)
    local secs = calls_of(W, "rtcWakeup")
    check("rtc: requested again every 2 s", #secs >= 2, #secs)
    check("rtc: seconds count down to the same target (2 s apart)", secs[1] - secs[2] == 2, table.concat(secs, ","))
    check("rtc: never beyond the target", secs[1] <= target - T0)
    Sleep.detach()
end

---------------------------------------------------------------- scheduled wake-up (R-P6, R-P3)

do
    local W = world()
    install_powerd(W)
    W.wifi.connect_after = 5
    Sleep.attach(W.host, { log_path = W.log_path })
    Sleep.enter("now")
    local target = Sleep._state().target
    W.advance(1800)         -- through suspend and the wake-up
    check("scheduled: woke once", W.woke_count == 1, W.woke_count)
    W.advance(Sleep.CLASSIFY_S + 12)
    check("scheduled: Wi-Fi turned on", W.wifi.enable_calls == 1)
    eq("scheduled: sleep-page apps refreshed", table.concat(W.refreshed or {}, ","), "alfa")
    do
        local ri, di
        for i, c in ipairs(W.host_calls) do
            if c == "refresh" then ri = i end
            if c == "draw" then di = i end
        end
        check("scheduled: sleep page redrawn after the refresh", ri ~= nil and di ~= nil and di > ri)
    end
    eq("scheduled: Wi-Fi off again after the batch", W.wifi.disable_calls, 1)
    eq("scheduled: powerButton pressed only on entering (powerd state untouched)", #calls_of(W, "powerButton"), 1)
    check("scheduled: still asleep (the Tinta is not shown)", Sleep.active() and W.after_wake == nil)
    check("scheduled: next target moved forward", Sleep._state().target > target)
    local log = slurp(W.log_path)
    check("scheduled: log line with wifi ok and charge", log:match("wake kind=scheduled") and log:match("wifi=ok") and log:match("charge_done=880"))
    Sleep.detach()
end

-- Wi-Fi never connects: old data, sleep again (R-P3 fallback)
do
    local W = world()
    install_powerd(W)
    Sleep.attach(W.host, { log_path = W.log_path })
    Sleep.enter("now")
    W.advance(1800)
    W.advance(Sleep.CLASSIFY_S + 40)
    check("wifi timeout: Wi-Fi was started", W.wifi.enable_calls == 1)
    check("wifi timeout: no refresh", W.refreshed == nil)
    check("wifi timeout: sleep page redrawn with the old data", count(W.host_calls, "draw") >= 2)
    eq("wifi timeout: Wi-Fi off again", W.wifi.disable_calls, 1)
    check("wifi timeout: logged", slurp(W.log_path):match("wifi=timeout") ~= nil)
    check("wifi timeout: still asleep, not busy", Sleep.active() and not Sleep._state().busy)
    Sleep.detach()
end

-- only local apps on the sleep page: no Wi-Fi at all
do
    local W = world({ need_net = false })
    install_powerd(W)
    Sleep.attach(W.host, { log_path = W.log_path })
    Sleep.enter("now")
    W.advance(1800 + Sleep.CLASSIFY_S + 5)
    eq("local only: Wi-Fi never turned on", W.wifi.enable_calls, 0)
    eq("local only: apps refreshed", table.concat(W.refreshed or {}, ","), "alfa")
    Sleep.detach()
end

---------------------------------------------------------------- unscheduled wake-up (R-P12)

do
    local W = world()
    install_powerd(W)
    Sleep.attach(W.host, { log_path = W.log_path })
    Sleep.enter("now")
    local target = Sleep._state().target
    W.advance(Sleep.SETTLE_S + 8)
    -- powerd's own 06:10 wake-up, far from the target: the clock jumps and no rtc was involved
    W.t = W.t + 600
    W.props.state = "screenSaver"
    W.device:wakeupFromSuspend()
    W.advance(Sleep.CLASSIFY_S + 2)
    check("unscheduled: no Wi-Fi, no refresh, no redraw",
        W.wifi.enable_calls == 0 and W.refreshed == nil and count(W.host_calls, "draw") == 1)
    check("unscheduled: still asleep, afterWake not called", Sleep.active() and W.after_wake == nil)
    eq("unscheduled: target unchanged", Sleep._state().target, target)
    check("unscheduled: logged", slurp(W.log_path):match("wake kind=unscheduled") ~= nil)
    Sleep.detach()
end

-- a target already in the past is moved forward (or rtcWakeup would fire again at once)
do
    local W = world()
    install_powerd(W)
    Sleep.attach(W.host, { log_path = W.log_path })
    Sleep.enter("now")
    W.advance(Sleep.SETTLE_S + 8)
    W.t = Sleep._state().target + 600
    W.props.state = "screenSaver"
    W.device:wakeupFromSuspend()
    W.advance(Sleep.CLASSIFY_S + 2)
    check("past target: moved forward after an unscheduled wake-up", Sleep._state().target > W.t)
    Sleep.detach()
end

---------------------------------------------------------------- button (R-P7, R-P9)

do
    local W = world()
    install_powerd(W)
    W.wifi.on, W.wifi.connected = true, true
    local orig = { W.device.intoScreenSaver, W.device.outofScreenSaver, W.device.wakeupFromSuspend }
    Sleep.attach(W.host, { log_path = W.log_path })
    Sleep.enter("now")
    W.advance(Sleep.SETTLE_S + 8)
    eq("button: prevent is 0 while asleep", W.props.preventScreenSaver, "0")
    W.props.state = "active"
    W.device:outofScreenSaver()
    check("button: KOReader's own outofScreenSaver ran first", count(W.orig_calls, "outof") == 1)
    check("button: normal use again", not Sleep.active() and W.host.sleeping == false and W.after_wake ~= nil)
    eq("button: preventScreenSaver back to 1 (R-P9)", W.props.preventScreenSaver, "1")
    eq("button: Wi-Fi state before sleeping is handed back (R-P2)", W.after_wake.wifi, true)
    check("button: hooks removed (KOReader's methods are back)", W.device.intoScreenSaver == orig[1]
        and W.device.outofScreenSaver == orig[2] and W.device.wakeupFromSuspend == orig[3])
    check("button: pump stopped", #W.tasks == 0 or (function() for _, t in ipairs(W.tasks) do if t.at < W.t + 3600 then return false end end return true end)())
    check("button: logged", slurp(W.log_path):match("wake kind=button") ~= nil)
    Sleep.detach()
    eq("button then close: the original preventScreenSaver is restored", W.props.preventScreenSaver, "0")
end

-- the same through the pump when OutOfSS was missed (powerd left screenSaver for active)
do
    local W = world()
    install_powerd(W)
    Sleep.attach(W.host, { log_path = W.log_path })
    Sleep.enter("now")
    W.advance(Sleep.SETTLE_S + 8)
    W.props.state = "active"
    W.advance(Sleep.PUMP_S + 1)
    check("button (pump): back to normal use", not Sleep.active() and W.after_wake ~= nil)
    Sleep.detach()
end

-- the button during a scheduled wake-up's Wi-Fi wait: the batch stops, the Tinta is back
do
    local W = world()
    install_powerd(W)
    Sleep.attach(W.host, { log_path = W.log_path })
    Sleep.enter("now")
    for _ = 1, 200 do if Sleep._state().busy then break end; W.advance(1) end
    W.advance(5)
    check("button mid-wake: waiting for Wi-Fi", Sleep._state().busy == true)
    W.props.state = "active"
    W.device:outofScreenSaver()
    W.advance(60)
    check("button mid-wake: tinta back, no refresh afterwards", not Sleep.active() and W.refreshed == nil and W.after_wake ~= nil)
    Sleep.detach()
end

---------------------------------------------------------------- abort when the Kindle does not suspend

do
    local W = world()
    -- powerd ignores the button (state stays active)
    W.handle.set_int_property = function(_, _, prop, v) W.calls[#W.calls + 1] = { prop, v }; return true end
    Sleep.attach(W.host, { log_path = W.log_path })
    Sleep.enter("now")
    W.advance(Sleep.SETTLE_S + Sleep.ABORT_S + 4)
    check("abort: back to the Tinta when powerd stays active", not Sleep.active() and W.after_wake ~= nil)
    eq("abort: preventScreenSaver restored", W.props.preventScreenSaver, "1")
    check("abort: logged", slurp(W.log_path):match("abort why=") ~= nil)
    Sleep.detach()
end

---------------------------------------------------------------- measurement mode and "never"

do
    local W = world()
    local fh = io.open(W.measure_path, "w"); fh:write("120\n"); fh:close()
    Sleep.attach(W.host, { log_path = W.log_path, measure_path = W.measure_path })
    Sleep.enter("now")
    eq("measure: wake-ups every N s", Sleep._state().target, T0 + 120)
    Sleep.detach()
    fh = io.open(W.measure_path, "w"); fh:write("5"); fh:close()
    Sleep.attach(W.host, { log_path = W.log_path, measure_path = W.measure_path })
    Sleep.enter("now")
    eq("measure: clamped to the minimum", Sleep._state().target, T0 + Sleep.MEASURE_MIN)
    Sleep.detach()
    os.remove(W.measure_path)
end

do
    local W = world({ never = true })
    install_powerd(W)
    Sleep.attach(W.host, { log_path = W.log_path })
    Sleep.enter("idle")
    W.advance(Sleep.SETTLE_S + 12)
    eq("never: no rtcWakeup is requested", #calls_of(W, "rtcWakeup"), 0)
    check("never: logged as never", slurp(W.log_path):match("target=never") ~= nil)
    Sleep.detach()
end

---------------------------------------------------------------- lipc-set-prop fallback (no liblipclua)

do
    local W = world({ no_lipc = true })
    W.props.preventScreenSaver = "1"
    install_powerd(W)
    Sleep.attach(W.host, { log_path = W.log_path })
    Sleep.enter("now")
    W.advance(Sleep.SETTLE_S + 2)
    local sh = table.concat(W.shell, "\n")
    check("shell: preventScreenSaver through lipc-set-prop", sh:find("lipc-set-prop com.lab126.powerd preventScreenSaver '0'", 1, true) ~= nil)
    check("shell: powerButton as an int", sh:find("lipc-set-prop -i com.lab126.powerd powerButton '1'", 1, true) ~= nil)
    W.advance(10)
    sh = table.concat(W.shell, "\n")
    check("shell: state read through lipc-get-prop", sh:find("lipc-get-prop com.lab126.powerd state", 1, true) ~= nil)
    check("shell: rtcWakeup requested as an int", sh:find("lipc-set-prop -i com.lab126.powerd rtcWakeup '", 1, true) ~= nil)
    Sleep.detach()
    eq("shell: preventScreenSaver restored", W.props.preventScreenSaver, "1")
end

---------------------------------------------------------------- wake requests (11.7, ctx.wake_at): min(schedule, request)

eq("earliest: both", Sleep.earliest(5, 3), 3)
eq("earliest: only a", Sleep.earliest(5, nil), 5)
eq("earliest: only b", Sleep.earliest(nil, 7), 7)
eq("earliest: none", Sleep.earliest(nil, nil), nil)

do
    local W = world()
    W.wifi.connect_after = 5
    W.request = T0 + 300                       -- the Timer ends in 5 min, the schedule says 30
    install_powerd(W)
    Sleep.attach(W.host, { log_path = W.log_path })
    Sleep.enter("now")
    eq("request: comes first, it is the target", Sleep._state().target, T0 + 300)
    eq("request: status bar shows it as the next wake-up", W.sleep_info[2], T0 + 300)
    W.advance(Sleep.SETTLE_S + 3)
    W.props.state = "readyToSuspend"; W.r2s_at = W.t
    W.advance(Sleep.PUMP_S * 2)
    local secs = calls_of(W, "rtcWakeup")
    check("request: rtcWakeup counts down to the request", #secs >= 1 and secs[1] <= 300, table.concat(secs, ","))
    W.advance(400)
    check("request: woke at the request", W.woke_count == 1, W.woke_count)
    W.advance(Sleep.CLASSIFY_S + 12)
    check("request: classified as the scheduled wake-up (batch ran)", W.refreshed ~= nil)
    check("request: after the batch the target is the schedule's again", Sleep._state().target >= T0 + 1800 - 5,
        Sleep._state().target - T0)
    Sleep.detach()
end

do
    local W = world()
    W.request = T0 + 7200                      -- later than the schedule: the schedule wins
    Sleep.attach(W.host, { log_path = W.log_path })
    Sleep.enter("now")
    eq("request later than the schedule is ignored", Sleep._state().target, T0 + 1800)
    Sleep.detach()
end

do
    local W = world({ never = true })          -- "never wakes", but a request still wakes it
    W.request = T0 + 600
    Sleep.attach(W.host, { log_path = W.log_path })
    Sleep.enter("now")
    eq("request with wake = never", Sleep._state().target, T0 + 600)
    Sleep.detach()
end

do
    local W = world()
    local fh = io.open(W.measure_path, "w"); fh:write("300\n"); fh:close()
    W.request = T0 + 100
    Sleep.attach(W.host, { log_path = W.log_path, measure_path = W.measure_path })
    Sleep.enter("now")
    eq("request wins over the measure file too", Sleep._state().target, T0 + 100)
    Sleep.detach()
    os.remove(W.measure_path)
end

do
    local W = world()
    W.host.nextWakeRequest = nil               -- a host without the hook keeps working
    Sleep.attach(W.host, { log_path = W.log_path })
    Sleep.enter("now")
    eq("no hook: the schedule", Sleep._state().target, T0 + 1800)
    Sleep.detach()
end

---------------------------------------------------------------- USB: powerd never suspends (awake-usb mode)

do
    local W = world()
    W.usb = true
    W.wifi.connect_after = 5
    install_powerd(W)
    Sleep.attach(W.host, { log_path = W.log_path })
    Sleep.enter("idle")
    local target = Sleep._state().target
    eq("usb: target is the schedule's", target, T0 + 1800)
    W.advance(Sleep.SETTLE_S + 30)
    eq("usb: powerd is stuck in screenSaver", W.props.state, "screenSaver")
    check("usb: not in awake mode before the wait", Sleep._state().awake_mode == false)
    W.advance(Sleep.USB_WAIT_S)
    check("usb: awake mode after USB_WAIT_S", Sleep._state().awake_mode == true)
    check("usb: logged as sleep mode=awake-usb", slurp(W.log_path):match("sleep mode=awake%-usb") ~= nil)
    eq("usb: no rtcWakeup was ever requested", #calls_of(W, "rtcWakeup"), 0)
    check("usb: still the sleep page, nothing refreshed yet", W.refreshed == nil and Sleep.active())
    W.advance(target - W.t - 1)
    check("usb: nothing before the target", W.refreshed == nil)
    W.advance(Sleep.WIFI_POLL_S + 12)
    eq("usb: the batch ran at the target without a suspend", table.concat(W.refreshed or {}, ","), "alfa")
    eq("usb: Wi-Fi turned on and off again", W.wifi.enable_calls .. "/" .. W.wifi.disable_calls, "1/1")
    check("usb: sleep page redrawn after the refresh", (function()
        local ri, di
        for i, c in ipairs(W.host_calls) do if c == "refresh" then ri = i end; if c == "draw" then di = i end end
        return ri ~= nil and di ~= nil and di > ri
    end)())
    check("usb: still asleep, the Tinta is not shown", Sleep.active() and W.after_wake == nil)
    local t2 = Sleep._state().target
    check("usb: next target moved forward", t2 > target, t2 - target)
    check("usb: log says awake-usb on the wake line", slurp(W.log_path):match("wake kind=scheduled mode=awake%-usb") ~= nil)
    eq("usb: the clock never jumped (no suspend)", W.woke_count, nil)
    -- the second round is driven by the timer again
    W.refreshed = nil
    W.advance(t2 - W.t + 15)
    check("usb: second scheduled batch", W.refreshed ~= nil)
    -- the cable comes out: powerd reaches readyToSuspend, the RTC pump takes over
    W.usb = false
    W.props.state = "readyToSuspend"; W.r2s_at = W.t
    W.advance(Sleep.PUMP_S * 2 + 1)
    check("usb: back to the RTC pump", Sleep._state().awake_mode == false and #calls_of(W, "rtcWakeup") >= 1)
    check("usb: the awake timer is gone", Sleep._state().awake_cb == nil)
    check("usb: logged the switch", slurp(W.log_path):match("sleep mode=rtc") ~= nil)
    Sleep.detach()
end

-- a wake request (the Timer) before the schedule also drives the awake-usb batch, once
do
    local W = world()
    W.usb = true
    W.wifi.connect_after = 5
    W.request = T0 + 300
    install_powerd(W)
    Sleep.attach(W.host, { log_path = W.log_path })
    Sleep.enter("idle")
    eq("usb+request: target is the request", Sleep._state().target, T0 + 300)
    W.advance(299)
    check("usb+request: not yet", W.refreshed == nil)
    W.advance(20)
    check("usb+request: the batch ran at the request", W.refreshed ~= nil)
    check("usb+request: the request was consumed, target back to the schedule", Sleep._state().target >= T0 + 1800, Sleep._state().target - T0)
    Sleep.detach()
end

-- the power button still wakes the Tinta in awake-usb mode, and detaching stops the timer
do
    local W = world()
    W.usb = true
    install_powerd(W)
    Sleep.attach(W.host, { log_path = W.log_path })
    Sleep.enter("idle")
    W.advance(Sleep.SETTLE_S + Sleep.USB_WAIT_S + 6)
    check("usb+button: in awake mode", Sleep._state().awake_mode == true)
    W.props.state = "active"
    W.advance(Sleep.PUMP_S + 1)
    check("usb+button: the button woke the tinta", W.after_wake ~= nil and not Sleep.active())
    check("usb+button: the awake timer is stopped", Sleep._state() ~= nil and Sleep._state().awake_cb == nil)
    Sleep.detach()
end

-- a normal (RTC) sleep never enters awake mode, even across several wake-ups
do
    local W = world()
    W.wifi.connect_after = 5
    W.resuspend = true
    install_powerd(W)
    Sleep.attach(W.host, { log_path = W.log_path })
    Sleep.enter("now")
    W.advance(1800 * 2 + 200)
    check("rtc: scheduled wake-ups happened", (W.woke_count or 0) >= 2, W.woke_count)
    check("rtc: never in awake mode", Sleep._state().awake_mode == false and slurp(W.log_path):match("awake%-usb") == nil)
    Sleep.detach()
end

---------------------------------------------------------------- battery log hooks (10.3): one sample per hook point

do
    local W = world()
    W.wifi.connect_after = 5
    install_powerd(W)
    Sleep.attach(W.host, { log_path = W.log_path })
    Sleep.enter("now")
    eq("log hook: sleep entry writes one sample", table.concat(W.bg or {}, ","), "sleep")
    check("log hook: the sample comes before the sleep page / Wi-Fi off", W.wifi.disable_calls == 0)
    W.advance(1800)
    W.advance(Sleep.CLASSIFY_S + 12)
    eq("log hook: a scheduled wake adds one sample at its end", table.concat(W.bg, ","), "sleep,sched")
    Sleep.detach()
end

do
    local W = world()
    install_powerd(W)
    Sleep.attach(W.host, { log_path = W.log_path })
    Sleep.enter("now")
    W.advance(Sleep.SETTLE_S + 8)
    W.props.state = "active"
    W.device:wakeupFromSuspend()
    W.advance(Sleep.CLASSIFY_S + 2)
    check("log hook: button wake writes one sample, before the Tinta comes back",
        table.concat(W.bg or {}, ",") == "sleep,button" and W.after_wake ~= nil, table.concat(W.bg or {}, ","))
    Sleep.detach()
end

-- a host without the hook (or one whose hook raises) never stops sleeping
do
    local W = world()
    install_powerd(W)
    W.host.background = function() error("boom") end
    Sleep.attach(W.host, { log_path = W.log_path })
    check("log hook: a failing hook does not stop entering sleep", Sleep.enter("now") == true and Sleep.active())
    Sleep.detach()
end

Sleep._set_deps(nil)
