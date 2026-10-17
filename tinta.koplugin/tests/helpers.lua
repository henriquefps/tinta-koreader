-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (C) 2026 Tinta contributors
-- Shared test helpers: check/eq/same (deep), a UTC clock and date function, a fake clock.
local T = { passed = 0, failed = 0, skipped = 0, quiet = os.getenv("QUIET") ~= nil }

function T.section(name)
    if not T.quiet then print("\n== " .. name) end
end

function T.check(name, cond, extra)
    if cond then
        T.passed = T.passed + 1
        if not T.quiet then print("ok   - " .. name) end
    else
        T.failed = T.failed + 1
        print("FAIL - " .. name .. (extra ~= nil and (" :: " .. tostring(extra)) or ""))
    end
end

function T.skip(name, why)
    T.skipped = T.skipped + 1
    print("skip - " .. name .. (why and (" :: " .. why) or ""))
end

function T.eq(name, got, want)
    T.check(name, got == want, "got " .. tostring(got) .. ", want " .. tostring(want))
end

local function dump(v, depth)
    depth = depth or 0
    if type(v) ~= "table" then return type(v) == "string" and string.format("%q", v) or tostring(v) end
    if depth > 5 then return "{…}" end
    local keys = {}
    for k in pairs(v) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    local parts = {}
    for _, k in ipairs(keys) do parts[#parts + 1] = tostring(k) .. "=" .. dump(v[k], depth + 1) end
    return "{" .. table.concat(parts, ",") .. "}"
end
T.dump = dump

local function deep_eq(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end
    for k, v in pairs(a) do if not deep_eq(v, b[k]) then return false end end
    for k in pairs(b) do if a[k] == nil then return false end end
    return true
end
T.deep_eq = deep_eq

function T.same(name, got, want)
    T.check(name, deep_eq(got, want), "got " .. dump(got) .. ", want " .. dump(want))
end

-- Days from civil (proleptic Gregorian), so tests do not depend on the machine's time zone.
function T.utc(y, m, d, hh, mm, ss)
    y = (m <= 2) and (y - 1) or y
    local era = math.floor(y / 400)
    local yoe = y - era * 400
    local mp = (m + 9) % 12
    local doy = math.floor((153 * mp + 2) / 5) + d - 1
    local doe = yoe * 365 + math.floor(yoe / 4) - math.floor(yoe / 100) + doy
    local days = era * 146097 + doe - 719468
    return days * 86400 + (hh or 0) * 3600 + (mm or 0) * 60 + (ss or 0)
end

-- os.date that reads timestamps as UTC.
function T.date(fmt, t)
    fmt = fmt or "%c"
    if fmt:sub(1, 1) ~= "!" then fmt = "!" .. fmt end
    return os.date(fmt, t)
end

-- Fake clock: c() returns the time; c.set(t), c.add(s).
function T.clock(t0)
    local t = t0 or 0
    local c = setmetatable({}, { __call = function() return t end })
    function c.set(v) t = v end
    function c.add(s) t = t + s end
    return c
end

-- Log collector: log(level, app, msg); .lines, .find(pattern)
function T.logger()
    local L = { lines = {} }
    L.fn = function(level, app, msg) L.lines[#L.lines + 1] = { level = level, app = app, msg = msg } end
    function L.find(pat)
        for _, l in ipairs(L.lines) do if tostring(l.msg):find(pat) then return l end end
    end
    return L
end

return T
