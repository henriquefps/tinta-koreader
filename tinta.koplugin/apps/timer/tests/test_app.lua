-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (C) 2026 Tinta contributors
-- init.lua over a fake ctx: restore, arming, the end of a run (awake and from a sleep wake-up), settings
local T = ...
local check, eq = T.check, T.eq
local M = require("apps/timer/init")
local A = M._A
local L = require("apps/timer/logic")
local Settings = require("core/settings")

local function fresh(ctx_opts)
    A.st, A.armed = nil, false
    return T.ctx(ctx_opts)
end
local function refresh(ctx) local res; M.refresh(ctx, function(ok) res = ok end); return res end
local function screen_actions(ctx)
    -- the actions are reached through the screen (callbacks of its buttons), like the Tinta does
    return M.screens.main
end

-- manifest settings validate through core/settings
local ok_fields = true
for _, f in ipairs(M.settings) do
    local good = f.default
    local ok = Settings.validate(f, good)
    if not ok then ok_fields = false end
end
check("manifest: every default validates", ok_fields)
check("manifest: work_min range", Settings.validate(M.settings[1], 0) == nil and Settings.validate(M.settings[1], 181) == nil)
check("manifest: custom_min range", Settings.validate(M.settings[4], 601) == nil and Settings.validate(M.settings[4], 90) == true)
local reg_ok = require("core/registry").validate(M)
check("manifest: registry accepts it", reg_ok == true)
check("manifest: sizes", table.concat(M.sizes, ",") == "2x2,4x2,1x1")
check("manifest: local, no network", M.net == false)

-- init: idle, nothing to ask for
do
    local ctx = fresh()
    M.init(ctx)
    eq("init idle: state read once", ctx.data_reads, 1)
    eq("init idle: no wake request (cancel)", ctx.wakes[1], false)
    eq("init idle: mode", A.st.mode, "idle")
end

-- init restores a running timer and asks to be awake at its end
do
    local ctx = fresh()
    local st = L.start(L.selection("m10", {}), ctx.t)
    ctx.data_store.state = st
    ctx.t = ctx.t + 120
    M.init(ctx)
    eq("restore: running", A.st.mode, "running")
    eq("restore: wake request is the end", ctx.wakes[1], st.end_at)
    -- first refresh of the session only arms
    eq("first refresh: ok", refresh(ctx), true)
    eq("first refresh: nothing notified", #ctx.notes, 0)
    -- widget reads from memory
    local reads = ctx.data_reads
    local vm = L.view(A.st, ctx.now(), ctx.i18n.t)
    check("render does not touch the store", ctx.data_reads == reads)
end

-- expired while the Tinta was closed: first refresh arms, second finishes and notifies
do
    local ctx = fresh()
    local st = L.start(L.selection("m10", {}), ctx.t)
    ctx.data_store.state = st
    ctx.t = st.end_at + 3600
    M.init(ctx)
    refresh(ctx)
    eq("expired: nothing yet", #ctx.notes, 0)
    check("expired: wake request in the past brings the second refresh at once", ctx.wakes[#ctx.wakes] == st.end_at)
    refresh(ctx)
    eq("expired: notified", #ctx.notes, 1)
    eq("expired: title", ctx.notes[1].title, "Tempo esgotado")
    eq("expired: prio alta", ctx.notes[1].prio, "alta")
    eq("expired: back to idle", A.st.mode, "idle")
    eq("expired: persisted idle", ctx.data_store.state.mode, "idle")
    eq("expired: request cancelled", ctx.wakes[#ctx.wakes], false)
    refresh(ctx)
    eq("a finished timer is not notified twice", #ctx.notes, 1)
end

-- the pomodoro: focus ends, the break starts with its own wake request, then ends too
do
    local ctx = fresh({ settings = { auto_break = true, work_min = 25, break_min = 5 } })
    M.init(ctx); refresh(ctx)
    local act = {}
    -- start through the screen's button callbacks: build the screen with a recording kit
    local kit_calls = {}
    local ui = { theme = require("ui/theme") }
    local function w() return { getSize = function() return { w = 10, h = 10 } end } end
    ui.text = function() return w() end
    ui.box = function(o) return o end
    ui.space = function() return w() end
    ui.vstack = function(parts) return { parts = parts } end
    ui.button_row = function(specs) for _, s in ipairs(specs) do kit_calls[#kit_calls + 1] = s end; return w() end
    ui.button = function(o) kit_calls[#kit_calls + 1] = { o.label, o.on_tap }; return w() end
    ctx.ui = ui
    M.screens.main(ctx, nil, { w = 584, h = 608, landscape = false })
    local function tap(label)
        for _, s in ipairs(kit_calls) do if s[1] == label then s[2](); return true end end
        return false
    end
    check("idle screen has Iniciar", tap("Iniciar"))
    eq("started: running", A.st.mode, "running")
    local end_at = ctx.t + 25 * 60
    eq("started: wake request", ctx.wakes[#ctx.wakes], end_at)
    eq("started: persisted", ctx.data_store.state.end_at, end_at)
    check("started: redrawn", ctx.redraws >= 1)
    ctx.t = end_at
    refresh(ctx)
    eq("focus end: notified", #ctx.notes, 1)
    eq("focus end: break running", A.st.kind, "break")
    eq("focus end: break wake request", ctx.wakes[#ctx.wakes], end_at + 5 * 60)
    ctx.t = end_at + 5 * 60 + 1
    refresh(ctx)
    eq("break end: second notification", #ctx.notes, 2)
    eq("break end: other key", ctx.notes[2].key ~= ctx.notes[1].key, true)
    eq("break end: idle", A.st.mode, "idle")
end

-- pause / resume / reset / custom through the buttons
do
    local ctx = fresh()
    M.init(ctx); refresh(ctx)
    local calls = {}
    local ui = { theme = require("ui/theme") }
    local function w() return { getSize = function() return { w = 10, h = 10 } end } end
    ui.text, ui.space = function() return w() end, function() return w() end
    ui.box = function(o) return o end
    ui.vstack = function(parts) return { parts = parts } end
    ui.button_row = function(specs) for _, s in ipairs(specs) do calls[#calls + 1] = s end; return w() end
    ui.button = function(o) calls[#calls + 1] = { o.label, o.on_tap }; return w() end
    ctx.ui = ui
    local function build() calls = {}; M.screens.main(ctx, nil, { w = 584, h = 608, landscape = false }) end
    local function tap(label) for _, s in ipairs(calls) do if s[1] == label then s[2](); return true end end return false end
    build(); check("select 10 min", tap("10 min")); eq("selected", A.st.sel.min, 10)
    build(); tap("Iniciar"); eq("running 10", A.st.total, 600)
    ctx.t = ctx.t + 240
    build(); check("Pausar", tap("Pausar")); eq("paused", A.st.mode, "paused"); eq("paused left", A.st.left, 360)
    eq("pause cancels the wake request", ctx.wakes[#ctx.wakes], false)
    ctx.t = ctx.t + 5000
    build(); check("Retomar", tap("Retomar")); eq("resumed", A.st.mode, "running")
    eq("resume wake request", ctx.wakes[#ctx.wakes], ctx.t + 360)
    build(); check("Zerar", tap("Zerar")); eq("reset", A.st.mode, "idle")
    eq("reset cancels", ctx.wakes[#ctx.wakes], false)
    build(); check("Outro…", tap("Outro…"))
    local inp = ctx.inputs[1]
    check("custom: input asked with number keyboard", inp and inp.opts and inp.opts.number == true)
    local ok, msg = inp.on_save("0")
    check("custom: invalid refused with a message", ok == false and msg == "Digite de 1 a 600 minutos")
    check("custom: valid saved", inp.on_save("45") == true)
    eq("custom: selection", A.st.sel.min, 45); eq("custom: remembered in settings", ctx.settings_store.custom_min, 45)
end
