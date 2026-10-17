-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (C) 2026 Tinta contributors
-- core/migrate: the one-time move from the Portal file names and the two-plugins guard, on a fake file system.
local T = ...
local Migrate = require("core/migrate")
local eq, same, check = T.eq, T.same, T.check

local function fake(files)
    local fs, log = { files = files, renames = {}, fail = {} }, {}
    function fs.exists(p) return fs.files[p] ~= nil end
    function fs.rename(a, b)
        if fs.fail[a] then return nil, "denied" end
        fs.files[b], fs.files[a] = fs.files[a], nil
        fs.renames[#fs.renames + 1] = a .. " -> " .. b
        return true
    end
    return fs
end

-- the user's KT3 today: everything under the Portal names
local fs = fake({ ["/k/portal.sqlite3"] = "db", ["/k/portal-battery.csv"] = "csv", ["/k/portal-power.log"] = "log", ["/k/other"] = "x" })
local moved, errs = Migrate.run("/k", fs)
eq("migrate: three files moved", #moved, 3)
check("migrate: new names hold the data", fs.files["/k/tinta.sqlite3"] == "db" and fs.files["/k/tinta-battery.csv"] == "csv" and fs.files["/k/tinta-power.log"] == "log")
check("migrate: old names are gone, nothing else touched", not fs.files["/k/portal.sqlite3"] and not fs.files["/k/portal-battery.csv"]
    and not fs.files["/k/portal-power.log"] and fs.files["/k/other"] == "x")
eq("migrate: no errors", #errs, 0)
local again = Migrate.run("/k", fs)
eq("migrate: second open does nothing", #again, 0)

-- never overwrite a new file
fs = fake({ ["/k/portal.sqlite3"] = "old", ["/k/tinta.sqlite3"] = "new", ["/k/portal-power.log"] = "oldlog" })
moved = Migrate.run("/k", fs)
check("migrate: an existing tinta.sqlite3 is kept, the old one stays", fs.files["/k/tinta.sqlite3"] == "new" and fs.files["/k/portal.sqlite3"] == "old")
check("migrate: the others still move", fs.files["/k/tinta-power.log"] == "oldlog" and #moved == 1)

-- side files follow the database only
fs = fake({ ["/k/portal.sqlite3"] = "db", ["/k/portal.sqlite3-journal"] = "j" })
Migrate.run("/k", fs)
check("migrate: journal goes with the database", fs.files["/k/tinta.sqlite3-journal"] == "j" and not fs.files["/k/portal.sqlite3-journal"])
fs = fake({ ["/k/portal.sqlite3"] = "db", ["/k/tinta.sqlite3"] = "new", ["/k/portal.sqlite3-wal"] = "w" })
Migrate.run("/k", fs)
check("migrate: a side file does not move when the database did not", fs.files["/k/portal.sqlite3-wal"] == "w" and not fs.files["/k/tinta.sqlite3-wal"])

-- fresh install, no data dir, a failing rename
fs = fake({})
eq("migrate: nothing to move", #Migrate.run("/k", fs), 0)
eq("migrate: no dir is a no-op", #Migrate.run(nil, fs), 0)
fs = fake({ ["/k/portal.sqlite3"] = "db", ["/k/portal-battery.csv"] = "csv" })
fs.fail["/k/portal.sqlite3"] = true
moved, errs = Migrate.run("/k", fs)
check("migrate: a failed rename is reported, the rest still moves", #errs == 1 and errs[1]:find("portal.sqlite3: denied", 1, true) and #moved == 1)
check("migrate: the failed file stays where it was (retried next open)", fs.files["/k/portal.sqlite3"] == "db")

-- real files (the default fs)
local dir = os.tmpname(); os.remove(dir); os.execute('mkdir -p "' .. dir .. '"')
local f = io.open(dir .. "/portal-power.log", "w"); f:write("L"); f:close()
local rm = Migrate.run(dir)
local r = io.open(dir .. "/tinta-power.log", "r")
check("migrate: default fs renames real files", #rm == 1 and r ~= nil and r:read("*a") == "L")
if r then r:close() end
os.execute('rm -rf "' .. dir .. '"')

-- two plugins at once
local pfs = fake({ ["/p/plugins/portal.koplugin/main.lua"] = "x" })
check("guard: old plugin folder next to this one", Migrate.legacy_plugin_present("/p/plugins/tinta.koplugin", pfs))
check("guard: trailing slash", Migrate.legacy_plugin_present("/p/plugins/tinta.koplugin/", pfs))
check("guard: not installed", not Migrate.legacy_plugin_present("/q/plugins/tinta.koplugin", pfs))
check("guard: junk path", not Migrate.legacy_plugin_present(nil, pfs) and not Migrate.legacy_plugin_present("tinta.koplugin", pfs))
