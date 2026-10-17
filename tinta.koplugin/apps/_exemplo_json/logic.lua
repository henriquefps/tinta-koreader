-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (C) 2026 Tinta contributors
-- Pure logic of the app (R-A1): no require, no KOReader, no ctx, no clock (the caller passes `now`). It decodes the
-- JSON the server answers with, decides when a reading deserves a notification and builds what the views show.
--
-- The JSON this example expects (any server that answers it will do):
--   { "value": 42, "label": "Queue", "unit": "items" }       value: number (required) · label, unit: text (optional)
local M = {}

M.MAX_LABEL, M.MAX_UNIT = 40, 12
M.MAX_THRESHOLD = 1000000

-- the setting as a usable number: 0 (or anything invalid) means "no alert"
function M.threshold(v)
    local n = tonumber(v)
    if not n or n ~= n or n <= 0 then return 0 end
    return math.min(n, M.MAX_THRESHOLD)
end

local function short_text(v, max)
    if type(v) ~= "string" then return nil end
    v = v:gsub("[%c]", " "):gsub("^%s+", ""):gsub("%s+$", "")
    if v == "" then return nil end
    if #v > max then v = v:sub(1, max) end
    return v
end

-- the decoded body -> { value, label, unit } keeping only the fields we use (R-A4: never store the raw answer).
-- nil, "bad_shape" when it is not an object with a numeric value.
function M.parse(body)
    if type(body) ~= "table" then return nil, "bad_shape" end
    local value = body.value
    if type(value) == "string" then value = tonumber(value) end
    if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then return nil, "bad_shape" end
    return { value = value, label = short_text(body.label, M.MAX_LABEL), unit = short_text(body.unit, M.MAX_UNIT) }
end

-- "42", "3.5": integers without decimals, the rest with one
function M.format_value(v)
    if v == math.floor(v) and math.abs(v) < 1e15 then return string.format("%d", v) end
    return string.format("%.1f", v)
end

-- notify only when the value crosses the threshold upwards, not on every reading above it.
-- was_over: the previous reading was over (nil on the first). Returns is_over_now, should_notify.
function M.crossed(was_over, value, threshold)
    local limit = M.threshold(threshold)
    if limit == 0 then return false, false end
    local over = value >= limit
    return over, over and not was_over
end

-- host[:port] of a URL, for the "source" line; nil when it is not a URL
function M.host(url)
    if type(url) ~= "string" then return nil end
    return url:match("^https?://([^/?#]+)")
end

-- what the widget and the screen show, from the cache table { value, label, unit, at } (nil before the first refresh).
-- `t` is ctx.i18n.t and `clock(at)` formats a time as "HH:MM".
function M.view(cache, url, threshold, t, clock)
    local limit = M.threshold(threshold)
    local vm = {
        host = M.host(url) or t("no_host"),
        limit = limit > 0 and M.format_value(limit) or t("alert_off"),
    }
    if not cache or type(cache.value) ~= "number" then
        vm.label, vm.primary, vm.secondary, vm.big = t("name"), t("empty"), t("never"), "—"
        return vm
    end
    vm.label = cache.label or t("name")
    vm.big = M.format_value(cache.value)
    vm.primary = cache.unit and (vm.big .. " " .. cache.unit) or vm.big
    vm.secondary = cache.at and t("at", clock(cache.at)) or t("never")
    vm.over = limit > 0 and cache.value >= limit
    return vm
end

return M
