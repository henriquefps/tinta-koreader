-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (C) 2026 Tinta contributors
-- Removing an app's folder (10.5 "Remover app"), pure Lua (R-A1): the file system is injected, so the guard rules
-- are testable and the device side only supplies lfs. Nothing outside <apps dir>/<id>/ is ever touched.
--   fs = { dir = fn(path) -> iterator of names, link = fn(path) -> bool (symbolic link),
--          is_dir = fn(path) -> bool, remove = fn(path) -> ok, err (file or link), rmdir = fn(path) -> ok, err }
local M = {}

M.MAX_DEPTH = 12

-- ids that are an app folder name (the same rule as the registry's manifest id)
function M.valid_id(id) return type(id) == "string" and id:match("^[a-z0-9_]+$") ~= nil end

-- the folder of an app: apps_dir .. "/" .. id; nil, reason for a bad id or dir
function M.path_of(apps_dir, id)
    if type(apps_dir) ~= "string" or apps_dir == "" then return nil, "no apps dir" end
    if not M.valid_id(id) then return nil, "bad id" end
    return (apps_dir:gsub("/+$", "")) .. "/" .. id
end

local function wipe(fs, path, depth, count)
    if depth > M.MAX_DEPTH then return false, "too deep: " .. path end
    -- list first: removing entries while the iterator is open is undefined on some file systems
    local names = {}
    for name in fs.dir(path) do
        if name ~= "." and name ~= ".." then names[#names + 1] = name end
    end
    for _, name in ipairs(names) do
        if name:find("/", 1, true) or name:find("\\", 1, true) then return false, "bad entry name" end
        local child = path .. "/" .. name
        -- a symbolic link is unlinked, never followed
        if not fs.link(child) and fs.is_dir(child) then
            local ok, err = wipe(fs, child, depth + 1, count)
            if not ok then return false, err end
            local rok, rerr = fs.rmdir(child)
            if not rok then return false, tostring(rerr) end
        else
            local ok, err = fs.remove(child)
            if not ok then return false, tostring(err) end
        end
        count.n = count.n + 1
    end
    return true
end

-- Deletes apps_dir/<id>/ with everything in it. Returns true, entries_removed | nil, reason.
-- Refused: a bad id (anything but [a-z0-9_]+, so "../x" and "a/b" never get here), a missing folder, a folder
-- that is a symbolic link.
function M.remove(fs, apps_dir, id)
    local path, why = M.path_of(apps_dir, id)
    if not path then return nil, why end
    if fs.link(path) then return nil, "is a link" end
    if not fs.is_dir(path) then return nil, "not a folder" end
    local count = { n = 0 }
    local ok, wok, werr = pcall(wipe, fs, path, 1, count)
    if not ok then return nil, tostring(wok) end
    if not wok then return nil, tostring(werr) end
    local rok, rerr = fs.rmdir(path)
    if not rok then return nil, tostring(rerr) end
    return true, count.n
end

return M
