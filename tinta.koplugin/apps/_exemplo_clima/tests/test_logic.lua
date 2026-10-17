-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (C) 2026 Tinta contributors
-- logic.lua: the request, decoding the recorded answer, weather kinds, the rain rule and the view model
local T = ...
local Logic = require("apps/_exemplo_clima/logic")
local Json = require("core/json")

local fh = assert(io.open(T.here .. "/sample.json", "r"))
local sample = Json.decode(fh:read("*a")); fh:close()
local NOW = 1792152000   -- 14:00 at the sample's place (UTC+2), the sample's "current" time

-- request
local url = Logic.url(51.5, -0.125, "metric")
T.check("url: host and place", url:find("^https://api.open%-meteo.com/v1/forecast%?latitude=51.5000&longitude=%-0.1250") ~= nil)
T.check("url: unix times and the place's zone", url:find("timeformat=unixtime", 1, true) and url:find("timezone=auto", 1, true))
T.check("url: metric asks no unit", not url:find("temperature_unit", 1, true))
T.check("url: imperial asks Fahrenheit", Logic.url(1, 2, "imperial"):find("temperature_unit=fahrenheit", 1, true) ~= nil)
T.check("url: no key or token in it", not url:find("key", 1, true) and not url:find("token", 1, true))
T.eq("latitude: out of range falls back", Logic.latitude(123), Logic.DEFAULT_LAT)
T.eq("longitude: text number", Logic.longitude("-46.6"), -46.6)
T.eq("longitude: garbage falls back", Logic.longitude("abc"), Logic.DEFAULT_LON)
T.eq("units: unknown is metric", Logic.units("kelvin"), "metric")

-- parse
local r = Logic.parse(sample)
T.check("parse: current temperature, code and offset", r and r.temp == 16.2 and r.code == 3 and r.offset == 7200)
T.eq("parse: hours kept", #r.hours, Logic.KEEP_HOURS)
local fields = 0
for _ in pairs(r.hours[1]) do fields = fields + 1 end
T.check("parse: an hour has only the fields we show", r.hours[1].at == 1792101600 and r.hours[1].temp == 11.2 and r.hours[1].pop == 0
    and r.hours[1].code == 1 and fields == 4)
T.check("parse: nothing else is kept", r.latitude == nil and r.timezone == nil and r.hourly == nil)
for name, body in pairs({ ["not a table"] = "x", ["no current"] = { hourly = {} }, ["text temperature"] = { current = { temperature_2m = "hot" } },
    ["nan"] = { current = { temperature_2m = 0 / 0 } } }) do
    local got, why = Logic.parse(body)
    T.check("parse: refuses " .. name, got == nil and why == "bad_shape")
end
local min = Logic.parse({ current = { temperature_2m = 5 } })
T.check("parse: no hourly part is fine", min and #min.hours == 0 and min.offset == 0)
local holes = Logic.parse({ current = { temperature_2m = 5 }, hourly = { time = { 1, 2, 3 }, temperature_2m = { 1, "x", 3 } } })
T.eq("parse: skips an hour with a bad temperature", #holes.hours, 2)

-- kinds
for code, want in pairs({ [0] = "clear", [2] = "partly", [3] = "cloudy", [45] = "fog", [53] = "drizzle", [63] = "rain", [73] = "snow",
    [81] = "showers", [86] = "snow", [95] = "storm", [1234] = "unknown" }) do
    T.eq("kind: " .. code, Logic.kind(code), want)
end
T.eq("kind: nil", Logic.kind(nil), "unknown")

-- upcoming and the rain rule
T.eq("upcoming: starts after now", Logic.upcoming(r.hours, NOW, 3)[1].at, NOW + 3600)
T.eq("upcoming: at most n", #Logic.upcoming(r.hours, NOW, 3), 3)
local rain = Logic.rain_ahead(r.hours, NOW)
T.check("rain: the first rainy hour of the next 6", rain and rain.at == NOW + 3600 and rain.code == 61)
T.check("rain: a dry stretch has none", Logic.rain_ahead(r.hours, NOW + 6 * 3600 + 3600 * 5) == nil)
T.check("rain: probability alone counts", Logic.rain_ahead({ { at = NOW + 60, temp = 1, pop = 60, code = 3 } }, NOW) ~= nil)
T.check("rain: 59% and cloudy does not", Logic.rain_ahead({ { at = NOW + 60, temp = 1, pop = 59, code = 3 } }, NOW) == nil)
T.check("rain: only the next hours count", Logic.rain_ahead({ { at = NOW + 7 * 3600, temp = 1, pop = 90, code = 63 } }, NOW) == nil)
T.check("rain: no hours, no rain", Logic.rain_ahead(nil, NOW) == nil)

-- keys and formatting
T.eq("day_key: at the place, not UTC", Logic.day_key(1792101600 + 24 * 3600 + 1800, 7200), "2026-10-17")
T.eq("day_key: same day, same key", Logic.day_key(NOW, 7200), Logic.day_key(NOW + 3600, 7200))
T.eq("clock: at the place", Logic.clock(NOW, 7200), "14:00")
T.eq("temp: rounds", Logic.format_temp(14.5), "15°")
T.eq("temp: negative", Logic.format_temp(-3.2), "-3°")

-- view model
local function t(key, ...) return T.L(key, ...) end
local vm = Logic.view(nil, NOW, t)
T.check("view: before the first refresh", vm.primary == T.L("empty") and vm.secondary == T.L("never") and vm.big == "—" and #vm.hours == 0)
local cache = { temp = 16.2, code = 3, offset = 7200, hours = r.hours, at = NOW, units = "metric" }
vm = Logic.view(cache, NOW, t)
T.check("view: temperature and sky", vm.primary == "16°" and vm.secondary == T.L("w_cloudy") and vm.units == "°C")
T.eq("view: rain line", vm.rain, T.L("rain_at", "15:00", 35))
T.check("view: rainy flag", vm.rainy == true)
T.eq("view: updated", vm.updated, T.L("at", "14:00"))
T.eq("view: next hour line", vm.next, T.L("next_line", "15:00", "16°", 35))
T.eq("view: eight hours listed", #vm.hours, 8)
T.check("view: an hour row", vm.hours[1].time == "15:00" and vm.hours[1].desc == T.L("w_rain") and vm.hours[1].right == "16° · 35%")
cache.units = "imperial"
T.eq("view: Fahrenheit unit", Logic.view(cache, NOW, t).units, "°F")
vm = Logic.view({ temp = 3, hours = {} }, NOW, t)
T.check("view: no forecast hours -> no rain, no next", vm.rain == T.L("rain_none", Logic.RAIN_HOURS) and vm.next == T.L("never") and vm.rainy == false)
