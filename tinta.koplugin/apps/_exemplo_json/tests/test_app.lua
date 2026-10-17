-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (C) 2026 Tinta contributors
-- init.lua over a fake ctx with a FAKE ctx.net: manifest, refresh (success, every failure kind, bad answers), the
-- notification rule and the re-arm button. This is how to test an app that talks to a server without any network.
local T = ...
local M = require("apps/_exemplo_json/init")
local Registry = require("core/registry")
local Settings = require("core/settings")

T.check("manifest: the registry accepts it", Registry.validate(M) == true)
T.check("manifest: compatible with this tinta", Registry.compat(M) == true)
T.check("manifest: needs the network", M.net == true)
T.check("manifest: sizes are 2x2 and 4x2", table.concat(M.sizes, ",") == "2x2,4x2")
for _, f in ipairs(M.settings) do
    T.check("manifest: setting " .. f.key .. " default validates", f.default == nil or Settings.validate(f, f.default) ~= nil)
end
T.check("manifest: the url setting is the source's url_key", M.source.url_key == "url")

-- a ctx with a cache and a fake net: net.answer is what get_json returns, net.calls records (url, opts)
local function make(opts)
    local ctx = T.ctx(opts)
    ctx.cache_val = nil
    ctx.cache = { get = function() return ctx.cache_val end, put = function(_, v) ctx.cache_val = v end }
    ctx.net = { calls = {}, answer = { { value = 10, label = "Queue", unit = "items" } } }
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

do   -- success: one done(true), only the used fields cached, the url and the token passed to ctx.net
    local ctx = make{ settings = { url = "https://example.com/s.json", token = "SECRET-TOKEN", threshold = 0 } }
    ctx.net.answer = { { { value = 10, label = "Queue", unit = "items", noise = { 1, 2, 3 } } } }
    local calls, ok = refresh(ctx)
    T.check("refresh: done(true) exactly once", calls == 1 and ok == true)
    T.check("refresh: asked the configured url with the token", ctx.net.calls[1].url == "https://example.com/s.json" and ctx.net.calls[1].opts.token == "SECRET-TOKEN")
    T.check("refresh: cache has the fields we use and the time", ctx.cache_val.value == 10 and ctx.cache_val.label == "Queue"
        and ctx.cache_val.unit == "items" and ctx.cache_val.at == ctx.t and ctx.cache_val.noise == nil)
    T.eq("refresh: threshold 0 -> no notification", #ctx.notes, 0)
end

do   -- every failure of the network is done(false, kind), nothing cached, nothing notified
    for _, kind in ipairs({ "unreachable", "unauthorized", "forbidden", "not_found", "http", "too_large", "bad_json" }) do
        local ctx = make{ settings = { threshold = 5 } }
        ctx.net.answer = { { nil, kind, "detail" } }
        local calls, ok, err = refresh(ctx)
        T.check("refresh: " .. kind .. " -> done(false, kind) once", calls == 1 and ok == false and err == kind)
        T.check("refresh: " .. kind .. " leaves cache and notifications alone", ctx.cache_val == nil and #ctx.notes == 0)
    end
    local ctx = make()
    ctx.net.answer = { { { label = "no value here" } } }
    local calls, ok, err = refresh(ctx)
    T.check("refresh: an answer of the wrong shape is a failure, not an exception", calls == 1 and ok == false and err == "bad_shape" and ctx.cache_val == nil)
    ctx = make(); ctx.net = nil
    calls, ok, err = refresh(ctx)
    T.check("refresh: no ctx.net -> done(false)", calls == 1 and ok == false and err == "unreachable")
end

do   -- the notification rule: once per crossing, re-armed when the value drops
    local ctx = make{ settings = { threshold = 50, url = "https://example.com/s.json" } }
    local readings = { 10, 60, 70, 20, 80 }
    ctx.net.answer = {}
    for _, v in ipairs(readings) do ctx.net.answer[#ctx.net.answer + 1] = { { value = v, label = "Queue" } } end
    local counts = {}
    for i = 1, #readings do refresh(ctx); counts[i] = #ctx.notes end
    T.eq("rule: notifications after each reading", table.concat(counts, ","), "0,1,1,1,2")
    local n = ctx.notes[1]
    T.check("notification: key, type and route", n.key == "over:1" and n.type == "over" and n.route[1] == "main")
    T.check("notification: texts", n.title == T.L("n_over_title", "Queue", "60") and n.body == T.L("n_over_body", "50"))
    T.check("notification: its key changes per crossing", ctx.notes[2].key == "over:2")
    local declared = false
    for _, d in ipairs(M.notifications) do if d.type == n.type then declared = true end end
    T.check("notification: its type is declared in the manifest", declared)
    T.check("notification: no token or url in it", not (n.title .. n.body):find("http", 1, true))
end

do   -- the re-arm button goes through the confirmation
    local ctx = make()
    EXJSON_H = EXJSON_H or require("uistub").install()   -- shared with test_view (ui/kit keeps the first stubs)
    local H = EXJSON_H
    ctx.ui = H.kit
    ctx.data_store.over = true
    local act
    ctx.ui = setmetatable({ button = function(o) act = o.on_tap; return H.kit.button(o) end }, { __index = H.kit })
    M.screens.main(ctx, nil, { w = 584, h = 608, landscape = false })
    act()
    T.check("rearm: asks first", ctx.confirmed ~= nil and ctx.data_store.over == true)
    ctx.confirmed.ok()
    T.check("rearm: flag cleared, toast and redraw", ctx.data_store.over == false and #ctx.toasts == 1 and ctx.redraws == 1)
end
