-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (C) 2026 Tinta contributors
-- Sistema → Dados → "Backup das configurações" / "Restaurar backup": the JSON file, its validation and how it is
-- applied (pure, R-A1; reading and writing files is ui/host's). A backup holds the layouts (home, sleep), the
-- Tinta settings and the settings of each app. It never holds secrets (tokens, passwords, URLs with
-- credentials), app data, caches or notifications (spec 14). Restoring goes through the validated setters of
-- core/settings: unknown keys are ignored, invalid values skipped, current tokens stay.
local Json = require("core/json")

local M = {}

M.FORMAT = "tinta-backup"
M.LEGACY_FORMAT = "portal-backup"   -- backups made before the rename (Portal): still valid, their `portal` table is the settings
M.FORMAT_VERSION = 1
M.MAX_BYTES = 512 * 1024        -- a bigger file is not read
M.PAGES = { "home", "sleep" }

-- koreader/tinta-backup-YYYYMMDD-HHMM.json (`t` is a unix time)
function M.filename(t)
    return os.date("tinta-backup-%Y%m%d-%H%M.json", t)
end

-- names that are backups (also the old portal-backup-*), newest first. Name order is date order within a prefix
-- only, so sort by the date part (the name without its prefix).
function M.list_names(names)
    local out = {}
    for _, n in ipairs(names or {}) do
        if type(n) == "string" and (n:match("^tinta%-backup%-[%w%-]+%.json$") or n:match("^portal%-backup%-[%w%-]+%.json$")) then
            out[#out + 1] = n
        end
    end
    local function key(n) return n:gsub("^%a+%-backup%-", "") end
    table.sort(out, function(a, b)
        local ka, kb = key(a), key(b)
        if ka ~= kb then return ka > kb end
        return a > b
    end)
    return out
end

-- "20260105-1432" of a backup name -> "05/01/2026 14:32"; the name itself when it has no such date
function M.label(name)
    local y, mo, d, h, mi = tostring(name):match("^tinta%-backup%-(%d%d%d%d)(%d%d)(%d%d)%-(%d%d)(%d%d)%.json$")
    if not y then return tostring(name) end
    return ("%s/%s/%s %s:%s"):format(d, mo, y, h, mi)
end

-- env = { settings = Settings object, apps = { { id, version } }, layout_get = fn(page), now = unix time,
--         tinta_version, api_version }
function M.build(env)
    local out = {
        format = M.FORMAT, format_version = M.FORMAT_VERSION,
        created = env.now and os.date("%Y-%m-%d %H:%M:%S", env.now) or nil,
        tinta_version = env.tinta_version, api_version = env.api_version,
        layouts = {}, tinta = env.settings:export_scope("portal"), apps = {},
    }
    for _, page in ipairs(M.PAGES) do
        local l = env.layout_get(page)
        if type(l) == "table" then
            local items = {}
            for i, it in ipairs(l) do items[i] = { app = it.app, size = it.size, hidden = it.hidden and true or nil } end
            out.layouts[page] = items
        end
    end
    for _, a in ipairs(env.apps or {}) do
        out.apps[a.id] = { version = tonumber(a.version) or 1, settings = env.settings:export_scope(a.id) }
    end
    return out
end

function M.encode(t) return Json.encode(t) end

-- text of a file -> table, or nil, "format" (not JSON / not a backup) | "newer" (made by a newer Tinta)
function M.decode(text)
    if type(text) ~= "string" or #text > M.MAX_BYTES then return nil, "format" end
    local ok, t = pcall(Json.decode, text)
    if not ok or type(t) ~= "table" then return nil, "format" end
    local ok2, err = M.validate(t)
    if not ok2 then return nil, err end
    if t.tinta == nil and t.portal ~= nil then t.tinta = t.portal end   -- old backup: same content, old key
    return t
end

-- Shape and versions. true | nil, "format" | "newer"
function M.validate(t)
    if type(t) ~= "table" or (t.format ~= M.FORMAT and t.format ~= M.LEGACY_FORMAT) then
        return nil, "format"
    end
    local v = t.format_version
    if type(v) ~= "number" or v < 1 or v ~= math.floor(v) then return nil, "format" end
    if v > M.FORMAT_VERSION then return nil, "newer" end
    if t.tinta ~= nil and type(t.tinta) ~= "table" then return nil, "format" end
    if t.portal ~= nil and type(t.portal) ~= "table" then return nil, "format" end
    if t.layouts ~= nil and type(t.layouts) ~= "table" then return nil, "format" end
    if t.apps ~= nil then
        if type(t.apps) ~= "table" then return nil, "format" end
        for _, a in pairs(t.apps) do
            if type(a) ~= "table" or (a.settings ~= nil and type(a.settings) ~= "table")
                or (a.version ~= nil and type(a.version) ~= "number") then return nil, "format" end
        end
    end
    return true
end

-- layout items that are valid (app id, a size the grid knows, hidden boolean), without repeats
local function clean_layout(list, valid_size)
    local out, seen, skipped = {}, {}, 0
    for _, it in ipairs(list) do
        if type(it) == "table" and type(it.app) == "string" and it.app ~= "" and not seen[it.app]
            and valid_size(it.size) and (it.hidden == nil or type(it.hidden) == "boolean") then
            seen[it.app] = true
            out[#out + 1] = { app = it.app, size = it.size, hidden = it.hidden and true or nil }
        else
            skipped = skipped + 1
        end
    end
    return out, skipped
end

-- env = { settings, apps = { { id, version } } (the installed ones), layout_set = fn(page, list), valid_size = fn }
-- Returns { applied, skipped, ignored, layouts = pages applied, apps_newer = apps left out because the
-- backup is from a newer version of the app }.
function M.apply(t, env)
    local r = { applied = 0, skipped = 0, ignored = 0, layouts = 0, apps_newer = 0 }
    local function add(c) r.applied, r.skipped, r.ignored = r.applied + c.applied, r.skipped + c.skipped, r.ignored + c.ignored end
    for _, page in ipairs(M.PAGES) do
        local l = (t.layouts or {})[page]
        if type(l) == "table" then
            local items, bad = clean_layout(l, env.valid_size)
            r.skipped = r.skipped + bad
            if #items > 0 or #l == 0 then env.layout_set(page, items); r.layouts = r.layouts + 1 end
        elseif l ~= nil then r.skipped = r.skipped + 1 end
    end
    if t.tinta then add(env.settings:import_scope("portal", t.tinta)) end
    local installed = {}
    for _, a in ipairs(env.apps or {}) do installed[a.id] = tonumber(a.version) or 1 end
    local ids = {}
    for id in pairs(t.apps or {}) do ids[#ids + 1] = id end
    table.sort(ids, function(a, b) return tostring(a) < tostring(b) end)
    for _, id in ipairs(ids) do
        local a = t.apps[id]
        local have = installed[id]
        if not have or type(id) ~= "string" then
            for _ in pairs(a.settings or {}) do r.ignored = r.ignored + 1 end
        elseif (tonumber(a.version) or 1) > have then
            r.apps_newer = r.apps_newer + 1
            for _ in pairs(a.settings or {}) do r.skipped = r.skipped + 1 end
        elseif a.settings then
            add(env.settings:import_scope(id, a.settings))
        end
    end
    return r
end

return M
