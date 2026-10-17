-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (C) 2026 Tinta contributors
-- Text formatting shared by the core and the apps: hm, ago, every, eta, UTF-8 truncation, the widget footer
-- (R-W4) and the app header (6.4). Pure Lua (R-A1). Functions that need local time take an optional `date`
-- function with the signature of os.date (default os.date); tests pass Format.utc_date.
local I18n = require("core/i18n")

local M = {}

local function T(...) return I18n.t(...) end

-- os.date replacement that reads timestamps as UTC (for tests and for fixed-offset clocks).
function M.utc_date(fmt, t)
    fmt = fmt or "%c"
    if fmt:sub(1, 1) == "!" then return os.date(fmt, t) end
    return os.date("!" .. fmt, t)
end

-- "HH:MM" of a timestamp in local time.
function M.hm(ts, date)
    date = date or os.date
    local d = date("*t", ts)
    return string.format("%02d:%02d", d.hour, d.min)
end

-- Minutes since local midnight.
function M.minute_of_day(ts, date)
    local d = (date or os.date)("*t", ts)
    return d.hour * 60 + d.min
end

-- "07:30" -> 450; nil for anything that is not a valid 24 h time.
function M.parse_hm(s)
    if type(s) ~= "string" then return nil end
    local h, m = s:match("^(%d%d?):(%d%d)$")
    h, m = tonumber(h), tonumber(m)
    if not h or h > 23 or m > 59 then return nil end
    return h * 60 + m
end

function M.hm_from_minutes(min)
    min = math.floor(min) % 1440
    return string.format("%02d:%02d", math.floor(min / 60), min % 60)
end

-- "agora", "há 3 min", "há 2 h", "há 3 d"; "" without a timestamp.
function M.ago(ts, now)
    if ts == nil then return "" end
    local s = (now or os.time()) - ts
    if s < 60 then return T("ago_now") end
    if s < 3600 then return T("ago_min", math.floor(s / 60)) end
    if s < 86400 then return T("ago_h", math.floor(s / 3600)) end
    return T("ago_d", math.floor(s / 86400))
end

-- "a cada 1 min", "manual" (0); "" for nil (apps without refresh).
function M.every(sec)
    if sec == nil then return "" end
    if sec == 0 then return T("every_manual") end
    if sec < 60 then return T("every_s", sec) end
    if sec < 3600 then return T("every_min", math.floor(sec / 60)) end
    return T("every_h", math.floor(sec / 3600))
end

-- Same format as the current plugin: ~25min (rounded to 5, at least 5), ~4h20, ~12h (10 h or more).
function M.eta(hours)
    if hours == nil or hours ~= hours or hours < 0 then return nil end
    local min = math.floor(hours * 60 + 0.5)
    if min < 60 then return "~" .. math.max(5, math.floor(min / 5 + 0.5) * 5) .. "min" end
    local h, m = math.floor(min / 60), min % 60
    if h >= 10 then return "~" .. h .. "h" end
    return string.format("~%dh%02d", h, m)
end

-- Status bar battery text (R-S1): "82% · ~17h", "⚡ 82% · ~40min"; the estimate is optional.
function M.battery(pct, charging, eta_text)
    local s = tostring(math.floor((pct or 0) + 0.5)) .. "%"
    if eta_text and eta_text ~= "" then s = s .. " · " .. eta_text end
    if charging then s = "⚡ " .. s end
    return s
end

---------------------------------------------------------------- UTF-8

-- Number of code points (invalid bytes count as one each).
function M.utf8_len(s)
    local n = 0
    for _ in tostring(s):gmatch("[^\128-\191][\128-\191]*") do n = n + 1 end
    return n
end

-- First `n` code points.
function M.utf8_head(s, n)
    s = tostring(s)
    if n <= 0 then return "" end
    local count, cut = 0, #s
    for pos in s:gmatch("()[^\128-\191]") do
        count = count + 1
        if count == n + 1 then cut = pos - 1; break end
    end
    return s:sub(1, cut)
end

-- Cuts to at most `max` code points, ending with "…" when cut (R-W1). Trailing spaces before "…" are removed.
function M.truncate(s, max)
    s = tostring(s or "")
    if max == nil or M.utf8_len(s) <= max then return s end
    if max <= 1 then return "…" end
    return (M.utf8_head(s, max - 1):gsub("%s+$", "")) .. "…"
end

---------------------------------------------------------------- windows, footer, header

-- "dias úteis 07:30–18:30" / "07:30–18:30" / "" without a window.
function M.window_text(window)
    if not window or not window.from or not window.to then return "" end
    return T(window.weekdays and "window_weekdays" or "window_all", window.from, window.to)
end

-- Widget footer (R-W4) from a status table (scheduler.status): returns a list of 1 or 2 strings, left to right.
-- Wide (4 columns): "idade · intervalo", "sem resposta · idade", "idade · volta 07:30", "atualizando…".
-- Narrow (2 columns): only the most important: atualizando, sem resposta, volta HH:MM, idade.
function M.footer(st, narrow, now)
    if st.kind == "none" then return { T("footer_settings") } end
    if st.kind == "busy" then return { T("busy") } end
    local age = M.ago(st.last_ok, now)
    if st.kind == "failed" then
        if narrow then return { T("no_response") } end
        return { T("no_response"), age }
    end
    if st.kind == "paused" then
        local back = T("resume_at", st.resume or "")
        if narrow then return { back } end
        return { age, back }
    end
    if st.kind == "error" then
        if narrow then return { T("app_error") } end
        return { T("app_error"), age }
    end
    if narrow then return { age } end
    return { age, M.every(st.interval) }
end

-- Right side of the app header (6.4): footer text joined, "pausado até HH:MM" out of the window, "erro na app"
-- (R-E4), "sem resposta · último dado há N min" (R-S5).
function M.header(st, now)
    if st.kind == "error" then return T("app_error") end
    if st.kind == "paused" then return T("paused_until", st.resume or "") end
    if st.kind == "failed" then
        if not st.last_ok then return T("no_response") end
        return T("stale_header", M.ago(st.last_ok, now))
    end
    local parts = {}
    for _, p in ipairs(M.footer(st, false, now)) do if p ~= "" then parts[#parts + 1] = p end end
    return table.concat(parts, " · ")
end

return M
