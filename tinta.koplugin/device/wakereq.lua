-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (C) 2026 Tinta contributors
-- Wake requests (spec 11.7), pure: an app asks the Tinta to be awake at a time (ctx.wake_at(ts), the Timer's end).
-- Awake, ui/host schedules a UIManager timer for the earliest one; asleep, device/sleep.lua takes the earliest as
-- an RTC target when it comes before the schedule's own, and the wake-up plan refreshes the apps whose request is
-- due. A request fires once: whoever consumes it removes it. One request per app; setting again replaces it.
local M = {}

M.SLACK = 30            -- s: a wake-up this much before a request still counts as its wake-up (RTC rounding)

function M.new() return { at = {} } end

-- ts = nil (or not a positive number) removes the app's request
function M.set(r, id, ts)
    if type(ts) == "number" and ts > 0 then r.at[id] = ts else r.at[id] = nil end
end

function M.get(r, id) return r.at[id] end

-- earliest request strictly after `from`: ts, id (nil when none)
function M.next(r, from)
    local best, who
    for id, ts in pairs(r.at) do
        if ts > from and (not best or ts < best or (ts == best and id < who)) then best, who = ts, id end
    end
    return best, who
end

-- earliest request of all, past ones included
function M.earliest(r) return M.next(r, -math.huge) end

-- ids whose request is due at `t` (ts <= t + slack), sorted
function M.due(r, t, slack)
    local out = {}
    for id, ts in pairs(r.at) do
        if ts <= t + (slack or 0) then out[#out + 1] = id end
    end
    table.sort(out)
    return out
end

-- removes the requests of `ids`
function M.consume(r, ids)
    for _, id in ipairs(ids) do r.at[id] = nil end
end

return M
