-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (C) 2026 Tinta contributors
-- Tinta: apps outside the plugin folder (<data dir>/tinta-apps/<id>/init.lua) and the one-time move from the Portal
-- file names, on the headless UI smoke's stubs. tests/tinta_ui_smoke.lua hands over to the scenario below:
--   * two apps (the private ones when present), copied from the repo into a fake tinta-apps/, load from there with a plugin
--     folder that does not have them (their own require("apps/<id>/...") resolves through core/extapps), open their
--     screens and show on Home;
--   * an external app with the id of a bundled one is refused with a log line and the bundled one keeps running;
--   * removing an external app deletes inside tinta-apps/ only;
--   * portal.sqlite3 / portal-battery.csv / portal-power.log in the data dir are renamed when the Tinta opens,
--     and never over an existing tinta-* file.
--   luajit tests/tinta_ui_external.lua       (from the repo root)
_G.SMOKE_SCENARIO = function(x)
    local Host, check, step, contains_text = x.Host, x.check, x.step, x.contains_text
    local TA = dofile("tests/testapps.lua")   -- the apps deployed to the fake tinta-apps/ (private ones when in the tree)
    local X1, X2 = TA.ext[1], TA.ext[2]
    local function sh(cmd) return os.execute(cmd) end
    local function exists(p) local f = io.open(p, "rb"); if f then f:close() end; return f ~= nil end
    local function read(p) local f = io.open(p, "rb"); if not f then return nil end; local s = f:read("*a"); f:close(); return s end
    local function write(p, s) local f = assert(io.open(p, "wb")); f:write(s); f:close() end

    Host:close(); x.run_scheduled(1)
    Host.DEFAULTS.dev_apps = false

    -- the smoke's lfs stub lists and tests files; removal needs the rest of what the device has
    local lfs = require("libs/libkoreader-lfs")
    local stub_attr = lfs.attributes
    lfs.attributes = function(path, what)
        local isdir = sh('test -d "' .. path .. '"') == 0 or sh('test -d "' .. path .. '"') == true
        if isdir then return "directory" end
        return stub_attr(path, what)
    end
    lfs.symlinkattributes = function(path, what)
        if sh('test -L "' .. path .. '"') == 0 or sh('test -L "' .. path .. '"') == true then return "link" end
        return nil
    end
    lfs.rmdir = function(path) return os.remove(path) end

    local root = os.tmpname(); os.remove(root)
    local plugin, data = root .. "/plugin", root .. "/data"
    sh('mkdir -p "' .. plugin .. '/apps" "' .. data .. '/tinta-apps"')
    -- a plugin folder with every bundled app but the two (symlinks to the repo's files)
    local cwd = io.popen("pwd"):read("*l")
    for _, d in ipairs({ "core", "ui", "device" }) do sh(('ln -s "%s/tinta.koplugin/%s" "%s/%s"'):format(cwd, d, plugin, d)) end
    local p = io.popen('ls -1 "' .. cwd .. '/tinta.koplugin/apps"')
    for id in p:lines() do
        if id ~= X1 and id ~= X2 then sh(('ln -s "%s/tinta.koplugin/apps/%s" "%s/apps/%s"'):format(cwd, id, plugin, id)) end
    end
    p:close()
    -- the apps as a user would deploy them: tinta-apps/<id>/ (scripts/deploy.sh --app), without their tests
    for _, id in ipairs({ X1, X2 }) do
        sh(('mkdir -p "%s/tinta-apps/%s" && cp -R "%s/tinta.koplugin/apps/%s/." "%s/tinta-apps/%s/" && rm -rf "%s/tinta-apps/%s/tests"')
            :format(data, id, cwd, id, data, id, data, id))
    end
    -- same id as a bundled app: refused
    sh(('mkdir -p "%s/tinta-apps/relogio" && cp "%s/tinta.koplugin/apps/relogio/init.lua" "%s/tinta-apps/relogio/init.lua"'):format(data, cwd, data))
    -- the Portal names
    write(data .. "/portal.sqlite3", "OLD-DB"); write(data .. "/portal-battery.csv", "OLD-CSV"); write(data .. "/portal-power.log", "OLD-LOG")
    write(data .. "/tinta-power.log", "NEW-LOG")     -- exists already: must survive, the old one stays

    -- the repo's tinta.koplugin/ is out of package.path: the two can only come from tinta-apps/
    local path = package.path
    package.path = plugin .. "/?.lua;" .. path:gsub("tinta%.koplugin/%?%.lua;", "")
    for k in pairs(package.loaded) do if k:match("^apps/") then package.loaded[k] = nil end end

    local logs = {}
    local real_log = Host.log
    Host.log = function(self, app, level, msg) logs[#logs + 1] = tostring(app) .. " " .. level .. " " .. tostring(msg); return real_log(self, app, level, msg) end
    local ok, err = xpcall(function() Host:open{ plugin_dir = plugin, data_dir = data, db_path = "/tmp/none.sqlite3", first_run = false } end, debug.traceback)
    check("external: tinta opens with a tinta-apps folder", ok, err)
    local win = Host.window
    x.run_scheduled(0)
    local function logged(s) for _, l in ipairs(logs) do if l:find(s, 1, true) then return true end end return false end

    check("external: first app loaded from tinta-apps", Host:app(X1) ~= nil)
    check("external: second app loaded from tinta-apps", Host:app(X2) ~= nil)
    check("external: the apps' own requires resolved in tinta-apps",
        (package.loaded["apps/" .. X1 .. "/logic"] ~= nil) and (package.loaded["apps/" .. X2 .. "/logic"] ~= nil))
    check("external: bundled apps still load", Host:app("relogio") ~= nil and Host:app("sistema") ~= nil)
    check("external: same id as a bundled app is refused, logged", logged("external app refused"), table.concat(logs, " | "))
    check("external: the refused one did not replace the bundled one", Host:app("relogio") ~= nil and package.loaded["apps/relogio/init"] ~= nil
        and Host:appsDir() == plugin .. "/apps")
    check("external: the apps list has both once", (function()
        local n = 0
        for _, a in ipairs(Host:apps()) do if a.id == X1 or a.id == X2 then n = n + 1 end end
        return n == 2
    end)())

    for _, id in ipairs({ X1, X2 }) do
        step("external: " .. id .. " main screen", function() win:goHome(); win:openApp(id) end)
        check("external: " .. id .. " screen is the app's, not the error screen",
            win:current().kind == "app" and win:current().app == id and not contains_text(win[1], Host:appName(id) .. " · erro"), win:current().kind)
    end
    win:goHome()

    -- the Portal files were moved before the store opened, and never over a tinta-* file
    check("rename: portal.sqlite3 -> tinta.sqlite3", exists(data .. "/tinta.sqlite3") and not exists(data .. "/portal.sqlite3") and read(data .. "/tinta.sqlite3") == "OLD-DB")
    check("rename: portal-battery.csv moved", read(data .. "/tinta-battery.csv") ~= nil and not exists(data .. "/portal-battery.csv"))
    check("rename: an existing tinta-power.log is not overwritten", read(data .. "/tinta-power.log") == "NEW-LOG" and read(data .. "/portal-power.log") == "OLD-LOG")
    check("rename: logged once", logged("renamed from Portal"))

    -- removal deletes inside tinta-apps/ only
    local before = exists(cwd .. "/tinta.koplugin/apps/" .. X1 .. "/init.lua")
    check("external: remove an external app", Host:removeApp(X1) == true)
    check("external: its folder gone from tinta-apps, repo copy untouched", not exists(data .. "/tinta-apps/" .. X1 .. "/init.lua")
        and exists(data .. "/tinta-apps/" .. X2 .. "/init.lua") and exists(data .. "/tinta-apps/relogio/init.lua") and before
        and exists(cwd .. "/tinta.koplugin/apps/" .. X1 .. "/init.lua"))
    check("external: removed app is gone from the registry", Host:app(X1) == nil)
    x.close()

    -- reopened: the removed one does not come back; the other does
    Host:open{ plugin_dir = plugin, data_dir = data, db_path = "/tmp/none.sqlite3", first_run = false }
    check("external: removed app stays out after a reopen", Host:app(X1) == nil and Host:app(X2) ~= nil)
    x.close()

    Host.log = real_log
    package.path = path
    for k in pairs(package.loaded) do if k:match("^apps/") then package.loaded[k] = nil end end
    sh('rm -rf "' .. root .. '"')
end
dofile("tests/tinta_ui_smoke.lua")
