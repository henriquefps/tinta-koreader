-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (C) 2026 Tinta contributors
-- Repouso (10.x): widget-only system app to control sleep without opening Sistema. It shows "Dormir sozinho"
-- (always / only on battery / never, and the minutes) and changes the same Tinta settings as Sistema → Repouso
-- (idle_mode, idle_sleep);
-- it keeps no state of its own. 1x1 = one "Dormir agora" button (with confirmation), 2x2 = state (tap opens the
-- screen with the actions), 4x2 = three buttons right in the widget (minutes, mode, sleep now). No network, no refresh.
local Logic = require("apps/repouso/logic")
local Strings = require("apps/repouso/strings")
local View = require("apps/repouso/view")

local A = {
    -- the host is only required while KOReader runs (seam for the tests)
    host = function()
        local ok, Host = pcall(require, "ui/host")
        return ok and type(Host) == "table" and Host or nil
    end,
}

local function vm(ctx)
    local Host = A.host()
    local mode, idle
    if Host then mode, idle = Host:get("idle_mode"), Host:get("idle_sleep") end
    return { L = ctx.i18n.t, mode = Logic.mode(mode), idle = idle }
end

-- the callbacks of the controls; each one changes a Tinta setting through the host and redraws
local function actions(ctx)
    local function with_host(fn)
        return function()
            local Host = A.host()
            if Host then fn(Host) end
        end
    end
    return {
        cycle = with_host(function(Host)
            Host:set("idle_sleep", Logic.cycle(Host:choices("idle_sleep"), Host:get("idle_sleep")))
            Host:redraw()
        end),
        cycle_mode = with_host(function(Host)
            Host:set("idle_mode", Logic.cycle(Host:choices("idle_mode") or Logic.MODES, Logic.mode(Host:get("idle_mode"))))
            Host:redraw()
        end),
        sleep = with_host(function(Host) Host:sleepNow() end),
        confirm_sleep = function()
            local L = ctx.i18n.t
            ctx.confirm(L("confirm_title"), L("confirm_text"), L("confirm_ok"), with_host(function(Host) Host:sleepNow() end))
        end,
    }
end

return {
    id = "repouso",
    name = "Repouso",
    names = { pt = Strings.pt.name, en = Strings.en.name },
    short = "Rep.",
    version = 1,
    api = 1,                -- Tinta app API this app was written for (5.1)
    system = true,          -- no refresh
    sizes = { "2x2", "4x2", "1x1" },
    net = false,
    defaults = {},
    settings = {},
    notifications = {},
    strings = Strings,

    widget = function(ctx, size, box)
        return View.widget(ctx, size, box, vm(ctx), actions(ctx))
    end,

    screens = {
        main = function(ctx, args, box)
            return View.screen(ctx, box, vm(ctx), actions(ctx))
        end,
    },

    _A = A,         -- tests only
}
