-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (C) 2026 Tinta contributors
-- One-time move from the Portal names (the platform was called Portal before it was named Tinta) and the guard
-- against both plugins running at once. Pure: the file system is injected (fs.exists(path), fs.rename(from, to)),
-- so the tests run it on a fake one (R-A1).
local M = {}

-- old name -> new name, in koreader/. The database goes with its SQLite side files (they only exist after a crash).
M.FILES = {
    { "portal.sqlite3", "tinta.sqlite3" },
    { "portal.sqlite3-journal", "tinta.sqlite3-journal" },
    { "portal.sqlite3-wal", "tinta.sqlite3-wal" },
    { "portal.sqlite3-shm", "tinta.sqlite3-shm" },
    { "portal-battery.csv", "tinta-battery.csv" },
    { "portal-power.log", "tinta-power.log" },
}

local function default_fs()
    return {
        exists = function(p) local f = io.open(p, "rb"); if f then f:close(); return true end; return false end,
        rename = os.rename,
    }
end

-- Renames every old file that exists to its new name, but never over a file that already exists. The database
-- side files only move when the database itself moves. Returns the list of "old -> new" moves made and the list of
-- errors (a failed rename leaves the old file where it was, so the next open tries again).
function M.run(dir, fs)
    local moved, errors = {}, {}
    if type(dir) ~= "string" or dir == "" then return moved, errors end
    fs = fs or default_fs()
    local db_moved = false
    for i, pair in ipairs(M.FILES) do
        local old, new = dir .. "/" .. pair[1], dir .. "/" .. pair[2]
        local side = i > 1 and i <= 4
        if (not side or db_moved) and fs.exists(old) and not fs.exists(new) then
            local ok, err = fs.rename(old, new)
            if ok then
                moved[#moved + 1] = pair[1] .. " -> " .. pair[2]
                if i == 1 then db_moved = true end
            else
                errors[#errors + 1] = pair[1] .. ": " .. tostring(err)
            end
        end
    end
    return moved, errors
end

-- true when the old plugin folder sits next to this one (plugins/portal.koplugin next to plugins/tinta.koplugin).
-- Then Tinta does not register: two copies of the platform would fight for the same files, the same wake-ups
-- and the same screen. Delete plugins/portal.koplugin, restart KOReader, and Tinta registers.
function M.legacy_plugin_present(plugin_dir, fs)
    if type(plugin_dir) ~= "string" then return false end
    local parent = plugin_dir:match("^(.*)/[^/]+/?$")
    if not parent then return false end
    fs = fs or default_fs()
    return fs.exists(parent .. "/portal.koplugin/main.lua")
end

return M
