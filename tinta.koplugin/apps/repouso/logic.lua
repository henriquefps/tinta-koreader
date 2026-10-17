-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (C) 2026 Tinta contributors
-- Repouso app: pure logic (R-A1: no KOReader require). The values and texts of the sleep controls. The state
-- itself is the Tinta settings "idle_mode" and "idle_sleep" (Sistema → Repouso); nothing is kept here.
local M = {}

M.IDLE = { 2, 5, 10, 15 }                          -- same list as the tinta's CHOICES.idle_sleep (the host's list wins when given)
M.MODES = { "always", "battery", "never" }         -- same as CHOICES.idle_mode
M.DEFAULT_MODE = "battery"

-- the value after `cur` in `values` (wraps); an unknown value gives the first
function M.cycle(values, cur)
    values = values or M.IDLE
    for i, v in ipairs(values) do if v == cur then return values[i % #values + 1] end end
    return values[1]
end

-- the mode as saved: anything unknown (or never saved) reads as the default
function M.mode(v)
    for _, m in ipairs(M.MODES) do if m == v then return m end end
    return M.DEFAULT_MODE
end

-- the minutes row/button only makes sense while the Kindle can sleep by itself
function M.sleeps_alone(mode) return M.mode(mode) ~= "never" end

-- "sempre" | "só na bateria" | "nunca" (screen); "sempre" | "bateria" | "nunca" (widgets, narrow)
function M.mode_text(L, mode) return L("mode_" .. M.mode(mode)) end
function M.mode_short(L, mode) return L("short_" .. M.mode(mode)) end

-- "5 min"; "–" when the mode is "nunca" (no minutes to show)
function M.idle_text(L, idle, mode)
    if not M.sleeps_alone(mode) or not idle or idle <= 0 then return L("dash") end
    return L("n_min", idle)
end

-- the state shown by the 2x2 widget: two { label, value } lines
function M.lines(L, mode, idle)
    return { { L("idle_short"), M.mode_short(L, mode) }, { L("after_short"), M.idle_text(L, idle, mode) } }
end

-- sub line of the mode row of the screen
function M.mode_sub(L, mode) return L("mode_sub_" .. M.mode(mode)) end

return M
