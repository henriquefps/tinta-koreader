-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (C) 2026 Tinta contributors
-- the pure rules
local T = ...
local L = require("apps/_modelo/logic")
T.eq("limit: default for nil", L.limit(nil), 5)
T.eq("limit: string is read", L.limit("7"), 7)
T.eq("limit: float is floored", L.limit(7.9), 7)
T.eq("limit: clamped low", L.limit(0), 1)
T.eq("limit: clamped high", L.limit(1000), 100)
T.eq("next_count: from nil", L.next_count(nil), 1)
T.eq("next_count: adds one", L.next_count(4), 5)
T.check("reached: every limit", L.reached(5, 5) and L.reached(10, 5) and not L.reached(4, 5))
T.check("reached: never at zero", not L.reached(0, 5))
local v = L.view({ count = 3, at = 100 }, 5, T.L, function(at) return "t" .. at end)
T.eq("view: primary", v.primary, "3 atualizações")
T.eq("view: secondary", v.secondary, "última às t100")
T.eq("view: before the first refresh", L.view(nil, 5, T.L, tostring).secondary, "ainda não atualizou")
