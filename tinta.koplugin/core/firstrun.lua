-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (C) 2026 Tinta contributors
-- First run (spec 7.5): is this a fresh install that should see the welcome wizard? Pure Lua (R-A1).
-- The rule is conservative: anything that shows the Tinta was used before counts as "done", so an existing install
-- (the user's KT3) never sees the wizard. Evaluated once per open, BEFORE the apps are registered (registering writes
-- the "app_version:" marks that this rule reads).
local Settings = require("core/settings")

local M = {}

M.DONE = "first_run_done"          -- meta: the wizard finished or was skipped (value: when)
M.PENDING = "first_run_pending"    -- meta: a fresh install was detected; the wizard shows until DONE (or a layout is saved)

-- Tinta settings that a fresh store already holds (core/settings migrate writes them on creation).
local SEEDED = { idle_mode = true }

-- store: core/store; ids: the app folders found on disk (their meta marks are checked).
function M.needed(store, ids)
    if store:meta_get(M.DONE) then return false end
    if store:layout_get("home") or store:layout_get("sleep") then return false end
    if store:meta_get(M.PENDING) then return true end
    for k in pairs(store:all(Settings.TINTA) or {}) do
        if not SEEDED[k] then return false end
    end
    for _, id in ipairs(ids or {}) do
        if store:meta_get("app_version:" .. id) or store:meta_get("legacy_imported:" .. id) then return false end
    end
    return true
end

function M.mark_pending(store) store:meta_set(M.PENDING, "1") end
function M.mark_done(store, at) store:meta_set(M.DONE, at or "1"); store:meta_set(M.PENDING, nil) end

return M
