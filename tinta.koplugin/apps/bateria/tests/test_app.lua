-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (C) 2026 Tinta contributors
-- the manifest against the real core (through ui/core, like ui/host): registration, legacy import hook (R-B5,
-- 16.4), refresh with a fake gauge, 8.6 first reading only records, notifications, status bar estimate (R-S1)
local T = ...
local check, eq = T.check, T.eq
local C = require("ui/core")
local Log = require("apps/bateria/csvlog")
local Logic = require("apps/bateria/logic")

local M = require("apps/bateria/init")
local A = M._A

eq("manifest: id", M.id, "bateria")
eq("manifest: sizes (10.3), 2x2 default (7.2)", table.concat(M.sizes, ","), "2x2,4x2,1x1")
eq("manifest: local", M.net, false)
eq("manifest: no source", M.source, nil)
eq("manifest: interval 1 min (R-U1)", M.defaults.interval, 60)
eq("manifest: notification types", M.notifications[1].type .. "," .. M.notifications[2].type, "low,full")
check("manifest: hooks", type(M.import_legacy) == "function" and type(M.battery_eta) == "function")
check("manifest: valid", (require("core/registry").validate(M)))

-- a data dir with the old plugin's log
local dir = T.tmp()
os.execute('mkdir -p "' .. dir .. '"')
local fh = io.open(dir .. "/old-battery.csv", "w")
fh:write(Logic.HEADER, "\n", "1000,90,0,1,4000,-48,816,25\n", "1600,89,0,1,3990,-48,808,25\n")
fh:close()
A.data_dir = function() return dir end
A.legacy_logs = function() return { "old-battery.csv", "missing-battery.csv" } end
A.store, A.last = nil, nil

local logs = {}
local now = 2000
local function open()
    local c = C.open{ db_path = dir .. "/none/tinta.sqlite3", now = function() return now end,
        log = function(app, level, msg) logs[#logs + 1] = (app or "-") .. " " .. level .. " " .. msg end }
    eq("register", C.register(c, M), true)
    return c
end
local c = open()
local imported = C.import_legacy(c)
eq("import hook: called once", table.concat(imported, ","), "bateria")
check("import hook: key set", c.store:meta_get("legacy_imported:bateria") ~= nil)
eq("import: merged into the new log", #T.lines(dir .. "/" .. Log.FILE), 3)
eq("import hook: second open does not call it", #C.import_legacy(c), 0)
check("import: logged without secrets", logs[#logs]:find("log antigo importado: 2 linhas", 1, true) ~= nil, logs[#logs])

-- an app whose import throws is asked again; one that returns false too
local calls = 0
local flaky = { id = "flaky", name = "Flaky", sizes = { "1x1" }, widget = function() end,
    import_legacy = function() calls = calls + 1; if calls == 1 then error("disk") end; return calls >= 3 end }
C.register(c, flaky)
C.import_legacy(c)
eq("import hook: a throw is retried", c.store:meta_get("legacy_imported:flaky"), nil)
C.import_legacy(c)
eq("import hook: false is retried", c.store:meta_get("legacy_imported:flaky"), nil)
C.import_legacy(c)
check("import hook: then set", c.store:meta_get("legacy_imported:flaky") ~= nil)
C.import_legacy(c)
eq("import hook: not called after", calls, 3)

-- refresh with a fake gauge
local gauge = { pct = 18, charging = false, mv = 3700, ma = -48, mah = 160, full_mah = 907, temp = 24, status = "Discharging" }
A.read = function() local r = {}; for k, v in pairs(gauge) do r[k] = v end; return r end
C.init_apps(c)
check("init opened the merged log", A.store and #A.store.samples == 2)
local results = {}
local function refresh()
    C.refresh(c, "bateria", function(ok, err, kind) results[#results + 1] = { ok, err, kind } end, true)
    return results[#results]
end
local r1 = refresh()
eq("refresh: ok", r1[1], true)
local cache = c.store:cache_get("bateria")
check("refresh: cache", type(cache) == "table" and cache.pct == 18 and cache.ma == -48 and cache.full_mah == 907)
check("refresh: last kept in memory", A.last and A.last.pct == 18)
eq("8.6: first reading after opening only records", c.notify:count(), 0)
now = now + 60
refresh()
eq("8.6: same discharge, no repeat", c.notify:count(), 0)
-- plug, charge to full: one 'full' notification
gauge.charging, gauge.status = true, "Charging"
for p = 20, 100, 20 do now = now + 600; gauge.pct = p; refresh() end
eq("full: one notification", c.notify:count(), 1)
local list = c.notify:list{ limit = 5 }
eq("full: key carries the charge start", list[1].key, "full:2660")
eq("full: prio normal", list[1].prio, "normal")
now = now + 60; refresh()
eq("full: not repeated", c.notify:count(), 1)
-- unplug and run down below 20 %: one 'low', alta
gauge.charging, gauge.status = false, "Discharging"
for p = 95, 15, -10 do now = now + 600; gauge.pct = p; gauge.mah = p * 9; refresh() end
eq("low: one notification", c.notify:count(), 2)
list = c.notify:list{ limit = 5 }
eq("low: newest first", list[1].title, "Bateria em 15%")
eq("low: alta", list[1].prio, "alta")
check("low: key", list[1].key:match("^low:%d+$") ~= nil, list[1].key)
now = now + 60; gauge.pct = 14; refresh()
eq("low: not repeated in the same discharge", c.notify:count(), 2)
-- tracking state persisted in ctx.data
local tr = c.store:data_get("bateria", "track")
check("track persisted", type(tr) == "table" and tr.chg == false and tr.pct == 14)

-- no reading: done(false) (counts as a failed refresh: dashed border, R-S5)
A.read = function() return nil end
local rf = refresh()
eq("no reading: not ok", rf[1], false)
eq("no reading: message", rf[2], "sem leitura do medidor")
A.read = function() local r = {}; for k, v in pairs(gauge) do r[k] = v end; return r end

-- the status bar estimate through the registry, like Host.battery_eta
A.last = { eta = 3 * 3600, charging = false, at = now }
local ok, eta = C.call(c, "bateria", "battery_eta", { pct = 14, charging = false })
eq("battery_eta: through the registry", ok and eta, "~3h00")
local ok2, eta2 = C.call(c, "bateria", "battery_eta", { pct = 14, charging = true })
eq("battery_eta: other state -> nil", ok2 and eta2, nil)
-- without this session's reading it falls back to the persisted cache
A.last = nil
c.store:cache_put("bateria", { eta = 7200, charging = false, at = now, pct = 14 }, now, 1)
c.registry:ctx("bateria").cache.reset()   -- written behind ctx.cache's back: drop its in-memory copy
local _, eta3 = C.call(c, "bateria", "battery_eta", { pct = 14, charging = false })
eq("battery_eta: from the cache", eta3, "~2h00")

-- the log file got the readings (changes only)
local lines = T.lines(dir .. "/" .. Log.FILE)
check("log: lines appended", #lines > 10, #lines)
eq("log: header", lines[1], Logic.HEADER)
check("log: gauge columns", lines[#lines]:match(",3700,%-48,%d+,24$") ~= nil, lines[#lines])

-- a missing data dir: import asks again later, the log works from memory
A.data_dir = function() return nil end
A.store = nil
local c2 = open()
eq("no data dir: import not recorded", #C.import_legacy(c2), 0)
eq("no data dir: key unset", c2.store:meta_get("legacy_imported:bateria"), nil)
A.read = function() return { pct = 50, charging = false } end
eq("no data dir: refresh still ok", (function() C.refresh(c2, "bateria", function(ok3) results[#results + 1] = { ok3 } end, true); return results[#results][1] end)(), true)
eq("no data dir: memory log", A.store.broken, true)

os.execute('rm -rf "' .. dir .. '"')
A.store, A.last = nil, nil
