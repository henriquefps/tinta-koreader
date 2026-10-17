-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (C) 2026 Tinta contributors
-- init.lua over a fake ctx: manifest, refresh, notification, reset
local T = ...
local M = require("apps/_modelo/init")
local Registry = require("core/registry")
local Settings = require("core/settings")

T.check("manifest: the registry accepts it", Registry.validate(M) == true)
T.check("manifest: compatible with this tinta", Registry.compat(M) == true)
T.check("manifest: sizes are 2x2 and 4x2", table.concat(M.sizes, ",") == "2x2,4x2")
for _, f in ipairs(M.settings) do
    T.check("manifest: setting " .. f.key .. " default validates", Settings.validate(f, f.default) == true)
end
T.check("manifest: limit range", Settings.validate(M.settings[1], 0) == nil and Settings.validate(M.settings[1], 101) == nil)

local function ctx_with_cache(opts)
    local ctx = T.ctx(opts)
    ctx.cache_val = nil
    ctx.cache = { get = function() return ctx.cache_val end, put = function(_, v) ctx.cache_val = v end }
    return ctx
end
local function refresh(ctx)
    local calls, ok = 0, nil
    M.refresh(ctx, function(o) calls = calls + 1; ok = o end)
    return calls, ok
end

do
    local ctx = ctx_with_cache{ settings = { limit = 3 } }
    M.init(ctx)
    for i = 1, 2 do
        local calls, ok = refresh(ctx)
        T.check("refresh " .. i .. ": done(true) exactly once", calls == 1 and ok == true)
    end
    T.eq("refresh: counter in ctx.data", ctx.data_store.count, 2)
    T.eq("refresh: counter in the cache", ctx.cache_val.count, 2)
    T.eq("refresh: no notification before the limit", #ctx.notes, 0)
    refresh(ctx)
    T.eq("refresh: one notification at the limit", #ctx.notes, 1)
    local n = ctx.notes[1]
    T.check("notification: key, type and route", n.key == "limit:3" and n.type == "limit" and n.route[1] == "main")
    T.check("notification: texts", n.title == T.L("n_limit_title", 3) and n.body == T.L("n_limit_body", 3))
    local declared = false
    for _, d in ipairs(M.notifications) do if d.type == n.type then declared = true end end
    T.check("notification: its type is declared in the manifest", declared)
end

do   -- the widget and the screen read the cache once each, and the reset goes through the confirmation
    local ctx = ctx_with_cache()
    ctx.data_store.count = 4
    ctx.cache_val = { count = 4, at = ctx.t }
    T.eq("widget: reads nothing from ctx.data", ctx.data_reads, 0)
    MODELO_H = MODELO_H or require("uistub").install()   -- shared with test_view (ui/kit keeps the first stubs)
    local H = MODELO_H
    ctx.ui = H.kit
    local res = M.screens.main(ctx, nil, { w = 584, h = 608, landscape = false })
    T.check("screen: returns a body", res and res.body ~= nil)
    H.begin(584, 608); res.body:paintTo(H.bb, 0, 0)
    T.check("screen: shows the counter and the button", H.has("4") and H.has(T.L("btn_reset")))
    -- tap the button by calling the confirmation's callback: the screen asked for it through ctx.confirm
    -- (the button callback is reached by the Tinta; here we call the action the same way)
    local act_reset
    ctx.ui = setmetatable({ button = function(o) act_reset = o.on_tap; return H.kit.button(o) end }, { __index = H.kit })
    M.screens.main(ctx, nil, { w = 584, h = 608, landscape = false })
    act_reset()
    T.check("reset: asks first", ctx.confirmed ~= nil and ctx.data_store.count == 4)
    ctx.confirmed.ok()
    T.check("reset: counter back to 0, toast and redraw", ctx.data_store.count == 0 and #ctx.toasts == 1 and ctx.redraws == 1)
end
