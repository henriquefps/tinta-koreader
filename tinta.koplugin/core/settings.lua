-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (C) 2026 Tinta contributors
-- Global and per-app settings over the store (spec 5.5, 9, 10.5, 11). Pure Lua (R-A1).
-- Scope "portal" holds the Tinta settings; each app uses its id as scope. A value never saved reads as the
-- default: Tinta defaults below, app defaults from the manifest (defaults table and settings fields).
local Scheduler = require("core/scheduler")
local Format = require("core/format")
local Registry = require("core/registry")

local M = {}

-- the scope keeps its stored name "portal": existing databases hold the settings under it (renaming the rows would
-- need a migration for no gain), and it is not shown anywhere
M.TINTA = "portal"

-- Tinta defaults. Keys are the ones core-ui shows in Sistema (10.5).
M.TINTA_DEFAULTS = {
    lang = "pt",                          -- 13, D7
    landscape = false,                    -- 6.8
    nav = "bar",                          -- R-N2: "bar" (barra + gestos) | "gestures" (só gestos)
    full_every = 10,                      -- R-R2
    wifi = true,                          -- R-P2: what the user chose with the Tinta awake
    quiet = { enabled = true, from = "23:00", to = "07:00" },   -- R-U3
    banner = true,                        -- R-T5
    sleep_shows = "alta",                 -- R-T11: "alta" | "todas" | "nenhuma"
    wake = "schedule",                    -- 10.5/11.4: seconds between wake-ups (900/1800/3600/7200), "schedule" | "never"
    idle_mode = "battery",                -- R-P4: idle sleep "always" | "battery" (not while plugged in) | "never"
    idle_sleep = 5,                       -- R-P4: minutes without touch (2/5/10/15; the mode "never" turns it off)
    disabled_apps = {},                   -- 10.5: ids of the apps the user turned off (not loaded at open)
    removed_apps = {},                    -- 10.5: ids of the apps the user removed (their folder is skipped at load)
    sleep_titles = "show",                -- 8.5: notification strip on the sleep page: "show" titles | "hide" ("1 não lida")
    text_size = "normal",                 -- 6.1: "normal" | "large" (factor on the theme's font sizes, M.TEXT_FACTORS)
}

-- 6.1: font factor of each "text_size" choice
M.TEXT_FACTORS = { normal = 1.0, large = 1.15 }
function M.text_factor(v) return M.TEXT_FACTORS[v] or 1.0 end

M.CHOICES = {
    nav = { "bar", "gestures" },
    sleep_shows = { "alta", "todas", "nenhuma" },
    wake = { 900, 1800, 3600, 7200, "schedule", "never" },
    idle_mode = { "always", "battery", "never" },
    idle_sleep = { 2, 5, 10, 15 },
    lang = { "pt", "en" },
    notify_pref = { "alta", "normal", "desligada" },   -- R-T2
    full_every = { 5, 10, 20 },
    sleep_titles = { "show", "hide" },
    text_size = { "normal", "large" },
    sleep_show = { "shown", "hidden" },   -- per app (8.5)
}

M.SLEEP_SHOW_KEY = "sleep_show"   -- per-app scope key: "shown" | "hidden"; the manifest's `sensitive = true` defaults to hidden

M.NOTIFY_KEY = "notify_pref"   -- per-app scope key for R-T2
M.FIELD_TYPES = { url = true, token = true, number = true, time = true, choice = true, bool = true }

local function copy(t)
    if type(t) ~= "table" then return t end
    local o = {}
    for k, v in pairs(t) do o[k] = copy(v) end
    return o
end

---------------------------------------------------------------- secrets (spec 14: what diagnostics and backups never carry)

-- Keys whose value is a secret whatever the app declares (a token field of a manifest is secret by its type).
function M.secret_key(key)
    local k = tostring(key):lower()
    return k:find("token", 1, true) or k:find("password", 1, true) or k:find("passwd", 1, true)
        or k:find("secret", 1, true) or k:find("apikey", 1, true) or k:find("api_key", 1, true)
        or k:find("authorization", 1, true) or false
end

-- true when a string holds a URL with credentials (scheme://user:pass@host or scheme://user@host)
function M.url_has_credentials(s)
    return type(s) == "string" and s:find("://[^/%s?#]*@") ~= nil
end

-- true when a value (or anything inside a table) is a URL with credentials
local function value_has_secret(v, depth)
    if type(v) == "string" then return M.url_has_credentials(v) end
    if type(v) == "table" and (depth or 0) < 4 then
        for k, x in pairs(v) do
            if M.secret_key(k) or value_has_secret(x, (depth or 0) + 1) then return true end
        end
    end
    return false
end
M.value_has_secret = value_has_secret

local REDACT_NAMES = {}
for _, n in ipairs({ "token", "password", "passwd", "secret", "api_key", "apikey" }) do
    REDACT_NAMES[#REDACT_NAMES + 1] = { plain = n, pattern = n:gsub("%a", function(c) return "[" .. c:upper() .. c:lower() .. "]" end) }
end

-- Free text (log lines) with the secrets taken out: credentials of URLs, token/password/secret assignments
-- (key=value, key: value, "key":"value") and Bearer/Basic headers.
function M.redact_text(s)
    s = tostring(s)
    s = s:gsub("(://)[^/%s?#]*@", "%1***@")
    local low = s:lower()
    for _, name in ipairs(REDACT_NAMES) do
        if low:find(name.plain, 1, true) then
            s = s:gsub("(" .. name.pattern .. "[%w_]*[\"']?%s*[=:]%s*[\"']?)([^%s\"',&}]+)",
                function(pre, val) return pre .. (val:find("^<redacted>") and val or "***") end)
        end
    end
    s = s:gsub("([Bb]earer%s+)[%w%-%._~%+/=]+", "%1***")
    s = s:gsub("([Bb]asic%s+)[%w%+/=]+", "%1***")
    return s
end

-- Validates one value for a settings field (R-C1). Returns ok, normalized_value | nil, reason.
-- reason: "type" | "range" | "choice" | "format" | "empty". A field's own validate(value) (R-C3) runs last and
-- may return false, reason.
function M.validate(field, value)
    local t = field.type
    local v = value
    if t == "url" then
        if type(v) ~= "string" then return nil, "type" end
        v = v:gsub("^%s+", ""):gsub("%s+$", "")
        if v == "" then return nil, "empty" end
        if not v:match("^https?://[%w%.%-]+[:%d]*") then return nil, "format" end
        v = v:gsub("/+$", "")
    elseif t == "token" then
        if type(v) ~= "string" then return nil, "type" end
        v = v:gsub("^%s+", ""):gsub("%s+$", "")
    elseif t == "number" then
        v = tonumber(v)
        if not v then return nil, "type" end
        if (field.min and v < field.min) or (field.max and v > field.max) then return nil, "range" end
    elseif t == "time" then
        if not Format.parse_hm(v) then return nil, "format" end
        local m = Format.parse_hm(v)
        v = Format.hm_from_minutes(m)
    elseif t == "choice" then
        local found = false
        for _, c in ipairs(field.choices or {}) do
            local cv = type(c) == "table" and c.value or c
            if cv == v then found = true end
        end
        if not found then return nil, "choice" end
    elseif t == "bool" then
        if type(v) ~= "boolean" then return nil, "type" end
    else
        return nil, "type"
    end
    if field.validate then
        local ok, res, reason = pcall(field.validate, v)
        if not ok then return nil, "format" end
        if res == false or res == nil then return nil, reason or "format" end
        if res ~= true then v = res end
    end
    return true, v
end

-- 10.5 Repouso: the old keys wake_every (minutes) and sleep_schedule (bool) became the single "wake" setting.
-- Pure mapping of the old values: schedule on -> "schedule"; else the nearest interval of M.CHOICES.wake;
-- 0/false (never) -> "never". Returns nil when neither old key was ever saved (the default applies).
function M.migrate_wake(every, schedule)
    if every == nil and schedule == nil then return nil end
    if schedule == true then return "schedule" end
    if every == nil then return 1800 end             -- old default (30 min) with the schedule turned off
    if every == false or every == 0 then return "never" end
    if type(every) ~= "number" or every < 0 then return nil end
    local best, bd
    for _, c in ipairs(M.CHOICES.wake) do
        if type(c) == "number" then
            local d = math.abs(c - every * 60)
            if not bd or d < bd then best, bd = c, d end
        end
    end
    return best
end

-- 10.5 Repouso: idle sleep was one setting (idle_sleep: 0 = never, or minutes). Pure mapping of the old value to
-- the new mode: 0 -> "never" and the minutes back to the default (second result false); a valid number of
-- minutes -> "always" (the user chose it before the option "só na bateria" existed) and the minutes stay;
-- never saved (or invalid) -> the default mode.
function M.migrate_idle(old)
    if old == 0 then return "never", false end
    for _, c in ipairs(M.CHOICES.idle_sleep) do
        if c == old then return "always", true end
    end
    if old ~= nil then return M.TINTA_DEFAULTS.idle_mode, false end   -- an invalid leftover: default minutes too
    return M.TINTA_DEFAULTS.idle_mode, true
end

-- Settings.new{ store = store } -> settings object.
function M.new(opts)
    opts = opts or {}
    local store = assert(opts.store, "settings: store required")
    local S = { store = store, defaults = { [M.TINTA] = copy(M.TINTA_DEFAULTS) }, fields = {} }
    for k, v in pairs(opts.tinta_defaults or {}) do S.defaults[M.TINTA][k] = copy(v) end

    -- Registers an app's defaults and fields: manifest.defaults (interval, window, ...) and manifest.settings
    -- ({ key, type, default, ... }). The notification preference defaults to "alta" (R-T2).
    function S:register_app(manifest)
        local d = { [M.NOTIFY_KEY] = "alta", [M.SLEEP_SHOW_KEY] = manifest.sensitive == true and "hidden" or "shown" }
        for k, v in pairs(manifest.defaults or {}) do d[k] = copy(v) end
        local fields = {}
        for _, f in ipairs(manifest.settings or {}) do
            fields[f.key] = f
            if f.default ~= nil and d[f.key] == nil then d[f.key] = copy(f.default) end
        end
        self.defaults[manifest.id] = d
        self.fields[manifest.id] = fields
    end

    -- Runs on creation: moves the old Repouso keys to "wake" once (nothing happens when "wake" is saved already
    -- or the old keys were never saved) and resets the old keys; then the idle sleep keys (M.migrate_idle).
    function S:migrate()
        local every = store:get(M.TINTA, "wake_every")
        local sched = store:get(M.TINTA, "sleep_schedule")
        if every ~= nil or sched ~= nil then
            if store:get(M.TINTA, "wake") == nil then
                local w = M.migrate_wake(every, sched)
                if w ~= nil then store:set(M.TINTA, "wake", w) end
            end
            store:set(M.TINTA, "wake_every", nil)
            store:set(M.TINTA, "sleep_schedule", nil)
        end
        -- idle sleep: before "idle_mode" existed, idle_sleep held 0 = never or the minutes. The mode is saved
        -- explicitly on the first run, so this happens once (a later change of the minutes is not read as old).
        if store:get(M.TINTA, "idle_mode") == nil then
            local mode, minutes = M.migrate_idle(store:get(M.TINTA, "idle_sleep"))
            store:set(M.TINTA, "idle_mode", mode)
            if minutes == false then store:set(M.TINTA, "idle_sleep", nil) end
        end
        if store:get(M.TINTA, "expediente") ~= nil then store:set(M.TINTA, "expediente", nil) end   -- modo expediente is gone
    end

    -- 8.5: may the app's widget show its content on the sleep page? (false: a neutral placeholder with its name)
    function S:sleep_visible(id) return self:get(id, M.SLEEP_SHOW_KEY) ~= "hidden" end
    function S:set_sleep_visible(id, visible) self:set(id, M.SLEEP_SHOW_KEY, visible and "shown" or "hidden") end

    function S:default(scope, key)
        return copy((self.defaults[scope] or {})[key])
    end

    function S:get(scope, key)
        local v = store:get(scope, key)
        if v == nil then return self:default(scope, key) end
        return v
    end

    -- Plain set (no validation); nil resets to the default.
    function S:set(scope, key, value)
        store:set(scope, key, value)
    end

    -- Set through the field declaration (R-C1/R-C3). Token fields: empty keeps the current value (R-C2).
    -- Returns true, value | nil, reason. Keys without a field declaration are set as is.
    function S:set_field(scope, key, value)
        local f = (self.fields[scope] or {})[key]
        if not f then self:set(scope, key, value); return true, value end
        if f.type == "token" and (value == nil or (type(value) == "string" and value:match("^%s*$"))) then
            return true, self:get(scope, key)
        end
        local ok, v = M.validate(f, value)
        if not ok then return nil, v end
        self:set(scope, key, v)
        return true, v
    end

    -- R-C2: a token is never shown; this is what the screen shows instead.
    function S:token_status(scope, key)
        local v = self:get(scope, key)
        return (type(v) == "string" and v ~= "") and "set" or "unset"
    end

    -- Text for the settings screen. Tokens are masked (R-C2, R-A4).
    function S:display(scope, key, T)
        local f = (self.fields[scope] or {})[key] or {}
        local v = self:get(scope, key)
        if f.type == "token" then return T and T(self:token_status(scope, key) == "set" and "token_set" or "token_unset")
            or self:token_status(scope, key) end
        if f.type == "bool" then return T and T(v and "bool_on" or "bool_off") or tostring(v) end
        if v == nil then return "" end
        return tostring(v)
    end

    -- Per-app view used as ctx.settings (5.2): :get(k), :set(k, v) (set goes through set_field).
    function S:scope(id)
        local parent = self
        return {
            id = id,
            get = function(_, k) return parent:get(id, k) end,
            set = function(_, k, v) return parent:set_field(id, k, v) end,
            fields = function() return parent.fields[id] or {} end,
        }
    end

    -- Refresh settings of every app (R-C4).
    function S:interval(app) return self:get(app, "interval") end
    function S:set_interval(app, v)
        if not Scheduler.valid_interval(v) then return nil, "choice" end
        self:set(app, "interval", v)
        return true, v
    end
    function S:cycle_interval(app)
        local v = Scheduler.cycle_interval(self:interval(app))
        self:set(app, "interval", v)
        return v
    end
    function S:window(app) return self:get(app, "window") end

    -- R-T2
    function S:notify_pref(app)
        local v = self:get(app, M.NOTIFY_KEY)
        for _, c in ipairs(M.CHOICES.notify_pref) do if c == v then return v end end
        return "alta"
    end
    function S:set_notify_pref(app, v)
        for _, c in ipairs(M.CHOICES.notify_pref) do
            if c == v then self:set(app, M.NOTIFY_KEY, v); return true end
        end
        return nil, "choice"
    end

    -- Tinta settings shortcuts.
    function S:tinta(key) return self:get(M.TINTA, key) end
    function S:set_tinta(key, value)
        local choices = M.CHOICES[key]
        if choices then
            local ok = false
            for _, c in ipairs(choices) do if c == value then ok = true end end
            if not ok then return nil, "choice" end
        end
        self:set(M.TINTA, key, value)
        return true, value
    end
    -- Next value of a Tinta choice setting (Sistema screens cycle on tap).
    function S:cycle_tinta(key)
        local choices = M.CHOICES[key]
        if not choices then return nil end
        local cur, nxt = self:tinta(key), choices[1]
        for i, c in ipairs(choices) do if c == cur then nxt = choices[i % #choices + 1] end end
        self:set(M.TINTA, key, nxt)
        return nxt
    end

    ---------------------------------------------------------------- 10.5 Sistema → Apps: turned off and removed apps

    -- Lists of ids kept as Tinta settings. The decoded set is memoized (the registry asks once per app at open,
    -- the launcher once per render): SQLite is slow on the Kindle, never read it in a loop.
    local sets = {}
    local function id_set(key)
        local m = sets[key]
        if m then return m end
        m = {}
        local list = store:get(M.TINTA, key)
        if type(list) == "table" then
            for _, id in ipairs(list) do if type(id) == "string" then m[id] = true end end
        end
        sets[key] = m
        return m
    end
    local function id_list(key)
        local out = {}
        for id in pairs(id_set(key)) do out[#out + 1] = id end
        table.sort(out)
        return out
    end
    local function save_ids(key)
        local list = id_list(key)
        store:set(M.TINTA, key, #list > 0 and list or nil)
    end
    local plain_set = S.set
    function S:set(scope, key, value)
        if scope == M.TINTA then sets[key] = nil end
        return plain_set(self, scope, key, value)
    end

    function S:is_disabled(id) return id_set("disabled_apps")[id] == true end
    function S:disabled_ids() return id_list("disabled_apps") end
    -- Turns an app on or off. The apps in Registry.PROTECTED cannot be turned off: nil, "protected".
    function S:set_disabled(id, off)
        if type(id) ~= "string" or not id:match("^[a-z0-9_]+$") then return nil, "id" end
        if off and Registry.PROTECTED[id] then return nil, "protected" end
        local set = id_set("disabled_apps")
        local now_off = set[id] == true
        if (off and true or false) == now_off then return true end
        set[id] = off and true or nil
        save_ids("disabled_apps")
        return true
    end

    function S:is_removed(id) return id_set("removed_apps")[id] == true end
    function S:removed_ids() return id_list("removed_apps") end
    function S:add_removed(id)
        if type(id) ~= "string" or not id:match("^[a-z0-9_]+$") then return nil, "id" end
        id_set("removed_apps")[id] = true
        save_ids("removed_apps")
        return true
    end
    function S:clear_removed()
        sets.removed_apps = {}
        store:set(M.TINTA, "removed_apps", nil)
    end

    ---------------------------------------------------------------- backup (Sistema → Dados)

    -- The saved settings of a scope without secrets: token fields, secret keys and URLs with credentials are
    -- left out. Only values the user saved (defaults are not written). One store read per call.
    function S:export_scope(scope)
        local out = {}
        local fields = self.fields[scope] or {}
        for k, v in pairs(store:all(scope)) do
            local f = fields[k]
            if not (f and f.type == "token") and not M.secret_key(k) and not value_has_secret(v) then out[k] = v end
        end
        return out
    end

    -- The saved settings of a scope for diagnostics: like export_scope, but a secret is shown as "<redacted>"
    -- (the key stays, so the report says it exists) and never with its value.
    function S:redacted_scope(scope)
        local out = {}
        local fields = self.fields[scope] or {}
        for k, v in pairs(store:all(scope)) do
            local f = fields[k]
            if (f and f.type == "token") or M.secret_key(k) or value_has_secret(v) then out[k] = "<redacted>" else out[k] = v end
        end
        return out
    end

    local function window_ok(w)
        if type(w) ~= "table" or not Format.parse_hm(w.from) or not Format.parse_hm(w.to) then return nil end
        if w.weekdays ~= nil and type(w.weekdays) ~= "boolean" then return nil end
        return { from = Format.hm_from_minutes(Format.parse_hm(w.from)), to = Format.hm_from_minutes(Format.parse_hm(w.to)),
                 weekdays = w.weekdays }
    end

    local function quiet_ok(q)
        if type(q) ~= "table" or type(q.enabled) ~= "boolean" or not Format.parse_hm(q.from) or not Format.parse_hm(q.to) then return nil end
        return { enabled = q.enabled, from = Format.hm_from_minutes(Format.parse_hm(q.from)),
                 to = Format.hm_from_minutes(Format.parse_hm(q.to)) }
    end

    -- One key of an import: "applied" | "skipped" (a known key with an invalid value) | "ignored" (unknown key,
    -- or a secret, which an import never touches: the current ones stay).
    local function import_key(self, scope, k, v, defaults, fields)
        if type(k) ~= "string" or M.secret_key(k) or value_has_secret(v) then return "ignored" end
        local f = fields[k]
        if f and f.type == "token" then return "ignored" end
        if scope == M.TINTA then
            if defaults[k] == nil then return "ignored" end
            if k == "quiet" then
                local q = quiet_ok(v)
                if not q then return "skipped" end
                self:set(scope, k, q)
                return "applied"
            end
            if M.CHOICES[k] then return self:set_tinta(k, v) and "applied" or "skipped" end
            if type(v) ~= type(defaults[k]) then return "skipped" end
            self:set(scope, k, v)
            return "applied"
        end
        if f then return self:set_field(scope, k, v) and "applied" or "skipped" end
        if k == "interval" then return self:set_interval(scope, v) and "applied" or "skipped" end
        if k == M.NOTIFY_KEY then return self:set_notify_pref(scope, v) and "applied" or "skipped" end
        if k == "window" then
            local w = window_ok(v)
            if not w then return "skipped" end
            self:set(scope, k, w)
            return "applied"
        end
        if defaults[k] ~= nil then
            if type(v) ~= type(defaults[k]) then return "skipped" end
            self:set(scope, k, copy(v))
            return "applied"
        end
        return "ignored"
    end

    -- Applies exported settings of a scope through the validated setters. Unknown keys and secrets are ignored,
    -- invalid values skipped. Returns { applied, skipped, ignored } counts. A scope with no registered
    -- defaults (an app that is not loaded) counts everything as ignored.
    function S:import_scope(scope, tbl)
        local r = { applied = 0, skipped = 0, ignored = 0 }
        if type(tbl) ~= "table" then r.skipped = 1; return r end
        local defaults = self.defaults[scope]
        local keys = {}
        for k in pairs(tbl) do keys[#keys + 1] = k end
        table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
        for _, k in ipairs(keys) do
            local res = defaults and import_key(self, scope, k, tbl[k], defaults, self.fields[scope] or {}) or "ignored"
            r[res] = r[res] + 1
        end
        return r
    end

    S:migrate()
    return S
end

return M
