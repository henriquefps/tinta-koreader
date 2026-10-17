-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (C) 2026 Tinta contributors
-- styles, date text in pt/en for every weekday and month, hand angles, wake-up line
local T = ...
local check, eq = T.check, T.eq
local Logic = require("apps/relogio/logic")
local D = T.utc
local Lpt, Len = T.LL("pt"), T.LL("en")

-- styles
eq("styles: list", table.concat(Logic.STYLES, ","), "digital,data,analogico,minimo")
eq("styles: default is the first", Logic.DEFAULT_STYLE, Logic.STYLES[1])
for _, s in ipairs(Logic.STYLES) do check("styles: valid " .. s, Logic.valid_style(s)) end
check("styles: junk is not valid", not Logic.valid_style("roman") and not Logic.valid_style(nil))
eq("styles: unknown -> default", Logic.style_or_default("roman"), "digital")
eq("styles: next wraps", Logic.next_style("minimo"), "digital")
eq("styles: next", Logic.next_style("digital"), "data")
eq("styles: next of unknown", Logic.next_style(nil), "digital")
for _, s in ipairs(Logic.STYLES) do eq("styles: 1x1 is always HH:MM (" .. s .. ")", Logic.style_for(s, "1x1"), "digital") end
eq("styles: analog keeps its style at 2x2", Logic.style_for("analogico", "2x2"), "analogico")
eq("styles: unknown at 4x4 -> default", Logic.style_for("zzz", "4x4"), "digital")

-- HH:MM
eq("hm: padded", Logic.hm(T.ts(2026, 10, 16, 7, 5), D), "07:05")
eq("hm: midnight", Logic.hm(T.ts(2026, 10, 16, 0, 0), D), "00:00")
eq("hm: 23:59", Logic.hm(T.ts(2026, 10, 16, 23, 59), D), "23:59")

-- the example of the brief
eq("date pt: sexta, 16 de outubro", Logic.date_text(Lpt, T.ts(2026, 10, 16, 10, 0), D), "sexta, 16 de outubro")
eq("date en: Friday, October 16", Logic.date_text(Len, T.ts(2026, 10, 16, 10, 0), D), "Friday, October 16")

-- every weekday: 2026-10-11 is a Sunday
local pt_wd = { "domingo", "segunda", "terça", "quarta", "quinta", "sexta", "sábado" }
local en_wd = { "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday" }
for i = 0, 6 do
    local t = T.ts(2026, 10, 11 + i, 12, 0)
    local a = Logic.date_lines(Lpt, t, D)
    eq("weekday pt " .. pt_wd[i + 1], a, pt_wd[i + 1])
    eq("weekday en " .. en_wd[i + 1], (Logic.date_lines(Len, t, D)), en_wd[i + 1])
    check("weekday pt in the full text: " .. pt_wd[i + 1], Logic.date_text(Lpt, t, D):find("^" .. pt_wd[i + 1] .. ", ") ~= nil)
end

-- every month
local pt_mo = { "janeiro", "fevereiro", "março", "abril", "maio", "junho", "julho", "agosto", "setembro", "outubro", "novembro", "dezembro" }
local en_mo = { "January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December" }
for m = 1, 12 do
    local t = T.ts(2026, m, 5, 12, 0)
    local _, b = Logic.date_lines(Lpt, t, D)
    eq("month pt " .. pt_mo[m], b, "5 de " .. pt_mo[m])
    local _, e = Logic.date_lines(Len, t, D)
    eq("month en " .. en_mo[m], e, en_mo[m] .. " 5")
    check("month in the full text pt " .. m, Logic.date_text(Lpt, t, D):find(pt_mo[m], 1, true) ~= nil)
    check("month in the full text en " .. m, Logic.date_text(Len, t, D):find(en_mo[m], 1, true) ~= nil)
end
-- edges of the year, leap day
eq("date: new year", Logic.date_text(Lpt, T.ts(2027, 1, 1, 0, 0), D), "sexta, 1 de janeiro")
eq("date: last day", Logic.date_text(Lpt, T.ts(2026, 12, 31, 23, 59), D), "quinta, 31 de dezembro")
eq("date: leap day", Logic.date_text(Lpt, T.ts(2028, 2, 29, 12, 0), D), "terça, 29 de fevereiro")

-- hand angles (0 = 12 o'clock, clockwise)
local function hands(h, m) local a = Logic.hands(h, m); return a.hour, a.min end
local function hh(name, h, m, want_h, want_m)
    local gh, gm = hands(h, m)
    T.near(name .. " hour hand", gh, want_h, 1e-9)
    T.near(name .. " minute hand", gm, want_m, 1e-9)
end
hh("hands 12:00", 12, 0, 0, 0)
hh("hands 00:00", 0, 0, 0, 0)
hh("hands 3:00", 3, 0, 90, 0)
hh("hands 6:00", 6, 0, 180, 0)
hh("hands 9:00", 9, 0, 270, 0)
hh("hands 15:00 = 3:00", 15, 0, 90, 0)
hh("hands 12:30", 12, 30, 15, 180)
hh("hands 10:10", 10, 10, 305, 60)
hh("hands 23:59", 23, 59, 359.5, 354)
hh("hands 6:15", 6, 15, 187.5, 90)
local at = Logic.hands_at(T.ts(2026, 10, 16, 14, 20), D)
T.near("hands_at hour", at.hour, 70, 1e-9)
T.near("hands_at minute", at.min, 120, 1e-9)

-- next wake-up line
local now = T.ts(2026, 10, 16, 23, 10)
eq("wake: same day", Logic.wake_text(Lpt, T.ts(2026, 10, 16, 23, 40), now, D), "próximo despertar 23:40")
eq("wake: next day shows the weekday", Logic.wake_text(Lpt, T.ts(2026, 10, 19, 7, 30), now, D), "próximo despertar segunda 07:30")
eq("wake: en", Logic.wake_text(Len, T.ts(2026, 10, 17, 7, 30), now, D), "next wake-up Saturday 07:30")
eq("wake: never", Logic.wake_text(Lpt, nil, now, D), "sem despertar agendado")
eq("wake: same yday, other year", Logic.wake_text(Lpt, T.ts(2027, 10, 16, 7, 30), now, D), "próximo despertar sábado 07:30")
