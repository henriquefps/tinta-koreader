-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (C) 2026 Tinta contributors
-- Relógio app: pure logic (R-A1: no KOReader require). Clock styles, the date text (pt/en), the hand angles of
-- the analog face and the next wake-up line. Times are timestamps; `date` is os.date or a test replacement.
local M = {}

M.STYLES = { "digital", "data", "analogico", "minimo" }
M.DEFAULT_STYLE = "digital"

function M.valid_style(s)
    for _, v in ipairs(M.STYLES) do if v == s then return true end end
    return false
end

function M.style_or_default(s) return M.valid_style(s) and s or M.DEFAULT_STYLE end

-- the style after `s` (wraps); an unknown value gives the default
function M.next_style(s)
    for i, v in ipairs(M.STYLES) do if v == s then return M.STYLES[i % #M.STYLES + 1] end end
    return M.DEFAULT_STYLE
end

-- the style actually drawn in a widget size: 1x1 is always HH:MM
function M.style_for(style, size)
    if size == "1x1" then return "digital" end
    return M.style_or_default(style)
end

-- "HH:MM"
function M.hm(t, date)
    local d = (date or os.date)("*t", t)
    return string.format("%02d:%02d", d.hour, d.min)
end

-- "sexta, 16 de outubro" (pt) | "Friday, October 16" (en); L = ctx.i18n.t
function M.date_text(L, t, date)
    local d = (date or os.date)("*t", t)
    local wd, mo = L("wd" .. d.wday), L("mo" .. d.month)
    if L("date_order") == "md" then return L("date_full", wd, mo, d.day) end
    return L("date_full", wd, d.day, mo)
end

-- the two lines of the narrow widget: "sexta" / "16 de outubro"
function M.date_lines(L, t, date)
    local d = (date or os.date)("*t", t)
    local wd, mo = L("wd" .. d.wday), L("mo" .. d.month)
    if L("date_order") == "md" then return wd, L("date_day", mo, d.day) end
    return wd, L("date_day", d.day, mo)
end

-- hand angles in degrees, 0 = 12 o'clock, clockwise: { hour, min }
function M.hands(hour, min)
    return { hour = ((hour % 12) * 60 + min) / 720 * 360, min = min * 6 }
end

function M.hands_at(t, date)
    local d = (date or os.date)("*t", t)
    return M.hands(d.hour, d.min)
end

-- "próximo despertar 07:30" (same day) | "próximo despertar segunda 07:30" | "sem despertar agendado"
function M.wake_text(L, next_at, now, date)
    if not next_at then return L("wake_none") end
    date = date or os.date
    local a, b = date("*t", next_at), date("*t", now)
    local hm = M.hm(next_at, date)
    if a.yday == b.yday and a.year == b.year then return L("wake_today", hm) end
    return L("wake_day", L("wd" .. a.wday), hm)
end

return M
