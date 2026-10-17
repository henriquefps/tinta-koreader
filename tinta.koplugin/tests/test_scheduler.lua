-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (C) 2026 Tinta contributors
local T = ...
local S = require("core/scheduler")
local eq, same, check = T.eq, T.same, T.check
local D = T.date
local FRI = function(h, m) return T.utc(2026, 10, 16, h, m or 0) end   -- Friday
local SAT = function(h, m) return T.utc(2026, 10, 17, h, m or 0) end
local opts = function(o) o = o or {}; o.date = D; return o end

-- R-U1 intervals
same("intervals R-U1", S.INTERVALS, { 30, 60, 300, 900, 1800, 3600, 0 })
eq("cycle 30 -> 60", S.cycle_interval(30), 60)
eq("cycle 3600 -> manual", S.cycle_interval(3600), 0)
eq("cycle manual -> 30", S.cycle_interval(0), 30)
eq("cycle unknown -> 30", S.cycle_interval(42), 30)
check("valid_interval", S.valid_interval(300) and not S.valid_interval(301))

-- R-U2 window
local PW = { from = "07:30", to = "18:30", weekdays = true }
check("window: nil = always", S.in_window(nil, FRI(3), D))
check("window: inside", S.in_window(PW, FRI(10), D))
check("window: start inclusive", S.in_window(PW, FRI(7, 30), D))
check("window: end inclusive", S.in_window(PW, FRI(18, 30), D))
check("window: before", not S.in_window(PW, FRI(7, 29), D))
check("window: after", not S.in_window(PW, FRI(18, 31), D))
check("window: saturday out (weekdays)", not S.in_window(PW, SAT(10), D))
check("window: saturday in without weekdays", S.in_window({ from = "07:30", to = "18:30" }, SAT(10), D))
check("window: wraps midnight", S.in_window({ from = "22:00", to = "02:00" }, FRI(23), D) and S.in_window({ from = "22:00", to = "02:00" }, FRI(1), D)
    and not S.in_window({ from = "22:00", to = "02:00" }, FRI(12), D))
check("window: own in_window wins", not S.in_window({ from = "00:00", to = "23:59", in_window = function() return false end }, FRI(10), D))
check("window: own in_window error = inside", S.in_window({ in_window = function() error("x") end }, FRI(10), D))

-- R-U3 quiet hours
check("quiet: 23:00 quiet", S.quiet_now(nil, FRI(23), D))
check("quiet: 03:00 quiet", S.quiet_now(nil, FRI(3), D))
check("quiet: 06:59 quiet", S.quiet_now(nil, FRI(6, 59), D))
check("quiet: 07:00 not quiet (end exclusive)", not S.quiet_now(nil, FRI(7), D))
check("quiet: 22:59 not quiet", not S.quiet_now(nil, FRI(22, 59), D))
check("quiet: disabled", not S.quiet_now({ enabled = false, from = "23:00", to = "07:00" }, FRI(3), D))
check("quiet: custom range", S.quiet_now({ enabled = true, from = "12:00", to = "13:00" }, FRI(12, 30), D))

-- R-S5 failed
check("failed: err after ok", S.failed({ last_ok = 1, last_err = 2 }))
check("failed: err without ok", S.failed({ last_err = 2 }))
check("failed: ok after err", not S.failed({ last_ok = 3, last_err = 2 }))
check("failed: nothing", not S.failed({}))

-- R-U4 tick
local now = FRI(10)
local function apps()
    return {
        { id = "alfa", interval = 60, net = true, last_ok = now - 60 },               -- due
        { id = "beta", interval = 1800, net = true, window = PW, last_ok = now - 1700 },   -- due in 100 s -> batched
        { id = "bateria", interval = 60, net = false, last_ok = now - 20 },           -- due in 40 s -> batched
        { id = "x", interval = 900, net = true, last_ok = now - 300 },                -- due in 600 s -> not
        { id = "manual", interval = 0, net = true },                                  -- manual: never auto
        { id = "sistema", interval = nil },                                           -- no refresh
    }
end
local ids, nnet = S.pick(apps(), now, opts())
same("pick: due + next 2 min", ids, { "alfa", "beta", "bateria" })
eq("pick: network apps in batch", nnet, 2)
local a = apps(); a[1].last_ok = now - 30
ids = S.pick(a, now, opts())
same("pick: nothing due -> empty (even if some soon)", ids, {})
a = apps(); a[1].last_ok = nil
same("pick: never refreshed = due", S.pick(a, now, opts()), { "alfa", "beta", "bateria" })
a = apps(); a[1].last_ok, a[1].last_err = now - 300, now - 30
same("pick: last attempt counts (failed 30 s ago)", S.pick(a, now, opts()), {})
a = apps(); a[1].busy = true; a[3].last_ok = now - 60
same("pick: busy app skipped (R-U8)", S.pick(a, now, opts()), { "bateria", "beta" })
a = apps(); a[1].disabled = true; a[3].last_ok = now - 60
same("pick: disabled app skipped (R-E4)", S.pick(a, now, opts()), { "bateria", "beta" })
same("pick: exact boundary due (last + interval == now)", S.pick({ { id = "o", interval = 60, last_ok = now - 60 } }, now, opts()), { "o" })
same("pick: 2-min boundary batched", S.pick({ { id = "o", interval = 60, last_ok = now - 60 }, { id = "p", interval = 300, last_ok = now - 180 } }, now, opts()), { "o", "p" })
same("pick: past 2 min not batched", S.pick({ { id = "o", interval = 60, last_ok = now - 60 }, { id = "p", interval = 300, last_ok = now - 179 } }, now, opts()), { "o" })
same("pick: custom ahead", S.pick({ { id = "o", interval = 60, last_ok = now - 60 }, { id = "p", interval = 300, last_ok = now - 179 } }, now, opts({ ahead = 300 })), { "o", "p" })
-- window
same("pick: out of window skipped", S.pick({ { id = "beta", interval = 60, window = PW, last_ok = SAT(9) } }, SAT(10), opts()), {})
same("pick: in window", S.pick({ { id = "beta", interval = 60, window = PW, last_ok = FRI(9) } }, FRI(10), opts()), { "beta" })
-- quiet: network apps only
local night = FRI(23, 30)
same("pick: quiet hours skip network, local still runs", S.pick({ { id = "alfa", interval = 60, net = true, last_ok = night - 600 },
    { id = "bateria", interval = 60, net = false, last_ok = night - 600 } }, night, opts()), { "bateria" })
same("pick: quiet off", S.pick({ { id = "alfa", interval = 60, net = true, last_ok = night - 600 } }, night,
    opts({ quiet = { enabled = false } })), { "alfa" })
-- R-U5 no Wi-Fi
same("pick: no wifi skips network apps", S.pick(apps(), now, opts({ wifi = false })), {})
a = apps(); a[3].last_ok = now - 60
local ids2, nn2 = S.pick(a, now, opts({ wifi = false }))
same("pick: no wifi, local apps update", ids2, { "bateria" })
eq("pick: no wifi batch has no network apps", nn2, 0)

-- R-U7 manual
local mids, skipped = S.manual(apps(), opts())
same("manual: ignores interval/window/quiet; skips no-refresh apps", mids, { "alfa", "beta", "bateria", "x", "manual" })
same("manual: nothing skipped with wifi", skipped, {})
mids, skipped = S.manual(apps(), opts({ wifi = false }))
same("manual: no wifi -> local only", mids, { "bateria" })
same("manual: no wifi -> network skipped (toast)", skipped, { "alfa", "beta", "x", "manual" })
mids = S.manual({ { id = "o", interval = 60, net = true, disabled = true, busy = true } }, opts())
same("manual: includes disabled and busy (registry queues)", mids, { "o" })

-- wake batch (R-P6)
local wk = {
    { id = "alfa", interval = 60, net = true, last_ok = now - 10 },
    { id = "beta", interval = 1800, net = true, window = PW, last_ok = now - 10 },
    { id = "manual", interval = 0, net = true },
    { id = "notificacoes", interval = nil },
}
same("wake: ignores interval", S.wake(wk, now, opts()), { "alfa", "beta" })
same("wake: respects window", S.wake(wk, SAT(10), opts()), { "alfa" })
same("wake: respects quiet", S.wake(wk, FRI(23, 30), opts()), {})

-- next_run
eq("next_run: last + interval", S.next_run({ interval = 60, last_ok = now - 20 }, now, opts()), now + 40)
eq("next_run: overdue -> now", S.next_run({ interval = 60, last_ok = now - 600 }, now, opts()), now)
eq("next_run: manual -> nil", S.next_run({ interval = 0 }, now, opts()), nil)
eq("next_run: no refresh -> nil", S.next_run({ interval = nil }, now, opts()), nil)
eq("next_run: disabled -> nil", S.next_run({ interval = 60, disabled = true }, now, opts()), nil)
eq("next_run: out of window -> next opening (Mon 07:30)", S.next_run({ interval = 1800, window = PW, last_ok = FRI(18, 20) }, FRI(18, 40), opts()),
    T.utc(2026, 10, 19, 7, 30))
eq("next_run: quiet -> 07:00 for network", S.next_run({ interval = 60, net = true, last_ok = FRI(23) }, FRI(23, 10), opts()), T.utc(2026, 10, 17, 7, 0))
eq("next_run: quiet does not affect local", S.next_run({ interval = 60, net = false, last_ok = FRI(23) }, FRI(23, 10), opts()), FRI(23, 10))
eq("next_run: never allowed -> nil", S.next_run({ interval = 60, window = { in_window = function() return false end } }, now, opts()), nil)

-- status (footer/header)
eq("status: none", S.status({ interval = nil }, now, opts()).kind, "none")
eq("status: busy", S.status({ interval = 60, busy = true, last_err = now }, now, opts()).kind, "busy")
eq("status: error (R-E4)", S.status({ interval = 60, disabled = true }, now, opts()).kind, "error")
eq("status: failed (R-S5)", S.status({ interval = 60, last_ok = now - 600, last_err = now - 10 }, now, opts()).kind, "failed")
eq("status: ok", S.status({ interval = 60, last_ok = now - 10 }, now, opts()).kind, "ok")
eq("status: manual app is ok", S.status({ interval = 0, last_ok = now - 10, window = PW }, SAT(10), opts()).kind, "ok")
local stp = S.status({ interval = 1800, window = PW, last_ok = FRI(18) }, FRI(19), opts())
eq("status: out of window paused", stp.kind, "paused")
eq("status: resume = next opening", stp.resume, "07:30")
local stq = S.status({ interval = 60, net = true, last_ok = FRI(23) }, FRI(23, 30), opts())
eq("status: quiet paused for network", stq.kind, "paused")
eq("status: quiet resume 07:00", stq.resume, "07:00")
eq("status: quiet local ok", S.status({ interval = 60, net = false, last_ok = FRI(23, 29) }, FRI(23, 30), opts()).kind, "ok")
eq("status: carries interval", S.status({ interval = 300, last_ok = now }, now, opts()).interval, 300)

-- next_run is cheap: coarse steps, then minutes (each check can run the app's in_window, Beta reads its cache)
do
    local calls = 0
    local win = { from = "07:30", to = "18:30", weekdays = true }
    win.in_window = function(t) calls = calls + 1; return S.in_window({ from = "07:30", to = "18:30", weekdays = true }, t, D) end
    local t = S.next_run({ interval = 60, last_ok = FRI(20) - 60, window = win }, FRI(20, 7), opts())
    eq("next_run: Friday night -> Monday 07:30", t, T.utc(2026, 10, 19, 7, 30))
    check("next_run: few in_window calls (" .. calls .. ")", calls < 600)
    local t2 = S.next_run({ interval = 60, last_ok = FRI(6) - 60, window = { from = "07:30", to = "18:30" } }, FRI(6, 59), opts())
    eq("next_run: exact minute after a coarse step", t2, FRI(7, 30))
end
