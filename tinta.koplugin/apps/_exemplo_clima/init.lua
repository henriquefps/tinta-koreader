-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (C) 2026 Tinta contributors
-- Weather: the third example app of the Tinta SDK (docs/sdk.md), the pattern of an app that uses a public web service:
-- refresh() asks the Open-Meteo API (no key, no account) for the current weather and the next hours through ctx.net,
-- keeps the few fields it shows in the cache, a 2x2 / 4x2 widget and a screen show them, and a notification says "rain
-- in the next hours" at most once per day. For a local app see apps/_modelo; for your own server, apps/_exemplo_json.
--
-- The folder starts with "_", so the Tinta loads it only when the Tinta setting dev_apps is on (development).
--
-- Layout: init.lua = manifest + wiring to ctx · logic.lua = pure rules (tested) · view.lua = drawing ·
-- strings.lua = pt/en texts · tests/ = the suite, with a fake ctx.net and a recorded sample answer.
local Logic = require("apps/_exemplo_clima/logic")
local Strings = require("apps/_exemplo_clima/strings")
local View = require("apps/_exemplo_clima/view")

return {
    id = "_exemplo_clima",
    name = "Weather",
    names = { pt = Strings.pt.name, en = Strings.en.name },
    short = "Weather",
    description = Strings.pt.description,
    version = 1,
    api = 1,
    sizes = { "2x2", "4x2" },
    net = true,                      -- refreshing needs Wi-Fi: the Tinta turns it on only when this app is due (R-P1)
    defaults = { interval = 1800 },  -- every 30 minutes; the user changes it in Sistema → Atualizações

    settings = {
        { key = "lat", label = Strings.pt.set_lat, type = "number", default = Logic.DEFAULT_LAT, min = -90, max = 90 },
        { key = "lon", label = Strings.pt.set_lon, type = "number", default = Logic.DEFAULT_LON, min = -180, max = 180 },
        { key = "units", label = Strings.pt.set_units, type = "choice", default = "metric",
          choices = { { value = "metric", label = Strings.pt.units_metric }, { value = "imperial", label = Strings.pt.units_imperial } } },
    },
    notifications = {
        { type = "rain", label = Strings.pt.notif_rain },
    },
    strings = Strings,

    -- the data fetch (docs/sdk.md section 7): done(true) or done(false, kind) exactly once. Logic.parse never throws.
    refresh = function(ctx, done)
        if not ctx.net then return done(false, "unreachable") end   -- ctx.net can be nil (tests, a failed load)
        local units = Logic.units(ctx.settings:get("units"))
        local body, kind = ctx.net.get_json(Logic.url(ctx.settings:get("lat"), ctx.settings:get("lon"), units))
        if not body then return done(false, kind) end
        local reading, why = Logic.parse(body)
        if not reading then return done(false, why) end
        local now = ctx.now()
        reading.at, reading.units = now, units
        ctx.cache:put(reading)                       -- only the fields we show, never the raw answer (R-A4)
        done(true)   -- done first: the first reading of a session only arms the notifications (8.6)
        local rain = Logic.rain_ahead(reading.hours, now)
        if rain then
            -- one key per day at the place: the Tinta drops a repeated key, so this fires at most once a day
            ctx.notify{ key = "rain:" .. Logic.day_key(now, reading.offset), type = "rain", title = ctx.i18n.t("n_rain_title"),
                body = ctx.i18n.t("n_rain_body", Logic.clock(rain.at, reading.offset), math.floor(rain.pop or 0)), route = { "main" } }
        end
    end,

    -- the widget reads the cache once (the Tinta draws it often; never query the store per item)
    widget = function(ctx, size, box)
        return View.widget(ctx, size, box, Logic.view(ctx.cache:get(), ctx.now(), ctx.i18n.t), ctx.i18n.t)
    end,

    screens = {
        main = function(ctx, args, box)
            return View.screen(ctx, box, Logic.view(ctx.cache:get(), ctx.now(), ctx.i18n.t), ctx.i18n.t)
        end,
    },
}
