-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (C) 2026 Tinta contributors
-- The versions the Tinta declares, in one place (spec 5.1). Pure Lua (R-A1).
--   TINTA_VERSION  "major.minor" of the Tinta itself (shown in Sistema; an app can ask for a minimum: min_portal)
--   API_VERSION     integer, the app API (manifest fields, ctx, screens). Raised only when an app written for the
--                   older one could break; an app declares the one it was written for (manifest.api, default 1).
local M = {}

M.TINTA_VERSION = "0.1"
M.API_VERSION = 1

-- "x.y" (or "x") -> major, minor numbers; nil when it is not a version
function M.parse(v)
    if type(v) ~= "string" then return nil end
    local a, b = v:match("^(%d+)%.(%d+)$")
    if not a then a = v:match("^(%d+)$"); b = "0" end
    if not a then return nil end
    return tonumber(a), tonumber(b)
end

-- -1 | 0 | 1, nil when either is not a version
function M.compare(a, b)
    local a1, a2 = M.parse(a)
    local b1, b2 = M.parse(b)
    if not a1 or not b1 then return nil end
    if a1 ~= b1 then return a1 < b1 and -1 or 1 end
    if a2 ~= b2 then return a2 < b2 and -1 or 1 end
    return 0
end

return M
