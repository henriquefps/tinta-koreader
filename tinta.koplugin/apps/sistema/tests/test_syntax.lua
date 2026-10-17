-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (C) 2026 Tinta contributors
local T = ...
-- every Lua file of the app compiles; the pure modules never require KOReader (R-A1)
local p = io.popen("ls " .. T.here .. "/.. 2>/dev/null")
for f in p:lines() do
    if f:match("%.lua$") then
        local fh = io.open(T.here .. "/../" .. f); local src = fh:read("*a"); fh:close()
        T.check("syntax: " .. f, loadstring(src, f) ~= nil)
        if f == "diag.lua" or f == "backup.lua" or f == "logic.lua" then
            local bad
            for mod in src:gmatch('require%(%s*"([^"]+)"%s*%)') do
                if not (mod:match("^core/") or mod:match("^apps/sistema/")) then bad = mod end
            end
            T.check("pure: " .. f .. " requires only core/ and its own app", bad == nil, bad)
        end
    end
end
p:close()
