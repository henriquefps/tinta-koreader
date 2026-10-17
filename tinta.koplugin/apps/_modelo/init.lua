-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (C) 2026 Tinta contributors
-- Modelo: the reference app of the Tinta SDK (docs/sdk.md). A refresh counter: every refresh adds one, the widget
-- (2x2 and 4x2) shows it, the main screen has a Zerar button, and a notification fires every N refreshes (a setting).
-- It is local (no network), so it works anywhere. Copy it with scripts/nova-app.sh <id> "<Nome>" and edit.
--
-- The folder starts with "_", so the Tinta loads it only when the Tinta setting dev_apps is on (development).
-- A copy made by nova-app.sh has no underscore and loads normally.
--
-- Layout: init.lua = manifest + wiring to ctx · logic.lua = pure rules (tested) · view.lua = drawing ·
-- strings.lua = pt/en texts · tests/ = the suite (scripts/test-all.sh runs it).
local Logic = require("apps/_modelo/logic")
local Strings = require("apps/_modelo/strings")
local View = require("apps/_modelo/view")

local function clock(at) return os.date("%H:%M", at) end

return {
    id = "_modelo",                  -- [a-z0-9_]+, equals the folder name, unique
    name = "Modelo",                 -- fallback name; names/strings below translate it
    names = { pt = Strings.pt.name, en = Strings.en.name },
    short = "Modelo",                -- short label of the organizer map
    description = Strings.pt.description,
    version = 1,                     -- version of the DATA schema: raise it and add migrate(ctx, from, to) when it changes
    api = 1,                         -- app API this was written for (the Tinta refuses an app that wants a newer one)
    sizes = { "2x2", "4x2" },        -- widget sizes; the first is the default
    net = false,                     -- true: needs Wi-Fi to refresh (the Tinta turns it on only when due)
    defaults = { interval = 300 },   -- seconds between refreshes (0 = manual); window = { from, to, weekdays } optional

    -- fields generate Sistema → Apps → <app>; types: url, token, number, time, choice, bool
    settings = {
        { key = "limit", label = Strings.pt.set_limit, type = "number", default = Logic.DEFAULT_LIMIT,
          min = Logic.MIN_LIMIT, max = Logic.MAX_LIMIT },
    },
    -- notification types the app emits: the user picks alta / normal / desligada for each
    notifications = {
        { type = "limit", label = Strings.pt.notif_limit },
    },
    strings = Strings,               -- gives ctx.i18n.t

    -- once, when the Tinta opens. Read the store here, not in widget().
    init = function(ctx)
        ctx.log("init")
    end,

    -- the data fetch. Must call done(true) or done(false, err) exactly once, sooner or later (no done for 120 s counts
    -- as a failure). A thrown error counts as an app error. For a network app: ctx.net.get_json(url, opts).
    refresh = function(ctx, done)
        local count = Logic.next_count(ctx.data:get("count"))
        ctx.data:set("count", count)
        ctx.cache:put({ count = count, at = ctx.now() })
        done(true)   -- done first: the first reading of a session only arms the notifications (8.6)
        local limit = Logic.limit(ctx.settings:get("limit"))
        if Logic.reached(count, limit) then
            ctx.notify{ key = "limit:" .. count, type = "limit", title = ctx.i18n.t("n_limit_title", count),
                body = ctx.i18n.t("n_limit_body", limit), route = { "main" } }
        end
    end,

    -- builds the widget for `size` inside `box` = { w, h, cols, rows, inv, size, big }. Pure drawing: one cache read.
    widget = function(ctx, size, box)
        local vm = Logic.view(ctx.cache:get(), ctx.settings:get("limit"), ctx.i18n.t, clock)
        return View.widget(ctx, size, box, vm, ctx.i18n.t)
    end,

    -- full screens; "main" opens when the widget is tapped. Called as (ctx, args, box).
    screens = {
        main = function(ctx, args, box)
            local vm = Logic.view(ctx.cache:get(), ctx.settings:get("limit"), ctx.i18n.t, clock)
            local act = {
                reset = function()
                    ctx.confirm(ctx.i18n.t("confirm_title"), ctx.i18n.t("confirm_text"), ctx.i18n.t("confirm_ok"), function()
                        ctx.data:set("count", 0)
                        ctx.cache:put({ count = 0 })
                        ctx.toast(ctx.i18n.t("toast_reset"))
                        ctx.redraw()
                    end)
                end,
            }
            return View.screen(ctx, box, vm, act, ctx.i18n.t)
        end,
    },
}
