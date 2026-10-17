-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (C) 2026 Tinta contributors
-- Pure logic of the app (R-A1): no require, no KOReader, no ctx, no clock (the caller passes `now`). It builds the
-- Open-Meteo request, decodes the answer keeping only the fields the app shows, decides when "rain soon" deserves a
-- notification (once per day) and builds what the views show.
--
-- The API is public and needs no key: https://open-meteo.com/en/docs . The request asks for unix times
-- (timeformat=unixtime) and the place's own UTC offset (timezone=auto), so no date parsing is needed. The answer is
--   { utc_offset_seconds = 7200,
--     current = { time = 1792000200, temperature_2m = 14.3, weather_code = 3 },
--     hourly  = { time = {...}, temperature_2m = {...}, precipitation_probability = {...}, weather_code = {...} } }
local M = {}

M.HOST = "https://api.open-meteo.com/v1/forecast"
M.DEFAULT_LAT, M.DEFAULT_LON = 51.51, -0.13
M.KEEP_HOURS = 24         -- hours kept in the cache (the forecast asks for 2 days)
M.RAIN_HOURS = 6          -- "rain in the next hours" looks this far ahead
M.RAIN_POP = 60           -- precipitation probability (%) that counts as rain
M.HOUR = 3600

local function num(v, lo, hi, default)
    v = tonumber(v)
    if not v or v ~= v then return default end
    if v < lo or v > hi then return default end
    return v
end

function M.latitude(v) return num(v, -90, 90, M.DEFAULT_LAT) end
function M.longitude(v) return num(v, -180, 180, M.DEFAULT_LON) end
function M.units(v) return v == "imperial" and "imperial" or "metric" end

-- the request URL for a place; imperial asks for Fahrenheit
function M.url(lat, lon, units)
    local url = string.format("%s?latitude=%.4f&longitude=%.4f&current=temperature_2m,weather_code" ..
        "&hourly=temperature_2m,precipitation_probability,weather_code&forecast_days=2&timezone=auto&timeformat=unixtime",
        M.HOST, M.latitude(lat), M.longitude(lon))
    if M.units(units) == "imperial" then url = url .. "&temperature_unit=fahrenheit" end
    return url
end

local function number(v)
    if type(v) ~= "number" or v ~= v or v == math.huge or v == -math.huge then return nil end
    return v
end

-- the decoded body -> { temp, code, at, offset, hours = { { at, temp, pop, code }, ... } } keeping only what we show
-- (R-A4: never store the raw answer). nil, "bad_shape" when it is not a forecast with a current temperature.
function M.parse(body)
    if type(body) ~= "table" or type(body.current) ~= "table" then return nil, "bad_shape" end
    local temp = number(body.current.temperature_2m)
    if not temp then return nil, "bad_shape" end
    local out = { temp = temp, code = number(body.current.weather_code), offset = number(body.utc_offset_seconds) or 0, hours = {} }
    local h = body.hourly
    if type(h) == "table" and type(h.time) == "table" then
        for i = 1, #h.time do
            if #out.hours >= M.KEEP_HOURS then break end
            local at = number(h.time[i])
            local t = type(h.temperature_2m) == "table" and number(h.temperature_2m[i])
            if at and t then
                out.hours[#out.hours + 1] = { at = at, temp = t,
                    pop = type(h.precipitation_probability) == "table" and number(h.precipitation_probability[i]) or 0,
                    code = type(h.weather_code) == "table" and number(h.weather_code[i]) or nil }
            end
        end
    end
    return out
end

-- WMO weather code -> a key of strings.lua (w_<kind>)
function M.kind(code)
    if not code then return "unknown" end
    if code <= 1 then return "clear" end
    if code == 2 then return "partly" end
    if code == 3 then return "cloudy" end
    if code == 45 or code == 48 then return "fog" end
    if code >= 51 and code <= 57 then return "drizzle" end
    if code >= 61 and code <= 67 then return "rain" end
    if (code >= 71 and code <= 77) or code == 85 or code == 86 then return "snow" end
    if code >= 80 and code <= 82 then return "showers" end
    if code >= 95 and code <= 99 then return "storm" end
    return "unknown"
end

local WET = { drizzle = true, rain = true, showers = true, storm = true }

local function wet(h) return (h.pop or 0) >= M.RAIN_POP or WET[M.kind(h.code)] == true end

-- the entries after `now`, at most `n`
function M.upcoming(hours, now, n)
    local out = {}
    for _, h in ipairs(hours or {}) do
        if h.at > now then
            out[#out + 1] = h
            if #out >= n then break end
        end
    end
    return out
end

-- the first rainy entry within the next RAIN_HOURS hours, or nil
function M.rain_ahead(hours, now)
    local limit = now + M.RAIN_HOURS * M.HOUR
    for _, h in ipairs(M.upcoming(hours, now, #(hours or {}))) do
        if h.at > limit then return nil end
        if wet(h) then return h end
    end
    return nil
end

-- "YYYY-MM-DD" at the place: the notification key, so "rain soon" fires at most once per day
function M.day_key(now, offset)
    return os.date("!%Y-%m-%d", now + (tonumber(offset) or 0))
end

-- "HH:MM" at the place
function M.clock(at, offset) return os.date("!%H:%M", at + (tonumber(offset) or 0)) end

-- 14.3 -> "14°"; the unit letter is left to the screen title
function M.format_temp(t) return string.format("%d°", math.floor(t + 0.5)) end

-- what the widget and the screen show, from the cache table (nil before the first refresh). `t` is ctx.i18n.t.
function M.view(cache, now, t)
    if not cache or type(cache.temp) ~= "number" then
        return { label = t("name"), primary = t("empty"), secondary = t("never"), big = "—", hours = {}, rain = t("rain_unknown") }
    end
    local offset = cache.offset or 0
    local vm = { label = t("name"), big = M.format_temp(cache.temp), hours = {} }
    vm.primary = vm.big
    vm.secondary = t("w_" .. M.kind(cache.code))
    vm.updated = cache.at and t("at", M.clock(cache.at, offset)) or t("never")
    vm.units = cache.units == "imperial" and "°F" or "°C"
    local r = M.rain_ahead(cache.hours, now)
    vm.rain = r and t("rain_at", M.clock(r.at, offset), math.floor(r.pop or 0)) or t("rain_none", M.RAIN_HOURS)
    vm.rainy = r ~= nil
    local nxt = M.upcoming(cache.hours, now, 1)[1]
    vm.next = nxt and t("next_line", M.clock(nxt.at, offset), M.format_temp(nxt.temp), math.floor(nxt.pop or 0)) or t("never")
    for i, h in ipairs(M.upcoming(cache.hours, now, 8)) do
        vm.hours[i] = { time = M.clock(h.at, offset), desc = t("w_" .. M.kind(h.code)),
            right = M.format_temp(h.temp) .. " · " .. math.floor(h.pop or 0) .. "%" }
    end
    return vm
end

return M
