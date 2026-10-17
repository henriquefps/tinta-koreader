-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (C) 2026 Tinta contributors
-- JSON: the second example app of the Tinta SDK (docs/sdk.md), the common pattern of an app that talks to a server:
-- refresh() fetches a JSON from a configurable URL through ctx.net, keeps the few fields it uses in the cache, a 2x2 / 4x2
-- widget shows the value, a screen shows it big, and a notification fires when the value goes over a threshold.
-- For the simplest local app see apps/_modelo
-- (scripts/nova-app.sh copies that one); to start from this one, copy the folder and rename the id inside the files.
--
-- The folder starts with "_", so the Tinta loads it only when the Tinta setting dev_apps is on (development).
--
-- Layout: init.lua = manifest + wiring to ctx · logic.lua = pure rules (tested) · view.lua = drawing ·
-- strings.lua = pt/en texts · tests/ = the suite, with a fake ctx.net (scripts/test-all.sh runs it).
local Logic = require("apps/_exemplo_json/logic")
local Strings = require("apps/_exemplo_json/strings")
local View = require("apps/_exemplo_json/view")

local function clock(at) return os.date("%H:%M", at) end

return {
    id = "_exemplo_json",
    name = "JSON",
    names = { pt = Strings.pt.name, en = Strings.en.name },
    short = "JSON",
    description = Strings.pt.description,
    version = 1,
    api = 1,
    sizes = { "2x2", "4x2" },
    net = true,                      -- refreshing needs Wi-Fi: the Tinta turns it on only when this app is due (R-P1)
    defaults = { interval = 300 },
    -- the server of the app, for Sistema → Conexões: "down" / "back" notifications after repeated failures
    source = { id = "_exemplo_json", name = "JSON", url_key = "url" },

    settings = {
        { key = "url", label = Strings.pt.set_url, type = "url", default = "https://example.com/status.json" },
        { key = "token", label = Strings.pt.set_token, type = "token" },
        { key = "threshold", label = Strings.pt.set_threshold, type = "number", default = 0, min = 0, max = Logic.MAX_THRESHOLD },
    },
    notifications = {
        { type = "over", label = Strings.pt.notif_over },
    },
    strings = Strings,

    -- the data fetch (docs/sdk.md section 7): done(true) or done(false, kind) exactly once. A network failure is
    -- done(false, kind); an exception would count as an app error, so decoding goes through Logic.parse, which never throws.
    refresh = function(ctx, done)
        if not ctx.net then return done(false, "unreachable") end   -- ctx.net can be nil (tests, a failed load)
        local body, kind = ctx.net.get_json(ctx.settings:get("url"), { token = ctx.settings:get("token") })
        if not body then return done(false, kind) end
        local reading, why = Logic.parse(body)
        if not reading then return done(false, why) end
        reading.at = ctx.now()
        ctx.cache:put(reading)                       -- only the fields we use, never the raw answer (R-A4)
        local over, fire = Logic.crossed(ctx.data:get("over") == true, reading.value, ctx.settings:get("threshold"))
        ctx.data:set("over", over)
        done(true)   -- done first: the first reading of a session only arms the notifications (8.6)
        if fire then
            local n = (tonumber(ctx.data:get("alerts")) or 0) + 1
            ctx.data:set("alerts", n)
            ctx.notify{ key = "over:" .. n, type = "over", title = ctx.i18n.t("n_over_title", reading.label or ctx.i18n.t("name"), Logic.format_value(reading.value)),
                body = ctx.i18n.t("n_over_body", Logic.format_value(Logic.threshold(ctx.settings:get("threshold")))), route = { "main" } }
        end
    end,

    -- the widget reads the cache once (the Tinta draws it often; never query the store per item)
    widget = function(ctx, size, box)
        local vm = Logic.view(ctx.cache:get(), ctx.settings:get("url"), ctx.settings:get("threshold"), ctx.i18n.t, clock)
        return View.widget(ctx, size, box, vm, ctx.i18n.t)
    end,

    screens = {
        main = function(ctx, args, box)
            local vm = Logic.view(ctx.cache:get(), ctx.settings:get("url"), ctx.settings:get("threshold"), ctx.i18n.t, clock)
            local act = {
                rearm = function()
                    ctx.confirm(ctx.i18n.t("confirm_title"), ctx.i18n.t("confirm_text"), ctx.i18n.t("confirm_ok"), function()
                        ctx.data:set("over", false)
                        ctx.toast(ctx.i18n.t("toast_rearmed"))
                        ctx.redraw()
                    end)
                end,
            }
            return View.screen(ctx, box, vm, act, ctx.i18n.t)
        end,
    },
}
