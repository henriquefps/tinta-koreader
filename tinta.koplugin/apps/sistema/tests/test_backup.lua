-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (C) 2026 Tinta contributors
local T = ...
local Backup = require("apps/sistema/backup")
local Settings = require("core/settings")
local Layout = require("core/layout")
local Store = require("core/store")
local Json = require("core/json")

local SECRETS = { "tok-ALFA-9f8e7d", "hunter2-PW", "bob:s3cr3t" }

local function setup()
    local store = Store.memory()
    local S = Settings.new{ store = store }
    S:register_app{ id = "alfa", version = 1, defaults = { interval = 60 }, settings = {
        { key = "server_url", type = "url" }, { key = "token", type = "token" },
        { key = "mode", type = "choice", choices = { "a", "b" }, default = "a" },
        { key = "max", type = "number", min = 1, max = 10, default = 3 } } }
    S:register_app{ id = "beta", version = 2, defaults = { interval = 300, window = { from = "08:00", to = "18:00", weekdays = true } },
        settings = { { key = "pass", type = "token" } } }
    local env = {
        settings = S, now = 1700000000, tinta_version = "0.1", api_version = 1,
        apps = { { id = "alfa", version = 1 }, { id = "beta", version = 2 } },
        layout_get = function(p) return store:layout_get(p) end,
        layout_set = function(p, l) return store:layout_set(p, l) end,
        valid_size = Layout.valid_size,
    }
    return S, store, env
end

local S, store, env = setup()
S:set("alfa", "token", SECRETS[1])
S:set("alfa", "server_url", "http://192.0.2.2:4747")
S:set("alfa", "mode", "b")
S:set("alfa", "max", 7)
S:set("alfa", "interval", 300)
S:set("alfa", "notify_pref", "desligada")
S:set("beta", "pass", SECRETS[2])
S:set("beta", "server_url", "http://" .. SECRETS[3] .. "@h:1")
S:set("beta", "window", { from = "09:00", to = "17:00", weekdays = false })
S:set("portal", "nav", "gestures")
S:set("portal", "quiet", { enabled = false, from = "22:00", to = "06:30" })
S:set("portal", "wake", 3600)
S:set("portal", "banner", false)
store:layout_set("home", { { app = "alfa", size = "4x4" }, { app = "beta", size = "2x4", hidden = true }, { app = "ghost", size = "1x1" } })
store:layout_set("sleep", { { app = "alfa", size = "2x2" } })
store:data_set("alfa", "private", { secret = "data" })
store:cache_put("alfa", { cached = "payload" }, 1, 1)

-- build: contents and privacy
local b = Backup.build(env)
T.eq("build: format", b.format, "tinta-backup")
T.eq("build: format_version", b.format_version, 1)
T.eq("build: tinta version", b.tinta_version, "0.1")
T.check("build: layouts home and sleep", #b.layouts.home == 3 and #b.layouts.sleep == 1 and b.layouts.home[2].hidden == true)
T.eq("build: tinta setting", b.tinta.nav, "gestures")
T.eq("build: app setting", b.apps.alfa.settings.mode, "b")
T.eq("build: app version", b.apps.beta.version, 2)
local text = Backup.encode(b)
for _, s in ipairs(SECRETS) do T.check("file: secret never appears: " .. s, not text:find(s, 1, true)) end
T.check("file: no token key", not text:find('"token"', 1, true) and not text:find('"pass"', 1, true))
T.check("file: no URL with credentials", not text:find("://[^/%s\"]*@"))
T.check("file: no app data, cache or notifications", not text:find("payload", 1, true) and not text:find('"secret"', 1, true)
    and not text:find("notifications", 1, true))
T.check("file: plain URL kept", text:find("http://192.0.2.2:4747", 1, true) ~= nil)
T.check("file: under the read limit", #text < Backup.MAX_BYTES)

-- round trip into a fresh install: same layouts and settings, no tokens invented
local S2, store2, env2 = setup()
S2:set("alfa", "token", "CURRENT-TOKEN")
S2:set("beta", "pass", "CURRENT-PASS")
local decoded, err = Backup.decode(text)
T.check("decode: ok", decoded ~= nil, err)
local res = Backup.apply(decoded, env2)
T.eq("apply: nothing skipped", res.skipped, 0)
T.eq("apply: layouts applied", res.layouts, 2)
T.check("apply: counted settings", res.applied >= 10, res.applied)
local function same(a, b) return Json.encode(a) == Json.encode(b) end
T.check("round trip: home layout", same(store2:layout_get("home"), store:layout_get("home")))
T.check("round trip: sleep layout", same(store2:layout_get("sleep"), store:layout_get("sleep")))
T.check("round trip: tinta settings", same(S2:export_scope("portal"), S:export_scope("portal")))
T.check("round trip: alfa settings", same(S2:export_scope("alfa"), S:export_scope("alfa")))
T.check("round trip: beta settings", same(S2:export_scope("beta"), S:export_scope("beta")))
T.eq("round trip: quiet", S2:tinta("quiet").from, "22:00")
T.eq("tokens preserved (alfa)", S2:get("alfa", "token"), "CURRENT-TOKEN")
T.eq("tokens preserved (beta)", S2:get("beta", "pass"), "CURRENT-PASS")
T.eq("credentials URL not restored", S2:get("beta", "server_url"), nil)
T.check("app data and cache not carried", store2:data_get("alfa", "private") == nil)

-- a hand-made backup with bad content: unknown ignored, invalid skipped, tokens never touched
local S3, store3, env3 = setup()
S3:set("alfa", "token", "KEEP-ME")
S3:set("portal", "nav", "gestures")
local bad = {
    format = "tinta-backup", format_version = 1,
    layouts = { home = { { app = "alfa", size = "9x9" }, { app = "beta", size = "2x2" }, "junk", { app = "beta", size = "4x2" },
        { app = "", size = "2x2" } }, sleep = "nope" },
    tinta = { nav = "weird", wake = 5, lang = "en", unknown_key = 1, banner = "yes", quiet = { enabled = "x" }, idle_sleep = 10,
        token = "EVIL", password = "EVIL" },
    apps = {
        alfa = { version = 1, settings = { mode = "zzz", max = 99, server_url = "not a url", token = "EVIL", interval = 999,
            notify_pref = "normal", bogus = true, window = { from = "25:99" } } },
        beta = { version = 3, settings = { interval = 60 } },     -- newer app version: left out
        gone = { version = 1, settings = { a = 1, b = 2 } },       -- not installed: ignored
    },
}
T.check("validate: bad content still has a valid shape", Backup.validate(bad) == true)
local r = Backup.apply(bad, env3)
T.eq("restore: lang applied", S3:tinta("lang"), "en")
T.eq("restore: idle_sleep applied", S3:tinta("idle_sleep"), 10)
T.eq("restore: invalid choice skipped (nav keeps)", S3:tinta("nav"), "gestures")
T.eq("restore: invalid wake skipped", S3:tinta("wake"), "schedule")
T.eq("restore: invalid bool skipped", S3:tinta("banner"), true)
T.eq("restore: invalid quiet skipped", S3:tinta("quiet").from, "23:00")
T.eq("restore: unknown Tinta key ignored", store3:get("portal", "unknown_key"), nil)
T.eq("restore: tinta token ignored", store3:get("portal", "token"), nil)
T.eq("restore: token kept", S3:get("alfa", "token"), "KEEP-ME")
T.eq("restore: invalid choice skipped (alfa mode)", S3:get("alfa", "mode"), "a")
T.eq("restore: out of range skipped", S3:get("alfa", "max"), 3)
T.eq("restore: bad url skipped", S3:get("alfa", "server_url"), nil)
T.eq("restore: bad interval skipped", S3:get("alfa", "interval"), 60)
T.eq("restore: notify_pref applied", S3:notify_pref("alfa"), "normal")
T.eq("restore: unknown app key ignored", store3:get("alfa", "bogus"), nil)
T.eq("restore: invalid window skipped", store3:get("alfa", "window"), nil)
T.eq("restore: newer app version left out", store3:get("beta", "interval"), nil)
T.eq("restore: only the newer app is counted as newer", r.apps_newer, 1)
T.eq("restore: uninstalled app writes nothing", store3:get("gone", "a"), nil)
local home = store3:layout_get("home")
T.check("restore: layout keeps only valid items without repeats", home and #home == 1 and home[1].app == "beta" and home[1].size == "2x2")
T.eq("restore: bad layout type skipped", store3:layout_get("sleep"), nil)
T.check("restore: skipped and ignored are counted", r.skipped >= 9 and r.ignored >= 5, r.skipped .. "/" .. r.ignored)
T.check("restore: applied counted", r.applied == 3, r.applied)

-- an all-invalid layout does not wipe the current one; an emptied one is restored empty
local S4, store4, env4 = setup()
store4:layout_set("home", { { app = "alfa", size = "4x4" } })
Backup.apply({ format = "tinta-backup", format_version = 1, layouts = { home = { { app = "x", size = "bad" } } } }, env4)
T.eq("restore: all-invalid layout leaves the current one", #store4:layout_get("home"), 1)
Backup.apply({ format = "tinta-backup", format_version = 1, layouts = { home = {} } }, env4)
T.eq("restore: emptied layout restored", #(store4:layout_get("home") or { 1 }), 0)

-- validation of shape and versions
local function bad_shape(t) return Backup.validate(t) == nil end
T.check("validate: not a table", bad_shape("x") and bad_shape(nil))
T.check("validate: wrong format name", bad_shape({ format = "other", format_version = 1 }))
T.check("validate: no version", bad_shape({ format = "tinta-backup" }))
T.check("validate: version 0 / fractional", bad_shape({ format = "tinta-backup", format_version = 0 }) and bad_shape({ format = "tinta-backup", format_version = 1.5 }))
T.check("validate: tinta not a table", bad_shape({ format = "tinta-backup", format_version = 1, tinta = 3 }))
T.check("validate: apps entry not a table", bad_shape({ format = "tinta-backup", format_version = 1, apps = { alfa = 1 } }))
T.check("validate: app version not a number", bad_shape({ format = "tinta-backup", format_version = 1, apps = { alfa = { version = "x" } } }))
local ok, why = Backup.validate({ format = "tinta-backup", format_version = 99 })
T.check("validate: newer format", ok == nil and why == "newer")
T.check("decode: not JSON", select(2, Backup.decode("{oops")) == "format")
T.check("decode: JSON of another kind", select(2, Backup.decode("[1,2]")) == "format")
T.check("decode: too big", select(2, Backup.decode(("x"):rep(Backup.MAX_BYTES + 1))) == "format")
T.check("decode: empty object", select(2, Backup.decode("{}")) == "format")
T.check("decode: minimal valid", Backup.decode('{"format":"tinta-backup","format_version":1}') ~= nil)

-- files
T.eq("filename", Backup.filename(0):match("^tinta%-backup%-%d%d%d%d%d%d%d%d%-%d%d%d%d%.json$") ~= nil, true)
local names = Backup.list_names({ "tinta-backup-20260101-0900.json", "crash.log", "tinta-backup-20260301-1000.json",
    "tinta-backup-20260301-0900.json", "tinta-backup-x/../y.json", "tinta-backup-.json.txt", "tinta.sqlite3" })
T.eq("list: only backups, newest first", table.concat(names, ","),
    "tinta-backup-20260301-1000.json,tinta-backup-20260301-0900.json,tinta-backup-20260101-0900.json")
T.eq("label", Backup.label("tinta-backup-20260301-1000.json"), "01/03/2026 10:00")
T.eq("label: odd name stays", Backup.label("tinta-backup-x.json"), "tinta-backup-x.json")

-- a backup made before the rename (format "portal-backup", settings under `portal`) still restores
do
    local Backup2 = require("apps/sistema/backup")
    local old = '{"format":"portal-backup","format_version":1,"portal":{"lang":"en"},"layouts":{},"apps":{}}'
    local t, err = Backup2.decode(old)
    T.check("legacy backup: decodes", t ~= nil, err)
    T.check("legacy backup: its `portal` table becomes the settings", t and t.tinta and t.tinta.lang == "en")
    T.check("legacy backup: other formats still refused", select(2, Backup2.decode('{"format":"x","format_version":1}')) == "format")
    local names = Backup2.list_names({ "portal-backup-20261001-1000.json", "tinta-backup-20261017-0900.json", "tinta-backup-20261001-1000.json" })
    T.check("legacy backup: listed, newest first by date", names[1] == "tinta-backup-20261017-0900.json" and #names == 3 and names[3] == "portal-backup-20261001-1000.json" or names[3] == "tinta-backup-20261001-1000.json")
end
