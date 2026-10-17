-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (C) 2026 Tinta contributors
-- Tinta device backend: Kindle (spec 11.5, 2.2). Everything that was device/sleep.lua and device/battery.lua on the
-- KT3 lives here, MOVED and not rewritten: powerd over lipc with preventScreenSaver (R-P9), the rtcWakeup pump
-- (R-P10), the OutOfSS / IntoSS hooks, the awake-usb mode, the bd7181x gauge (mV, mA, mAh, °C) and the plugged
-- detection (gauge status + powerd isCharging). device/sleep.lua keeps the state machine (enter, wake-up batch,
-- button) and calls this object for what is device specific; device/battery.lua calls B.battery_*.
-- Measured on the KT3 only (Kindle Basic 2); other Kindles use the same code, untested.
local Gauge = require("device/backends/gauge")

local B = { name = "kindle", can_wake = true }

local POWERD = "com.lab126.powerd"
local LIPC_ID = "com.github.koreader.tinta"
local BATTERY_DIR = "/sys/class/power_supply/bd7181x_bat/"

---------------------------------------------------------------- battery (gauge files, R-L3)

B.DIR = BATTERY_DIR

-- reading key -> sysfs file
B.FILES = {
    pct = "capacity", status = "status", charging = "charging",
    mv = "voltage_now", ma = "current_now", mah = "charge_now",
    full_mah = "charge_full", design_mah = "charge_full_design", temp = "temp",
}

B.read_file = Gauge.read_file
B.parse = Gauge.parse

-- Plugged in (USB cable or charger)? Used by the idle sleep mode "só na bateria". Two cheap sources, either one
-- says plugged: (1) the gauge's status / charging files (parse: "Charging" or "Full" count, so a full battery on
-- the cable is still plugged); (2) KOReader's power device isCharging(), which on Kindle is powerd's lipc property
-- "isCharging" (in-process lipc, no process spawn), the same signal as the Charging/NotCharging events.
-- Limits: a charger that powers the device without the gauge reporting it (very low current at 100 %) may be read
-- as not plugged if both sources agree on "no"; on a failed read the answer is false (the Kindle may then sleep).
-- opts = { dir, read_file, powerd } as in M.read.
function B.battery_plugged(opts)
    opts = opts or {}
    local dir = opts.dir or B.DIR
    local rf = opts.read_file or Gauge.read_file
    local raw = {}
    for _, key in ipairs({ "status", "charging" }) do
        local ok, v = pcall(rf, dir .. B.FILES[key])
        if ok then raw[key] = v end
    end
    if Gauge.parse(raw).charging == true then return true end
    local pd = opts.powerd
    if pd and pd.isCharging then
        local ok, v = pcall(pd.isCharging, pd)
        if ok and v == true then return true end
    end
    return false
end

-- opts = { dir = B.DIR, read_file = fn(path) -> string | nil, powerd = KOReader power device | false }
-- Returns the reading (Gauge.parse), with pct and charging from KOReader's power device when the files lack them;
-- nil when no percentage is known at all.
function B.battery_read(opts)
    opts = opts or {}
    local dir = opts.dir or B.DIR
    local rf = opts.read_file or Gauge.read_file
    local raw = {}
    for key, file in pairs(B.FILES) do
        local ok, v = pcall(rf, dir .. file)
        if ok then raw[key] = v end
    end
    local r = Gauge.parse(raw)
    if r.pct == nil or r.charging == nil then
        local pd = opts.powerd
        if pd == nil then
            local ok, Device = pcall(require, "device")
            if ok and type(Device) == "table" and Device.getPowerDevice then
                local pok, p = pcall(Device.getPowerDevice, Device)
                pd = pok and p or nil
            end
        end
        if pd then
            if r.pct == nil and pd.getCapacity then
                local ok, v = pcall(pd.getCapacity, pd)
                if ok and tonumber(v) then r.pct = tonumber(v) end
            end
            if r.charging == nil and pd.isCharging then
                local ok, v = pcall(pd.isCharging, pd)
                if ok then r.charging = v == true end
            end
        end
    end
    if r.pct == nil then return nil end
    r.charging = r.charging == true
    return r
end

-- opts = { dir = B.DIR, read_file = fn(path) -> string | nil, powerd = KOReader power device | false }
-- Returns the reading (Gauge.parse), with pct and charging from KOReader's power device when the files lack them;
-- nil when no percentage is known at all.
function B.battery_read(opts)
    opts = opts or {}
    local dir = opts.dir or B.DIR
    local rf = opts.read_file or Gauge.read_file
    local raw = {}
    for key, file in pairs(B.FILES) do
        local ok, v = pcall(rf, dir .. file)
        if ok then raw[key] = v end
    end
    local r = Gauge.parse(raw)
    if r.pct == nil or r.charging == nil then
        local pd = opts.powerd
        if pd == nil then
            local ok, Device = pcall(require, "device")
            if ok and type(Device) == "table" and Device.getPowerDevice then
                local pok, p = pcall(Device.getPowerDevice, Device)
                pd = pok and p or nil
            end
        end
        if pd then
            if r.pct == nil and pd.getCapacity then
                local ok, v = pcall(pd.getCapacity, pd)
                if ok and tonumber(v) then r.pct = tonumber(v) end
            end
            if r.charging == nil and pd.isCharging then
                local ok, v = pcall(pd.isCharging, pd)
                if ok then r.charging = v == true end
            end
        end
    end
    if r.pct == nil then return nil end
    r.charging = r.charging == true
    return r
end

---------------------------------------------------------------- sleep (the controller of one attach)

-- env = { M = device/sleep (constants and wake-up entry points), S = its state table, dep, now, log, record }
function B.sleep(env)
    local M, S, dep, now, log, record = env.M, env.S, env.dep, env.now, env.log, env.record
    local K = {}
    local function hms(t) return os.date("%H:%M:%S", t) end

    local function lipc_handle()
        if S.lipc == nil then
            S.lipc = false
            local lib = dep("lipc_lib")
            if lib and lib.init then
                local ok, h = pcall(lib.init, LIPC_ID)
                if ok and h then S.lipc = h end
            end
        end
        return S.lipc or nil
    end

    local function sh_quote(s) return "'" .. tostring(s):gsub("'", "'\\''") .. "'" end

    local function shell_get(prop)
        local exec = dep("exec")
        local out = exec and exec("lipc-get-prop " .. POWERD .. " " .. prop)
        if not out then return nil end
        return (out:gsub("%s+$", "")):gsub("^%s+", "")
    end

    local function shell_set(prop, value, int)
        local exec = dep("exec")
        if not exec then return false end
        exec("lipc-set-prop " .. (int and "-i " or "") .. POWERD .. " " .. prop .. " " .. sh_quote(value))
        return true
    end

    -- powerd state: "active" | "screenSaver" | "readyToSuspend" | "suspended" | nil
    local function powerd_state()
        local h = lipc_handle()
        if h then
            local ok, v = pcall(h.get_string_property, h, POWERD, "state")
            if ok and type(v) == "string" and v ~= "" then return v end
        end
        local v = shell_get("state")
        if v and v ~= "" then return v end
        return nil
    end

    local function set_int(prop, value)
        local h = lipc_handle()
        if h then
            local ok = pcall(h.set_int_property, h, POWERD, prop, value)
            if ok then return true end
        end
        return shell_set(prop, tostring(value), true)
    end

    -- preventScreenSaver is a string property for lipc-set-prop (what KOReader's keepalive and the measured scripts
    -- use). Through the binding it is written as a string and read back; on any doubt the shell tools do it.
    local function get_prevent()
        local h = lipc_handle()
        if h then
            local ok, v = pcall(h.get_string_property, h, POWERD, "preventScreenSaver")
            if ok and v ~= nil and tonumber(v) then return tonumber(v) end
        end
        local v = shell_get("preventScreenSaver")
        return v and tonumber(v) or nil
    end

    local function set_prevent(value)
        local h = lipc_handle()
        if h then
            local ok = pcall(h.set_string_property, h, POWERD, "preventScreenSaver", tostring(value))
            if ok and get_prevent() == value then S.prevent_via = "liblipclua"; return true end
        end
        S.prevent_via = "lipc-set-prop"
        shell_set("preventScreenSaver", tostring(value), false)
        return get_prevent() == value
    end

    local function charge()
        local rf = dep("read_file")
        local v = rf and rf(BATTERY_DIR .. "charge_now")
        v = v and tonumber((v:gsub("%s+", "")))
        if v and v > 100000 then v = v / 1000 end   -- µAh on other kernels
        return v
    end


    -- Kindle:intoScreenSaver would draw KOReader's screensaver over the sleep page (and, with "cover" types, load
    -- images): while sleeping it only does what the screensaver "disable" mode does, flag screen_saver_mode and
    -- suspend input (powerd:beforeSuspend). Kindle:outofScreenSaver is wrapped to tell us about the power button.
    function K.hook()
        local dev = dep("device")
        if not dev or S.hooks then return end
        S.hooks = {}
        local function wrap(name, fn)
            S.hooks[name] = { had = rawget(dev, name), orig = dev[name] }
            dev[name] = fn
        end
        local orig_into, orig_out = dev.intoScreenSaver, dev.outofScreenSaver
        if orig_into then
            wrap("intoScreenSaver", function(self, source)
                if S and S.sleeping then
                    self.screen_saver_mode = true
                    if self.powerd and self.powerd.beforeSuspend then self.powerd:beforeSuspend() end
                    return
                end
                return orig_into(self, source)
            end)
        end
        if orig_out then
            wrap("outofScreenSaver", function(self, source)
                local r = orig_out(self, source)
                if S and S.sleeping then M._button("OutOfSS") end
                return r
            end)
        end
        local orig_wake = dev.wakeupFromSuspend
        if orig_wake then
            wrap("wakeupFromSuspend", function(self, ts)
                local r = orig_wake(self, ts)
                if S and S.sleeping then M._woke("WakeupFromSuspend") end
                return r
            end)
        end
    end

    function K.unhook()
        if not S or not S.hooks then return end
        local dev = dep("device")
        for name, h in pairs(S.hooks) do
            if dev then dev[name] = h.had end      -- nil again when the method came from the class
        end
        S.hooks = nil
    end

    function K.stop_pump()
        if S and S.awake_cb then dep("ui"):unschedule(S.awake_cb); S.awake_cb = nil end
        if S and S.pump_cb then dep("ui"):unschedule(S.pump_cb); S.pump_cb = nil end
        if S and S.settle_cb then dep("ui"):unschedule(S.settle_cb); S.settle_cb = nil end
        if S and S.classify_cb then dep("ui"):unschedule(S.classify_cb); S.classify_cb = nil end
    end

    local function request_rtc()
        if not S.target then return end
        local t = now()
        local secs = S.host:rtcSeconds(S.target, t)
        set_int("rtcWakeup", secs)
        S.rtc_requests = (S.rtc_requests or 0) + 1
        if S.rtc_requests == 1 then
            record("rtc", { { "target", hms(S.target) }, { "in_s", secs }, { "charge", charge() } })
        end
    end

    local function pump()
        if not S then return end
        S.pump_cb = nil
        if not S.sleeping then return end
        local t = now()
        local state = powerd_state()
        local late = S.last_tick and (t - S.last_tick) or 0
        S.last_tick = t
        if not S.busy and late >= M.WAKE_GAP_S then M._woke("gap " .. late .. "s") end
        -- how long powerd has been in screenSaver without a wake-up in between (USB: it never goes on)
        if state == "screenSaver" then S.ss_since = S.ss_since or t else S.ss_since = nil end
        if state == "readyToSuspend" and S.awake_mode then K.leave_awake_mode() end
        if state == "screenSaver" and S.ss_since and t - S.ss_since >= M.USB_WAIT_S and not S.awake_mode
                and not S.busy and not S.classify_cb then
            K.enter_awake_mode()
        end
        if state == "readyToSuspend" then
            if not S.r2s_seen then
                S.r2s_seen = true
                if S.wake_at then
                    record("r2s", { { "after_wake_s", t - S.wake_at }, { "charge", charge() } })
                end
            end
            request_rtc()                       -- also while a wake-up batch runs: the next wake-up must be asked for
        else
            S.r2s_seen = false
            S.rtc_requests = 0
        end
        if state ~= nil and state ~= "active" then S.left_active = true end
        if not S.busy then
            if state == "active" and S.left_active then
                return M._button("powerd active")                   -- OutOfSS missed: powerd says the button was pressed
            elseif (state == "active" or state == nil) and not S.left_active and S.pressed_at
                    and t - S.pressed_at >= M.ABORT_S then
                return M._abort("powerd did not leave active after the power button")
            end
        end
        S.pump_cb = function() pump() end
        dep("ui"):scheduleIn(M.PUMP_S, S.pump_cb)
    end

    ---------------------------------------------------------------- USB: no suspend, timer-driven wake-ups

    function K.arm_awake()
        if S.awake_cb then dep("ui"):unschedule(S.awake_cb); S.awake_cb = nil end
        if not S.target then return end
        S.awake_cb = function()
            S.awake_cb = nil
            if not S or not S.sleeping or not S.awake_mode then return end
            if S.busy then
                S.awake_cb = function() S.awake_cb = nil; if S and S.sleeping and S.awake_mode then K.arm_awake() end end
                return dep("ui"):scheduleIn(M.WIFI_POLL_S, S.awake_cb)
            end
            M._scheduled(powerd_state())
        end
        dep("ui"):scheduleIn(math.max(1, S.target - now()), S.awake_cb)
    end

    function K.enter_awake_mode()
        S.awake_mode = true
        log("powerd stays in screenSaver (USB?): wake-ups by timer")
        record("sleep", { { "mode", "awake-usb" }, { "target", S.target and hms(S.target) or "never" }, { "charge", charge() } })
        K.arm_awake()
    end

    function K.leave_awake_mode()
        S.awake_mode = false
        if S.awake_cb then dep("ui"):unschedule(S.awake_cb); S.awake_cb = nil end
        log("powerd reached readyToSuspend: back to the RTC wake-up")
        record("sleep", { { "mode", "rtc" }, { "target", S.target and hms(S.target) or "never" }, { "charge", charge() } })
    end


    -- ---- the interface device/sleep.lua uses

    K.name = "kindle"
    K.can_wake = true
    K.charge = charge

    -- attach: remember preventScreenSaver and hold it at 1 (R-P9, awake); returns the text for the log
    function K.attach()
        S.prevent_orig = get_prevent()
        S.prevent_awake = 1
        set_prevent(1)                       -- R-P9: the Tinta decides when the Kindle sleeps, not powerd
        return "preventScreenSaver was " .. tostring(S.prevent_orig) .. " via " .. tostring(S.prevent_via)
    end

    -- detach, after stop(): leave powerd the way KOReader had it
    function K.detach()
        if S.prevent_orig ~= nil then set_prevent(S.prevent_orig) end
        if S.lipc then pcall(S.lipc.close, S.lipc) end
    end

    function K.stop() K.stop_pump(); K.unhook() end

    function K.state() return powerd_state() end

    -- after the sleep page settled (Wi-Fi already off): hold the KOReader hooks, prevent 0, powerButton 1, pump
    function K.suspend()
        K.hook()
        S.prevent_awake = get_prevent() or S.prevent_awake
        set_prevent(0)                                   -- R-P9
        S.last_tick = now()
        set_int("powerButton", 1)
        S.pressed_at = now()
        S.pump_cb = function() pump() end
        dep("ui"):scheduleIn(M.PUMP_S, S.pump_cb)
    end

    -- the power button woke the tinta: preventScreenSaver back to what the Tinta held while awake (R-P9)
    function K.restore() set_prevent(S.prevent_awake or 1) end

    -- the target changed: the pump reads S.target itself
    function K.retarget() end

    -- a wake-up batch ended
    function K.batch_done() if S.awake_mode then K.arm_awake() end end

    return K
end

return B
