-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (C) 2026 Tinta contributors
-- Bateria (10.3): local app, no network. Every refresh (default 1 min) reads the gauge (device/battery.lua), logs
-- the reading when due (koreader/tinta-battery.csv, D2) and estimates the time left (D3: from charge_now mAh when
-- the gauge has it, % otherwise). Widgets 2x2, 4x2 (with a small chart) and 1x1 (percentage); the screen has the
-- big percentage, the estimate, the discharge chart and the stat blocks. Notifications of 8.6 (below 20 %, full).
-- Also the status bar estimate (Host.battery_eta, R-S1) and the one-time import of the old log (16.4).
-- The logic is pure (logic.lua, csvlog.lua, chart.lua); this file only wires it to the device and to ctx.
local Battery = require("device/battery")
local Log = require("apps/bateria/csvlog")
local Logic = require("apps/bateria/logic")
local Strings = require("apps/bateria/strings")
local View = require("apps/bateria/view")

-- state while KOReader runs: the open log, the last reading. `read` and `data_dir` are seams for the tests.
local A = {
    store = nil,
    last = nil,
    read = function() return Battery.read() end,
    data_dir = function()
        local ok, DataStorage = pcall(require, "datastorage")
        if ok and type(DataStorage) == "table" and DataStorage.getDataDir then return DataStorage:getDataDir() end
        return nil
    end,
    -- file names (in the data dir) of old battery logs to merge once; the optional apps/bateria/legacy_logs.lua
    -- returns them as a list of strings (a build that migrates from another plugin ships that file)
    legacy_logs = function()
        local ok, list = pcall(require, "apps/bateria/legacy_logs")
        return ok and type(list) == "table" and list or {}
    end,
}

local function log_path(name)
    local dir = A.data_dir()
    return dir and (dir .. "/" .. name) or nil
end

local function log_store()
    if not A.store then
        local ok, st = pcall(Log.open, log_path(Log.FILE))
        A.store = ok and st or Log.open(nil)
    end
    return A.store
end

local function wifi_on(ctx)
    if ctx.net and ctx.net.wifi_on then
        local ok, v = pcall(ctx.net.wifi_on)
        if ok then return v == true end
    end
    local ok, NetworkMgr = pcall(require, "ui/network/manager")
    if ok and type(NetworkMgr) == "table" and NetworkMgr.isWifiOn then
        local wok, v = pcall(NetworkMgr.isWifiOn, NetworkMgr)
        return wok and v == true
    end
    return false
end

-- the last reading: this session's, else the persisted cache (shown before the first refresh)
local function last(ctx)
    if A.last then return A.last end
    local c = ctx.cache and ctx.cache:get()
    return type(c) == "table" and c or nil
end

local function vm(ctx)
    return Logic.view(last(ctx), ctx.now(), ctx.i18n.t, ctx.i18n.lang())
end

return {
    id = "bateria",
    name = "Bateria",
    names = { pt = Strings.pt.name, en = Strings.en.name },
    short = "Bat.",
    version = 1,
    api = 1,                -- Tinta app API this app was written for (5.1)
    sizes = { "2x2", "4x2", "1x1" },
    net = false,
    defaults = { interval = 60, window = nil },
    settings = {},
    notifications = {
        { type = "low", label = "abaixo de 20%" },
        { type = "full", label = "carga completa" },
    },
    strings = Strings,

    init = function(ctx)
        log_store()
    end,

    refresh = function(ctx, done)
        local r = A.read()
        if not r then return done(false, ctx.i18n.t("no_reading")) end
        r.wifi = wifi_on(ctx)
        local cache, state, events = Logic.cycle(log_store(), r, ctx.now(), ctx.data:get("track"), ctx.i18n.t)
        ctx.data:set("track", state)
        ctx.cache:put(cache)
        A.last = cache
        for _, n in ipairs(events) do ctx.notify(n) end
        done(true)
    end,

    -- core hook `background(ctx, now, kind)` (ui/CORE_CALLS.md): the host calls it every minute while the Tinta is
    -- open, whatever the screen, and with kind "sleep" | "sched" | "button" around a suspend (10.3, 11.x). It only
    -- logs the reading (same CSV, same should_log, no estimate, no cache): the refresh keeps doing the rest.
    background = function(ctx, now, kind)
        local r = A.read()
        if not r or not tonumber(r.pct) then return end
        local pct = math.max(0, math.min(100, math.floor(tonumber(r.pct) + 0.5)))
        log_store():sample(now, { pct = pct, charging = r.charging == true, wifi = wifi_on(ctx), mv = r.mv, ma = r.ma,
            mah = r.mah, temp = r.temp }, kind and Logic.EV[kind] or nil)
    end,

    widget = function(ctx, size, box)
        return View.widget(ctx, size, box, vm(ctx), log_store().samples, ctx.i18n.t)
    end,

    screens = {
        main = function(ctx, args, box)
            return View.screen(ctx, box, vm(ctx), last(ctx), log_store().samples, ctx.i18n.t)
        end,
    },

    -- R-S1: Host.battery_eta(b) calls this through the registry; b = { pct, charging } from KOReader
    battery_eta = function(ctx, b)
        return Logic.status_eta(last(ctx), b, ctx.now())
    end,

    -- 16.4: one-time import of the old plugins' logs (A.legacy_logs()) into the tinta's. They had no battery
    -- settings, so the log is all there is (R-B5). Returns false to be asked again next time (no data dir);
    -- a write failure raises, so the host logs it and retries on the next open.
    import_legacy = function(ctx)
        local new = log_path(Log.FILE)
        if not new then return false end
        for _, name in ipairs(A.legacy_logs()) do
            local n, err = Log.import(log_path(name), new)
            if n then
                A.store = nil         -- reopen with the merged lines
                ctx.log(ctx.i18n.t("imported", n))
            elseif err ~= "no_legacy" then
                error("import of " .. name .. " failed: " .. tostring(err))
            end
        end
        return true
    end,

    _A = A,       -- tests only
}
