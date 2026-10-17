-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (C) 2026 Tinta contributors
-- Pure logic of the app (R-A1): no require, no KOReader, no ctx, no clock (the caller passes `now`). This is the part
-- worth testing in depth; init.lua only wires it to ctx and view.lua only draws it.
local M = {}

M.DEFAULT_LIMIT = 5
M.MIN_LIMIT, M.MAX_LIMIT = 1, 100

-- the setting as a usable integer: the store may hand back a string, a float or nil
function M.limit(v)
    local n = math.floor(tonumber(v) or M.DEFAULT_LIMIT)
    return math.max(M.MIN_LIMIT, math.min(M.MAX_LIMIT, n))
end

-- the next counter value after a refresh
function M.next_count(count)
    return (math.floor(tonumber(count) or 0)) + 1
end

-- does this count deserve a notification? (every `limit` refreshes)
function M.reached(count, limit)
    return count > 0 and count % M.limit(limit) == 0
end

-- what the widget and the screen show, from the cache table { count, at } (or nil before the first refresh).
-- `t` is ctx.i18n.t and `clock(at)` formats a time as "HH:MM".
function M.view(cache, limit, t, clock)
    cache = cache or {}
    local count = math.floor(tonumber(cache.count) or 0)
    return {
        count = count,
        primary = t("primary", count),
        secondary = cache.at and t("last", clock(cache.at)) or t("never"),
        limit = M.limit(limit),
    }
end

return M
