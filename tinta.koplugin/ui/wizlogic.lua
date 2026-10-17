-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (C) 2026 Tinta contributors
-- Tinta: first-run wizard (spec 7.5), the pure part: steps, which apps can be chosen and the layouts the wizard
-- writes. Pure Lua (R-A1 spirit: no KOReader).
local Org = require("ui/orglogic")

local M = {}

M.STEPS = { "welcome", "wifi", "apps", "sleep" }

local function user_app(id, protected)
    return type(id) == "string" and id:sub(1, 1) ~= "_" and not (protected and protected(id))
end

-- ids the user can choose, in registry order: no protected (Sistema, Notificações) and no test apps
function M.candidates(apps, protected)
    local out = {}
    for _, m in ipairs(apps or {}) do
        if user_app(m.id, protected) then out[#out + 1] = m.id end
    end
    return out
end

-- set of ids checked at the start: the apps of the default Home layout
function M.initial(candidates, default_home)
    local want, sel = {}, {}
    for _, it in ipairs(default_home or {}) do want[it.app] = true end
    for _, id in ipairs(candidates) do if want[id] then sel[id] = true end end
    return sel
end

-- one new layout page: default order first, the chosen apps that are not in the default after, sizes the app declares.
-- Apps the user cannot choose (Sistema, Notificações) stay where the default has them, when registered.
local function page(sel, known, candidates, default, extras, protected)
    local out, done = {}, {}
    local function add(id, size)
        local m = known[id]
        if not m or done[id] then return end
        done[id] = true
        out[#out + 1] = { app = id, size = Org.effective_size(size or (m.sizes or {})[1] or "2x2", m.sizes) }
    end
    for _, it in ipairs(default or {}) do
        if user_app(it.app, protected) then
            if sel[it.app] then add(it.app, it.size) end
        else
            add(it.app, it.size)
        end
    end
    if extras then
        for _, id in ipairs(candidates) do if sel[id] and not done[id] then add(id) end end
    end
    return out
end

-- apps: manifests; returns home, sleep (lists of { app, size }) for the chosen set `sel`
function M.layouts(sel, apps, default_home, default_sleep, protected)
    local known = {}
    for _, m in ipairs(apps or {}) do known[m.id] = m end
    local cand = M.candidates(apps, protected)
    return page(sel, known, cand, default_home, true, protected), page(sel, known, cand, default_sleep, false, protected)
end

return M
