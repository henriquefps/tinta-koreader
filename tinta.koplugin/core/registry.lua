-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (C) 2026 Tinta contributors
-- App registry (spec 5): manifests, protected calls (R-A2, R-E1..R-E4), per-app state (ctx.state), refresh
-- runs with one in flight per app (R-U8), app schema versions (R-D2) and the core part of ctx (5.2).
-- Pure Lua (R-A1): clock, log, store and notification center are injected.
local Layout = require("core/layout")
local I18n = require("core/i18n")
local Version = require("core/version")

local M = {}

M.EXC_LIMIT = 3            -- R-E4: three refresh exceptions in a row turn auto refresh off
M.TINTA_VERSION = Version.TINTA_VERSION
M.API_VERSION = Version.API_VERSION
-- apps the user cannot turn off (10.5): the notification center and Sistema itself
M.PROTECTED = { notificacoes = true, sistema = true }
M.BUSY_TIMEOUT = 120       -- s; a refresh that never calls done() stops blocking the app after this

-- First frame of a traceback ("file:line: in function ..."), for R-E3.
local function first_frame(tb)
    if type(tb) ~= "string" then return nil end
    for line in tb:gmatch("[^\n]+") do
        local l = line:gsub("^%s+", "")
        if l ~= "" and not l:match("^stack traceback:") and not l:match("%[C%]: in function 'error'")
                and not l:match("%[C%]: in function 'xpcall'") then
            return l
        end
    end
end
M.first_frame = first_frame

local function handler(e)
    return { msg = tostring(e), tb = debug and debug.traceback and debug.traceback("", 2) or nil }
end

-- Validates a manifest (5.1). Returns true or nil, reason. `refresh` may be absent: such an app has no
-- refresh at all (Notificações, Sistema); when present it must be a function.
function M.validate(m)
    if type(m) ~= "table" then return nil, "manifest is not a table" end
    if type(m.id) ~= "string" or not m.id:match("^[a-z0-9_]+$") then return nil, "bad id" end
    if type(m.name) ~= "string" or m.name == "" then return nil, "bad name" end
    if type(m.sizes) ~= "table" or #m.sizes == 0 then return nil, "no sizes" end
    for _, s in ipairs(m.sizes) do
        if not Layout.valid_size(s) then return nil, "bad size " .. tostring(s) end
    end
    if type(m.widget) ~= "function" then return nil, "no widget()" end
    if m.refresh ~= nil and type(m.refresh) ~= "function" then return nil, "refresh is not a function" end
    if m.background ~= nil and type(m.background) ~= "function" then return nil, "background is not a function" end
    if m.screens ~= nil and type(m.screens) ~= "table" then return nil, "screens is not a table" end
    if m.api ~= nil and (type(m.api) ~= "number" or m.api < 1 or m.api % 1 ~= 0) then return nil, "bad api" end
    if m.default_layout ~= nil and type(m.default_layout) ~= "table" then return nil, "default_layout is not a table" end
    if m.min_tinta ~= nil and not Version.parse(m.min_tinta) then return nil, "bad min_tinta" end
    if m.min_portal ~= nil and not Version.parse(m.min_portal) then return nil, "bad min_portal" end
    return true
end

-- 5.1: can this Tinta load the app? Apps without `api` are api 1. Returns true, or false, "api" | "min_tinta" | "min_portal".
-- A manifest that does not even have the shape of an app is for validate() to reject, not for this.
function M.compat(m)
    if type(m) ~= "table" then return true end
    local api = type(m.api) == "number" and m.api or 1
    if api > M.API_VERSION then return false, "api" end
    -- min_tinta; min_portal is what manifests said before the platform was named Tinta, and still counts
    for _, field in ipairs({ "min_tinta", "min_portal" }) do
        if m[field] ~= nil then
            local c = Version.compare(m[field], M.TINTA_VERSION)
            if c and c > 0 then return false, field end
        end
    end
    return true
end

-- Registry.new{ now = fn, log = fn(level, app, msg), store = store (optional: app_state, versions),
--               notify = center (optional: arm after the first good reading), busy_timeout = s,
--               is_disabled = fn(id) -> bool (optional: the user turned the app off, 10.5) }
function M.new(opts)
    opts = opts or {}
    local now = opts.now or os.time
    local log = opts.log or function() end
    local store = opts.store
    local busy_timeout = opts.busy_timeout or M.BUSY_TIMEOUT

    local R = { apps = {}, order = {}, states = {}, ctxs = {}, inactive = {}, inactive_order = {} }
    local is_disabled = opts.is_disabled

    -- An app that is not loaded but must still be listed (Sistema → Apps, launcher): the manifest is kept,
    -- with why: "disabled" | "api" | "min_tinta" | "min_portal".
    local function park(m, why)
        if not R.inactive[m.id] then R.inactive_order[#R.inactive_order + 1] = m.id end
        R.inactive[m.id] = { id = m.id, name = type(m.name) == "string" and m.name or m.id, names = m.names, why = why,
            system = m.system and true or false, protected = M.PROTECTED[m.id] and true or false,
            api = m.api, min_portal = m.min_portal, min_tinta = m.min_tinta, description = m.description, manifest = m }
    end
    local function unpark(id)
        if not R.inactive[id] then return end
        R.inactive[id] = nil
        for i, x in ipairs(R.inactive_order) do if x == id then table.remove(R.inactive_order, i); break end end
    end

    local function persist(id)
        if store then
            local ok, err = pcall(store.state_set, store, id, R.states[id])
            if not ok then log("error", id, "registry: state not saved: " .. tostring(err)) end
        end
    end

    -- Registers a manifest. Returns true or nil, reason (logged; never throws).
    -- An app that needs a newer Tinta (api / min_portal) or that the user turned off is not loaded: it is kept
    -- in :inactive() and register returns nil, "api" | "min_portal" | "disabled".
    function R:register(m)
        if type(m) == "table" and type(m.id) == "string" and m.id:match("^[a-z0-9_]+$") and not self.apps[m.id] then
            local cok, why = M.compat(m)
            if not cok then
                park(m, why)
                log("warn", m.id, "registry: not loaded, needs a newer Tinta (" .. why .. ")")
                return nil, why
            end
            if is_disabled and not M.PROTECTED[m.id] and is_disabled(m.id) then
                park(m, "disabled")
                return nil, "disabled"
            end
            unpark(m.id)
        end
        local ok, err = M.validate(m)
        if ok and self.apps[m.id] then ok, err = nil, "duplicate id" end
        if not ok then
            log("error", type(m) == "table" and tostring(m.id) or nil, "registry: rejected manifest: " .. err)
            return nil, err
        end
        self.apps[m.id] = m
        self.order[#self.order + 1] = m.id
        local st = { busy = false, fail_streak = 0, exc_streak = 0, disabled = false }
        if store then
            local oks, saved = pcall(store.state_get, store, m.id)
            if oks and saved then
                st.last_ok, st.last_err, st.err_text = saved.last_ok, saved.last_err, saved.err_text
                st.fail_streak = saved.fail_streak or 0
            end
        end
        self.states[m.id] = st
        return true
    end

    -- Not loaded apps, in the order they were seen: { id, name, names, why, system, protected, api, min_portal, manifest }
    function R:inactive_list()
        local o = {}
        for i, id in ipairs(self.inactive_order) do o[i] = self.inactive[id] end
        return o
    end
    function R:inactive_get(id) return self.inactive[id] end

    -- Turns a loaded app into a parked one (disable at runtime). Returns false for unknown or protected ids.
    function R:unload(id)
        local m = self.apps[id]
        if not m or M.PROTECTED[id] then return false end
        self.apps[id], self.states[id], self.ctxs[id] = nil, nil, nil
        for i, x in ipairs(self.order) do if x == id then table.remove(self.order, i); break end end
        park(m, "disabled")
        return true
    end

    -- Drops an app completely (removed): loaded or parked, it is gone from every list.
    function R:forget(id)
        if M.PROTECTED[id] then return false end
        if self.apps[id] then
            self.apps[id], self.states[id], self.ctxs[id] = nil, nil, nil
            for i, x in ipairs(self.order) do if x == id then table.remove(self.order, i); break end end
        end
        unpark(id)
        return true
    end

    -- Sorts the registration order (organizer and Sistema order) after a late register; cmp(a, b) on ids.
    function R:sort_order(cmp) table.sort(self.order, cmp) end

    function R:get(id) return self.apps[id] end
    function R:ids() local o = {} for i, id in ipairs(self.order) do o[i] = id end return o end
    function R:list() local o = {} for i, id in ipairs(self.order) do o[i] = self.apps[id] end return o end
    -- ctx.state (5.2): { last_ok, last_err, err_text, busy, fail_streak, exc_streak, disabled }
    function R:state(id) return self.states[id] end
    function R:set_ctx(id, ctx) self.ctxs[id] = ctx end
    function R:ctx(id) return self.ctxs[id] end

    -- Resolves "refresh", "screens.main", ... in the manifest.
    local function resolve(m, name)
        if type(name) == "function" then return name end
        local v = m
        for part in tostring(name):gmatch("[^%.]+") do
            if type(v) ~= "table" then return nil end
            v = v[part]
        end
        return type(v) == "function" and v or nil
    end

    function R:has(id, name)
        local m = self.apps[id]
        return m ~= nil and resolve(m, name) ~= nil
    end

    -- R-A2/R-E1: every call into an app. `name` is a manifest path ("init", "screens.main") or a function the
    -- app handed over (callbacks). Returns true, results... or false, err. A missing function returns
    -- false, "missing" without logging; an error is logged with app, function and first frame (R-E3).
    function R:call(id, name, ...)
        local m = self.apps[id]
        if not m then return false, "unknown app" end
        local fn = resolve(m, name)
        if not fn then return false, "missing" end
        local args, n = { ... }, select("#", ...)
        local res = { xpcall(function() return fn(unpack(args, 1, n)) end, handler) }
        if res[1] then return unpack(res, 1, table.maxn(res)) end
        local e = res[2]
        local label = type(name) == "string" and name or "callback"
        local frame = first_frame(e.tb)
        log("error", id, label .. ": " .. e.msg .. (frame and (" · " .. frame) or ""))
        return false, e.msg
    end

    -- Wraps a callback from an app so the core can call it safely (R-E1): errors are logged, never raised.
    function R:wrap(id, fn, label)
        local reg = self
        return function(...)
            local res = { reg:call_fn(id, fn, label, ...) }
            if not res[1] then return nil end
            return unpack(res, 2, table.maxn(res))
        end
    end
    function R:call_fn(id, fn, label, ...)
        if type(fn) ~= "function" then return false, "missing" end
        local args, n = { ... }, select("#", ...)
        local res = { xpcall(function() return fn(unpack(args, 1, n)) end, handler) }
        if res[1] then return unpack(res, 1, table.maxn(res)) end
        local frame = first_frame(res[2].tb)
        log("error", id, (label or "callback") .. ": " .. res[2].msg .. (frame and (" · " .. frame) or ""))
        return false, res[2].msg
    end

    -- R-E2: the widget, or fallback(manifest, size, box, err) ("Nome · erro na app") when it fails or
    -- returns nothing.
    function R:widget(id, ctx, size, box, fallback)
        local ok, w = self:call(id, "widget", ctx, size, box)
        if ok and w ~= nil then return w, true end
        local m = self.apps[id]
        local err = ok and "widget() returned nil" or w
        if fallback then return fallback(m, size, box, err), false end
        return nil, false, err
    end

    -- R-E2: a screen, or fallback(manifest, name, err) (error screen with Voltar) when it fails or is missing.
    function R:screen(id, name, ctx, args, fallback)
        local ok, s = self:call(id, "screens." .. tostring(name), ctx, args)
        if ok and s ~= nil then return s, true end
        local err = ok and "screen returned nil" or s
        if fallback then return fallback(self.apps[id], name, err), false end
        return nil, false, err
    end

    -- attention(ctx) -> boolean; false when missing or on error.
    function R:attention(id, ctx)
        local ok, v = self:call(id, "attention", ctx)
        return ok and v and true or false
    end

    -- Text for the error widget (R-E2).
    function R:error_text(id)
        local m = self.apps[id]
        return I18n.t("widget_error", m and m.name or tostring(id))
    end

    -- Runs one refresh (R-U8: one in flight per app; a request while busy is queued and runs after).
    -- opts = { manual = bool, on_done = fn(id, ok, err, kind) } with kind = "done" | "exception" | "timeout".
    -- Returns true when started, or false, reason: "unknown" | "no_refresh" | "busy" (queued) | "disabled".
    -- manual (R-U7) also clears the R-E4 lock.
    function R:refresh(id, ctx, ropts)
        ropts = ropts or {}
        local m = self.apps[id]
        if not m then return false, "unknown" end
        if not m.refresh then return false, "no_refresh" end
        local st = self.states[id]
        local t0 = now()
        if st.busy then
            if t0 - (st.busy_since or t0) < busy_timeout then
                st.pending = st.pending or {}
                st.pending.manual = st.pending.manual or ropts.manual or false
                st.pending.on_done = ropts.on_done or st.pending.on_done
                return false, "busy"
            end
            -- the previous run never finished: count it as a failure and move on
            st.busy, st.token = false, nil
            st.last_err, st.err_text = t0, "timeout"
            st.fail_streak = (st.fail_streak or 0) + 1
            log("warn", id, "registry: refresh timed out")
            if ropts.on_done then pcall(ropts.on_done, id, false, "timeout", "timeout") end
        end
        if ropts.manual then
            if st.disabled then log("info", id, "registry: auto refresh back on (manual)") end
            st.disabled, st.exc_streak = false, 0
        elseif st.disabled then
            return false, "disabled"
        end

        local token = {}
        st.busy, st.busy_since, st.token = true, t0, token
        local finished = false
        local reg = self

        local function after(ok, err, kind)
            if ropts.on_done then
                local okc, e = pcall(ropts.on_done, id, ok, err, kind)
                if not okc then log("error", id, "registry: on_done: " .. tostring(e)) end
            end
            local p = st.pending
            if p then
                st.pending = nil
                reg:refresh(id, ctx or reg.ctxs[id], { manual = p.manual, on_done = p.on_done })
            end
        end

        -- done(ok, err) handed to the app; only the first call of the current run counts
        local function done(ok, err)
            if finished or st.token ~= token then return end
            finished = true
            st.busy, st.token, st.busy_since = false, nil, nil
            st.exc_streak = 0
            if ok then
                st.last_ok, st.err_text, st.fail_streak = now(), nil, 0
                if opts.notify then opts.notify:arm(id) end
            else
                st.last_err, st.err_text = now(), tostring(err or "error")
                st.fail_streak = (st.fail_streak or 0) + 1
            end
            persist(id)
            after(ok and true or false, err, "done")
        end

        local ok, err = self:call(id, "refresh", ctx or self.ctxs[id], done)
        if not ok and not finished then
            finished = true
            st.busy, st.token, st.busy_since = false, nil, nil
            st.exc_streak = (st.exc_streak or 0) + 1
            st.last_err, st.err_text = now(), I18n.t("app_error")
            if st.exc_streak >= M.EXC_LIMIT and not st.disabled then
                st.disabled = true
                log("error", id, "registry: " .. M.EXC_LIMIT .. " refresh errors in a row, auto refresh off (R-E4)")
            end
            persist(id)
            after(false, err, "exception")
        end
        return true
    end

    -- Entries for core/scheduler (pick/manual/wake/status/next_run). `settings` gives interval and window
    -- (settings:interval(id), settings:window(id)). manifest.in_window(ctx, now), when present, decides the
    -- window (R-U2, e.g. working days); errors there count as "inside".
    function R:sched_entry(id, settings)
        local m = self.apps[id]
        if not m then return nil end
        local st = self.states[id]
        local window = settings and settings:window(id) or (m.defaults and m.defaults.window)
        if m.in_window then
            local reg = self
            local w = {}
            for k, v in pairs(window or {}) do w[k] = v end
            w.in_window = function(t)
                local ok, v = reg:call(id, "in_window", reg.ctxs[id], t)
                if not ok then return true end
                return v
            end
            window = w
        end
        local interval = nil
        if m.refresh then
            interval = settings and settings:interval(id)
            if interval == nil then interval = (m.defaults or {}).interval end
            if interval == nil then interval = 0 end
        end
        return {
            id = id, interval = interval, net = m.net and true or false, window = window,
            last_ok = st.last_ok, last_err = st.last_err, busy = st.busy, disabled = st.disabled,
        }
    end
    function R:sched_entries(ids, settings)
        local out = {}
        for _, id in ipairs(ids or self.order) do
            local e = self:sched_entry(id, settings)
            if e then out[#out + 1] = e end
        end
        return out
    end

    -- R-D2: when manifest.version is higher than the stored one, calls migrate(ctx, from, to) if present;
    -- without migrate (or when it fails) the app's cache is cleared. Needs the store. Returns the action:
    -- "new" | "same" | "migrated" | "cache_cleared".
    function R:check_version(id, ctx)
        local m = self.apps[id]
        if not m or not store then return nil end
        local key = "app_version:" .. id
        local to = tonumber(m.version) or 1
        local from = tonumber(store:meta_get(key))
        if from == nil then store:meta_set(key, to); return "new" end
        if to <= from then return "same" end
        local action = "cache_cleared"
        if m.migrate then
            local ok = self:call(id, "migrate", ctx or self.ctxs[id], from, to)
            if ok then action = "migrated" else store:cache_clear(id) end
        else
            store:cache_clear(id)
        end
        store:meta_set(key, to)
        local c = ctx or self.ctxs[id]
        if c and c.cache and c.cache.reset then c.cache.reset() end   -- the in-memory copy may be stale now
        log("info", id, "registry: version " .. from .. " -> " .. to .. " (" .. action .. ")")
        return action
    end

    return R
end

-- Core part of ctx (5.2). deps = { registry, store, settings, notify, now, log = fn(level, app, msg) }.
-- ui/main adds open, confirm, toast, ui and net. ctx.cache:put stores with the manifest version.
function M.make_ctx(id, deps)
    local reg, store = deps.registry, deps.store
    local m = reg and reg:get(id) or {}
    local now = deps.now or os.time
    local log = deps.log or function() end
    local ctx = {
        id = id,
        now = now,
        state = reg and reg:state(id) or {},
        i18n = I18n.new(m.strings),
        log = function(msg) log("info", id, tostring(msg)) end,
    }
    if deps.settings then ctx.settings = deps.settings:scope(id) end
    if store then
        ctx.data = {
            get = function(_, k) return store:data_get(id, k) end,
            set = function(_, k, v) return store:data_set(id, k, v) end,
        }
        -- The decoded cache is kept in memory: reading it means a SQLite query plus a JSON decode, which on the
        -- Kindle's /mnt/us is slow, and apps read it often (an app's in_window is called for every minute the
        -- scheduler looks ahead). The value returned is shared: apps must treat it as read-only.
        local memo   -- nil = not loaded; else { value, fetched_at, version }
        ctx.cache = {
            get = function()
                if not memo then memo = { store:cache_get(id) } end
                return memo[1], memo[2], memo[3]
            end,
            put = function(_, tbl)
                local at, ver = now(), tonumber(m.version) or 1
                local r = store:cache_put(id, tbl, at, ver)
                memo = { tbl, at, ver }
                return r
            end,
            reset = function() memo = nil end,
        }
    end
    if deps.notify then ctx.notify = deps.notify:emitter(id) end
    if reg then reg:set_ctx(id, ctx) end
    return ctx
end

return M
