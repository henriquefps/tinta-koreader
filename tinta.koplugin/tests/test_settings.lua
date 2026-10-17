-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (C) 2026 Tinta contributors
local T = ...
local Settings = require("core/settings")
local Store = require("core/store")
local I18n = require("core/i18n")
local eq, same, check = T.eq, T.same, T.check

local store = Store.memory()
local S = Settings.new({ store = store })
check("settings: store required", not pcall(Settings.new, {}))

-- Tinta defaults
eq("tinta: lang default pt", S:tinta("lang"), "pt")
eq("tinta: nav default bar", S:tinta("nav"), "bar")
same("tinta: quiet default 23-07 on", S:tinta("quiet"), { enabled = true, from = "23:00", to = "07:00" })
eq("tinta: sleep_shows default alta", S:tinta("sleep_shows"), "alta")
eq("tinta: wake default schedule", S:tinta("wake"), "schedule")
eq("tinta: old keys are gone", S:tinta("wake_every"), nil)
eq("tinta: idle default 5", S:tinta("idle_sleep"), 5)
eq("tinta: idle_mode default battery", S:tinta("idle_mode"), "battery")
for _, v in ipairs({ "always", "battery", "never" }) do
    check("tinta: idle_mode accepts " .. v, S:set_tinta("idle_mode", v) and S:tinta("idle_mode") == v)
end
check("tinta: idle_mode rejects x", not S:set_tinta("idle_mode", "x"))
eq("tinta: idle_mode cycles never -> always", S:cycle_tinta("idle_mode"), "always")
S:set("portal", "idle_mode", nil)
check("tinta: idle_sleep rejects 0 (never is the mode)", not S:set_tinta("idle_sleep", 0))
eq("tinta: banner on", S:tinta("banner"), true)
eq("tinta: full_every 10", S:tinta("full_every"), 10)
local q = S:tinta("quiet"); q.enabled = false
eq("tinta: defaults are copies", S:tinta("quiet").enabled, true)
check("tinta: set choice ok", S:set_tinta("nav", "gestures") and S:tinta("nav") == "gestures")
check("tinta: set choice rejected", not S:set_tinta("nav", "weird") and S:tinta("nav") == "gestures")
eq("tinta: cycle (schedule -> never)", S:cycle_tinta("wake"), "never")
eq("tinta: cycle wraps to 15 min", S:cycle_tinta("wake"), 900)
eq("tinta: cycle 15 -> 30 min", S:cycle_tinta("wake"), 1800)
for _, v in ipairs({ 900, 1800, 3600, 7200, "schedule", "never" }) do
    check("tinta: wake accepts " .. tostring(v), S:set_tinta("wake", v) and S:tinta("wake") == v)
end
check("tinta: wake rejects 60 / 'x'", not S:set_tinta("wake", 60) and not S:set_tinta("wake", "x") and S:tinta("wake") == "never")
check("tinta: idle accepts 15", S:set_tinta("idle_sleep", 15) and S:tinta("idle_sleep") == 15)
check("tinta: idle rejects 7", not S:set_tinta("idle_sleep", 7))
S:set("portal", "wake", nil)
S:set("portal", "idle_sleep", nil)
eq("tinta: cycle non-choice -> nil", S:cycle_tinta("banner"), nil)
S:set_tinta("banner", false)
eq("tinta: false is stored, not default", S:tinta("banner"), false)
S:set("portal", "banner", nil)
eq("tinta: nil resets to default", S:tinta("banner"), true)
local S2 = Settings.new({ store = Store.memory(), tinta_defaults = { lang = "en" } })
eq("tinta: defaults overridable", S2:tinta("lang"), "en")

-- app defaults and fields (R-C1, R-C4)
local alfa = {
    id = "alfa", defaults = { interval = 60 },
    settings = {
        { key = "server_url", type = "url", default = "http://192.0.2.101:4747" },
        { key = "token", type = "token" },
        { key = "max", type = "number", min = 1, max = 10, default = 3 },
        { key = "start", type = "time", default = "07:30" },
        { key = "mode", type = "choice", choices = { "grid", { value = "list", label = "Lista" } }, default = "grid" },
        { key = "show_remote", type = "bool", default = false },
        { key = "tz", type = "number", validate = function(v) if v < -12 or v > 14 then return false, "range" end return math.floor(v) end },
    },
}
S:register_app(alfa)
eq("app: default from manifest.defaults", S:interval("alfa"), 60)
eq("app: default from field", S:get("alfa", "server_url"), "http://192.0.2.101:4747")
eq("app: bool default false", S:get("alfa", "show_remote"), false)
eq("app: notify pref default alta (R-T2)", S:notify_pref("alfa"), "alta")
eq("app: window nil", S:window("alfa"), nil)

-- validation
local function sf(k, v) return { S:set_field("alfa", k, v) } end
same("url: trimmed and trailing slash removed", sf("server_url", "  http://192.0.2.2:4747/  "), { true, "http://192.0.2.2:4747" })
same("url: bad", sf("server_url", "ftp://x"), { nil, "format" })
same("url: empty", sf("server_url", "   "), { nil, "empty" })
eq("url: unchanged after bad input", S:get("alfa", "server_url"), "http://192.0.2.2:4747")
same("number: ok from text", sf("max", "7"), { true, 7 })
same("number: range", sf("max", 11), { nil, "range" })
same("number: not a number", sf("max", "x"), { nil, "type" })
same("time: normalized", sf("start", "7:05"), { true, "07:05" })
same("time: bad", sf("start", "25:00"), { nil, "format" })
same("choice: plain", sf("mode", "grid"), { true, "grid" })
same("choice: table choice", sf("mode", "list"), { true, "list" })
same("choice: bad", sf("mode", "x"), { nil, "choice" })
same("bool: ok", sf("show_remote", true), { true, true })
same("bool: type", sf("show_remote", "yes"), { nil, "type" })
same("validate: app validator transforms", sf("tz", -3.5), { true, -4 })
same("validate: app validator rejects", sf("tz", 20), { nil, "range" })
same("unknown key: set as is", sf("free", { 1 }), { true, { 1 } })
same("validate: unknown type", { Settings.validate({ type = "weird" }, 1) }, { nil, "type" })
same("validate: crashing validator", { Settings.validate({ type = "number", validate = function() error("x") end }, 1) }, { nil, "format" })

-- tokens (R-C2)
eq("token: unset", S:token_status("alfa", "token"), "unset")
same("token: set", sf("token", " abc123 "), { true, "abc123" })
eq("token: set status", S:token_status("alfa", "token"), "set")
same("token: empty keeps current", sf("token", ""), { true, "abc123" })
eq("token: still there", S:get("alfa", "token"), "abc123")
eq("token: display masked", S:display("alfa", "token", I18n.t), "definido")
check("token: display never shows the value", not S:display("alfa", "token"):find("abc"))
eq("display: bool", S:display("alfa", "show_remote", I18n.t), "ligado")
eq("display: plain", S:display("alfa", "max"), "7")

-- scope (ctx.settings)
local sc = S:scope("alfa")
eq("scope: get", sc:get("max"), 7)
check("scope: set validates", sc:set("max", 2) and sc:get("max") == 2)
check("scope: set rejects", not sc:set("max", 99))
check("scope: fields", sc.fields().token.type == "token")

-- intervals (R-U1/R-C4)
check("interval: set valid", S:set_interval("alfa", 300) and S:interval("alfa") == 300)
same("interval: set invalid", { S:set_interval("alfa", 301) }, { nil, "choice" })
eq("interval: cycle", S:cycle_interval("alfa"), 900)
S:set("alfa", "interval", 0)
eq("interval: cycle from manual", S:cycle_interval("alfa"), 30)

-- notification preference (R-T2)
check("pref: set normal", S:set_notify_pref("alfa", "normal") and S:notify_pref("alfa") == "normal")
same("pref: set invalid", { S:set_notify_pref("alfa", "x") }, { nil, "choice" })
S:set("alfa", Settings.NOTIFY_KEY, "garbage")
eq("pref: garbage reads as alta", S:notify_pref("alfa"), "alta")
eq("pref: unknown app alta", S:notify_pref("zz"), "alta")

-- persisted in the store
eq("store: value written", store:get("alfa", "max"), 2)
local S3 = Settings.new({ store = store }); S3:register_app(alfa)
eq("store: new settings object reads it", S3:get("alfa", "max"), 2)

-- 10.5: wake_every + sleep_schedule -> wake (one-time migration)
local function migrated(old)
    local st = Store.memory()
    for k, v in pairs(old) do st:set("portal", k, v) end
    local s = Settings.new({ store = st })
    return s, st
end
eq("migrate: nothing saved -> default", migrated({}):tinta("wake"), "schedule")
eq("migrate: schedule on -> schedule", migrated({ sleep_schedule = true, wake_every = 60 }):tinta("wake"), "schedule")
eq("migrate: only schedule on -> schedule", migrated({ sleep_schedule = true }):tinta("wake"), "schedule")
eq("migrate: schedule off, 15 -> 900", migrated({ sleep_schedule = false, wake_every = 15 }):tinta("wake"), 900)
eq("migrate: schedule off, 30 -> 1800", migrated({ sleep_schedule = false, wake_every = 30 }):tinta("wake"), 1800)
eq("migrate: schedule off, 60 -> 3600", migrated({ sleep_schedule = false, wake_every = 60 }):tinta("wake"), 3600)
eq("migrate: schedule off, 120 -> 7200", migrated({ sleep_schedule = false, wake_every = 120 }):tinta("wake"), 7200)
eq("migrate: schedule off, 45 -> tie goes to the lower (1800)", migrated({ sleep_schedule = false, wake_every = 45 }):tinta("wake"), 1800)
eq("migrate: schedule off, 5 -> nearest (900)", migrated({ sleep_schedule = false, wake_every = 5 }):tinta("wake"), 900)
eq("migrate: schedule off, no interval -> 30 min", migrated({ sleep_schedule = false }):tinta("wake"), 1800)
eq("migrate: only wake_every saved -> nearest", migrated({ wake_every = 120 }):tinta("wake"), 7200)
eq("migrate: never (0) -> never", migrated({ sleep_schedule = false, wake_every = 0 }):tinta("wake"), "never")
eq("migrate: never (false) -> never", migrated({ sleep_schedule = false, wake_every = false }):tinta("wake"), "never")
eq("migrate: schedule on wins over 0", migrated({ sleep_schedule = true, wake_every = 0 }):tinta("wake"), "schedule")
do
    local _, st = migrated({ sleep_schedule = false, wake_every = 60 })
    eq("migrate: old keys are removed", st:get("portal", "wake_every"), nil)
    eq("migrate: old keys are removed (schedule)", st:get("portal", "sleep_schedule"), nil)
    local s2 = Settings.new({ store = st })
    s2:set_tinta("wake", 7200)
    local s3 = Settings.new({ store = st })
    eq("migrate: runs once (a later choice stays)", s3:tinta("wake"), 7200)
    local st2 = Store.memory()
    st2:set("portal", "wake", "never"); st2:set("portal", "wake_every", 15)
    eq("migrate: an existing wake is not overwritten", Settings.new({ store = st2 }):tinta("wake"), "never")
end
eq("migrate_wake pure: nothing", Settings.migrate_wake(nil, nil), nil)
eq("migrate_wake pure: garbage", Settings.migrate_wake("x", false), nil)

-- 10.5: idle_sleep 0 / minutes -> idle_mode (one-time migration); "expediente" is deleted
local function idle_migrated(old)
    local st = Store.memory()
    for k, v in pairs(old) do st:set("portal", k, v) end
    local s = Settings.new({ store = st })
    return s, st
end
do
    local s, st = idle_migrated({})
    eq("idle migrate: nothing saved -> mode battery", s:tinta("idle_mode"), "battery")
    eq("idle migrate: nothing saved -> 5 min", s:tinta("idle_sleep"), 5)
    -- changing the minutes afterwards is not read as an old value on the next start
    s:set_tinta("idle_sleep", 10)
    local s2 = Settings.new({ store = st })
    eq("idle migrate: runs once (mode stays battery)", s2:tinta("idle_mode"), "battery")
    eq("idle migrate: runs once (minutes kept)", s2:tinta("idle_sleep"), 10)
    s, st = idle_migrated({ idle_sleep = 0 })
    eq("idle migrate: 0 -> never", s:tinta("idle_mode"), "never")
    eq("idle migrate: 0 -> minutes back to 5", s:tinta("idle_sleep"), 5)
    eq("idle migrate: 0 is not kept in the store", st:get("portal", "idle_sleep"), nil)
    for _, m in ipairs({ 2, 5, 10, 15 }) do
        s = idle_migrated({ idle_sleep = m })
        eq("idle migrate: " .. m .. " -> always", s:tinta("idle_mode"), "always")
        eq("idle migrate: " .. m .. " kept", s:tinta("idle_sleep"), m)
    end
    s = idle_migrated({ idle_sleep = 7 })
    eq("idle migrate: invalid -> default mode", s:tinta("idle_mode"), "battery")
    eq("idle migrate: invalid -> default minutes", s:tinta("idle_sleep"), 5)
    s = idle_migrated({ idle_sleep = 15, idle_mode = "never" })
    eq("idle migrate: an existing mode wins", s:tinta("idle_mode"), "never")
    eq("idle migrate: ... and nothing else changes", s:tinta("idle_sleep"), 15)
    s, st = idle_migrated({ expediente = true })
    eq("expediente: stored value deleted", st:get("portal", "expediente"), nil)
    s, st = idle_migrated({ expediente = false, idle_sleep = 10 })
    eq("expediente: deleted with the idle migration too", st:get("portal", "expediente"), nil)
    eq("expediente: idle migration still runs", s:tinta("idle_mode"), "always")
end

-- sleep-page privacy (11.8) and text size (6.1)
do
    local st = Store.memory()
    local s = Settings.new({ store = st })
    s:register_app({ id = "nota", sensitive = true })
    s:register_app({ id = "bateria" })
    eq("privacy: a sensitive app defaults to hidden", s:get("nota", "sleep_show"), "hidden")
    eq("privacy: others default to shown", s:get("bateria", "sleep_show"), "shown")
    check("privacy: sleep_visible follows the default", s:sleep_visible("nota") == false and s:sleep_visible("bateria") == true)
    s:set_sleep_visible("nota", true)
    check("privacy: the user can allow it", s:sleep_visible("nota") == true and st:get("nota", "sleep_show") == "shown")
    s:set_sleep_visible("bateria", false)
    check("privacy: or hide any app", s:sleep_visible("bateria") == false)
    check("privacy: an unregistered app is shown", s:sleep_visible("ghost") == true)
    eq("tinta: sleep_titles default show", s:tinta("sleep_titles"), "show")
    check("tinta: sleep_titles accepts hide, rejects x", s:set_tinta("sleep_titles", "hide") and not s:set_tinta("sleep_titles", "x"))
    eq("tinta: text_size default normal", s:tinta("text_size"), "normal")
    check("tinta: text_size accepts large, rejects huge", s:set_tinta("text_size", "large") and not s:set_tinta("text_size", "huge"))
    eq("text factor: normal 1.0", Settings.text_factor("normal"), 1.0)
    eq("text factor: large 1.15", Settings.text_factor("large"), 1.15)
    eq("text factor: unknown is 1.0", Settings.text_factor("x"), 1.0)
    eq("text_size cycles normal -> large", (function() s:set("portal", "text_size", nil); return s:cycle_tinta("text_size") end)(), "large")
end
