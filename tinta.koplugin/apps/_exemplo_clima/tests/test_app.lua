-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (C) 2026 Tinta contributors
-- init.lua over a fake ctx with a FAKE ctx.net that answers the recorded sample: manifest, refresh (success, every failure
-- kind, a bad answer), the "rain soon" notification (once per day) and the widget/screen reading one cache. No network.
local T = ...
local M = require("apps/_exemplo_clima/init")
local Logic = require("apps/_exemplo_clima/logic")
local Registry = require("core/registry")
local Settings = require("core/settings")
local Json = require("core/json")

local fh = assert(io.open(T.here .. "/sample.json", "r"))
local SAMPLE = Json.decode(fh:read("*a")); fh:close()
local NOW = 1792152000   -- 14:00 at the sample's place

T.check("manifest: the registry accepts it", Registry.validate(M) == true)
T.check("manifest: compatible with this tinta", Registry.compat(M) == true)
T.check("manifest: needs the network", M.net == true)
T.check("manifest: sizes are 2x2 and 4x2", table.concat(M.sizes, ",") == "2x2,4x2")
T.eq("manifest: refreshes every 30 minutes", M.defaults.interval, 1800)
for _, f in ipairs(M.settings) do
    T.check("manifest: setting " .. f.key .. " default validates", f.default == nil or Settings.validate(f, f.default) ~= nil)
end
T.eq("manifest: settings are lat, lon and units", M.settings[1].key .. M.settings[2].key .. M.settings[3].key, "latlonunits")
T.check("manifest: the rain type is declared", M.notifications[1].type == "rain")

-- a ctx with a cache and a fake net: net.answer is what get_json returns, net.calls records (url, opts)
local function make(opts)
    local ctx = T.ctx(opts or { now = NOW })
    ctx.t = NOW
    ctx.cache_val, ctx.cache_reads = nil, 0
    ctx.cache = { get = function() ctx.cache_reads = ctx.cache_reads + 1; return ctx.cache_val end, put = function(_, v) ctx.cache_val = v end }
    ctx.net = { calls = {}, answer = { { SAMPLE } } }
    ctx.net.get_json = function(url, o)
        ctx.net.calls[#ctx.net.calls + 1] = { url = url, opts = o }
        local a = table.remove(ctx.net.answer, 1) or ctx.net.last
        ctx.net.last = a
        return a[1], a[2], a[3]
    end
    return ctx
end
local function refresh(ctx)
    local calls, ok, err = 0, nil, nil
    M.refresh(ctx, function(o, e) calls = calls + 1; ok, err = o, e end)
    return calls, ok, err
end

do   -- success: one done(true), the configured place asked, only the shown fields cached
    local ctx = make{ settings = { lat = 52.52, lon = 13.41, units = "metric" } }
    local calls, ok = refresh(ctx)
    T.check("refresh: done(true) exactly once", calls == 1 and ok == true)
    T.check("refresh: asked the configured place", ctx.net.calls[1].url:find("latitude=52.5200&longitude=13.4100", 1, true) ~= nil)
    T.check("refresh: no token is sent", ctx.net.calls[1].opts == nil or ctx.net.calls[1].opts.token == nil)
    local c = ctx.cache_val
    T.check("refresh: cache has temperature, hours, time and units", c.temp == 16.2 and #c.hours == Logic.KEEP_HOURS and c.at == NOW and c.units == "metric")
    T.check("refresh: cache has nothing of the raw answer", c.hourly == nil and c.timezone == nil and c.latitude == nil)
end

do   -- units are passed on
    local ctx = make{ settings = { units = "imperial" } }
    refresh(ctx)
    T.check("refresh: imperial asks Fahrenheit and caches the unit", ctx.net.calls[1].url:find("fahrenheit", 1, true) and ctx.cache_val.units == "imperial")
end

do   -- every failure of the network is done(false, kind), nothing cached, nothing notified
    for _, kind in ipairs({ "unreachable", "unauthorized", "forbidden", "not_found", "http", "too_large", "bad_json", "server_failed" }) do
        local ctx = make()
        ctx.net.answer = { { nil, kind, "detail" } }
        local calls, ok, err = refresh(ctx)
        T.check("refresh: " .. kind .. " -> done(false, kind) once", calls == 1 and ok == false and err == kind)
        T.check("refresh: " .. kind .. " leaves cache and notifications alone", ctx.cache_val == nil and #ctx.notes == 0)
    end
    local ctx = make()
    ctx.net.answer = { { { error = true, reason = "Latitude must be in range of -90 to 90" } } }
    local calls, ok, err = refresh(ctx)
    T.check("refresh: an answer of the wrong shape is a failure, not an exception", calls == 1 and ok == false and err == "bad_shape" and ctx.cache_val == nil)
    ctx = make(); ctx.net = nil
    calls, ok, err = refresh(ctx)
    T.check("refresh: no ctx.net -> done(false)", calls == 1 and ok == false and err == "unreachable")
end

do   -- the rain notification: declared, no secrets, once per day, again the next day
    local ctx = make()
    refresh(ctx)
    T.eq("rain: one notification", #ctx.notes, 1)
    local n = ctx.notes[1]
    T.check("rain: key per day at the place, type and route", n.key == "rain:2026-10-16" and n.type == "rain" and n.route[1] == "main")
    T.check("rain: texts", n.title == T.L("n_rain_title") and n.body == T.L("n_rain_body", "15:00", 35))
    local declared = false
    for _, d in ipairs(M.notifications) do if d.type == n.type then declared = true end end
    T.check("rain: its type is declared in the manifest", declared)
    T.check("rain: no coordinates or url in it", not (n.title .. n.body):find("http", 1, true) and not (n.title .. n.body):find("52", 1, true))
    ctx.net.answer = { { SAMPLE } }
    ctx.t = NOW + 1800
    refresh(ctx)
    T.check("rain: a second refresh the same day repeats the key (the Tinta drops it)", #ctx.notes == 2 and ctx.notes[2].key == n.key)
end

do   -- a dry day: no notification
    local dry = Json.decode(Json.encode(SAMPLE))
    for i = 1, #dry.hourly.time do dry.hourly.precipitation_probability[i] = 0; dry.hourly.weather_code[i] = 3 end
    local ctx = make()
    ctx.net.answer = { { dry } }
    local _, ok = refresh(ctx)
    T.check("dry: refresh works and notifies nothing", ok == true and #ctx.notes == 0)
end

do   -- the widget and the screen read the cache once per call (R: no store reads per item)
    EXCLIMA_H = EXCLIMA_H or require("uistub").install()   -- shared with test_view (ui/kit keeps the first stubs)
    local H = EXCLIMA_H
    local ctx = make()
    refresh(ctx)
    ctx.ui = H.kit
    ctx.cache_reads = 0
    local box = H.cell("4x2", "portrait", false)
    M.widget(ctx, "4x2", box)
    T.eq("widget: one cache read", ctx.cache_reads, 1)
    ctx.cache_reads = 0
    M.screens.main(ctx, nil, { w = 584, h = 608, landscape = false })
    T.eq("screen: one cache read", ctx.cache_reads, 1)
end
