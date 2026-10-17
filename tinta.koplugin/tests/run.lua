-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (C) 2026 Tinta contributors
-- Plain-Lua test runner for the Tinta core (no frameworks, no KOReader). Run from the repo root:
--   luajit tinta.koplugin/tests/run.lua           (all suites)
--   luajit tinta.koplugin/tests/run.lua layout    (only the named suites)
-- Each suite is tests/test_<name>.lua and gets the shared helpers (T.check, T.eq, T.utc, ...).
local here = (arg and arg[0] or ""):match("^(.*)/[^/]*$") or "."
package.path = here .. "/../?.lua;" .. here .. "/?.lua;" .. package.path

local T = require("helpers")
T.here = here

local SUITES = { "json", "i18n", "format", "layout", "scheduler", "registry", "store", "store_sqlite",
                 "settings", "firstrun", "notify", "power", "apps_manage", "sleep", "backends", "sleep_driven", "wakereq", "migrate", "extapps", "syntax" }

local only = {}
for i = 1, #(arg or {}) do only[arg[i]] = true end

for _, name in ipairs(SUITES) do
    if next(only) == nil or only[name] then
        T.section(name)
        local fn = assert(loadfile(here .. "/test_" .. name .. ".lua"))
        local ok, err = xpcall(function() fn(T) end, debug.traceback)
        if not ok then T.check(name .. ": suite crashed", false, err) end
    end
end

print(string.format("\n%d passed, %d failed, %d skipped", T.passed, T.failed, T.skipped))
os.exit(T.failed == 0 and 0 or 1)
