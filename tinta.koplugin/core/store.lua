-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (C) 2026 Tinta contributors
-- Persistence behind a small interface (R-B1): settings by scope, layouts, app data, app cache, app state,
-- notifications, log, meta. Two backends with the same methods:
--   Store.memory(opts)        tables in memory (tests, and fallback when the database cannot be opened)
--   Store.sqlite(path, opts)  SQLite through KOReader's lua-ljsqlite3 binding (spec 12)
-- The binding is required lazily (only by Store.sqlite), so this module loads without it (R-A1, tests).
-- Values (settings, app data, cache, routes) are stored as JSON; both backends round-trip them through JSON,
-- so a value that does not survive JSON fails the same way in tests and on the device.
local JSON = require("core/json")

local M = {}

M.LOG_MAX = 500        -- spec 12: only the last 500 log lines
M.NOTIF_MAX = 200      -- R-T4

-- R-B3: numbered migrations. `sql` runs on SQLite (statements separated by ";", no ";" inside literals: the
-- binding splits on it); `memory` (optional) runs on the memory backend's tables.
M.MIGRATIONS = {
    {
        version = 1,
        sql = [[
            CREATE TABLE IF NOT EXISTS settings (scope TEXT, key TEXT, value TEXT, PRIMARY KEY (scope, key));
            CREATE TABLE IF NOT EXISTS layout (page TEXT, pos INTEGER, app TEXT, size TEXT, hidden INTEGER,
                PRIMARY KEY (page, pos));
            CREATE TABLE IF NOT EXISTS app_data (app TEXT, key TEXT, value TEXT, PRIMARY KEY (app, key));
            CREATE TABLE IF NOT EXISTS app_cache (app TEXT PRIMARY KEY, value TEXT, fetched_at INTEGER, version INTEGER);
            CREATE TABLE IF NOT EXISTS app_state (app TEXT PRIMARY KEY, last_ok INTEGER, last_err INTEGER,
                err_text TEXT, fail_streak INTEGER);
            CREATE TABLE IF NOT EXISTS notifications (
                id INTEGER PRIMARY KEY, app TEXT, key TEXT, type TEXT, title TEXT, body TEXT, prio TEXT, route TEXT,
                created_at INTEGER, read_at INTEGER, UNIQUE (app, key));
            CREATE INDEX IF NOT EXISTS notifications_created ON notifications (created_at);
            CREATE TABLE IF NOT EXISTS log (id INTEGER PRIMARY KEY, at INTEGER, app TEXT, level TEXT, msg TEXT)
        ]],
    },
}

-- Migrations with version > current, in version order.
function M.pending(current, migrations)
    local out = {}
    for _, m in ipairs(migrations or M.MIGRATIONS) do
        if m.version > (current or 0) then out[#out + 1] = m end
    end
    table.sort(out, function(a, b) return a.version < b.version end)
    return out
end

function M.latest_version(migrations)
    local v = 0
    for _, m in ipairs(migrations or M.MIGRATIONS) do if m.version > v then v = m.version end end
    return v
end

local function encode(v)
    if v == nil then return nil end
    return JSON.encode(v)
end

local function decode(s)
    if s == nil then return nil end
    return (JSON.decode(s))
end

local function roundtrip(v) return decode(encode(v)) end

local function copy(t)
    if type(t) ~= "table" then return t end
    local o = {}
    for k, v in pairs(t) do o[k] = copy(v) end
    return o
end

local function newest_first(a, b)
    if a.created_at ~= b.created_at then return (a.created_at or 0) > (b.created_at or 0) end
    return a.id > b.id
end

local function oldest_first(a, b) return newest_first(b, a) end

---------------------------------------------------------------- memory backend

function M.memory(opts)
    opts = opts or {}
    local migrations = opts.migrations or M.MIGRATIONS
    local db = {
        meta = {}, settings = {}, layout = {}, app_data = {}, app_cache = {}, app_state = {},
        notifications = {}, log = {}, next_notif = 0, next_log = 0,
    }
    local S = { kind = "memory", _db = db }

    -- schema version bookkeeping, same rules as SQLite
    local function migrate()
        local cur = tonumber(db.meta.schema_version) or 0
        for _, m in ipairs(M.pending(cur, migrations)) do
            if m.memory then m.memory(db) end
            db.meta.schema_version = tostring(m.version)
        end
        db.meta.created_at = db.meta.created_at or tostring(opts.now and opts.now() or os.time())
    end
    function S.migrate(more)
        if more then migrations = more end
        migrate()
    end
    migrate()

    function S:schema_version() return tonumber(db.meta.schema_version) or 0 end
    function S:meta_get(k) return db.meta[k] end
    function S:meta_set(k, v) db.meta[k] = v ~= nil and tostring(v) or nil end

    -- settings: scope = "portal" or app id
    function S:get(scope, key)
        local s = db.settings[scope]
        if not s then return nil end
        return decode(s[key])
    end
    function S:set(scope, key, value)
        db.settings[scope] = db.settings[scope] or {}
        db.settings[scope][key] = encode(value)
    end
    function S:all(scope)
        local out = {}
        for k, v in pairs(db.settings[scope] or {}) do out[k] = decode(v) end
        return out
    end

    -- layout: page = "home" | "sleep"; nil when never saved
    function S:layout_get(page)
        local l = db.layout[page]
        if not l then return nil end
        local out = {}
        for i, it in ipairs(l) do out[i] = { app = it.app, size = it.size, hidden = it.hidden and true or nil } end
        return out
    end
    function S:layout_set(page, list)
        local l = {}
        for i, it in ipairs(list or {}) do l[i] = { app = it.app, size = it.size, hidden = it.hidden and true or nil } end
        db.layout[page] = l
    end

    -- app data (R-D1)
    function S:data_get(app, key) return decode((db.app_data[app] or {})[key]) end
    function S:data_set(app, key, value)
        db.app_data[app] = db.app_data[app] or {}
        db.app_data[app][key] = encode(value)
    end
    function S:data_clear(app) db.app_data[app] = nil end

    -- app cache: last good data (ctx.cache)
    function S:cache_get(app)
        local c = db.app_cache[app]
        if not c then return nil end
        return decode(c.value), c.fetched_at, c.version
    end
    function S:cache_put(app, value, fetched_at, version)
        db.app_cache[app] = { value = encode(value), fetched_at = fetched_at, version = version }
    end
    function S:cache_clear(app) db.app_cache[app] = nil end

    -- app state (registry)
    function S:state_get(app) return copy(db.app_state[app]) end
    function S:state_set(app, st)
        db.app_state[app] = st and {
            last_ok = st.last_ok, last_err = st.last_err, err_text = st.err_text, fail_streak = st.fail_streak,
        } or nil
    end

    -- notifications (R-T3); route is a Lua table (stored as JSON)
    local function notif_out(n)
        local o = copy(n)
        o.route = decode(n.route)
        return o
    end
    function S:notif_find(app, key)
        for _, n in ipairs(db.notifications) do
            if n.app == app and n.key == key then return notif_out(n) end
        end
    end
    function S:notif_add(n)
        if self:notif_find(n.app, n.key) then return nil, "dup" end
        db.next_notif = db.next_notif + 1
        db.notifications[#db.notifications + 1] = {
            id = db.next_notif, app = n.app, key = n.key, type = n.type, title = n.title, body = n.body,
            prio = n.prio, route = encode(n.route), created_at = n.created_at, read_at = n.read_at,
        }
        return db.next_notif
    end
    function S:notif_get(id)
        for _, n in ipairs(db.notifications) do if n.id == id then return notif_out(n) end end
    end
    -- newest first; opts = { offset = 0, limit = nil, unread = bool }
    function S:notif_list(opts)
        opts = opts or {}
        local all = {}
        for _, n in ipairs(db.notifications) do
            if not opts.unread or n.read_at == nil then all[#all + 1] = n end
        end
        table.sort(all, newest_first)
        local out, offset = {}, opts.offset or 0
        for i = offset + 1, #all do
            if opts.limit and #out >= opts.limit then break end
            out[#out + 1] = notif_out(all[i])
        end
        return out
    end
    function S:notif_count()
        return #db.notifications
    end
    function S:notif_unread_count()
        local c = 0
        for _, n in ipairs(db.notifications) do if n.read_at == nil then c = c + 1 end end
        return c
    end
    function S:notif_mark_read(id, at)
        for _, n in ipairs(db.notifications) do
            if n.id == id then
                local changed = n.read_at == nil
                n.read_at = n.read_at or at
                return changed
            end
        end
        return false
    end
    function S:notif_mark_all_read(at)
        local c = 0
        for _, n in ipairs(db.notifications) do
            if n.read_at == nil then n.read_at = at; c = c + 1 end
        end
        return c
    end
    function S:notif_clear()
        local c = #db.notifications
        db.notifications = {}
        return c
    end
    -- 10.5 "Remover app": everything the store holds for one app (settings scope, data, cache, state, its
    -- notifications, the version and legacy-import marks). The layouts are the caller's (they hold ids, not data).
    function S:purge_app(app)
        db.settings[app], db.app_data[app], db.app_cache[app], db.app_state[app] = nil, nil, nil, nil
        db.meta["app_version:" .. app], db.meta["legacy_imported:" .. app] = nil, nil
        local keep = {}
        for _, n in ipairs(db.notifications) do if n.app ~= app then keep[#keep + 1] = n end end
        db.notifications = keep
        return true
    end
    -- R-T4: keep the `max` most recent; over it, the oldest read ones go first, then the oldest unread.
    function S:notif_trim(max)
        local excess = #db.notifications - max
        if excess <= 0 then return 0 end
        local order = {}
        for _, n in ipairs(db.notifications) do order[#order + 1] = n end
        table.sort(order, oldest_first)
        local drop = {}
        for pass = 1, 2 do
            for _, n in ipairs(order) do
                if excess <= 0 then break end
                local is_read = n.read_at ~= nil
                if not drop[n] and ((pass == 1 and is_read) or pass == 2) then drop[n] = true; excess = excess - 1 end
            end
        end
        local keep, removed = {}, 0
        for _, n in ipairs(db.notifications) do
            if drop[n] then removed = removed + 1 else keep[#keep + 1] = n end
        end
        db.notifications = keep
        return removed
    end

    -- log (spec 12: last 500)
    function S:log(at, app, level, msg)
        db.next_log = db.next_log + 1
        db.log[#db.log + 1] = { id = db.next_log, at = at, app = app, level = level, msg = msg }
        while #db.log > M.LOG_MAX do table.remove(db.log, 1) end
    end
    function S:log_list(opts)
        opts = opts or {}
        local out, offset = {}, opts.offset or 0
        for i = #db.log - offset, 1, -1 do
            if opts.limit and #out >= opts.limit then break end
            out[#out + 1] = copy(db.log[i])
        end
        return out
    end
    function S:log_count() return #db.log end

    -- R-B2: one transaction per refresh cycle. The memory backend has nothing to flush; it keeps the same
    -- contract: returns true, results... or false, err (never throws), nesting allowed.
    local depth = 0
    function S:transaction(fn, ...)
        depth = depth + 1
        local res = { pcall(fn, ...) }
        depth = depth - 1
        if not res[1] and depth > 0 then error(res[2], 0) end   -- nested: the outermost level reports it
        if not res[1] then return false, res[2] end
        return unpack(res, 1, table.maxn(res))
    end

    function S:stats()
        return { notifications = #db.notifications, log = #db.log, size_bytes = nil }
    end
    function S:close() end

    return S
end

---------------------------------------------------------------- SQLite backend

local function num(v)
    if type(v) == "cdata" then return tonumber(v) end
    return v
end

-- Loads the binding; nil, err when it is not there (tests, desktop).
function M.load_binding()
    local ok, SQ3 = pcall(require, "lua-ljsqlite3/init")
    if ok and type(SQ3) == "table" and SQ3.open then return SQ3 end
    return nil, ok and "lua-ljsqlite3: no open()" or tostring(SQ3)
end

-- Opens (or creates) the database, checks it and migrates. Throws on any problem; M.sqlite handles R-B4.
local function open_sqlite(path, opts, SQ3)
    local conn = SQ3.open(path)
    local ok, err = pcall(function()
        if conn.set_busy_timeout then conn:set_busy_timeout(2000) end
        local check = conn:rowexec("PRAGMA quick_check")
        if check ~= "ok" then error("quick_check: " .. tostring(check)) end
        conn:exec("PRAGMA synchronous = NORMAL")
        conn:exec("CREATE TABLE IF NOT EXISTS meta (key TEXT PRIMARY KEY, value TEXT)")
    end)
    if not ok then pcall(conn.close, conn); error(err, 0) end
    return conn
end

-- Parameter for the binding: whole numbers as int64 (the binding binds Lua numbers as REAL), booleans as 0/1.
local int64
local function param(v)
    if type(v) == "boolean" then v = v and 1 or 0 end
    if type(v) == "number" and v == math.floor(v) and math.abs(v) < 2^53 then
        int64 = int64 or require("ffi").typeof("int64_t")
        return int64(v)
    end
    return v
end

-- Runs one statement with positional parameters; returns the rows (arrays; NULL columns are nil) for SELECTs.
local function run(conn, sql, ...)
    local stmt = conn:prepare(sql)
    local n, args = select("#", ...), { ... }
    local ok, err = pcall(function()
        for i = 1, n do stmt:bind1(i, param(args[i])) end
    end)
    if not ok then stmt:close(); error(err, 0) end
    local rows = {}
    ok, err = pcall(function()
        local ncol = stmt:_ncol()
        while true do
            local r = stmt:step()
            if not r then break end
            local row = {}
            for i = 1, ncol do row[i] = num(r[i]) end
            rows[#rows + 1] = row
        end
    end)
    stmt:close()
    if not ok then error(err, 0) end
    return rows
end

-- R-B4: corrupt or unreadable database -> renamed to <path>.bad-<date>, a new one is created, the log says so.
-- If even a fresh database cannot be opened (or the binding is missing), returns a memory store so the Tinta
-- still opens with the default layout. Returns store, info = { recovered, bad_path, fallback, error }.
-- opts = { now = fn, sq3 = binding (injected in tests), rename = fn(from, to) (default os.rename),
--          remove = fn(path) (default os.remove), migrations = list }
function M.sqlite(path, opts)
    opts = opts or {}
    local now = opts.now or os.time
    local info = {}
    local SQ3, berr = opts.sq3, nil
    if not SQ3 then SQ3, berr = M.load_binding() end
    if not SQ3 then
        info.fallback, info.error = true, berr
        local mem = M.memory(opts)
        mem:log(now(), nil, "error", "store: sqlite binding unavailable, using memory: " .. tostring(berr))
        return mem, info
    end

    -- phase "open": cannot open, or the integrity check fails -> the file is bad (R-B4).
    -- phase "migrate": the file opened fine but a migration failed; that is a code problem, so the file is
    -- left alone (a later version can migrate it) and the Tinta runs on memory — unless SQLite itself
    -- reports corruption, which counts as a bad file.
    local function attempt()
        local okc, conn = pcall(open_sqlite, path, opts, SQ3)
        if not okc then return nil, "open", conn end
        local ok, store = pcall(M._wrap, conn, opts)
        if not ok then
            pcall(conn.close, conn)
            local msg = tostring(store)
            local corrupt = msg:find("malformed") or msg:find("not a database") or msg:find("corrupt")
            return nil, corrupt and "open" or "migrate", store
        end
        return store
    end
    local function first_line(e) return (tostring(e):match("^[^\n]*")) end

    local store, phase, err = attempt()
    if store then return store, info end
    info.error = first_line(err)

    local renamed, bad = false, nil
    if phase == "open" then
        bad = path .. ".bad-" .. os.date("%Y%m%d-%H%M%S", now())
        local rename = opts.rename or os.rename
        local remove = opts.remove or os.remove
        renamed = rename(path, bad) and true or false
        if renamed then
            info.recovered, info.bad_path = true, bad
            -- journal files belong to the bad database; a fresh database must not pick them up
            pcall(remove, path .. "-journal")
            pcall(remove, path .. "-wal")
            pcall(remove, path .. "-shm")
            local store2, _, err2 = attempt()
            if store2 then
                store2:log(now(), nil, "warn", "store: database unreadable (" .. info.error .. "), moved to " .. bad)
                return store2, info
            end
            info.error = first_line(err2)
        end
    end
    info.fallback = true
    local mem = M.memory(opts)
    mem:log(now(), nil, "error", "store: cannot open database (" .. info.error .. "), using memory"
        .. (renamed and (", bad file moved to " .. bad) or ""))
    return mem, info
end

-- Builds the store object over an open connection and migrates it. Internal (exposed for tests).
function M._wrap(conn, opts)
    opts = opts or {}
    local migrations = opts.migrations or M.MIGRATIONS
    local S = { kind = "sqlite", _conn = conn }
    local depth = 0

    local function q(sql, ...) return run(conn, sql, ...) end
    local function q1(sql, ...) return q(sql, ...)[1] end

    -- Read-through memory of single-key reads (settings, app data, meta). On the Kindle every query goes through
    -- /mnt/us (slow), and the core reads the same keys many times per screen (an app's in_window reads its
    -- settings for every minute the scheduler looks ahead). Values are kept encoded (each read decodes a fresh
    -- copy), writes go to SQLite and update the memory, and a rollback forgets it all.
    local mem
    local function mem_reset() mem = { settings = {}, data = {}, meta = {} } end
    mem_reset()
    local function mem_get(kind, a, b, load)
        local t = mem[kind][a]
        if not t then t = {}; mem[kind][a] = t end
        local v = t[b]
        if v == nil then v = load() or false; t[b] = v end
        return v or nil
    end
    local function mem_put(kind, a, b, raw)
        local t = mem[kind][a]
        if not t then t = {}; mem[kind][a] = t end
        t[b] = raw or false
    end

    function S:meta_get(k)
        return mem_get("meta", "", k, function()
            local r = q1("SELECT value FROM meta WHERE key = ?", k)
            return r and r[1] or nil
        end)
    end
    function S:meta_set(k, v)
        if v == nil then q("DELETE FROM meta WHERE key = ?", k)
        else q("INSERT OR REPLACE INTO meta (key, value) VALUES (?, ?)", k, tostring(v)) end
        mem_put("meta", "", k, v ~= nil and tostring(v) or nil)
    end
    function S:schema_version() return tonumber(self:meta_get("schema_version")) or 0 end

    function S:transaction(fn, ...)
        if depth > 0 then
            depth = depth + 1
            local res = { pcall(fn, ...) }
            depth = depth - 1
            if not res[1] then error(res[2], 0) end   -- the outermost level rolls back
            return unpack(res, 1, table.maxn(res))
        end
        conn:exec("BEGIN")
        depth = 1
        local res = { pcall(fn, ...) }
        depth = 0
        if res[1] then
            local ok, err = pcall(conn.exec, conn, "COMMIT")
            if ok then return unpack(res, 1, table.maxn(res)) end
            pcall(conn.exec, conn, "ROLLBACK")
            mem_reset()
            return false, err
        end
        pcall(conn.exec, conn, "ROLLBACK")
        mem_reset()
        return false, res[2]
    end

    -- R-B3
    function S.migrate(more)
        if more then migrations = more end
        local cur = S:schema_version()
        for _, m in ipairs(M.pending(cur, migrations)) do
            local ok, err = S:transaction(function()
                if m.sql then conn:exec(m.sql) end
                if m.lua then m.lua(conn) end
                S:meta_set("schema_version", m.version)
            end)
            if not ok then error("migration " .. m.version .. ": " .. tostring(err), 0) end
        end
        mem_reset()   -- migrations write through raw SQL
        if not S:meta_get("created_at") then S:meta_set("created_at", (opts.now or os.time)()) end
    end

    function S:get(scope, key)
        return decode(mem_get("settings", scope, key, function()
            local r = q1("SELECT value FROM settings WHERE scope = ? AND key = ?", scope, key)
            return r and r[1] or nil
        end))
    end
    function S:set(scope, key, value)
        if value == nil then q("DELETE FROM settings WHERE scope = ? AND key = ?", scope, key); mem_put("settings", scope, key, nil)
        else
            local raw = encode(value)
            q("INSERT OR REPLACE INTO settings (scope, key, value) VALUES (?, ?, ?)", scope, key, raw)
            mem_put("settings", scope, key, raw)
        end
    end
    function S:all(scope)
        local out = {}
        for _, r in ipairs(q("SELECT key, value FROM settings WHERE scope = ?", scope)) do out[r[1]] = decode(r[2]) end
        return out
    end

    function S:layout_get(page)
        local rows = q("SELECT app, size, hidden FROM layout WHERE page = ? ORDER BY pos", page)
        if #rows == 0 then
            -- an empty saved layout is remembered in meta so it is not mistaken for "never saved"
            if self:meta_get("layout_empty:" .. page) then return {} end
            return nil
        end
        local out = {}
        for i, r in ipairs(rows) do out[i] = { app = r[1], size = r[2], hidden = (r[3] == 1) or nil } end
        return out
    end
    function S:layout_set(page, list)
        self:transaction(function()
            q("DELETE FROM layout WHERE page = ?", page)
            for i, it in ipairs(list or {}) do
                q("INSERT INTO layout (page, pos, app, size, hidden) VALUES (?, ?, ?, ?, ?)",
                    page, i, it.app, it.size, it.hidden and 1 or 0)
            end
            self:meta_set("layout_empty:" .. page, (#(list or {}) == 0) and 1 or nil)
        end)
    end

    function S:data_get(app, key)
        return decode(mem_get("data", app, key, function()
            local r = q1("SELECT value FROM app_data WHERE app = ? AND key = ?", app, key)
            return r and r[1] or nil
        end))
    end
    function S:data_set(app, key, value)
        if value == nil then q("DELETE FROM app_data WHERE app = ? AND key = ?", app, key); mem_put("data", app, key, nil)
        else
            local raw = encode(value)
            q("INSERT OR REPLACE INTO app_data (app, key, value) VALUES (?, ?, ?)", app, key, raw)
            mem_put("data", app, key, raw)
        end
    end
    function S:data_clear(app) q("DELETE FROM app_data WHERE app = ?", app); mem.data[app] = nil end

    function S:cache_get(app)
        local r = q1("SELECT value, fetched_at, version FROM app_cache WHERE app = ?", app)
        if not r then return nil end
        return decode(r[1]), r[2], r[3]
    end
    function S:cache_put(app, value, fetched_at, version)
        q("INSERT OR REPLACE INTO app_cache (app, value, fetched_at, version) VALUES (?, ?, ?, ?)",
            app, encode(value), fetched_at, version)
    end
    function S:cache_clear(app) q("DELETE FROM app_cache WHERE app = ?", app) end

    function S:state_get(app)
        local r = q1("SELECT last_ok, last_err, err_text, fail_streak FROM app_state WHERE app = ?", app)
        if not r then return nil end
        return { last_ok = r[1], last_err = r[2], err_text = r[3], fail_streak = r[4] }
    end
    function S:state_set(app, st)
        if not st then q("DELETE FROM app_state WHERE app = ?", app); return end
        q("INSERT OR REPLACE INTO app_state (app, last_ok, last_err, err_text, fail_streak) VALUES (?, ?, ?, ?, ?)",
            app, st.last_ok, st.last_err, st.err_text, st.fail_streak)
    end

    local NCOLS = "id, app, key, type, title, body, prio, route, created_at, read_at"
    local function notif_row(r)
        return { id = r[1], app = r[2], key = r[3], type = r[4], title = r[5], body = r[6], prio = r[7],
                 route = decode(r[8]), created_at = r[9], read_at = r[10] }
    end
    function S:notif_find(app, key)
        local r = q1("SELECT " .. NCOLS .. " FROM notifications WHERE app = ? AND key = ?", app, key)
        return r and notif_row(r) or nil
    end
    function S:notif_add(n)
        if self:notif_find(n.app, n.key) then return nil, "dup" end
        q("INSERT INTO notifications (app, key, type, title, body, prio, route, created_at, read_at)"
            .. " VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
            n.app, n.key, n.type, n.title, n.body, n.prio, encode(n.route), n.created_at, n.read_at)
        return num(q1("SELECT last_insert_rowid()")[1])
    end
    function S:notif_get(id)
        local r = q1("SELECT " .. NCOLS .. " FROM notifications WHERE id = ?", id)
        return r and notif_row(r) or nil
    end
    function S:notif_list(opts)
        opts = opts or {}
        local sql = "SELECT " .. NCOLS .. " FROM notifications"
            .. (opts.unread and " WHERE read_at IS NULL" or "")
            .. " ORDER BY created_at DESC, id DESC LIMIT ? OFFSET ?"
        local out = {}
        for i, r in ipairs(q(sql, opts.limit or -1, opts.offset or 0)) do out[i] = notif_row(r) end
        return out
    end
    function S:notif_count() return q1("SELECT COUNT(*) FROM notifications")[1] end
    function S:notif_unread_count() return q1("SELECT COUNT(*) FROM notifications WHERE read_at IS NULL")[1] end
    function S:notif_mark_read(id, at)
        local before = self:notif_get(id)
        if not before or before.read_at then return false end
        q("UPDATE notifications SET read_at = ? WHERE id = ?", at, id)
        return true
    end
    function S:notif_mark_all_read(at)
        local c = self:notif_unread_count()
        q("UPDATE notifications SET read_at = ? WHERE read_at IS NULL", at)
        return c
    end
    function S:notif_clear()
        local c = self:notif_count()
        q("DELETE FROM notifications")
        return c
    end
    function S:purge_app(app)
        return self:transaction(function()
            q("DELETE FROM settings WHERE scope = ?", app)
            q("DELETE FROM app_data WHERE app = ?", app)
            q("DELETE FROM app_cache WHERE app = ?", app)
            q("DELETE FROM app_state WHERE app = ?", app)
            q("DELETE FROM notifications WHERE app = ?", app)
            self:meta_set("app_version:" .. app, nil)
            self:meta_set("legacy_imported:" .. app, nil)
            mem.settings[app], mem.data[app] = nil, nil
        end)
    end
    function S:notif_trim(max)
        local excess = self:notif_count() - max
        if excess <= 0 then return 0 end
        local removed = 0
        for _, where in ipairs({ "read_at IS NOT NULL", "1 = 1" }) do
            if excess > 0 then
                local rows = q("SELECT id FROM notifications WHERE " .. where
                    .. " ORDER BY created_at ASC, id ASC LIMIT ?", excess)
                for _, r in ipairs(rows) do q("DELETE FROM notifications WHERE id = ?", r[1]) end
                excess, removed = excess - #rows, removed + #rows
            end
        end
        return removed
    end

    function S:log(at, app, level, msg)
        q("INSERT INTO log (at, app, level, msg) VALUES (?, ?, ?, ?)", at, app, level, msg)
        q("DELETE FROM log WHERE id <= (SELECT id FROM log ORDER BY id DESC LIMIT 1 OFFSET ?)", M.LOG_MAX)
    end
    function S:log_list(opts)
        opts = opts or {}
        local out = {}
        for i, r in ipairs(q("SELECT id, at, app, level, msg FROM log ORDER BY id DESC LIMIT ? OFFSET ?",
                opts.limit or -1, opts.offset or 0)) do
            out[i] = { id = r[1], at = r[2], app = r[3], level = r[4], msg = r[5] }
        end
        return out
    end
    function S:log_count() return q1("SELECT COUNT(*) FROM log")[1] end

    function S:stats()
        local pc = q1("PRAGMA page_count")
        local ps = q1("PRAGMA page_size")
        return {
            notifications = self:notif_count(), log = self:log_count(),
            size_bytes = (pc and ps) and pc[1] * ps[1] or nil,
        }
    end
    function S:close()
        if conn and not conn._closed then conn:close() end
    end

    S.migrate()
    return S
end

-- Convenience used by main.lua: SQLite at `path` with every fallback of M.sqlite.
M.open = M.sqlite
M.roundtrip = roundtrip

return M
