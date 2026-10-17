-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (C) 2026 Tinta contributors
-- Sistema app tests (plain Lua, no KOReader): diagnostic export and settings backup. Run from the repo root:
--   luajit tinta.koplugin/apps/sistema/tests/run.lua            (all suites)
--   luajit tinta.koplugin/apps/sistema/tests/run.lua diag       (only the named suites)
-- QUIET=1 prints only failures and the total. Suites are tests/test_<name>.lua and get the helpers table T.
local here = (arg and arg[0] or ""):match("^(.*)/[^/]*$") or "."
local plugin = here .. "/../../.."
package.path = plugin .. "/?.lua;" .. here .. "/?.lua;" .. package.path

local quiet = os.getenv("QUIET") == "1"
local T = { passed = 0, failed = 0, here = here, plugin = plugin }
function T.check(name, cond, extra)
    if cond then
        T.passed = T.passed + 1
        if not quiet then print("ok   - " .. name) end
    else
        T.failed = T.failed + 1
        print("FAIL - " .. name .. (extra ~= nil and (" :: " .. tostring(extra)) or ""))
    end
end
function T.eq(name, got, want) T.check(name, got == want, "got " .. tostring(got) .. ", want " .. tostring(want)) end

local SUITES = { "diag", "backup", "syntax" }
local only = {}
for i = 1, #(arg or {}) do only[arg[i]] = true end
for _, name in ipairs(SUITES) do
    if next(only) == nil or only[name] then
        if not quiet then print("\n# " .. name) end
        local fn = assert(loadfile(here .. "/test_" .. name .. ".lua"))
        local ok, err = xpcall(function() fn(T) end, debug.traceback)
        if not ok then T.check(name .. ": suite crashed", false, err) end
    end
end
print(string.format("\nsistema: %d passed, %d failed", T.passed, T.failed))
os.exit(T.failed == 0 and 0 or 1)
