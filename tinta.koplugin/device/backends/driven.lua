-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (C) 2026 Tinta contributors
-- Tinta: the sleep controller for devices where KOReader itself suspends (Kobo, and the generic fallback), built
-- from KOReader v2025.04: Device:onPowerEvent("Suspend") -> Screensaver -> Device:suspend (Kobo:suspend writes
-- /sys/power/state), Device:resume on the power button, WakeupMgr for the RTC. EXPERIMENTAL, untested on hardware:
-- every path here is modelled on the KOReader sources and exercised only against fakes of them.
--
-- How the Tinta cooperates with KOReader instead of replacing it (the Kindle backend replaces powerd's job; here
-- KOReader's own suspend logic stays in charge and the Tinta only steers it):
--   * attach: PluginShare.pause_auto_suspend = true (the autosuspend plugin then only re-schedules itself, it never
--     suspends or powers off behind the tinta's idle timer, so there is no double suspend); the awake power button /
--     sleep cover (Device:onPowerEvent "Power" / "Suspend") is turned into the tinta's own sleep (sleep page,
--     wake-up plan) before KOReader's screensaver would draw;
--   * suspend(): while sleeping, KOReader's Screensaver:setup/show only flag Device.screen_saver_mode (what the
--     screensaver "disable" mode does) so the sleep page stays on the screen, then UIManager:suspend() runs the
--     normal KOReader suspend (Wi-Fi off, frontlight, Kobo's state-extended + mem dance);
--   * RTC (Kobo): Device.wakeup_mgr:addTask(seconds, cb). After an RTC wake Kobo:checkUnexpectedWakeup runs cb
--     (wakeupAction(30)) and schedules its own suspend in 30 s; the Tinta takes that suspend back (unschedule) for
--     the duration of its Wi-Fi + refresh batch and re-arms it with Device:rescheduleSuspend() when the batch ends;
--   * the power button / sleep cover opening reach KOReader as Resume -> Device:resume: that is the tinta's "button"
--     wake (an RTC wake never calls Device:resume);
--   * USB: the Tinta never touches KOReader's UsbPlugIn / Charging handlers. Awake, KOReader may show its USBMS
--     prompt over the Tinta; asleep, plug events wake the kernel and KOReader puts the device back to sleep.
local Driven = {}

-- opts = { name, can_wake = uses Device.wakeup_mgr, wifi_timeout }
function Driven.sleep(env, opts)
    local M, S, dep, now, log = env.M, env.S, env.dep, env.now, env.log
    local K = { name = opts.name, can_wake = opts.can_wake, wifi_timeout = opts.wifi_timeout }

    local function dev() return dep("device") end

    -- replaces dev[name] (or the module's) and remembers how to put it back
    local function wrap(holder, store, name, fn)
        store[name] = { holder = holder, had = rawget(holder, name), orig = holder[name] }
        holder[name] = fn
    end
    local function unwrap(store)
        for name, h in pairs(store) do h.holder[name] = h.had end   -- nil again when the method came from the class
        for name in pairs(store) do store[name] = nil end
    end

    S.awake_hooks, S.sleep_hooks = {}, {}

    ------------------------------------------------------------ attach / detach

    function K.attach()
        local d = dev()
        local ps = dep("pluginshare")
        if ps then
            S.autosuspend_orig = ps.pause_auto_suspend
            ps.pause_auto_suspend = true
        end
        if d and d.onPowerEvent then
            local orig = d.onPowerEvent
            wrap(d, S.awake_hooks, "onPowerEvent", function(self, ev)
                -- awake, not in KOReader's own screensaver: the power button and the sleep cover become the
                -- tinta's sleep; anything else (or a refusal) goes to KOReader as usual
                if S and not S.sleeping and not self.screen_saver_mode and (ev == "Power" or ev == "Suspend") then
                    local ok, started = pcall(M.enter, "power")
                    if ok and started == true then return end
                end
                return orig(self, ev)
            end)
        end
        return "KOReader suspends (" .. K.name .. ", experimental), autosuspend " .. (ps and "paused" or "not found")
    end

    function K.detach()
        unwrap(S.awake_hooks)
        local ps = dep("pluginshare")
        if ps then ps.pause_auto_suspend = S.autosuspend_orig end
    end

    ------------------------------------------------------------ the RTC wake-up (Kobo)

    local function disarm()
        local d = dev()
        local wm = d and d.wakeup_mgr
        if wm and S.rtc_cb then pcall(wm.removeTasks, wm, nil, S.rtc_cb) end
        S.rtc_cb = nil
    end

    local function on_rtc()
        S.rtc_cb = nil
        -- KOReader schedules its own suspend right after this callback returns: wait a tick to take it back
        dep("ui"):scheduleIn(1, function()
            if not S or not S.sleeping then return end
            local d = dev()
            if d and d.suspend then dep("ui"):unschedule(d.suspend) end
            M._woke("RTC", "scheduled")
        end)
    end

    function K.retarget()
        if not opts.can_wake then return end
        disarm()
        local d = dev()
        local wm = d and d.wakeup_mgr
        if not wm or not S.target then return end
        S.rtc_cb = on_rtc
        local ok, err = pcall(wm.addTask, wm, math.max(1, S.target - now()), S.rtc_cb)
        if not ok then
            S.rtc_cb = nil
            log("wakeup_mgr:addTask failed: " .. tostring(err))
        end
    end

    ------------------------------------------------------------ suspending

    function K.suspend()
        local d = dev()
        if not d or (d.canSuspend and d:canSuspend() == false) then
            return M._abort("this device cannot suspend")
        end
        local sc = dep("screensaver")
        if sc and not S.sleep_hooks.show then
            -- Screensaver "disable": flag the mode, draw nothing (the tinta's sleep page is on the screen)
            wrap(sc, S.sleep_hooks, "setup", function() end)
            wrap(sc, S.sleep_hooks, "show", function() d.screen_saver_mode = true end)
        end
        if d.resume and not S.sleep_hooks.resume then
            local orig = d.resume
            wrap(d, S.sleep_hooks, "resume", function(self, ...)
                local r = orig(self, ...)
                if S and S.sleeping then M._button("resume") end
                return r
            end)
        end
        dep("ui"):suspend()
    end

    function K.stop()
        disarm()
        unwrap(S.sleep_hooks)
    end

    function K.restore() end

    function K.state() return nil end

    -- a wake-up batch ended: Kobo's suspend, taken back at the start of the batch, runs again
    function K.batch_done()
        local d = dev()
        if opts.can_wake and d and d.rescheduleSuspend then pcall(d.rescheduleSuspend, d) end
    end

    function K.charge() return "-" end

    return K
end

return Driven
