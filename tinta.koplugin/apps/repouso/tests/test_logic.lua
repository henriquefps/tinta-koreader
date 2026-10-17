-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (C) 2026 Tinta contributors
-- cycling values, texts and the mode logic of the sleep controls
local T = ...
local check, eq = T.check, T.eq
local Logic = require("apps/repouso/logic")
local L = T.L

eq("idle list is 2/5/10/15", table.concat(Logic.IDLE, ","), "2,5,10,15")
eq("modes", table.concat(Logic.MODES, ","), "always,battery,never")
-- the cycle walks the list and wraps
local seq, cur = {}, 15
for i = 1, 5 do cur = Logic.cycle(Logic.IDLE, cur); seq[i] = cur end
eq("cycle minutes", table.concat(seq, ","), "2,5,10,15,2")
eq("cycle: unknown value goes to the first", Logic.cycle(Logic.IDLE, 7), 2)
eq("cycle: nil goes to the first", Logic.cycle(Logic.IDLE, nil), 2)
eq("cycle: the host's list wins", Logic.cycle({ 1, 3 }, 1), 3)
eq("cycle: default list", Logic.cycle(nil, 5), 10)
seq, cur = {}, "battery"
for i = 1, 4 do cur = Logic.cycle(Logic.MODES, cur); seq[i] = cur end
eq("cycle modes", table.concat(seq, ","), "never,always,battery,never")

eq("mode: nil = battery", Logic.mode(nil), "battery")
eq("mode: unknown = battery", Logic.mode("x"), "battery")
eq("mode: never", Logic.mode("never"), "never")
check("sleeps alone: always/battery yes, never no", Logic.sleeps_alone("always") and Logic.sleeps_alone("battery") and not Logic.sleeps_alone("never") and Logic.sleeps_alone(nil))
eq("mode text pt", Logic.mode_text(L, "always") .. "/" .. Logic.mode_text(L, "battery") .. "/" .. Logic.mode_text(L, "never"), "sempre/só na bateria/nunca")
eq("mode text en", Logic.mode_text(T.LL("en"), "battery"), "on battery only")
eq("mode short", Logic.mode_short(L, "battery"), "bateria")
eq("mode sub: battery", Logic.mode_sub(L, "battery"), "não dorme com o cabo ligado")
eq("mode sub: never", Logic.mode_sub(L, "never"), "não dorme sozinho")
eq("idle text: 5", Logic.idle_text(L, 5, "always"), "5 min")
eq("idle text: 15", Logic.idle_text(L, 15, "battery"), "15 min")
eq("idle text: never mode shows a dash", Logic.idle_text(L, 5, "never"), "–")
eq("idle text: nil minutes dash", Logic.idle_text(L, nil, "always"), "–")
local lines = Logic.lines(L, "battery", 5)
eq("lines: mode", lines[1][1] .. "=" .. lines[1][2], "sozinho=bateria")
eq("lines: minutes", lines[2][1] .. "=" .. lines[2][2], "depois de=5 min")
eq("lines: never", Logic.lines(L, "never", 5)[2][2], "–")
