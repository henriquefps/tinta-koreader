-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (C) 2026 Tinta contributors
-- Apps outside the plugin folder: <KOReader data dir>/tinta-apps/<id>/init.lua. They survive an update of
-- tinta.koplugin (a deploy replaces the whole folder). An app is written the same either way and asks for its
-- own files with require of apps/<id>/logic; for the bundled ones package.path finds them under the plugin
-- folder, for the external ones this module adds a searcher that maps apps/<id>/<x> to <dir>/<id>/<x>.lua.
-- Only the file system calls `loadfile` and `fs.exists` are used, so the tests run it on a temp folder.
local M = {}

M.DIRNAME = "tinta-apps"

-- <data dir>/tinta-apps, or nil without a data dir
function M.dir_of(data_dir)
    if type(data_dir) ~= "string" or data_dir == "" then return nil end
    return (data_dir:gsub("/+$", "")) .. "/" .. M.DIRNAME
end

local function exists(p) local f = io.open(p, "rb"); if f then f:close(); return true end; return false end

-- module name -> id, rest ("apps/alfa/logic" -> "alfa", "logic"); nil when the name is not an app file or the
-- path could leave the app folder
function M.split(name)
    if type(name) ~= "string" then return nil end
    local id, rest = name:match("^apps/([a-z0-9_]+)/(.+)$")
    if not id or rest:find("..", 1, true) or rest:find("//", 1, true) or rest:sub(1, 1) == "/" then return nil end
    if not rest:match("^[%w_%-%./]+$") then return nil end
    return id, rest
end

-- state shared by the one installed searcher: reopening the plugin points it at the new folder and ids
local state = { dir = nil, ids = {} }

-- The searcher: a loader for apps/<id>/<rest> when <id> is a registered external app. Appended to package.loaders
-- after the default path searcher, so a bundled app is always found first (and an external one with a bundled id
-- is refused by the host before it gets here).
function M.searcher(name)
    local id, rest = M.split(name)
    if not id or not state.dir or not state.ids[id] then
        return "\n\tno external app file for '" .. tostring(name) .. "'"
    end
    local path = state.dir .. "/" .. id .. "/" .. rest .. ".lua"
    if not exists(path) then return "\n\tno file '" .. path .. "'" end
    local chunk, err = loadfile(path)
    if not chunk then error("error loading module '" .. name .. "' from file '" .. path .. "':\n\t" .. tostring(err), 0) end
    return chunk, path
end

local function loaders() return package.loaders or package.searchers end

-- Makes a require of apps/<id>/... resolve in <dir>/<id>/ for each id in `ids` (a list). Idempotent.
function M.install(dir, ids)
    state.dir = dir
    state.ids = {}
    for _, id in ipairs(ids or {}) do state.ids[id] = true end
    local l = loaders()
    for _, f in ipairs(l) do if f == M.searcher then return end end
    l[#l + 1] = M.searcher
end

-- tests, and Host:close
function M.uninstall()
    state.dir, state.ids = nil, {}
    local l = loaders()
    for i = #l, 1, -1 do if l[i] == M.searcher then table.remove(l, i) end end
end

-- ids of the folders in `dir` that hold an init.lua, sorted. `fs` = { dir = fn(path) -> iterator, is_file = fn(path) }
-- (the device passes lfs; nil dir or an unreadable one gives an empty list)
function M.scan(dir, fs)
    local out = {}
    if not dir then return out end
    local ok = pcall(function()
        for name in fs.dir(dir) do
            if name:match("^[a-z0-9_]+$") and fs.is_file(dir .. "/" .. name .. "/init.lua") then out[#out + 1] = name end
        end
    end)
    table.sort(out)
    return out, ok
end

return M
