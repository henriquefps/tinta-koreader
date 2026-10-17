-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (C) 2026 Tinta contributors
-- The SQLite backend against KOReader's real lua-ljsqlite3 binding, when it can be loaded on this machine:
-- needs the KOReader sources (KOREADER_REF=<dir with common/lua-ljsqlite3>, default ../../.koreader-ref) and a
-- system libsqlite3. Skipped otherwise; the memory backend covers the contract either way.
local T = ...
local Store = require("core/store")
local contract = require("store_contract")
local eq, same, check = T.eq, T.same, T.check

local ref = os.getenv("KOREADER_REF") or (T.here .. "/../../.koreader-ref")
local function exists(p) local f = io.open(p) if f then f:close() return true end return false end
if not exists(ref .. "/common/lua-ljsqlite3/init.lua") then
    T.skip("sqlite backend", "KOReader sources not found (set KOREADER_REF)")
    return
end

-- the two KOReader-specific pieces the binding expects, provided the desktop way
local ffi = require("ffi")
local saved_path = package.path
local saved_loadlib = ffi.loadlib
ffi.loadlib = ffi.loadlib or function(name) return ffi.load(name) end
package.preload["ffi/posix_h"] = package.preload["ffi/posix_h"] or function() pcall(ffi.cdef, "void free(void *);") return true end
package.path = ref .. "/common/?.lua;" .. package.path
local okb, SQ3 = pcall(require, "lua-ljsqlite3/init")
package.path = saved_path
if not okb then
    ffi.loadlib = saved_loadlib
    T.skip("sqlite backend", "binding failed to load: " .. tostring(SQ3))
    return
end

local dir = os.tmpname()
os.remove(dir)
local function tmp(name) return dir .. "-" .. name end
local files = {}
local function db_path(name) local p = tmp(name); files[#files + 1] = p; return p end

-- interface contract on a real file
local p1 = db_path("contract.sqlite3")
contract(T, function()
    local s, info = Store.sqlite(p1, { sq3 = SQ3, now = T.clock(1) })
    check("sqlite: opened without fallback", s.kind == "sqlite" and not info.fallback, info.error)
    return s
end, "sqlite")

-- schema per section 12
local s = Store.sqlite(db_path("schema.sqlite3"), { sq3 = SQ3, now = T.clock(1) })
local conn = s._conn
local tables = {}
local stmt = conn:prepare("SELECT name FROM sqlite_master WHERE type = 'table' ORDER BY name")
for row in stmt:rows() do tables[#tables + 1] = row[1] end
stmt:close()
same("sqlite: tables of spec 12", tables, { "app_cache", "app_data", "app_state", "layout", "log", "meta", "notifications", "settings" })
eq("sqlite: schema_version in meta", s:meta_get("schema_version"), tostring(Store.latest_version()))
-- UNIQUE (app, key) enforced by the schema too
s:notif_add({ app = "a", key = "k", title = "t", created_at = 1 })
check("sqlite: UNIQUE(app, key) in schema", not pcall(conn.exec, conn, "INSERT INTO notifications (app, key) VALUES ('a', 'k')"))
-- integers come back as Lua numbers, not int64 cdata
eq("sqlite: integer type", type(s:notif_find("a", "k").created_at), "number")
s:close()

-- data survives reopen; migrations run once and in order (R-B3)
local p2 = db_path("migrate.sqlite3")
local a = Store.sqlite(p2, { sq3 = SQ3, now = T.clock(1) })
a:set("portal", "lang", "en")
a:layout_set("home", { { app = "alfa", size = "4x4" } })
a:close()
local migs = {}
for _, m in ipairs(Store.MIGRATIONS) do migs[#migs + 1] = m end
local nxt = Store.latest_version() + 1
migs[#migs + 1] = { version = nxt, sql = "ALTER TABLE app_state ADD COLUMN extra TEXT" }
migs[#migs + 1] = { version = nxt + 1, sql = "CREATE TABLE extra_t (x INTEGER)" }
local b, binfo = Store.sqlite(p2, { sq3 = SQ3, now = T.clock(2), migrations = migs })
check("sqlite: reopened", b.kind == "sqlite" and not binfo.recovered, binfo.error)
eq("sqlite: migrated to newest", b:schema_version(), nxt + 1)
eq("sqlite: data kept across migration", b:get("portal", "lang"), "en")
same("sqlite: layout kept", b:layout_get("home"), { { app = "alfa", size = "4x4" } })
check("sqlite: migration applied", pcall(b._conn.exec, b._conn, "SELECT extra FROM app_state"))
b:close()
local c = Store.sqlite(p2, { sq3 = SQ3, now = T.clock(3), migrations = migs })
eq("sqlite: reopen does not re-run migrations", c:schema_version(), nxt + 1)
c:close()
-- a failing migration (code problem) leaves the file alone, rolls back, and the Tinta runs on memory
local bad_migs = {}
for _, m in ipairs(migs) do bad_migs[#bad_migs + 1] = m end
bad_migs[#bad_migs + 1] = { version = nxt + 2, sql = "CREATE TABLE extra_t (x INTEGER)" }   -- already exists
local renamed = false
local d, dinfo = Store.sqlite(p2, { sq3 = SQ3, now = T.clock(4), migrations = bad_migs,
    rename = function() renamed = true; return false end })
check("sqlite: failing migration -> memory fallback", d.kind == "memory" and dinfo.fallback, dinfo.error)
check("sqlite: failing migration does not rename the file", not renamed and not dinfo.recovered)
check("sqlite: error is one line", dinfo.error and not dinfo.error:find("\n"), dinfo.error)
local d2 = Store.sqlite(p2, { sq3 = SQ3, now = T.clock(5), migrations = migs })
eq("sqlite: version unchanged after failed migration (rolled back)", d2:schema_version(), nxt + 1)
eq("sqlite: data intact after failed migration", d2:get("portal", "lang"), "en")
d2:close()

-- R-B4: corrupt file is renamed to .bad-<date>, a new database opens, the log says so, default layout
local p3 = db_path("corrupt.sqlite3")
local f = io.open(p3, "wb"); f:write(string.rep("this is not a database\0", 400)); f:close()
local clock = T.clock(T.utc(2026, 10, 16, 12, 0, 0))
local e, einfo = Store.sqlite(p3, { sq3 = SQ3, now = clock })
check("R-B4: recovered", einfo.recovered and e.kind == "sqlite", einfo.error)
check("R-B4: bad file kept with date suffix", einfo.bad_path and exists(einfo.bad_path) and einfo.bad_path:find("%.bad%-%d+%-%d+$"), einfo.bad_path)
if einfo.bad_path then files[#files + 1] = einfo.bad_path end
check("R-B4: warning in the log", e:log_list()[1].msg:find("moved to"))
eq("R-B4: fresh db has no layout (tinta uses the default)", e:layout_get("home"), nil)
e:set("portal", "lang", "pt")
eq("R-B4: fresh db works", e:get("portal", "lang"), "pt")
e:close()

for _, p in ipairs(files) do
    os.remove(p); os.remove(p .. "-journal")
end
ffi.loadlib = saved_loadlib
