-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (C) 2026 Tinta contributors
-- Platform wave B: app API versioning (5.1), turning apps on and off, removing apps (10.5).
local T = ...
local Registry = require("core/registry")
local Version = require("core/version")
local Appfiles = require("core/appfiles")
local Store = require("core/store")
local Settings = require("core/settings")
local C = require("ui/core")
local L = require("ui/launchlogic")
local eq, same, check = T.eq, T.same, T.check

local function app(id, over)
    local m = { id = id, name = id:upper(), sizes = { "2x2", "1x1" }, defaults = { interval = 60 },
        widget = function() return { app = id } end,
        refresh = function(ctx, done) done(true) end }
    for k, v in pairs(over or {}) do m[k] = v end
    return m
end

---------------------------------------------------------------- versions
eq("version: Tinta version declared", Version.TINTA_VERSION, "0.1")
eq("version: api version declared", Version.API_VERSION, 1)
eq("version: registry re-exports api", Registry.API_VERSION, Version.API_VERSION)
local a, b = Version.parse("1.12")
check("version: parse 1.12", a == 1 and b == 12)
a, b = Version.parse("2")
check("version: parse 2", a == 2 and b == 0)
check("version: parse junk", Version.parse("x") == nil and Version.parse(3) == nil and Version.parse("1.2.3") == nil)
eq("version: 0.9 < 0.10 (numeric)", Version.compare("0.9", "0.10"), -1)
eq("version: equal", Version.compare("1.0", "1"), 0)
eq("version: major wins", Version.compare("2.0", "1.9"), 1)

---------------------------------------------------------------- registry gating
check("compat: no api = api 1", Registry.compat(app("a")))
check("compat: api = current", Registry.compat(app("a", { api = Version.API_VERSION })))
local cok, why = Registry.compat(app("a", { api = Version.API_VERSION + 1 }))
check("compat: newer api refused", cok == false and why == "api")
cok, why = Registry.compat(app("a", { min_portal = "99.0" }))
check("compat: newer min_portal refused", cok == false and why == "min_portal")
check("compat: min_portal = this tinta", Registry.compat(app("a", { min_portal = Version.TINTA_VERSION })))
check("compat: older min_portal", Registry.compat(app("a", { min_portal = "0.0" })))
check("validate: api must be a positive integer", not Registry.validate(app("a", { api = 0 })) and not Registry.validate(app("a", { api = 1.5 }))
    and not Registry.validate(app("a", { api = "1" })))
check("validate: min_portal must be x.y", not Registry.validate(app("a", { min_portal = "new" })))
check("validate: api and min_portal accepted", Registry.validate(app("a", { api = 1, min_portal = "0.1" })))

local log = T.logger()
local reg = Registry.new({ now = T.clock(1000), log = log.fn })
check("gating: current app loads", reg:register(app("ok", { api = 1 })))
check("gating: app without api loads", reg:register(app("old")))
local r1, e1 = reg:register(app("future", { api = Version.API_VERSION + 1, name = "Futura",
    -- a future manifest may not even have the shape of today's (no widget, new size names)
    widget = false, sizes = { "9x9" } }))
check("gating: newer api not registered, no crash", r1 == nil and e1 == "api")
local r2, e2 = reg:register(app("needs", { min_portal = "99.1" }))
check("gating: newer min_portal not registered", r2 == nil and e2 == "min_portal")
same("gating: ids hold only the loaded apps", reg:ids(), { "ok", "old" })
eq("gating: get is nil for the skipped app", reg:get("future"), nil)
local inact = reg:inactive_list()
eq("gating: two inactive", #inact, 2)
check("gating: inactive entry has name, reason and the numbers",
    inact[1].id == "future" and inact[1].why == "api" and inact[1].name == "Futura" and inact[1].api == Version.API_VERSION + 1
    and inact[2].id == "needs" and inact[2].why == "min_portal" and inact[2].min_portal == "99.1")
check("gating: skipped app is logged", log.find("needs a newer Tinta"))
check("gating: no refresh / call into the skipped app", reg:refresh("future", {}) == false and reg:call("future", "widget", {}) == false)

---------------------------------------------------------------- settings: disabled / removed lists
local store = Store.memory()
local gets = 0
local raw_get = store.get
store.get = function(self, ...) gets = gets + 1; return raw_get(self, ...) end
local S = Settings.new({ store = store })
same("settings: nothing disabled by default", S:disabled_ids(), {})
check("settings: protected sistema cannot be disabled", S:set_disabled("sistema", true) == nil)
local pr, perr = S:set_disabled("notificacoes", true)
check("settings: protected notificacoes cannot be disabled", pr == nil and perr == "protected")
check("settings: bad id refused", S:set_disabled("../x", true) == nil and S:set_disabled("", true) == nil)
check("settings: disable", S:set_disabled("timer", true) and S:is_disabled("timer"))
check("settings: disable a second one", S:set_disabled("nota", true))
same("settings: list sorted", S:disabled_ids(), { "nota", "timer" })
check("settings: enable", S:set_disabled("timer", false) and not S:is_disabled("timer"))
same("settings: list after enable", S:disabled_ids(), { "nota" })
gets = 0
for _ = 1, 200 do S:is_disabled("nota"); S:is_disabled("timer") end
eq("settings: memoized (no store read per call)", gets, 0)
local S2 = Settings.new({ store = store })
check("settings: persisted in the Tinta scope", S2:is_disabled("nota") and not S2:is_disabled("timer"))
check("settings: tinta default is an empty list", Settings.TINTA_DEFAULTS.disabled_apps and #Settings.TINTA_DEFAULTS.disabled_apps == 0)
S:set_disabled("nota", false)
eq("settings: list key cleared when empty", store:get("portal", "disabled_apps"), nil)
check("settings: removed list", S:add_removed("timer") and S:is_removed("timer") and not S:is_removed("nota"))
check("settings: removed refuses a bad id", S:add_removed("../x") == nil)
S:clear_removed()
check("settings: removed list cleared", not S:is_removed("timer") and #S:removed_ids() == 0)

---------------------------------------------------------------- registry: disabled apps
local off = { b = true, sistema = true }
local reg2 = Registry.new({ now = T.clock(1000), log = log.fn, is_disabled = function(id) return off[id] end })
check("disabled: other app loads", reg2:register(app("a")))
local dr, dwhy = reg2:register(app("b"))
check("disabled: not registered", dr == nil and dwhy == "disabled" and reg2:get("b") == nil)
check("disabled: protected app loads even when listed", reg2:register(app("sistema", { refresh = nil, system = true })))
same("disabled: ids", reg2:ids(), { "a", "sistema" })
eq("disabled: inactive entry", reg2:inactive_get("b").why, "disabled")
check("disabled: unload refuses a protected app", reg2:unload("sistema") == false and reg2:get("sistema") ~= nil)
check("disabled: unload a loaded app parks it", reg2:unload("a") and reg2:get("a") == nil and reg2:inactive_get("a").why == "disabled")
off.b = nil
check("disabled: registering again once on", reg2:register(app("b")) and reg2:get("b") ~= nil and reg2:inactive_get("b") == nil)
reg2:register(app("c"))
reg2:sort_order(function(x, y) return x < y end)
same("disabled: order can be restored", reg2:ids(), { "b", "c", "sistema" })

---------------------------------------------------------------- core: turn off / on, layouts, hooks
local function open_core()
    local logs = {}
    local c = C.open{ db_path = nil, now = T.clock(5000), log = function(a, l, m) logs[#logs + 1] = { app = a, level = l, msg = m } end }
    c.test_logs = logs
    return c
end
local c = open_core()
local inits, bgs = {}, {}
local function reg_app(id, over)
    local m = app(id, over)
    m.init = function() inits[#inits + 1] = id end
    m.background = function() bgs[#bgs + 1] = id end
    return C.register(c, m)
end
check("core: sistema registers", reg_app("sistema", { system = true, refresh = nil }))
check("core: a registers", reg_app("a"))
check("core: b registers", reg_app("b"))
c.store:layout_set("home", { { app = "a", size = "2x2" }, { app = "b", size = "1x1" }, { app = "sistema", size = "1x1" } })
c.store:layout_set("sleep", { { app = "b", size = "2x2" }, { app = "a", size = "2x2", hidden = true } })
check("core: protected cannot be turned off", C.set_disabled(c, "sistema", true) == nil and C.app(c, "sistema") ~= nil)
check("core: turn b off", C.set_disabled(c, "b", true))
check("core: b no longer registered", C.app(c, "b") == nil)
same("core: apps list without b", (function() local o = {} for i, m in ipairs(C.list_apps(c)) do o[i] = m.id end return o end)(), { "sistema", "a" })
eq("core: b is inactive, disabled", C.inactive(c, "b").why, "disabled")
local refresh_res = C.refresh(c, "b", function() end, false)
check("core: no refresh for a disabled app", refresh_res == false)
check("core: no call into a disabled app", select(1, C.call(c, "b", "widget")) == false)
same("core: layouts keep the app (home)", (function() local o = {} for i, it in ipairs(C.load_layout(c, "home")) do o[i] = it.app end return o end)(), { "a", "b", "sistema" })
same("core: layouts keep the app (sleep)", (function() local o = {} for i, it in ipairs(C.load_layout(c, "sleep")) do o[i] = it.app end return o end)(), { "b", "a" })
same("core: background ids skip it", C.background_ids(c), { "sistema", "a" })
inits = {}
C.init_apps(c)
same("core: init skips it", inits, { "sistema", "a" })

-- a new session: the disabled list is read at registration
local store_keep = c.store
local c2 = open_core()
c2.store, c2.settings = store_keep, Settings.new({ store = store_keep })
c2.registry = Registry.new{ now = c2.now, log = c2.log, store = store_keep, is_disabled = function(id) return c2.settings:is_disabled(id) end }
c2.notify = c.notify
check("core: new session, b is skipped at register", C.register(c2, app("b")) == nil and C.app(c2, "b") == nil)
check("core: new session, a loads", C.register(c2, app("a")))

-- turn it on again: the manifest comes back from the inactive list, in order, with its place in the layouts
local entry = C.inactive(c, "b")
C.set_disabled(c, "b", false)
check("core: turn b on", C.register(c, entry.manifest))
C.sort_apps(c, function(x, y) return x < y end)
check("core: b registered again, no longer inactive", C.app(c, "b") ~= nil and C.inactive(c, "b") == nil)
same("core: layouts untouched by the round trip", (function() local o = {} for i, it in ipairs(C.load_layout(c, "home")) do o[i] = it.app end return o end)(), { "a", "b", "sistema" })
same("core: background ids back", C.background_ids(c), { "a", "b", "sistema" })

-- needs-newer apps show as inactive, not loaded
local rn, rwhy = C.register(c, app("future", { api = 7 }))
check("core: newer api not loaded", rn == nil and rwhy == "api" and C.app(c, "future") == nil)
eq("core: newer api listed inactive", C.inactive(c, "future").why, "api")
check("core: no settings registered for it", c.settings.defaults.future == nil)

---------------------------------------------------------------- launcher rules
local home = { { app = "a", size = "2x2" }, { app = "b", size = "1x1", hidden = true } }
local names = { a = "Alfa", b = "Beta", c = "Gama", d = "Delta" }
local entries = L.entries({ app("a"), app("b") }, function(id) return names[id] end, nil, home,
    { { id = "c", why = "disabled", manifest = app("c") }, { id = "d", why = "api", manifest = app("d") } })
eq("launcher: loaded + disabled entries (not the newer-api one)", #entries, 3)
check("launcher: sorted with the rest", entries[1].id == "a" and entries[2].id == "b" and entries[3].id == "c")
check("launcher: disabled entry is marked, has no Home mark", entries[3].disabled == true and entries[3].mark == nil)
check("launcher: loaded entries are not disabled", not entries[1].disabled and entries[1].mark == "home" and entries[2].mark == "hidden")
eq("launcher: no inactive list = as before", #L.entries({ app("a") }, function(id) return names[id] end, nil, home), 1)

---------------------------------------------------------------- appfiles: the guard
-- an in-memory file system: kinds = { [path] = "dir" | "file" | "link" }
local function fake_fs(kinds)
    local fs = { removed = {}, rmdirs = {}, kinds = kinds }
    local function children(path)
        local out = {}
        for p in pairs(kinds) do
            local parent, name = p:match("^(.*)/([^/]+)$")
            if parent == path then out[#out + 1] = name end
        end
        table.sort(out)
        return out
    end
    function fs.dir(path)
        if kinds[path] ~= "dir" then error("cannot open " .. path) end
        local list, i = children(path), 0
        list[#list + 1] = "."; list[#list + 1] = ".."
        return function() i = i + 1; return list[i] end
    end
    function fs.link(p) return kinds[p] == "link" end
    function fs.is_dir(p) return kinds[p] == "dir" end
    function fs.remove(p)
        if kinds[p] == nil then return nil, "missing" end
        if kinds[p] == "dir" then return nil, "is a dir" end
        kinds[p] = nil; fs.removed[#fs.removed + 1] = p; return true
    end
    function fs.rmdir(p)
        if kinds[p] ~= "dir" then return nil, "not a dir" end
        if #children(p) > 0 then return nil, "not empty" end
        kinds[p] = nil; fs.rmdirs[#fs.rmdirs + 1] = p; return true
    end
    return fs
end
local function tree()
    return fake_fs({
        ["/k"] = "dir", ["/k/apps"] = "dir",
        ["/k/apps/timer"] = "dir", ["/k/apps/timer/init.lua"] = "file", ["/k/apps/timer/tests"] = "dir",
        ["/k/apps/timer/tests/run.lua"] = "file", ["/k/apps/timer/tests/deep"] = "dir", ["/k/apps/timer/tests/deep/x"] = "file",
        ["/k/apps/nota"] = "dir", ["/k/apps/nota/init.lua"] = "file",
        ["/k/main.lua"] = "file", ["/k/x"] = "dir", ["/k/x/keep.txt"] = "file",
        ["/outside"] = "dir", ["/outside/secret"] = "file",
    })
end

local fs = tree()
local rok, n = Appfiles.remove(fs, "/k/apps", "timer")
check("appfiles: removes the folder of the id", rok == true and n == 5, n)
check("appfiles: folder and everything in it gone", fs.kinds["/k/apps/timer"] == nil and fs.kinds["/k/apps/timer/tests/deep/x"] == nil)
check("appfiles: the sibling app and the plugin files stay",
    fs.kinds["/k/apps/nota/init.lua"] == "file" and fs.kinds["/k/main.lua"] == "file" and fs.kinds["/k/apps"] == "dir")
check("appfiles: trailing slash on the apps dir is fine", Appfiles.remove(tree(), "/k/apps/", "nota"))

for _, bad in ipairs({ "../x", "..", ".", "", "a/b", "/etc", "../../outside", "timer/..", "Timer", "ti mer", "nota/../timer", "x\0y" }) do
    local f = tree()
    local ok2, why2 = Appfiles.remove(f, "/k/apps", bad)
    check("appfiles: refuses id '" .. bad:gsub("%z", "\\0") .. "'", ok2 == nil and why2 == "bad id" and #f.removed == 0 and #f.rmdirs == 0, why2)
end
check("appfiles: path_of refuses traversal", Appfiles.path_of("/k/apps", "../x") == nil and Appfiles.path_of("/k/apps", "x") == "/k/apps/x")
check("appfiles: no apps dir", Appfiles.remove(tree(), "", "timer") == nil and Appfiles.remove(tree(), nil, "timer") == nil)
local fm = tree()
local mok, mwhy = Appfiles.remove(fm, "/k/apps", "ghost")
check("appfiles: a missing folder is refused, nothing touched", mok == nil and mwhy == "not a folder" and #fm.removed == 0)
local ff = tree()
local fok, fwhy = Appfiles.remove(ff, "/k/apps", "main")
check("appfiles: a file is not a folder", fok == nil and fwhy == "not a folder")
-- links: never followed
local fl = tree()
fl.kinds["/k/apps/evil"] = "link"
local lok, lwhy = Appfiles.remove(fl, "/k/apps", "evil")
check("appfiles: the app folder as a link is refused", lok == nil and lwhy == "is a link" and #fl.removed == 0)
local fi = tree()
fi.kinds["/k/apps/timer/escape"] = "link"      -- points outside; the fake fs would list /outside if it followed
local iok = Appfiles.remove(fi, "/k/apps", "timer")
check("appfiles: a link inside is unlinked, not followed", iok == true and fi.kinds["/outside/secret"] == "file"
    and fi.kinds["/k/apps/timer/escape"] == nil)
local fe = tree()
local real_remove = fe.remove
fe.remove = function(p) if p:find("run.lua", 1, true) then return nil, "read-only" end return real_remove(p) end
local eok, ewhy = Appfiles.remove(fe, "/k/apps", "timer")
check("appfiles: a file that cannot be removed stops with the reason", eok == nil and tostring(ewhy):find("read-only", 1, true), ewhy)
check("appfiles: ...and nothing outside the app folder was touched", fe.kinds["/k/apps/nota/init.lua"] == "file" and fe.kinds["/k/main.lua"] == "file")

---------------------------------------------------------------- core: remove an app
local c3 = open_core()
local function reg3(id, over) return C.register(c3, app(id, over)) end
reg3("sistema", { system = true, refresh = nil }); reg3("notificacoes", { system = true, refresh = nil })
reg3("relogio", { system = true, refresh = nil }); reg3("timer"); reg3("nota")
local st = c3.store
st:set("timer", "interval", 300); st:data_set("timer", "d", 1); st:cache_put("timer", { x = 1 }, 1, 1)
st:state_set("timer", { last_ok = 3 }); st:notif_add({ app = "timer", key = "k", type = "t", title = "T", body = "b", prio = "alta", created_at = 9 })
st:set("nota", "interval", 60); st:data_set("nota", "d", 2)
st:layout_set("home", { { app = "timer", size = "2x2" }, { app = "nota", size = "2x2" }, { app = "sistema", size = "1x1" } })
st:layout_set("sleep", { { app = "nota", size = "2x2" }, { app = "timer", size = "2x2", hidden = true } })
local ffs = tree()
check("remove: ok", C.remove_app(c3, "timer", ffs, "/k/apps") == true)
check("remove: folder deleted", ffs.kinds["/k/apps/timer"] == nil and ffs.kinds["/k/apps/nota"] == "dir")
check("remove: not in the registry nor in the inactive list", C.app(c3, "timer") == nil and C.inactive(c3, "timer") == nil)
check("remove: settings, data, cache, state, notifications cleared",
    st:get("timer", "interval") == nil and st:data_get("timer", "d") == nil and st:cache_get("timer") == nil
    and st:state_get("timer") == nil and st:notif_find("timer", "k") == nil)
check("remove: other app's data stays", st:get("nota", "interval") == 60 and st:data_get("nota", "d") == 2)
same("remove: out of the home layout", (function() local o = {} for i, it in ipairs(st:layout_get("home")) do o[i] = it.app end return o end)(), { "nota", "sistema" })
same("remove: out of the sleep layout", (function() local o = {} for i, it in ipairs(st:layout_get("sleep")) do o[i] = it.app end return o end)(), { "nota" })
same("remove: id recorded so a copy of the plugin folder does not bring it back", C.removed_ids(c3), { "timer" })
for _, id in ipairs({ "sistema", "notificacoes", "relogio" }) do
    local f = tree()
    local sok, swhy = C.remove_app(c3, id, f, "/k/apps")
    check("remove: system app '" .. id .. "' refused", sok == nil and swhy == "system" and #f.removed == 0 and C.app(c3, id) ~= nil)
end
for _, bad in ipairs({ "../x", "..", "a/b", "" }) do
    local f = tree()
    local bok, bwhy = C.remove_app(c3, bad, f, "/k/apps")
    check("remove: id '" .. bad .. "' refused", bok == nil and bwhy == "bad id" and #f.removed == 0 and #f.rmdirs == 0)
end
check("remove: nothing outside apps/ was touched", ffs.kinds["/k/x/keep.txt"] == "file" and ffs.kinds["/outside/secret"] == "file" and ffs.kinds["/k/main.lua"] == "file")
-- a disabled app can be removed (its manifest sits in the inactive list)
C.set_disabled(c3, "nota", true)
check("remove: a turned-off app can be removed", C.remove_app(c3, "nota", ffs, "/k/apps") == true and C.inactive(c3, "nota") == nil
    and ffs.kinds["/k/apps/nota"] == nil)
same("remove: removed list has both", C.removed_ids(c3), { "nota", "timer" })
-- the files are already gone (removed by hand): the data is still cleaned
c3.store:set("ghost", "k", 1)
check("remove: folder already gone, data still cleaned", C.remove_app(c3, "ghost", ffs, "/k/apps") == true and c3.store:get("ghost", "k") == nil)
-- a failing delete leaves the app and its data alone
local c4 = open_core()
C.register(c4, app("timer")); c4.store:data_set("timer", "d", 1)
local fbad = tree()
local old = fbad.remove
fbad.remove = function(p) if p:find("init.lua", 1, true) then return nil, "denied" end return old(p) end
local xok, xwhy = C.remove_app(c4, "timer", fbad, "/k/apps")
check("remove: a failed delete keeps the app and its data", xok == nil and tostring(xwhy):find("denied") and C.app(c4, "timer") ~= nil
    and c4.store:data_get("timer", "d") == 1 and #C.removed_ids(c4) == 0)

---------------------------------------------------------------- min_tinta (and the old min_portal)
do
    local cok2, why2 = Registry.compat(app("a", { min_tinta = "99.0" }))
    check("compat: min_tinta newer than the Tinta refused", cok2 == false and why2 == "min_tinta")
    check("compat: min_tinta met", Registry.compat(app("a", { min_tinta = "0.1" })))
    cok2, why2 = Registry.compat(app("a", { min_portal = "99.0" }))
    check("compat: the old min_portal still refuses", cok2 == false and why2 == "min_portal")
    check("compat: the old min_portal still passes when met", Registry.compat(app("a", { min_portal = "0.1" })))
    check("validate: bad min_tinta rejected", not Registry.validate(app("a", { min_tinta = "x" })))
    local r = Registry.new()
    local rok, rwhy = r:register(app("future", { min_tinta = "99.0" }))
    check("register: parked with why min_tinta", rok == nil and rwhy == "min_tinta" and r:inactive_get("future").why == "min_tinta")
end
