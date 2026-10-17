-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (C) 2026 Tinta contributors
-- Relógio (10.x): widget-only system app, no network and no refresh (the host's minute tick redraws it). Four
-- styles chosen by the app setting "style" (digital, data, analogico, minimo); 1x1 is always HH:MM. The main
-- screen shows a preview and lets the user pick the style. Pure logic in logic.lua and face.lua; this file only
-- reads the clock and the sleep state of the host.
local Logic = require("apps/relogio/logic")
local Strings = require("apps/relogio/strings")
local View = require("apps/relogio/view")

local A = {
    -- seams for the tests; the host is only required while KOReader runs
    now = function() return os.time() end,
    host = function()
        local ok, Host = pcall(require, "ui/host")
        return ok and type(Host) == "table" and Host or nil
    end,
}

local function sleep_state()
    local Host = A.host()
    if not Host or not Host.isSleeping or not Host:isSleeping() then return false, nil end
    return true, Host.sleep_info and Host.sleep_info.next_at or nil
end

local function vm(ctx)
    local asleep, next_at = sleep_state()
    return { t = ctx.now and ctx.now() or A.now(), L = ctx.i18n.t, style = ctx.settings:get("style"), asleep = asleep, next_at = next_at }
end

local choices = {}
for _, s in ipairs(Logic.STYLES) do choices[#choices + 1] = { value = s, label = Strings.pt["style_" .. s] } end

return {
    id = "relogio",
    name = "Relógio",
    names = { pt = Strings.pt.name, en = Strings.en.name },
    short = "Hora",
    version = 1,
    api = 1,                -- Tinta app API this app was written for (5.1)
    system = true,          -- no refresh
    sizes = { "2x2", "4x2", "4x4", "2x4", "1x1" },
    net = false,
    defaults = {},
    settings = {
        { key = "style", label = Strings.pt.style_label, hint = Strings.pt.style_hint, type = "choice",
          default = Logic.DEFAULT_STYLE, choices = choices },
    },
    notifications = {},
    strings = Strings,

    widget = function(ctx, size, box)
        return View.widget(ctx, size, box, vm(ctx))
    end,

    screens = {
        main = function(ctx, args, box)
            return View.screen(ctx, box, vm(ctx), function(style)
                ctx.settings:set("style", style)
                local Host = A.host()
                if Host and Host.redraw then Host:redraw() end
            end)
        end,
    },

    _A = A,         -- tests only
}
