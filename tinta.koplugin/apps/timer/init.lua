-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (C) 2026 Tinta contributors
-- Timer (10.6): countdown with the pomodoro follow-up. Local, no network. The end time is kept in ctx.data
-- ("state"), so the timer survives closing the Tinta; it is told to the host with ctx.wake_at(end_at) (11.7), which
-- fires a refresh at that second when awake and brings the RTC wake-up forward when the Kindle sleeps. The refresh
-- notifies "Tempo esgotado" (prio alta) and, for the pomodoro, starts the break. Widgets 2x2, 4x2 and 1x1. The logic
-- is pure (logic.lua); this file wires it to ctx. State is read from the store once, at init, and written through.
local Logic = require("apps/timer/logic")
local Strings = require("apps/timer/strings")
local View = require("apps/timer/view")

-- A.armed: the first refresh of a session only arms the notifications (core/notify 8.6): the end is checked from
-- the second one, which the host runs right away when the end time already passed.
local A = { st = nil, armed = false }

local function cfg(ctx)
    local s = ctx.settings
    return {
        work_min = tonumber(s:get("work_min")), break_min = tonumber(s:get("break_min")),
        custom_min = tonumber(s:get("custom_min")),
    }
end

local function save(ctx)
    ctx.data:set("state", A.st)
    ctx.wake_at(Logic.wake_time(A.st))
end

local function state(ctx)
    if not A.st then
        A.st = Logic.sanitize(ctx.data:get("state"), Logic.selection("pomo", cfg(ctx)))
    end
    return A.st
end

-- an idle pomodoro selection follows the settings
local function sync_pomo(ctx)
    local st = state(ctx)
    local c = cfg(ctx)
    local pomo = Logic.selection("pomo", c)
    st.pomo = pomo
    if st.mode == "idle" and (st.sel == nil or st.sel.id == "pomo") then st.sel = pomo end
    return c
end

local function vm_of(ctx)
    return Logic.view(state(ctx), ctx.now(), ctx.i18n.t)
end

local function actions(ctx)
    local c = cfg(ctx)
    local act = {}
    function act.select(preset)
        A.st = Logic.idle(Logic.selection(preset, c))
        save(ctx)
        ctx.redraw()
    end
    function act.custom()
        local cur = Logic.selection("custom", c).min
        ctx.input(ctx.i18n.t("custom_title"), tostring(cur), ctx.i18n.t("custom_hint"), function(text)
            local n = Logic.parse_minutes(text)
            if not n then return false, ctx.i18n.t("custom_bad") end
            ctx.settings:set("custom_min", n)
            A.st = Logic.idle(Logic.selection("custom", { custom_min = n }))
            save(ctx)
            return true
        end, { number = true })
    end
    function act.start()
        A.st = Logic.start(state(ctx).sel or Logic.selection("pomo", c), ctx.now())
        save(ctx)
        ctx.redraw()
    end
    function act.pause() A.st = Logic.pause(state(ctx), ctx.now()); save(ctx); ctx.redraw() end
    function act.resume() A.st = Logic.resume(state(ctx), ctx.now()); save(ctx); ctx.redraw() end
    function act.reset() A.st = Logic.reset(state(ctx)); save(ctx); ctx.redraw() end
    return act
end

return {
    id = "timer",
    name = "Timer",
    names = { pt = Strings.pt.name, en = Strings.en.name },
    short = "Timer",
    version = 1,
    api = 1,                -- Tinta app API this app was written for (5.1)
    sizes = { "2x2", "4x2", "1x1" },
    net = false,
    defaults = { interval = 300, window = nil },
    settings = {
        { key = "work_min", label = Strings.pt.set_work, type = "number", default = 25, min = 1, max = 180 },
        { key = "break_min", label = Strings.pt.set_break, type = "number", default = 5, min = 1, max = 60 },
        { key = "auto_break", label = Strings.pt.set_auto, type = "bool", default = true },
        { key = "custom_min", label = Strings.pt.set_custom, type = "number", default = Logic.CUSTOM_DEFAULT,
          min = Logic.MIN_MIN, max = Logic.MAX_MIN },
    },
    notifications = {
        { type = "done", label = Strings.pt.notif_done },
    },
    strings = Strings,

    init = function(ctx)
        A.armed = false
        A.st = nil
        ctx.wake_at(Logic.wake_time(state(ctx)))
    end,

    refresh = function(ctx, done)
        local st = state(ctx)
        if not A.armed then
            A.armed = true
            ctx.wake_at(Logic.wake_time(st))
            return done(true)
        end
        local now = ctx.now()
        if Logic.is_due(st, now) then
            local nst, ev = Logic.finish(st, now, ctx.settings:get("auto_break") == true)
            A.st = nst
            ctx.data:set("state", nst)
            ctx.notify(Logic.notification(ev, ctx.i18n.t))
            st = nst
        end
        ctx.wake_at(Logic.wake_time(st))
        done(true)
    end,

    widget = function(ctx, size, box)
        return View.widget(ctx, size, box, vm_of(ctx), ctx.i18n.t)
    end,

    screens = {
        main = function(ctx, args, box)
            sync_pomo(ctx)
            return View.screen(ctx, box, vm_of(ctx), state(ctx), actions(ctx), ctx.i18n.t)
        end,
    },

    _A = A,       -- tests only
}
