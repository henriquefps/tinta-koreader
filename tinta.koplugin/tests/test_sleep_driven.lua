-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (C) 2026 Tinta contributors
-- device/sleep.lua over the Kobo and generic backends (EXPERIMENTAL, untested on hardware). The fakes are modelled on
-- KOReader v2025.04: UIManager (scheduleIn / unschedule / suspend), generic Device:onPowerEvent + Kobo:suspend,
-- _doSuspend, resume, rescheduleSuspend, checkUnexpectedWakeup, WakeupMgr (task queue, dodgy_rtc chain,
-- wakeupAction proximity), Screensaver (setup/show/close), the autosuspend plugin (PluginShare.pause_auto_suspend) and
-- NetworkMgr. The device "suspends" inside _doSuspend; the test wakes it by RTC (clock jumps to the alarm) or by the
-- power button.
local T = ...
local Sleep = require("device/sleep")
local Battery = require("device/battery")
local Power = require("core/power")
local eq, check = T.eq, T.check

local T0 = T.utc(2026, 10, 16, 10, 0)

local function world(kind, opts)
    opts = opts or {}
    local W = { t = T0, tasks = {}, calls = {}, host_calls = {}, wifi = { on = false, connected = false, enable_calls = 0, disable_calls = 0 },
        suspends = 0, screensaver_drawn = 0, auto_suspends = 0 }
    W.ui = {}
    function W.ui:scheduleIn(d, fn, ...)
        local args = { n = select("#", ...), ... }
        W.tasks[#W.tasks + 1] = { at = W.t + d, fn = fn, args = args }
    end
    function W.ui:unschedule(fn)
        local found = false
        for i = #W.tasks, 1, -1 do if W.tasks[i].fn == fn then table.remove(W.tasks, i); found = true end end
        return found
    end
    function W.ui:nextTick(fn, ...) self:scheduleIn(0, fn, ...) end
    function W.ui:forceRePaint() W.host_calls[#W.host_calls + 1] = "repaint" end
    function W.ui:suspend() self:nextTick(W.handlers.Suspend) end
    function W.run_due()
        local progressed = true
        while progressed do
            progressed = false
            table.sort(W.tasks, function(a, b) return a.at < b.at end)
            if W.tasks[1] and W.tasks[1].at <= W.t and not W.suspended then
                local task = table.remove(W.tasks, 1)
                task.fn(unpack(task.args, 1, task.args.n))
                progressed = true
            end
        end
    end
    function W.advance(s)
        for _ = 1, s do
            W.t = W.t + 1
            if W.wifi.connect_at and W.t >= W.wifi.connect_at and W.wifi.on then W.wifi.connected = true; W.wifi.connect_at = nil end
            W.run_due()
        end
    end

    -- WakeupMgr (frontend/device/wakeupmgr.lua), the RTC itself reduced to "the alarm epoch"
    local WM = { _task_queue = {}, dodgy_rtc = opts.dodgy_rtc }
    function WM.DummyTaskCallback() end
    function WM:setWakeupAlarm(epoch) W.alarm = epoch end
    function WM:addTask(seconds, callback)
        assert(type(seconds) == "number" and type(callback) == "function")
        local old = (self._task_queue[1] or {}).epoch
        if self.dodgy_rtc and seconds > 0xFFFF then
            local left = seconds
            while left > 0 do
                table.insert(self._task_queue, { epoch = W.t + left, callback = left == seconds and callback or self.DummyTaskCallback })
                left = left - 0xFFFF
            end
        else
            table.insert(self._task_queue, { epoch = W.t + seconds, callback = callback })
        end
        table.sort(self._task_queue, function(a, b) return a.epoch < b.epoch end)
        local new = self._task_queue[1].epoch
        if not old or new < old then self:setWakeupAlarm(new) end
    end
    function WM:removeTasks(epoch, callback)
        if #self._task_queue == 0 then return end
        local removed, reschedule, match_epoch = false, false, epoch
        for k = #self._task_queue, 1, -1 do
            local v = self._task_queue[k]
            if (epoch == v.epoch or callback == v.callback) or
               (self.dodgy_rtc and match_epoch and self.DummyTaskCallback == v.callback and v.epoch < match_epoch) then
                if not match_epoch then match_epoch = v.epoch end
                table.remove(self._task_queue, k)
                removed = true
                if k == 1 then reschedule = true end
            end
        end
        if reschedule and self._task_queue[1] then self:setWakeupAlarm(self._task_queue[1].epoch) end
        return removed
    end
    function WM:isWakeupAlarmScheduled() return #self._task_queue > 0 end
    function WM:wakeupAction(proximity)
        local task = self._task_queue[1]
        if not task then return nil end
        if math.abs(W.t - task.epoch) <= proximity then
            task.callback()
            table.remove(self._task_queue, 1)
            if self._task_queue[1] then self:setWakeupAlarm(self._task_queue[1].epoch) end
            return true
        end
        return false
    end
    W.wm = WM

    -- Screensaver (frontend/ui/screensaver.lua), only what the suspend path touches
    W.screensaver = {
        setup = function() end,
        show = function() W.screensaver_drawn = W.screensaver_drawn + 1; W.device.screen_saver_mode = true end,
        close = function() W.device.screen_saver_mode = false end,
    }
    W.screensaver_orig = { setup = W.screensaver.setup, show = W.screensaver.show }

    -- Device: generic/device.lua onPowerEvent + kobo/device.lua suspend / resume / wakeup guard
    local D = { screen_saver_mode = false, suspend_wait_timeout = 15, wakeup_mgr = kind == "kobo" and WM or nil,
        can_suspend = opts.cannot_suspend ~= true }
    W.device = D
    D.powerd = { beforeSuspend = function() W.calls[#W.calls + 1] = "beforeSuspend" end,
        afterResume = function() W.calls[#W.calls + 1] = "afterResume" end,
        getCapacity = function() return W.pct or 70 end,
        isCharging = function() return W.charging == true end,
        isCharged = function() return false end }
    function D:isKindle() return false end
    function D:isKobo() return kind == "kobo" end
    function D:canSuspend() return self.can_suspend end
    function D:getPowerDevice() return self.powerd end
    function D:rescheduleSuspend()
        W.ui:unschedule(self.suspend); W.ui:unschedule(self._doSuspend); W.ui:unschedule(self.checkUnexpectedWakeup)
        W.ui:scheduleIn(self.suspend_wait_timeout, self.suspend, self)
    end
    function D:onPowerEvent(ev)
        if self.screen_saver_mode then
            if ev == "Power" or ev == "Resume" then
                W.ui:unschedule(self.suspend)
                self:resume()
                W.screensaver:close()
                self.powerd:afterResume()
            elseif ev == "Suspend" then
                if W.wifi.on then W.network:disableWifi() end
                self:rescheduleSuspend()
            end
        elseif ev == "Power" or ev == "Suspend" then
            W.screensaver:setup(); W.screensaver:show()
            W.ui:forceRePaint()
            if W.wifi.on then W.network:disableWifi() end
            self.powerd:beforeSuspend()
            self:rescheduleSuspend()
        end
    end
    function D:suspend()
        if W.wifi.on then W.network:disableWifi() end
        W.ui:unschedule(self.checkUnexpectedWakeup)
        W.ui:scheduleIn(2, self._doSuspend, self)
    end
    function D:_doSuspend()
        W.suspends = W.suspends + 1
        W.suspended = true           -- the process is frozen here until a wake-up
    end
    function D:scheduleUnexpectedWakeupGuard() W.ui:scheduleIn(15, self.checkUnexpectedWakeup, self) end
    function D:checkUnexpectedWakeup()
        W.ui:unschedule(self.suspend)
        if self.wakeup_mgr and self.wakeup_mgr:isWakeupAlarmScheduled() and self.wakeup_mgr:wakeupAction(30) then
            W.ui:scheduleIn(30, self.suspend, self)
        end
    end
    function D:resume()
        W.ui:unschedule(self.checkUnexpectedWakeup); W.ui:unschedule(self.suspend); W.ui:unschedule(self._doSuspend)
        W.calls[#W.calls + 1] = "resume"
    end
    -- the process runs again: by the RTC alarm (no input event) or by the power button (Power event)
    function W.wake_rtc()
        assert(W.suspended and W.alarm, "wake_rtc needs a suspended device with an alarm")
        W.t = math.max(W.t, W.alarm)
        W.suspended = false
        D:scheduleUnexpectedWakeupGuard()      -- Kobo:_doSuspend ends with this
        W.run_due()
    end
    function W.wake_button()
        W.suspended = false
        D:scheduleUnexpectedWakeupGuard()
        W.handlers.Power()
        W.run_due()
    end
    W.handlers = {
        Suspend = function() D:onPowerEvent("Suspend") end,
        Power = function() D:onPowerEvent("Power") end,
        UsbPlugIn = function() end, UsbPlugOut = function() end, Charging = function() end, NotCharging = function() end,
    }
    W.handlers_orig = {}
    for k, v in pairs(W.handlers) do W.handlers_orig[k] = v end

    W.network = {
        isWifiOn = function() return W.wifi.on end,
        isConnected = function() return W.wifi.connected end,
        enableWifi = function() W.wifi.enable_calls = W.wifi.enable_calls + 1; W.wifi.on = true
            if W.wifi.connect_after then W.wifi.connect_at = W.t + W.wifi.connect_after end end,
        disableWifi = function() W.wifi.disable_calls = W.wifi.disable_calls + 1; W.wifi.on = false; W.wifi.connected = false end,
    }

    -- the autosuspend plugin (plugins/autosuspend.koplugin/main.lua), the part that matters: once the idle timeout is
    -- past it suspends, unless PluginShare.pause_auto_suspend (or charging)
    W.pluginshare = {}
    function W.autosuspend_check(idle_s)
        if W.pluginshare.pause_auto_suspend or W.charging then return false end
        if idle_s >= 60 * 60 then W.auto_suspends = W.auto_suspends + 1; W.ui:suspend(); return true end
        return false
    end

    W.host = {
        sleeping = false,
        log = function() end,
        beforeSleep = function() W.host_calls[#W.host_calls + 1] = "beforeSleep" end,
        setSleepInfo = function(_, u, n) W.sleep_info = { u, n } end,
        drawSleep = function() W.host_calls[#W.host_calls + 1] = "draw" end,
        wakeTarget = function(_, from) return from + 1800 end,
        rtcSeconds = function(_, target, from) return Power.rtc_seconds(target, from) end,
        classifyWakeup = function(_, o) return Power.classify_wakeup(o) end,
        wakePlan = function() return opts.plan_ids or { "alfa" }, opts.need_net ~= false end,
        sleepRefresh = function(_, ids, done) W.refreshed = ids; W.host_calls[#W.host_calls + 1] = "refresh"; done() end,
        wifiTimeout = function() return 30 end,
        afterWake = function(_, wifi) W.after_wake = { wifi = wifi }; W.host_calls[#W.host_calls + 1] = "afterWake" end,
    }
    W.log_path = os.tmpname()
    Sleep._set_deps({
        ui = W.ui, clock = function() return W.t end, device = W.device, network = W.network,
        pluginshare = W.pluginshare, screensaver = W.screensaver, logger = { info = function() end },
        read_file = function() return nil end, exec = function() return "" end,
    })
    return W
end

local function count(list, name) local n = 0; for _, v in ipairs(list) do if v == name then n = n + 1 end end; return n end
local function slurp(path) local fh = io.open(path); if not fh then return "" end; local s = fh:read("*a"); fh:close(); return s end

---------------------------------------------------------------- Kobo: attach, autosuspend, the awake power button

do
    -- control: without the Tinta, an idle device is suspended by the autosuspend plugin with KOReader's screensaver
    local C = world("kobo")
    check("control: autosuspend suspends an idle device when nothing pauses it", C.autosuspend_check(3600) == true)
    C.advance(25)
    check("control: ... and draws KOReader's own screensaver, not the tinta's page", C.suspends == 1 and C.screensaver_drawn == 1)
end

do
    local W = world("kobo")
    W.pluginshare.pause_auto_suspend = false
    local orig_power_event = W.device.onPowerEvent
    local orig_resume = W.device.resume
    Sleep.attach(W.host, { log_path = W.log_path })
    eq("kobo attach: backend", Sleep._state().backend.name, "kobo")
    eq("kobo attach: PluginShare.pause_auto_suspend set (no double suspend)", W.pluginshare.pause_auto_suspend, true)
    check("kobo attach: autosuspend never fires while the Tinta is open", W.autosuspend_check(7200) == false and W.auto_suspends == 0)
    check("kobo attach: Host.enter_sleep set", type(W.host.enter_sleep) == "function")
    check("kobo attach: KOReader's USB / charging handlers untouched",
        W.handlers.UsbPlugIn == W.handlers_orig.UsbPlugIn and W.handlers.UsbPlugOut == W.handlers_orig.UsbPlugOut
        and W.handlers.Charging == W.handlers_orig.Charging and W.handlers.NotCharging == W.handlers_orig.NotCharging)
    -- the power button while awake becomes the tinta's sleep, KOReader's screensaver never draws
    W.handlers.Power()
    check("kobo: power button awake -> tinta sleep (page drawn)", Sleep.active() and count(W.host_calls, "draw") == 1)
    eq("kobo: KOReader's screensaver did not draw", W.screensaver_drawn, 0)
    eq("kobo: one RTC task for the target", #W.wm._task_queue, 1)
    eq("kobo: the RTC task is at the target", W.wm._task_queue[1].epoch, Sleep._state().target)
    eq("kobo: the alarm is at the target", W.alarm, Sleep._state().target)
    eq("kobo: nothing suspends before the page settled", W.suspends + count(W.calls, "beforeSuspend"), 0)
    W.advance(Sleep.SETTLE_S + 1)
    check("kobo: KOReader's suspend path ran with the screensaver flagged only",
        W.device.screen_saver_mode == true and W.screensaver_drawn == 0 and count(W.calls, "beforeSuspend") == 1)
    W.advance(W.device.suspend_wait_timeout + 3)
    eq("kobo: the device suspended once", W.suspends, 1)
    check("kobo: suspended", W.suspended == true)
    Sleep.detach()
    eq("kobo detach: pause flag restored", W.pluginshare.pause_auto_suspend, false)
    check("kobo detach: onPowerEvent back", W.device.onPowerEvent == orig_power_event)
    eq("kobo detach: no RTC task left", #W.wm._task_queue, 0)
end

---------------------------------------------------------------- Kobo: an RTC wake-up (WakeupMgr task fired), batch, suspend again

do
    local W = world("kobo")
    W.wifi.connect_after = 45             -- slow Kobo Wi-Fi: past the Kindle's 30 s, inside the Kobo's limit
    Sleep.attach(W.host, { log_path = W.log_path })
    Sleep.enter("now")
    local target = Sleep._state().target
    W.advance(Sleep.SETTLE_S + W.device.suspend_wait_timeout + 4)
    check("kobo rtc: asleep", W.suspended == true and W.suspends == 1)
    W.wake_rtc()
    check("kobo rtc: woke at the alarm", W.t >= target and W.t - target < 5, W.t - target)
    W.advance(14)                          -- up to Kobo:checkUnexpectedWakeup (15 s after the wake)
    W.advance(2)                           -- the tinta's tick after the callback
    check("kobo rtc: the WakeupMgr task ran (batch started, Wi-Fi asked for)", W.wifi.enable_calls == 1 and Sleep._state().busy == true,
        tostring(W.wifi.enable_calls))
    W.advance(34)                          -- KOReader would have suspended 30 s after the callback: the Tinta took it back
    check("kobo rtc: no suspend during the batch (Wi-Fi still connecting)", W.suspended == false and W.suspends == 1 and Sleep._state().busy == true)
    W.advance(15)
    eq("kobo rtc: Wi-Fi connected inside the Kobo limit (60 s), apps refreshed", table.concat(W.refreshed or {}, ","), "alfa")
    check("kobo rtc: redrawn, Wi-Fi off, not busy", count(W.host_calls, "draw") == 2 and W.wifi.on == false and not Sleep._state().busy)
    check("kobo rtc: next RTC task armed at the new target", #W.wm._task_queue == 1 and W.wm._task_queue[1].epoch == Sleep._state().target
        and Sleep._state().target > target)
    check("kobo rtc: still the sleep page, no button wake", Sleep.active() and W.after_wake == nil)
    W.advance(W.device.suspend_wait_timeout + 5)
    check("kobo rtc: suspended again after the batch (once, no double suspend)", W.suspended == true and W.suspends == 2)
    check("kobo rtc: log says kind=scheduled", slurp(W.log_path):match("wake kind=scheduled") ~= nil)
    Sleep.detach()
end

---------------------------------------------------------------- Kobo: Wi-Fi never connects (backend limit 60 s), old data, sleep again

do
    local W = world("kobo")
    Sleep.attach(W.host, { log_path = W.log_path })
    Sleep.enter("now")
    W.advance(Sleep.SETTLE_S + W.device.suspend_wait_timeout + 4)
    W.wake_rtc()
    W.advance(16)
    W.advance(50)
    check("kobo wifi: still waiting at 50 s (Kindle would have given up at 30)", Sleep._state().busy == true)
    W.advance(20)
    check("kobo wifi: gave up after the limit, redrawn with the old data", not Sleep._state().busy and count(W.host_calls, "draw") == 2
        and W.refreshed == nil)
    check("kobo wifi: asleep and re-armed", Sleep.active() and #W.wm._task_queue == 1)
    Sleep.detach()
end

---------------------------------------------------------------- Kobo: the power button

do
    local W = world("kobo")
    local orig_resume = W.device.resume
    Sleep.attach(W.host, { log_path = W.log_path })
    Sleep.enter("now")
    W.advance(Sleep.SETTLE_S + W.device.suspend_wait_timeout + 4)
    W.wake_button()
    check("kobo button: tinta back, afterWake called", not Sleep.active() and W.after_wake ~= nil and W.host.sleeping == false)
    eq("kobo button: Device:resume ran once", count(W.calls, "resume"), 1)
    eq("kobo button: RTC task removed", #W.wm._task_queue, 0)
    check("kobo button: KOReader's screensaver functions restored",
        W.screensaver.show == W.screensaver_orig.show and W.screensaver.setup == W.screensaver_orig.setup)
    check("kobo button: Device.resume hook removed", W.device.resume == orig_resume)
    eq("kobo button: autosuspend still paused while the Tinta is open", W.pluginshare.pause_auto_suspend, true)
    -- the next power press sleeps the Tinta again
    W.handlers.Power()
    check("kobo button: pressing again sleeps again", Sleep.active() and #W.wm._task_queue == 1)
    Sleep.detach()
end

---------------------------------------------------------------- Kobo: sleep cover, USB

do
    local W = world("kobo")
    Sleep.attach(W.host, { log_path = W.log_path })
    W.handlers.Suspend()                    -- SleepCoverClosed -> Suspend
    check("kobo cover: closing the cover sleeps the tinta", Sleep.active())
    W.advance(Sleep.SETTLE_S + W.device.suspend_wait_timeout + 4)
    check("kobo cover: suspended", W.suspended == true)
    W.suspended = false
    -- a plug event wakes the kernel; KOReader's handler sends Suspend again: it goes through to KOReader, not the Tinta
    local before = count(W.host_calls, "draw")
    W.handlers.Suspend()
    W.run_due()
    check("kobo usb: a second Suspend while asleep is KOReader's (no second sleep page)", count(W.host_calls, "draw") == before)
    check("kobo usb: KOReader's handlers still the originals",
        W.handlers.UsbPlugIn == W.handlers_orig.UsbPlugIn and W.handlers.UsbPlugOut == W.handlers_orig.UsbPlugOut)
    Sleep.detach()
    -- plugged detection through the facade: KOReader's powerd, nothing else
    W.charging = true
    eq("kobo usb: Battery.plugged follows powerd isCharging", Battery.plugged{ powerd = W.device.powerd }, true)
    eq("kobo usb: Battery.read through the Kobo backend (no mAh)", Battery.read{ powerd = W.device.powerd, backend = require("device/backends/kobo") }.mah, nil)
    W.charging = false
    eq("kobo usb: unplugged", Battery.plugged{ powerd = W.device.powerd }, false)
end

---------------------------------------------------------------- Kobo: dodgy RTC (alarms further than UINT16_MAX are chained by WakeupMgr)

do
    local W = world("kobo", { dodgy_rtc = true })
    W.host.wakeTarget = function(_, from) return from + 20 * 3600 end
    Sleep.attach(W.host, { log_path = W.log_path })
    Sleep.enter("now")
    eq("kobo dodgy rtc: a chain of alarms for a 20 h target", #W.wm._task_queue, 2)
    Sleep.detach()
    eq("kobo dodgy rtc: detach removes the whole chain", #W.wm._task_queue, 0)
end

---------------------------------------------------------------- Kobo: a wake request (Timer) brings the RTC task forward

do
    local W = world("kobo")
    W.host.nextWakeRequest = function(_, from) if W.request and W.request > from then return W.request end end
    Sleep.attach(W.host, { log_path = W.log_path })
    W.request = T0 + 300
    Sleep.enter("now")
    eq("kobo request: the RTC task is the request", W.wm._task_queue[1].epoch, T0 + 300)
    Sleep.detach()
end

---------------------------------------------------------------- generic: no wake-up, KOReader suspends, button wakes

do
    local W = world("generic")
    W.pluginshare.pause_auto_suspend = nil
    Sleep.attach(W.host, { log_path = W.log_path })
    eq("generic attach: backend", Sleep._state().backend.name, "generic")
    Sleep.enter("now")
    eq("generic: no wake-up target", Sleep._state().target, nil)
    eq("generic: sleep page told there is none", W.sleep_info[2], nil)
    W.advance(Sleep.SETTLE_S + W.device.suspend_wait_timeout + 4)
    check("generic: KOReader suspended", W.suspended == true and W.suspends == 1 and W.screensaver_drawn == 0)
    W.wake_button()
    check("generic: the power button brings the Tinta back", not Sleep.active() and W.after_wake ~= nil)
    Sleep.detach()
    eq("generic detach: pause flag restored", W.pluginshare.pause_auto_suspend, nil)
end

-- a device that cannot suspend (the emulator): the Tinta comes back instead of staying on a dead sleep page
do
    local W = world("generic", { cannot_suspend = true })
    Sleep.attach(W.host, { log_path = W.log_path })
    Sleep.enter("now")
    W.advance(Sleep.SETTLE_S + 1)
    check("generic: cannot suspend -> abort, tinta shown again", not Sleep.active() and W.after_wake ~= nil)
    check("generic: the abort is logged", slurp(W.log_path):match("abort why=") ~= nil)
    Sleep.detach()
end

-- the Kindle path is untouched by all of this: a Device that says it is a Kindle keeps the lipc backend
do
    local W = world("kobo")
    W.device.isKindle = function() return true end
    W.props = nil
    Sleep._set_deps({ ui = W.ui, clock = function() return W.t end, device = W.device, network = W.network,
        lipc_lib = { init = function() return { get_string_property = function() return "0" end,
            set_string_property = function() return true end, set_int_property = function() return true end,
            close = function() end } end },
        logger = { info = function() end }, read_file = function() return nil end, exec = function() return "" end })
    Sleep.attach(W.host, { log_path = W.log_path })
    eq("kindle device: kindle backend", Sleep._state().backend.name, "kindle")
    Sleep.detach()
end
