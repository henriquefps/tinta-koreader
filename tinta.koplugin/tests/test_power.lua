-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (C) 2026 Tinta contributors
local T = ...
local P = require("core/power")
local eq, same, check = T.eq, T.same, T.check
local D = T.date
local FRI = function(h, m) return T.utc(2026, 10, 16, h, m or 0) end
local SAT = function(h, m) return T.utc(2026, 10, 17, h, m or 0) end
local MON = function(h, m) return T.utc(2026, 10, 19, h, m or 0) end
local o = function(x) x = x or {}; x.date = D; return x end

-- 11.4 schedule
eq("interval: weekday day 30", P.wake_interval(FRI(10), o()), 30)
eq("interval: weekday 07:30 starts day band", P.wake_interval(FRI(7, 30), o()), 30)
eq("interval: weekday 18:29", P.wake_interval(FRI(18, 29), o()), 30)
eq("interval: weekday 18:30 evening", P.wake_interval(FRI(18, 30), o()), 60)
eq("interval: evening 22:59", P.wake_interval(FRI(22, 59), o()), 60)
eq("interval: 23:00 night (no wake)", P.wake_interval(FRI(23), o()), nil)
eq("interval: 03:00 night", P.wake_interval(SAT(3), o()), nil)
eq("interval: 07:29 night", P.wake_interval(FRI(7, 29), o()), nil)
eq("interval: weekend day 60", P.wake_interval(SAT(10), o()), 60)
eq("interval: default setting is the schedule", P.wake_interval(FRI(10), o()), 30)
eq("interval: wake = 900 s -> 15 min, any hour", P.wake_interval(FRI(3), o({ wake = 900 })), 15)
eq("interval: wake = 1800 s -> 30 min", P.wake_interval(FRI(3), o({ wake = 1800 })), 30)
eq("interval: wake = 3600 s -> 60 min", P.wake_interval(FRI(10), o({ wake = 3600 })), 60)
eq("interval: wake = 7200 s -> 120 min", P.wake_interval(FRI(10), o({ wake = 7200 })), 120)
eq("interval: wake = schedule, day", P.wake_interval(FRI(10), o({ wake = "schedule" })), 30)
eq("interval: wake = schedule, night", P.wake_interval(FRI(23, 30), o({ wake = "schedule" })), nil)
eq("interval: wake = never", P.wake_interval(FRI(10), o({ wake = "never" })), nil)
eq("band: day", P.band(FRI(10), nil, D).from, "07:30")

-- next wake-up
eq("next: day +30 min", P.next_wakeup(FRI(10), o()), FRI(10, 30))
eq("next: evening +60", P.next_wakeup(FRI(19), o()), FRI(20))
eq("next: crossing day->evening keeps +30", P.next_wakeup(FRI(18, 15), o()), FRI(18, 45))
eq("next: evening landing in night -> 07:30 next day", P.next_wakeup(FRI(22, 30), o()), SAT(7, 30))
eq("next: inside night -> 07:30", P.next_wakeup(SAT(2), o()), SAT(7, 30))
eq("next: Friday night -> Saturday 07:30 (weekend band wakes too)", P.next_wakeup(FRI(23, 30), o()), SAT(7, 30))
eq("next: Sunday 22:30 -> Monday 07:30", P.next_wakeup(T.utc(2026, 10, 18, 22, 30), o()), MON(7, 30))
eq("next: weekend +60", P.next_wakeup(SAT(10), o()), SAT(11))
eq("next: wake 900 = now + 15 min, even at night", P.next_wakeup(FRI(23, 30), o({ wake = 900 })), FRI(23, 45))
eq("next: wake 1800", P.next_wakeup(FRI(10), o({ wake = 1800 })), FRI(10, 30))
eq("next: wake 3600 ignores the bands", P.next_wakeup(FRI(22, 30), o({ wake = 3600 })), FRI(23, 30))
eq("next: wake 7200", P.next_wakeup(SAT(1), o({ wake = 7200 })), SAT(3))
eq("next: wake schedule = bands", P.next_wakeup(FRI(22, 30), o({ wake = "schedule" })), SAT(7, 30))
eq("next: wake never -> nil", P.next_wakeup(FRI(10), o({ wake = "never" })), nil)
eq("next: never-waking bands -> nil", P.next_wakeup(FRI(10), o({ bands = { { from = "00:00", to = "12:00", every = nil }, { from = "12:00", to = "00:00", every = nil } } })), nil)

-- R-P10
eq("rtc: seconds to target", P.rtc_seconds(1000, 910), 90)
eq("rtc: never below 1", P.rtc_seconds(1000, 1005), 1)
eq("rtc: repeat every 2 s", P.RTC_REPEAT, 2)

-- R-P4 idle
-- R-P4 idle sleep: mode x plugged x idle due
local M_ = { "always", "battery", "never" }
local due_expect = {   -- [mode][plugged] -> fires once the idle time is due
    always = { [false] = true, [true] = true },
    battery = { [false] = true, [true] = false },
    never = { [false] = false, [true] = false },
}
for _, mode in ipairs(M_) do
    for _, plugged in ipairs({ false, true }) do
        local tag = ("idle %s, %s"):format(mode, plugged and "plugged" or "unplugged")
        eq(tag .. ", due", P.idle_due(0, 300, 5, mode, plugged), due_expect[mode][plugged])
        check(tag .. ", not due yet", not P.idle_due(0, 299, 5, mode, plugged))
        eq(tag .. ", plugged as a function", P.idle_due(0, 300, 5, mode, function() return plugged end), due_expect[mode][plugged])
    end
end
check("idle: no touch info", not P.idle_due(nil, 99999, 5, "always", false))
check("idle: no minutes", not P.idle_due(0, 99999, nil, "always", false) and not P.idle_due(0, 99999, 0, "always", false))
check("idle: unknown mode reads as battery", P.idle_due(0, 300, 5, "x", false) and not P.idle_due(0, 300, 5, "x", true))
check("idle: nil mode reads as battery", P.idle_due(0, 300, 5, nil, false) and not P.idle_due(0, 300, 5, nil, true))
-- cheap: the plugged state is asked for only when the answer needs it (mode "battery", idle time due)
local asked = 0
local ask = function() asked = asked + 1; return false end
P.idle_due(0, 100, 5, "battery", ask); P.idle_due(0, 300, 5, "always", ask); P.idle_due(0, 300, 5, "never", ask)
eq("idle: no plugged lookups unless battery mode and due", asked, 0)
P.idle_due(0, 300, 5, "battery", ask)
eq("idle: one plugged lookup when due in battery mode", asked, 1)
eq("idle: choices are 2/5/10/15", table.concat(P.IDLE, ","), "2,5,10,15")
eq("idle: default mode is battery", P.DEFAULT_IDLE_MODE, "battery")
check("expediente is gone", P.WORKDAY == nil and P.in_expediente == nil)

-- R-P11 / R-P12 classification
eq("wake: button (state active)", P.classify_wakeup({ powerd_state = "active", target = 1000, now = 1000 }), "button")
eq("wake: scheduled (6 s early, R-P10)", P.classify_wakeup({ powerd_state = "screenSaver", target = 1000, now = 994 }), "scheduled")
eq("wake: unscheduled (06:10 powerd)", P.classify_wakeup({ powerd_state = "screenSaver", target = FRI(7, 30), now = FRI(6, 10) }), "unscheduled")
eq("wake: no target -> unscheduled", P.classify_wakeup({ powerd_state = "suspended", now = 5 }), "unscheduled")
eq("wake: reason button", P.classify_wakeup({ reason = "button", now = 1 }), "button")

-- R-S4
eq("sleep bar", P.sleep_bar(FRI(10), FRI(10, 30), D), "Repouso · atualizado 10:00 · próxima 10:30")
eq("sleep bar never wakes", P.sleep_bar(FRI(23), nil, D), "Repouso · atualizado 23:00")
same("choices", { P.WAKE, P.IDLE }, { { 900, 1800, 3600, 7200, "schedule", "never" }, { 2, 5, 10, 15 } })
