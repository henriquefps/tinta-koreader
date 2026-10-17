-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (C) 2026 Tinta contributors
local T = ...
local Diag = require("apps/sistema/diag")
local Settings = require("core/settings")
local Store = require("core/store")

local SECRETS = { "tok-ALFA-9f8e7d", "hunter2-PW", "bob:s3cr3t", "sk-LIVE-1234", "Zm9vOmJhcg==" }

-- a settings object with tokens, a password field, a secret-looking key and a URL with credentials
local store = Store.memory()
local S = Settings.new{ store = store }
S:register_app{ id = "alfa", defaults = { interval = 60 }, settings = {
    { key = "server_url", type = "url" }, { key = "token", type = "token" }, { key = "mode", type = "choice", choices = { "a", "b" } } } }
S:register_app{ id = "other", settings = { { key = "pass", type = "token" }, { key = "secret_note", type = "token" } } }
S:set("alfa", "token", SECRETS[1])
S:set("alfa", "server_url", "http://" .. SECRETS[3] .. "@192.0.2.2:4747")
S:set("alfa", "mode", "b")
S:set("other", "pass", SECRETS[2])
S:set("other", "password", SECRETS[2])               -- not declared, secret by its name
S:set("other", "api_key", SECRETS[4])
S:set("other", "nested", { url = "https://u:" .. SECRETS[2] .. "@h/x", ok = 1 })
S:set("portal", "nav", "gestures")

local red = S:redacted_scope("alfa")
T.eq("redacted: token", red.token, "<redacted>")
T.eq("redacted: url with credentials", red.server_url, "<redacted>")
T.eq("redacted: plain value kept", red.mode, "b")
local ro = S:redacted_scope("other")
T.check("redacted: all secret keys",
    ro.pass == "<redacted>" and ro.password == "<redacted>" and ro.api_key == "<redacted>" and ro.nested == "<redacted>")
T.eq("redacted: tinta untouched", S:redacted_scope("portal").nav, "gestures")

local function sample_log(n)
    local rows = {}
    for i = 1, n do
        rows[i] = { at = 1700000000 + i, app = "alfa", level = "info",
            msg = "request http://" .. SECRETS[3] .. "@192.0.2.2/x token=" .. SECRETS[1] .. " n=" .. i }
    end
    return rows
end

local info = {
    generated = 1700000000, tinta_version = "0.1", api_version = 1, koreader_version = "v2025.04-1-g1234",
    model = "KT3", backend = "kindle", screen = { w = 600, h = 800, dpi = 167, scale = "1.00" },
    apps = { { id = "alfa", version = 1, enabled = true }, { id = "other", version = 2, enabled = false } },
    settings = { tinta = S:redacted_scope("portal"), apps = { alfa = red, other = ro } },
    log = Diag.log_lines(sample_log(600), 500),
    power_log = { "10:00 sleep Authorization: Bearer " .. SECRETS[5], "10:01 wake" },
    battery = { "ts,mAh", "1,2000" },
    crash = { "Tinta: error password=" .. SECRETS[2], "stack traceback:", "\tfoo.lua:1: in function x" },
}
local text = Diag.build(info)
for _, s in ipairs(SECRETS) do
    T.check("diag: secret never appears: " .. s, not text:find(s, 1, true))
end
T.check("diag: no user:pass@ in any URL", not text:find("://[^/%s]*:[^/%s]*@") and not text:find("://bob"))
for _, want in ipairs({ "tinta version: 0.1", "api version: 1", "koreader: v2025.04-1-g1234", "KT3", "backend kindle",
    "600x800", "167 dpi", "alfa v1 enabled", "other v2 disabled", "nav=\"gestures\"", "mode=\"b\"", "== tinta-power.log",
    "== tinta-battery.csv", "== crash.log", "stack traceback:" }) do
    T.check("diag: contains " .. want, text:find(want, 1, true) ~= nil)
end
T.check("diag: log keeps 500 lines at most", select(2, text:gsub("request http", "")) == 500)
T.check("diag: under 256 KB", #text < 256 * 1024)

-- size bound: huge logs still fit and keep the newest lines
local big = {}
for i = 1, 20000 do big[i] = "line " .. i .. " " .. ("x"):rep(300) end
local huge = Diag.build({ log = big, power_log = big, battery = big, crash = big, apps = {}, settings = {} })
T.check("diag: huge input bounded below 256 KB", #huge < 256 * 1024, #huge)
T.check("diag: huge input keeps the newest line", huge:find("line 20000 ", 1, true) ~= nil)
T.check("diag: huge input says lines were left out", huge:find("older lines left out", 1, true) ~= nil)
local long = Diag.build({ log = { ("y"):rep(5000) }, apps = {}, settings = {} })
T.check("diag: one long line is cut", #long < 2000)

-- helpers
local lines = {}
for i = 1, 10 do lines[i] = tostring(i) end
T.eq("tail: last 3", table.concat(Diag.tail(lines, 3), ","), "8,9,10")
T.eq("tail: more than there is", #Diag.tail(lines, 50), 10)
local crash = Diag.crash_lines({
    "unrelated 1", "Tinta: first", "other", "stack traceback:", "\t[C]: in ?", "\tx.lua:2: in main", "tail unrelated",
    "Tinta: second" }, 200)
T.eq("crash: only Tinta lines and tracebacks", table.concat(crash, "|"),
    "Tinta: first|stack traceback:|\t[C]: in ?|\tx.lua:2: in main|Tinta: second")
T.eq("crash: last N", #Diag.crash_lines({ "Tinta a", "Tinta b", "Tinta c" }, 2), 2)
T.eq("filename", Diag.filename(0):match("^tinta%-diagnostico%-%d%d%d%d%d%d%d%d%-%d%d%d%d%.txt$") ~= nil, true)
T.check("log_lines: oldest first", Diag.log_lines({ { at = 2, msg = "new" }, { at = 1, msg = "old" } }, 500)[1]:find("old", 1, true) ~= nil)

-- redact_text / url_has_credentials directly
T.check("redact_text: bearer and basic", not Settings.redact_text("Authorization: Basic Zm9vOmJhcg=="):find("Zm9v", 1, true))
T.check("redact_text: json token", not Settings.redact_text('{"token":"abc123"}'):find("abc123", 1, true))
T.eq("redact_text: plain stays", Settings.redact_text("alfa: refresh ok in 120 ms"), "alfa: refresh ok in 120 ms")
T.check("url_has_credentials", Settings.url_has_credentials("http://a:b@h") and Settings.url_has_credentials("http://a@h")
    and not Settings.url_has_credentials("http://h/x?e=a@b") and not Settings.url_has_credentials("http://h:4747"))
