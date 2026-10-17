-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (C) 2026 Tinta contributors
-- Relógio app tests (plain Lua, no KOReader). Run from the repo root:
--   luajit tinta.koplugin/apps/relogio/tests/run.lua            (all suites)
--   luajit tinta.koplugin/apps/relogio/tests/run.lua style      (only the named suites)
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
function T.near(name, got, want, tol) T.check(name, got ~= nil and math.abs(got - want) <= tol, "got " .. tostring(got) .. ", want " .. tostring(want) .. " ± " .. tostring(tol)) end
-- UTC os.date, so times in the tests do not depend on the machine's time zone
function T.utc(fmt, t) if fmt:sub(1, 1) == "!" then return os.date(fmt, t) end; return os.date("!" .. fmt, t) end
-- UTC timestamp of a calendar date (no os.time: it reads the machine's time zone)
function T.ts(y, m, d, hh, mm)
    y = m <= 2 and y - 1 or y
    local era = math.floor(y / 400)
    local yoe = y - era * 400
    local doy = math.floor((153 * (m + (m > 2 and -3 or 9)) + 2) / 5) + d - 1
    local doe = yoe * 365 + math.floor(yoe / 4) - math.floor(yoe / 100) + doy
    return ((era * 146097 + doe - 719468) * 86400) + (hh or 0) * 3600 + (mm or 0) * 60
end
-- a translator over the app's strings (pt), like ctx.i18n.t
local Strings = require("apps/relogio/strings")
-- T.LL(lang) is the translator of that language
function T.LL(lang)
    return function(key, ...)
        local s = Strings[lang][key] or key
        if select("#", ...) > 0 then return string.format(s, ...) end
        return (s:gsub("%%%%", "%%"))
    end
end
T.L = T.LL("pt")

local SUITES = { "logic", "face", "strings", "view", "syntax" }
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
print(string.format("\nrelogio: %d passed, %d failed", T.passed, T.failed))
os.exit(T.failed == 0 and 0 or 1)
