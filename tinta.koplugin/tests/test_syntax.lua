-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (C) 2026 Tinta contributors
-- luajit -bl on every file of core/, tests/, device/, ui/ and apps/sistema/ (15.1).
local T = ...
local function ls(dir)
    local p = io.popen('ls "' .. dir .. '"')
    local out = {}
    for f in p:lines() do if f:match("%.lua$") then out[#out + 1] = f end end
    p:close()
    return out
end
local exe = arg and arg[-1] or "luajit"
for _, d in ipairs({ "core", "tests", "device", "device/backends", "ui", "apps/sistema" }) do
    local dir = T.here .. "/../" .. d
    for _, f in ipairs(ls(dir)) do
        local ok = os.execute(exe .. ' -bl "' .. dir .. "/" .. f .. '" > /dev/null 2>&1')
        T.check("syntax: " .. d .. "/" .. f, ok == 0 or ok == true)
    end
end
-- core modules never require KOReader modules (R-A1)
local allowed = { ["core/i18n"] = true, ["core/format"] = true, ["core/json"] = true, ["core/layout"] = true,
    ["core/scheduler"] = true, ["core/registry"] = true, ["core/store"] = true, ["core/notify"] = true,
    ["core/settings"] = true, ["core/power"] = true, ["core/version"] = true, ["core/appfiles"] = true, ["lua-ljsqlite3/init"] = true, ["ffi"] = true }
local bad = {}
for _, f in ipairs(ls(T.here .. "/../core")) do
    local fh = io.open(T.here .. "/../core/" .. f)
    local src = fh:read("*a"); fh:close()
    for mod in src:gmatch('require%(%s*"([^"]+)"%s*%)') do
        if not allowed[mod] then bad[#bad + 1] = f .. ":" .. mod end
    end
end
T.eq("R-A1: core requires only core modules (+ lazy sqlite binding)", table.concat(bad, ","), "")
-- every module of the spec is there
for _, m in ipairs({ "registry", "layout", "scheduler", "notify", "store", "settings", "power", "i18n", "format" }) do
    T.check("module present: core/" .. m, (pcall(require, "core/" .. m)))
end
