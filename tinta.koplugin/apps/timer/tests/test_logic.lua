-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (C) 2026 Tinta contributors
-- state machine, minute text, notification (apps/timer/logic.lua)
local T = ...
local check, eq = T.check, T.eq
local L = require("apps/timer/logic")
local t = T.L
local N = 1792000000

-- parse_minutes
eq("parse 25", L.parse_minutes("25"), 25)
eq("parse with spaces and unit", L.parse_minutes(" 45 min "), 45)
eq("parse number", L.parse_minutes(7), 7)
eq("parse 0 rejected", L.parse_minutes("0"), nil)
eq("parse 601 rejected", L.parse_minutes("601"), nil)
eq("parse 600 accepted", L.parse_minutes("600"), 600)
eq("parse text rejected", L.parse_minutes("abc"), nil)
eq("parse decimal rejected", L.parse_minutes("2.5"), nil)
eq("parse negative rejected", L.parse_minutes("-5"), nil)
eq("parse nil", L.parse_minutes(nil), nil)

-- selection
local pomo = L.selection("pomo", { work_min = 30, break_min = 10 })
eq("pomo work", pomo.min, 30); eq("pomo break", pomo.brk, 10)
eq("pomo defaults", L.selection("pomo", {}).min, 25)
eq("fixed 15", L.selection("m15", {}).min, 15)
eq("fixed has no break", L.selection("m5", {}).brk, nil)
eq("custom", L.selection("custom", { custom_min = 42 }).min, 42)
eq("custom default", L.selection("custom", {}).min, L.CUSTOM_DEFAULT)

-- start / remaining / pause / resume / reset
local sel = L.selection("pomo", {})
local st = L.start(sel, N)
eq("start: running", st.mode, "running")
eq("start: end", st.end_at, N + 25 * 60)
eq("remaining", L.remaining(st, N + 600), 15 * 60)
eq("remaining never negative", L.remaining(st, N + 99999), 0)
local p = L.pause(st, N + 600)
eq("pause: paused", p.mode, "paused"); eq("pause: left", p.left, 15 * 60)
eq("paused remaining ignores the clock", L.remaining(p, N + 5000), 15 * 60)
eq("pause of a paused is a no-op", L.pause(p, N + 700), p)
local r = L.resume(p, N + 1000)
eq("resume: running", r.mode, "running"); eq("resume: new end", r.end_at, N + 1000 + 15 * 60)
local z = L.reset(r)
eq("reset: idle", z.mode, "idle"); eq("reset keeps the selection", z.sel, sel)
eq("wake_time running", L.wake_time(st), st.end_at)
eq("wake_time paused", L.wake_time(p), nil)
eq("wake_time idle", L.wake_time(z), nil)

-- is_due with the grace of the RTC wake-up
check("not due early", not L.is_due(st, st.end_at - 60))
check("due within grace", L.is_due(st, st.end_at - L.GRACE))
check("due after", L.is_due(st, st.end_at + 3000))
check("paused never due", not L.is_due(p, N + 99999))

-- finish: pomodoro focus -> break (auto), break -> idle
local nst, ev = L.finish(st, st.end_at + 3, true)
eq("finish focus: break starts", nst.kind, "break"); eq("finish focus: break running", nst.mode, "running")
eq("finish focus: break from now", nst.end_at, st.end_at + 3 + 5 * 60)
eq("event kind", ev.kind, "focus"); eq("event minutes", ev.minutes, 25)
eq("event key", ev.key, "timer:" .. st.end_at)
local nst2, ev2 = L.finish(nst, nst.end_at, true)
eq("finish break: idle", nst2.mode, "idle"); eq("break event kind", ev2.kind, "break")
local nst3 = L.finish(st, st.end_at, false)
eq("finish without auto break: idle", nst3.mode, "idle")
local plain = L.start(L.selection("m10", {}), N)
eq("finish without break preset: idle", (L.finish(plain, plain.end_at, true)).mode, "idle")
check("two runs never share a key", select(2, L.finish(plain, plain.end_at, true)).key ~= ev.key)

-- sanitize: what comes back from the store
local def = L.selection("pomo", {})
eq("sanitize nil", L.sanitize(nil, def).mode, "idle")
eq("sanitize junk", L.sanitize("x", def).mode, "idle")
eq("sanitize running", L.sanitize(st, def).mode, "running")
eq("sanitize paused", L.sanitize(p, def).mode, "paused")
eq("sanitize running without end", L.sanitize({ mode = "running", total = 60 }, def).mode, "idle")
eq("sanitize bad sel falls back", L.sanitize({ mode = "idle", sel = { min = -4 } }, def).sel, def)
eq("sanitize keeps break kind", L.sanitize({ mode = "running", kind = "break", total = 300, end_at = N }, def).kind, "break")

-- minute text
eq("minutes rounded up", L.minutes_left(61), 2)
eq("59 s is 1 min", L.minutes_left(59), 1)
eq("0 s", L.minutes_left(0), 0)
eq("text 12 min", L.left_text(12 * 60, t), "12 min")
eq("text 1 h 05", L.left_text(65 * 60, t), "1 h 05")
eq("text 60 min", L.left_text(60 * 60, t), "1 h 00")
eq("text zero", L.left_text(0, t), "fim")

-- view
local utc = function(fmt, ts) return T.utc(fmt, ts) end
local v = L.view(st, N + 600, t, utc)
eq("view running primary", v.primary, "15 min")
eq("view running number", v.number, "15")
check("view running until", v.secondary:match("^até %d%d:%d%d$") ~= nil, v.secondary)
eq("view status focus", v.status, "foco")
local vp = L.view(p, N + 9999, t, utc)
eq("view paused", vp.status, "pausado"); eq("view paused primary", vp.primary, "15 min")
local vi = L.view(z, N, t, utc)
eq("view idle primary", vi.primary, "25 min"); eq("view idle pomodoro", vi.secondary, "pomodoro 25/5"); eq("view idle number", vi.number, nil)
eq("view break status", L.view(nst, nst.end_at - 120, t, utc).status, "pausa")

-- notification
local n = L.notification(ev, t)
eq("notification title", n.title, "Tempo esgotado"); eq("notification prio", n.prio, "alta")
eq("notification key", n.key, ev.key); eq("notification body", n.body, "25 min concluídos")
eq("break notification body", L.notification(ev2, t).body, "pausa terminada")
