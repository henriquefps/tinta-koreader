-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (C) 2026 Tinta contributors
local T = ...
local Store = require("core/store")
local contract = require("store_contract")
local eq, same, check = T.eq, T.same, T.check

contract(T, function() return Store.memory({ now = T.clock(1) }) end, "memory")

-- module loads without the SQLite binding (lazy require)
check("store: module loaded without lua-ljsqlite3", package.loaded["lua-ljsqlite3/init"] == nil)

-- migrations (R-B3) on the memory backend
same("pending: from 0", (function() local o = {} for _, m in ipairs(Store.pending(0)) do o[#o + 1] = m.version end return o end)(), { 1 })
same("pending: up to date", Store.pending(Store.latest_version()), {})
local migs = {
    { version = 1, memory = function(db) db.meta.v1 = "y" end },
    { version = 3, memory = function(db) db.meta.v3 = "y" end },
    { version = 2, memory = function(db) db.meta.order = (db.meta.v1 or "") .. (db.meta.v3 or "") .. "2" end },
}
same("pending: sorted", (function() local o = {} for _, m in ipairs(Store.pending(1, migs)) do o[#o + 1] = m.version end return o end)(), { 2, 3 })
eq("latest_version", Store.latest_version(migs), 3)
local s = Store.memory({ migrations = { migs[1] } })
eq("memory migrate: v1", s:schema_version(), 1)
s.migrate(migs)
eq("memory migrate: upgraded to 3", s:schema_version(), 3)
eq("memory migrate: in order (2 before 3)", s:meta_get("order"), "y2")
eq("memory migrate: v1 not re-run", s:meta_get("v1"), "y")
s:meta_set("v1", "changed"); s.migrate(migs)
eq("memory migrate: idempotent", s:meta_get("v1"), "changed")

-- R-B4 with a fake binding: unreadable db is renamed, a fresh one is created and the log says so
local Fake = {}
do
    local opened = {}
    Fake.opened = opened
    function Fake.open(path)
        opened[#opened + 1] = path
        if Fake.fail_next then
            Fake.fail_next = Fake.fail_next - 1
            if Fake.fail_next <= 0 then Fake.fail_next = nil end
            error("file is not a database")
        end
        -- minimal in-memory connection that answers the calls M._wrap makes is out of scope here: hand back a
        -- connection whose quick_check fails or succeeds as asked
        return { rowexec = function() return "ok" end, exec = function() end, close = function() end,
                 prepare = function() error("fake: no SQL") end }
    end
end
local renamed = {}
local clock = T.clock(T.utc(2026, 10, 16, 12, 0, 0))
Fake.fail_next = 1
local st, info = Store.sqlite("/x/tinta.sqlite3", { sq3 = Fake, now = clock,
    rename = function(a, b) renamed[#renamed + 1] = a .. " -> " .. b; return true end, remove = function() end })
check("R-B4: fake binding cannot run SQL -> falls back to memory", st.kind == "memory" and info.fallback)
check("R-B4: renamed with date", renamed[1] and renamed[1]:find("^/x/tinta.sqlite3 %-> /x/tinta.sqlite3.bad%-%d%d%d%d%d%d%d%d%-%d%d%d%d%d%d$"), renamed[1])
check("R-B4: recovered flag", info.recovered and info.bad_path:find("%.bad%-"))
check("R-B4: logged", st:log_list()[1].msg:find("cannot open database"))
eq("R-B4: fallback store has default (empty) layout", st:layout_get("home"), nil)

-- missing binding -> memory store, logged
local st2, info2 = Store.sqlite("/x/p.sqlite3", { now = clock })
if package.loaded["lua-ljsqlite3/init"] == nil then
    check("no binding: memory fallback", st2.kind == "memory" and info2.fallback)
    check("no binding: logged", st2:log_list()[1].msg:find("binding unavailable"))
else
    T.skip("no binding: memory fallback", "binding present")
end
-- rename fails -> memory fallback
Fake.fail_next = 5
local st3, info3 = Store.sqlite("/x/p.sqlite3", { sq3 = Fake, now = clock, rename = function() return nil end })
check("R-B4: rename impossible -> memory fallback, not recovered", st3.kind == "memory" and info3.fallback and not info3.recovered)
Fake.fail_next = nil

-- JSON round trip in the memory backend mirrors SQLite
local m = Store.memory()
local t = { 1, 2 }
m:data_set("a", "k", t)
t[3] = 3
same("memory: values are copied (no aliasing)", m:data_get("a", "k"), { 1, 2 })
