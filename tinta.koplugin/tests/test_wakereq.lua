-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (C) 2026 Tinta contributors
-- device/wakereq.lua (11.7): per-app wake requests, earliest after a time, due ones, consuming
local T = ...
local W = require("device/wakereq")
local eq, check = T.eq, T.check

local r = W.new()
eq("empty: no next", W.next(r, 0), nil)
eq("empty: no earliest", W.earliest(r), nil)
W.set(r, "timer", 1000)
W.set(r, "other", 500)
eq("next after 0 is the earliest", (W.next(r, 0)), 500)
eq("next names the app", select(2, W.next(r, 0)), "other")
eq("next after 500 skips it (strictly after)", (W.next(r, 500)), 1000)
eq("next after the last is nil", W.next(r, 1000), nil)
eq("earliest includes the past", (W.earliest(r)), 500)
W.set(r, "timer", 900)
eq("setting again replaces", W.get(r, "timer"), 900)
eq("due at 500 with no slack", table.concat(W.due(r, 500, 0), ","), "other")
eq("due with slack", table.concat(W.due(r, 480, W.SLACK), ","), "other")
eq("due sorted", table.concat(W.due(r, 2000, 0), ","), "other,timer")
W.consume(r, { "other" })
eq("consumed is gone", W.get(r, "other"), nil)
W.set(r, "timer", nil)
eq("nil cancels", W.get(r, "timer"), nil)
W.set(r, "timer", "x")
eq("junk is a cancel", W.get(r, "timer"), nil)
W.set(r, "timer", -5)
eq("non positive is a cancel", W.get(r, "timer"), nil)
