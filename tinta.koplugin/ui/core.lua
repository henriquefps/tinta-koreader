-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (C) 2026 Tinta contributors
-- Tinta: the only place where ui/ talks to core/. Every call the UI makes into core/ goes through here and is
-- listed in ui/CORE_CALLS.md, against core/README.md (the core-logic interface). The rest of ui/ never
-- requires core/ directly, so a change of core names means editing this file only.
--
-- c = { store, settings, notify, registry, Layout, Scheduler, Format, I18n, Registry, ctxs, log }
local M = {}

local Format = require("core/format")
local I18n = require("core/i18n")
local Appfiles = require("core/appfiles")
local Layout = require("core/layout")
local Notify = require("core/notify")
local Power = require("core/power")
local Registry = require("core/registry")
local Scheduler = require("core/scheduler")
local Settings = require("core/settings")
local FirstRun = require("core/firstrun")
local Store = require("core/store")

-- opts = { db_path, now, log = fn(app, level, msg), on_new = fn(notification), extra_ctx = fn(id) -> table }
-- Returns c. Never throws for a bad database: store.lua renames it (R-B4) or falls back to memory.
function M.open(opts)
    local now = opts.now or os.time
    -- core logs are log(level, app, msg); the host's are log(app, level, msg)
    local function log(level, app, msg) if opts.log then opts.log(app, level, msg) end end
    local c = { Layout = Layout, Scheduler = Scheduler, Format = Format, I18n = I18n, Registry = Registry,
        now = now, log = log, extra_ctx = opts.extra_ctx }
    local ok, store, info = pcall(Store.open, opts.db_path, { now = now })
    if not ok or not store then
        log("error", nil, "store: " .. tostring(store))
        store, info = Store.memory(), nil
    end
    if info and (info.recovered or info.fallback or info.error) then
        log("warn", nil, "store: " .. tostring(info.error or (info.recovered and ("recovered, old file " .. tostring(info.bad_path))) or "memory fallback"))
    end
    c.store = store
    c.settings = Settings.new{ store = store }
    c.notify = Notify.new{
        store = store, now = now, log = log,
        pref = function(app) return c.settings:notify_pref(app) end,
        on_new = opts.on_new,
    }
    c.notify:begin_session()   -- 8.6: the first reading after opening only records state
    c.registry = Registry.new{ now = now, log = log, store = store, notify = c.notify,
        is_disabled = function(id) return c.settings:is_disabled(id) end }
    return c
end

function M.close(c)
    if c and c.store and c.store.close then pcall(c.store.close, c.store) end
end

-- One refresh cycle in one transaction (R-B2)
function M.transaction(c, fn, ...)
    if c.store.transaction then return c.store:transaction(fn, ...) end
    return pcall(fn, ...)
end

---------------------------------------------------------------- apps and ctx

-- Registers a manifest, its settings defaults and its ctx (core part + what ui adds: open, confirm, toast,
-- ui, net). Returns true or nil, reason; an app that needs a newer Tinta (api / min_portal, 5.1) or that the
-- user turned off (10.5) is not loaded: reason "api" | "min_portal" | "disabled", and it shows in inactive_list.
function M.register(c, manifest)
    local ok, err = c.registry:register(manifest)
    if not ok then return nil, err end
    c.settings:register_app(manifest)
    local ctx = Registry.make_ctx(manifest.id, {
        registry = c.registry, store = c.store, settings = c.settings, notify = c.notify, now = c.now, log = c.log,
    })
    if c.extra_ctx then
        for k, v in pairs(c.extra_ctx(manifest.id) or {}) do ctx[k] = v end
    end
    pcall(c.registry.check_version, c.registry, manifest.id, ctx)   -- R-D2
    return true
end

function M.list_apps(c) return c.registry:list() end
-- 5.1, 10.5: manifests that are not loaded: { id, name, names, why = "disabled" | "api" | "min_portal", system,
-- protected, api, min_portal, manifest }
function M.inactive_list(c) return c.registry:inactive_list() end
function M.inactive(c, id) return c.registry:inactive_get(id) end
M.TINTA_VERSION = Registry.TINTA_VERSION
M.API_VERSION = Registry.API_VERSION
function M.is_protected(id) return Registry.PROTECTED[id] == true end
function M.app(c, id) return c.registry:get(id) end
function M.ctx(c, id) return c.registry:ctx(id) end

function M.init_apps(c)
    for _, id in ipairs(c.registry:ids()) do
        if c.registry:has(id, "init") then c.registry:call(id, "init", c.registry:ctx(id)) end
    end
end

-- init of one app (turned on while the Tinta is open)
function M.init_app(c, id)
    if c.registry:has(id, "init") then c.registry:call(id, "init", c.registry:ctx(id)) end
end

-- registration order after a late register (cmp on ids)
function M.sort_apps(c, cmp) c.registry:sort_order(cmp) end

-- Apps that declare manifest.background(ctx, now, kind): listed once (after loading), so the host tick does not
-- walk the registry every 5 s.
function M.background_ids(c)
    local out = {}
    for _, id in ipairs(c.registry:ids()) do
        if c.registry:has(id, "background") then out[#out + 1] = id end
    end
    return out
end

-- Calls background(ctx, now, kind) of each id, protected (R-E1): an app that throws is logged and the others still run.
function M.background(c, ids, now, kind)
    for _, id in ipairs(ids) do c.registry:call(id, "background", c.registry:ctx(id), now, kind) end
end

-- R-B5, 16.4: for each app with manifest.import_legacy(ctx) whose meta key "legacy_imported:<id>" is unset, call
-- it once (protected, R-E1) and set the key. An app that throws, or returns false (nothing to read yet), is
-- asked again on the next open. Returns the ids imported now.
function M.import_legacy(c)
    local done = {}
    for _, id in ipairs(c.registry:ids()) do
        local key = "legacy_imported:" .. id
        if c.registry:has(id, "import_legacy") and not c.store:meta_get(key) then
            local ok, res = c.registry:call(id, "import_legacy", c.registry:ctx(id))
            if ok and res ~= false then
                c.store:meta_set(key, c.now())
                done[#done + 1] = id
            end
        end
    end
    return done
end

-- Protected call into an app with its ctx first (R-A2, R-E1). fn: manifest path ("widget", "attention",
-- "on_route", "footer", "screens.main") or a function. Returns true, results... or false, err (logged, R-E3).
function M.call(c, id, fn, ...)
    return c.registry:call(id, fn, c.registry:ctx(id), ...)
end

-- protected call of a callback the app handed to the UI (buttons, confirm); logged on error (R-E1, R-E3)
function M.call_fn(c, id, fn, label, ...)
    return c.registry:call_fn(id, fn, label, ...)
end

function M.has(c, id, name) return c.registry:has(id, name) end

-- Starts a refresh. done(ok, err, kind) with kind "net" (done(false) or timeout: R-U6) or "app" (exception,
-- R-E4). manual clears the R-E4 lock (R-U7). Returns true, or false, "busy" (queued) | "disabled" | ...
function M.refresh(c, id, done, manual)
    return c.registry:refresh(id, c.registry:ctx(id), {
        manual = manual,
        on_done = function(_, ok, err, kind) done(ok, err, kind == "exception" and "app" or "net") end,
    })
end

-- ctx.state: { last_ok, last_err, err_text, busy, fail_streak, exc_streak, disabled }
function M.state(c, id) return c.registry:state(id) or {} end

-- an error outside registry:call (window callbacks, render), logged like R-E3
function M.log_error(c, id, where, err)
    local frame = Registry.first_frame(debug.traceback and tostring(err) or nil)
    local msg = tostring(err):match("[^\n]*")
    c.log("error", id, (where or "?") .. ": " .. msg .. (frame and frame ~= msg and (" · " .. frame) or ""))
end

---------------------------------------------------------------- 10.5 turn off / remove apps

function M.is_disabled(c, id) return c.settings:is_disabled(id) end

-- Turns an app off (loaded -> parked) or on (the caller registers the manifest again, see ui/host). The layouts
-- keep the app, so turning it on restores its place. Returns true | nil, "protected" | "id".
function M.set_disabled(c, id, off)
    local ok, err = c.settings:set_disabled(id, off)
    if not ok then return nil, err end
    if off then c.registry:unload(id) end
    return true
end

function M.removed_ids(c) return c.settings:removed_ids() end
function M.clear_removed(c) c.settings:clear_removed() end

-- "Remover app": deletes apps_dir/<id>/ (fs as core/appfiles wants it), then clears what the store holds for the
-- app (settings, data, cache, state, notifications) and takes it out of the layouts, and records the id in the
-- removed list so a copy of the whole plugin folder does not bring it back at load. The system apps (manifest
-- system = true, notificacoes, sistema) are refused. Returns true | nil, reason.
function M.remove_app(c, id, fs, apps_dir)
    if not Appfiles.valid_id(id) then return nil, "bad id" end
    local m = c.registry:get(id) or (c.registry:inactive_get(id) or {}).manifest
    if Registry.PROTECTED[id] or (m and m.system) then return nil, "system" end
    local ok, err = Appfiles.remove(fs, apps_dir, id)
    if not ok and err ~= "not a folder" then return nil, err end   -- already gone is fine: clean up the rest
    c.registry:forget(id)
    pcall(c.store.purge_app, c.store, id)
    for _, page in ipairs({ "home", "sleep" }) do
        local list = c.store:layout_get(page)
        if list then
            local keep = {}
            for _, it in ipairs(list) do if it.app ~= id then keep[#keep + 1] = it end end
            if #keep ~= #list then c.store:layout_set(page, keep) end
        end
    end
    c.settings:add_removed(id)
    return true
end

---------------------------------------------------------------- layout

-- items { { app, size }, ... } (already visible and sized) -> pages of { app, size, x, y, w, h } (0-based cells)
function M.pack(c, items, cols, rows) return Layout.pack(items, cols, rows) end
function M.default_layout(c, page) return Layout.default(page, c.registry:list()) end
function M.load_layout(c, page) return c.store:layout_get(page) end
function M.save_layout(c, page, list) return c.store:layout_set(page, list) end

---------------------------------------------------------------- scheduler and state texts

local function quiet(c) return c.settings:tinta("quiet") end

-- ids due now (R-U4), for the apps `ids`
function M.due(c, ids, now, wifi)
    local entries = c.registry:sched_entries(ids, c.settings)
    local due = Scheduler.pick(entries, now, { wifi = wifi, quiet = quiet(c) })
    return due or {}
end

-- manual refresh (R-U7): ids to run and network ids skipped without Wi-Fi (R-U5)
function M.manual(c, ids, wifi)
    local entries = c.registry:sched_entries(ids, c.settings)
    return Scheduler.manual(entries, { wifi = wifi })
end

-- Scheduler.status of an app: { kind = none|busy|error|failed|paused|ok, last_ok, interval, resume }
function M.status(c, id, now)
    local e = c.registry:sched_entry(id, c.settings)
    if not e then return { kind = "none" } end
    return Scheduler.status(e, now, { quiet = quiet(c) })
end

function M.next_run(c, id, now)
    local e = c.registry:sched_entry(id, c.settings)
    return e and Scheduler.next_run(e, now, { quiet = quiet(c) }) or nil
end

-- R-W4 footer: left, right
function M.footer(c, st, narrow, now)
    local parts = Format.footer(st, narrow, now) or {}
    return parts[1], parts[2]
end

-- 6.4 header text
function M.header(c, st, now) return Format.header(st, now) end

---------------------------------------------------------------- sleep (11, core/power)

-- Timestamp of the next RTC wake-up from `now` for the "wake" setting (nil = never wakes)
function M.next_wakeup(c, now) return Power.next_wakeup(now, { wake = c.settings:tinta("wake") }) end
function M.rtc_seconds(c, target, now) return Power.rtc_seconds(target, now) end
-- "button" | "scheduled" | "unscheduled", o = { powerd_state, reason, target, now, tolerance }
function M.classify_wakeup(c, o) return Power.classify_wakeup(o) end
-- `plugged`: boolean or function (only called when the mode is "battery" and the idle time is due)
function M.idle_due(c, last_touch, now, plugged)
    return Power.idle_due(last_touch, now, c.settings:tinta("idle_sleep"), c.settings:tinta("idle_mode"), plugged)
end
-- R-S4 text of the sleep status bar
function M.sleep_bar(c, updated_at, next_at) return Power.sleep_bar(updated_at, next_at) end
M.RTC_REPEAT = Power.RTC_REPEAT
M.WIFI_TIMEOUT = Power.WIFI_TIMEOUT

-- R-P6: the apps to refresh on a scheduled wake-up, out of `ids` (the apps of the sleep page): returns ids
-- and whether any of them needs the network (Wi-Fi is only brought up for those)
function M.wake_plan(c, ids, now)
    local entries = c.registry:sched_entries(ids, c.settings)
    local picked = Scheduler.wake(entries, now, { quiet = quiet(c) }) or {}
    local want, need_net = {}, false
    for _, id in ipairs(picked) do want[id] = true end
    for _, e in ipairs(entries) do
        if want[e.id] and e.net then need_net = true end
    end
    return picked, need_net
end

---------------------------------------------------------------- settings

function M.tinta(c, key) return c.settings:tinta(key) end
function M.set_tinta(c, key, v) return c.settings:set_tinta(key, v) end
function M.cycle_tinta(c, key) return c.settings:cycle_tinta(key) end
function M.app_get(c, id, key) return c.settings:get(id, key) end
-- validated (R-C1/R-C3); an empty token keeps the current one (R-C2). true, value | nil, reason
function M.app_set_field(c, id, key, v) return c.settings:set_field(id, key, v) end
function M.app_display(c, id, key, T) return c.settings:display(id, key, T) end
function M.interval(c, id) return c.settings:interval(id) end
function M.cycle_interval(c, id) return c.settings:cycle_interval(id) end
function M.set_interval(c, id, v) return c.settings:set_interval(id, v) end
function M.intervals() return Scheduler.INTERVALS end
function M.window(c, id) return c.settings:window(id) end
function M.notify_pref(c, id) return c.settings:notify_pref(id) end
function M.set_notify_pref(c, id, v) return c.settings:set_notify_pref(id, v) end
function M.choices(c, key) return Settings.CHOICES[key] end
-- 6.1: font factor of a "text_size" value
function M.text_factor(v) return Settings.text_factor(v) end
-- 8.5: may the app's widget show its content on the sleep page
function M.sleep_visible(c, id) return c.settings:sleep_visible(id) end
function M.set_sleep_visible(c, id, visible) return c.settings:set_sleep_visible(id, visible) end

-- 8.5: once per install, the first time this Tinta version opens. A fresh install keeps the manifest defaults (apps
-- with `sensitive = true` are hidden on the sleep page); an install that existed before the option keeps what it
-- showed: every sensitive app with no saved choice is saved as "shown", so its sleep page does not change.
M.PRIVACY_MARK = "sleep_privacy_init"
function M.privacy_init(c, fresh)
    if c.store:meta_get(M.PRIVACY_MARK) then return false end
    if not fresh then
        for _, id in ipairs(c.registry:ids()) do
            local m = c.registry:get(id)
            if m and m.sensitive == true and c.store:get(id, Settings.SLEEP_SHOW_KEY) == nil then
                c.settings:set_sleep_visible(id, true)
            end
        end
    end
    c.store:meta_set(M.PRIVACY_MARK, "1")
    return true
end

---------------------------------------------------------------- first run (7.5)

-- fresh install? Call before the apps are registered. ids: the app folders on disk.
function M.first_run_needed(c, ids)
    local ok, needed = pcall(FirstRun.needed, c.store, ids)
    if ok and needed then pcall(FirstRun.mark_pending, c.store) end
    return ok and needed or false
end
function M.first_run_done(c, at) return pcall(FirstRun.mark_done, c.store, at) end

---------------------------------------------------------------- notifications

function M.notifications(c, opts) return c.notify:list(opts) or {} end
-- central page (R-T9); page is 0-based here, 1-based in core
function M.notif_page(c, page, per)
    local items, p, pages = c.notify:page((page or 0) + 1, per)
    return items or {}, (p or 1) - 1, pages or 1
end
function M.notif_count(c) return c.notify:count() end
function M.unread_count(c) return c.notify:unread_count() end
function M.mark_all_read(c) return c.notify:mark_all_read() end
function M.clear_notifications(c) return c.notify:clear() end
-- 8.4: marks read, returns { id, app, screen, args }
function M.open_notification(c, id) return c.notify:open(id) end
function M.emit(c, app, n) return c.notify:emit(app, n) end
-- R-T11: nil or { count, latest, text }
function M.sleep_summary(c, mode, hide_titles) return c.notify:sleep_summary(mode, hide_titles) end
-- R-T5: "App · HH:MM", title
function M.banner_lines(c, n, app_name) return c.notify.banner_lines(n, app_name) end
-- 8.6 Sistema rules: src = { id, name, host }
function M.source_result(c, src, ok, ms) return c.notify:source_result(src, ok, ms) end
function M.source_state(c, id) return c.notify:source_state(id) end

---------------------------------------------------------------- log and data

function M.log(c, app, level, msg) return c.store:log(c.now(), app, level, msg) end
-- newest first: { { at, app, level, msg }, ... }
function M.log_list(c, offset, limit) return c.store:log_list{ offset = offset, limit = limit } or {} end
-- { notifications, log, size_bytes }
function M.stats(c) return c.store:stats() or {} end

-- Sistema → Dados (diagnostic export, settings backup): settings without secrets, layouts, versions
function M.redacted_scope(c, scope) return c.settings:redacted_scope(scope) end
function M.backup_env(c)
    return {
        settings = c.settings,
        layout_get = function(page) return c.store:layout_get(page) end,
        layout_set = function(page, list) return c.store:layout_set(page, list) end,
        valid_size = Layout.valid_size,
    }
end
-- version of the app contract (manifest + ctx); 1 until the registry declares one
function M.api_version() return Registry.API_VERSION or 1 end

---------------------------------------------------------------- format and i18n

function M.hm(c, t) return Format.hm(t) end
function M.ago(c, now, t) return Format.ago(t, now) end
function M.every(c, sec) return Format.every(sec) end
function M.set_lang(c, lang) I18n.set_lang(lang) end

return M
