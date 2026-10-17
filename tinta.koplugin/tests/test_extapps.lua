-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (C) 2026 Tinta contributors
-- core/extapps: <data dir>/tinta-apps/<id>/ and the searcher that lets an app's own require("apps/<id>/...") find
-- its files there. Real files in a temp folder.
local T = ...
local Ext = require("core/extapps")
local Registry = require("core/registry")
local eq, same, check = T.eq, T.same, T.check

eq("dir_of", Ext.dir_of("/mnt/us/koreader"), "/mnt/us/koreader/tinta-apps")
eq("dir_of: trailing slash", Ext.dir_of("/mnt/us/koreader/"), "/mnt/us/koreader/tinta-apps")
eq("dir_of: no data dir", Ext.dir_of(nil), nil)

local function split(n) local a, b = Ext.split(n); return tostring(a) .. "|" .. tostring(b) end
eq("split: app file", split("apps/alfa/logic"), "alfa|logic")
eq("split: nested", split("apps/alfa/sub/x"), "alfa|sub/x")
eq("split: the id alone is not a file", split("apps/alfa"), "nil|nil")
eq("split: not an app module", split("core/json"), "nil|nil")
eq("split: parent escape refused", split("apps/alfa/../../x"), "nil|nil")
eq("split: bad id refused", split("apps/Or ca/x"), "nil|nil")
eq("split: absolute rest refused", split("apps/alfa//etc"), "nil|nil")
eq("split: weird characters refused", split("apps/alfa/x;y"), "nil|nil")

local root = os.tmpname(); os.remove(root)
local ext = root .. "/tinta-apps"
local function write(p, s) local f = assert(io.open(p, "w")); f:write(s); f:close() end
os.execute(('mkdir -p "%s/extdemo/sub" "%s/other"'):format(ext, ext))
write(ext .. "/extdemo/init.lua", [[
local Logic = require("apps/extdemo/logic")
local Deep = require("apps/extdemo/sub/deep")
return { id = "extdemo", name = "Ext demo", sizes = { "1x1" }, widget = function() return Logic.hello() .. Deep.x end }
]])
write(ext .. "/extdemo/logic.lua", 'return { hello = function() return "hi" end }')
write(ext .. "/extdemo/sub/deep.lua", 'return { x = "!" }')
write(ext .. "/other/init.lua", 'return { id = "other", name = "Other", sizes = { "1x1" }, widget = function() return "o" end }')

local function reset() for k in pairs(package.loaded) do if k:match("^apps/ext") or k:match("^apps/other") then package.loaded[k] = nil end end end
local function loaders() return package.loaders or package.searchers end
local n0 = #loaders()

check("require before install: not found", not pcall(require, "apps/extdemo/init"))
Ext.install(ext, { "extdemo" })
Ext.install(ext, { "extdemo" })
eq("install: one searcher however many installs", #loaders(), n0 + 1)
local ok, m = pcall(require, "apps/extdemo/init")
check("require resolves apps/<id>/init in tinta-apps (and its requires)", ok and type(m) == "table" and m.id == "extdemo" and m.widget() == "hi!", m)
check("the manifest it returns is valid", Registry.validate(m))
check("an id that is not registered is not resolved", not pcall(require, "apps/other/init"))
check("a file that is not there is an error, not a crash", not pcall(require, "apps/extdemo/nothing"))
reset()
Ext.install(ext, { "extdemo", "other" })
check("reinstall with another id list takes effect", pcall(require, "apps/other/init"))
reset()
Ext.install(ext, {})
check("reinstall with no ids resolves nothing", not pcall(require, "apps/extdemo/init"))

-- a syntax error in an app is reported with its file, not swallowed
write(ext .. "/extdemo/logic.lua", "return {")
reset(); Ext.install(ext, { "extdemo" })
local bad, err = pcall(require, "apps/extdemo/logic")
check("a broken app file raises with its path", not bad and tostring(err):find("extdemo/logic.lua", 1, true), err)

Ext.uninstall()
eq("uninstall removes the searcher", #loaders(), n0)
reset()

-- scan: folders with an init.lua, ids only
local lfs_like = {
    dir = function(d)
        local p = io.popen('ls -1a "' .. d .. '" 2>/dev/null')
        local names = {}
        for l in p:lines() do names[#names + 1] = l end
        p:close()
        local i = 0
        return function() i = i + 1; return names[i] end
    end,
    is_file = function(p) local f = io.open(p, "r"); if f then f:close() end; return f ~= nil end,
}
os.execute(('mkdir -p "%s/no_init" "%s/Bad-Id" && cp "%s/other/init.lua" "%s/Bad-Id/init.lua"'):format(ext, ext, ext, ext))
same("scan: only folders that are ids and have init.lua", (Ext.scan(ext, lfs_like)), { "extdemo", "other" })
same("scan: no dir", (Ext.scan(nil, lfs_like)), {})
local list, okscan = Ext.scan(root .. "/missing", lfs_like)
check("scan: a missing folder is an empty list", #list == 0)
os.execute('rm -rf "' .. root .. '"')
