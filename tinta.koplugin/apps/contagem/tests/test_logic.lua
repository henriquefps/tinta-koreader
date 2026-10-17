-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (C) 2026 Tinta contributors
-- date arithmetic in local time (UTC-3, no DST), validation, list operations, texts
local T = ...
local check, eq = T.check, T.eq
local L = require("apps/contagem/logic")
local t = T.L

-- a clock at UTC-3: ts of the local wall time y-m-d h:mi, and the os.date-like function reading it
local function at(y, m, d, h, mi)
    return L.day_number(y, m, d) * 86400 + ((h or 0) + 3) * 3600 + (mi or 0) * 60
end
local function brt(fmt, ts) return os.date("!" .. fmt, ts - 3 * 3600) end
local function today(y, m, d, h, mi) return L.today(at(y, m, d, h, mi), brt) end
local function days(date, y, m, d, h, mi) return L.days_until(date, today(y, m, d, h, mi)) end

-- day_number
eq("epoch", L.day_number(1970, 1, 1), 0)
eq("day after the epoch", L.day_number(1970, 1, 2), 1)
eq("before the epoch", L.day_number(1969, 12, 31), -1)
eq("2000-03-01 (leap century)", L.day_number(2000, 3, 1) - L.day_number(2000, 2, 28), 2)
eq("1900 is not leap", L.day_number(1900, 3, 1) - L.day_number(1900, 2, 28), 1)
eq("known day number of 2026-10-16", L.day_number(2026, 10, 16), 20742)
check("leap years", L.leap(2024) and not L.leap(2025) and L.leap(2000) and not L.leap(2100))
eq("february leap", L.days_in_month(2024, 2), 29); eq("february", L.days_in_month(2026, 2), 28)
eq("april", L.days_in_month(2026, 4), 30); eq("december", L.days_in_month(2026, 12), 31)

-- parse_date
eq("parse ok", (L.parse_date("2026-12-25")), "2026-12-25")
eq("parse pads", (L.parse_date("2026-1-5")), "2026-01-05")
eq("parse trims", (L.parse_date(" 2026-12-25 ")), "2026-12-25")
eq("parse returns parts", select(3, L.parse_date("2026-12-25")), 12)
eq("parse leap day", (L.parse_date("2028-02-29")), "2028-02-29")
eq("parse non-leap 29 feb", select(2, L.parse_date("2026-02-29")), "range")
eq("parse month 13", select(2, L.parse_date("2026-13-01")), "range")
eq("parse day 31 of april", select(2, L.parse_date("2026-04-31")), "range")
eq("parse day 0", select(2, L.parse_date("2026-05-00")), "range")
eq("parse far past", select(2, L.parse_date("1800-01-01")), "range")
eq("parse dd/mm/yyyy is a format error", select(2, L.parse_date("25/12/2026")), "format")
eq("parse junk", select(2, L.parse_date("amanhã")), "format")
eq("parse nil", select(2, L.parse_date(nil)), "format")
eq("parse short year", select(2, L.parse_date("26-12-25")), "format")

-- days_until: month ends, year ends, leap years, past
eq("same day", days("2026-10-16", 2026, 10, 16), 0)
eq("tomorrow", days("2026-10-17", 2026, 10, 16), 1)
eq("yesterday", days("2026-10-15", 2026, 10, 16), -1)
eq("across a month end", days("2026-11-02", 2026, 10, 30), 3)
eq("across a year end", days("2027-01-01", 2026, 12, 31), 1)
eq("across a year end, several days", days("2027-01-05", 2026, 12, 30), 6)
eq("a whole year", days("2027-10-16", 2026, 10, 16), 365)
eq("a year that holds a leap day", days("2029-02-28", 2028, 2, 28), 366)
eq("a year from just after the leap day", days("2029-02-28", 2028, 3, 1), 364)
eq("through a leap day", days("2028-03-01", 2028, 2, 28), 2)
eq("through a non-leap february", days("2026-03-01", 2026, 2, 28), 1)
eq("past across a year", days("2026-12-25", 2027, 1, 3), -9)
eq("25 Dec 2026 from 16 Oct 2026", days("2026-12-25", 2026, 10, 16), 70)
eq("bad date", days("x", 2026, 10, 16), nil)

-- local time: the local date decides, not the UTC one (UTC-3)
eq("23:59 local is still today", days("2026-10-17", 2026, 10, 16, 23, 59), 1)
eq("00:00 local is the next day", days("2026-10-17", 2026, 10, 17, 0, 0), 0)
eq("00:01 local", days("2026-10-17", 2026, 10, 17, 0, 1), 0)
do
    -- 22:30 local on the 16th is already the 17th in UTC: the countdown must still say it is the 16th
    local ts = at(2026, 10, 16, 22, 30)
    eq("the UTC date is one day ahead", os.date("!%Y-%m-%d", ts), "2026-10-17")
    eq("the local date is not", L.days_until("2026-10-17", L.today(ts, brt)), 1)
end
do
    -- the days between two instants never depend on how many hours the days had (no DST arithmetic)
    local a, b = at(2026, 11, 1, 0, 30), at(2026, 11, 2, 23, 30)
    eq("two calendar days apart in two hours short of 48", L.days_until("2026-11-02", L.today(a, brt)), 1)
    eq("and from the end of the next day", L.days_until("2026-11-02", L.today(b, brt)), 0)
end

-- names
eq("name trims", L.parse_name("  Férias  de   verão "), "Férias de verão")
eq("name empty", select(2, L.parse_name("   ")), "empty")
eq("name nil", select(2, L.parse_name(nil)), "empty")
eq("name 40 chars", L.parse_name(("é"):rep(40)), ("é"):rep(40))
eq("name 41 chars", select(2, L.parse_name(("é"):rep(41))), "too_long")

-- format_date
eq("format pt", L.format_date("2026-12-25", "pt"), "25/12/2026")
eq("format en", L.format_date("2026-12-25", "en"), "2026-12-25")
eq("format bad date passes through", L.format_date("x", "pt"), "x")

-- the list
local items = L.sanitize({ { name = "A", date = "2026-12-25" }, { name = "", date = "2026-12-25" },
    { name = "B", date = "2026-02-30" }, "junk", { name = "C", date = "2027-01-01" }, { name = "D", date = "2027-02-01" },
    { name = "E", date = "2027-03-01" } })
eq("sanitize keeps the valid ones, at most 3", #items, 3)
eq("sanitize order", items[1].name .. items[2].name .. items[3].name, "ACD")
eq("sanitize nil", #L.sanitize(nil), 0)
local l1 = L.put({}, nil, "Férias", "2026-12-25")
eq("put adds", #l1, 1); eq("put normalises the date", l1[1].date, "2026-12-25")
eq("put rejects a bad date", select(2, L.put({}, nil, "x", "2026-02-30")), "date_range")
eq("put rejects a date format", select(2, L.put({}, nil, "x", "hoje")), "date_format")
eq("put rejects an empty name", select(2, L.put({}, nil, "", "2026-12-25")), "name_empty")
local full = L.put(L.put(L.put({}, nil, "a", "2026-01-01"), nil, "b", "2026-01-02"), nil, "c", "2026-01-03")
eq("put refuses a fourth", select(2, L.put(full, nil, "d", "2026-01-04")), "full")
local edited = L.put(full, 2, "bb", "2026-02-02")
eq("put replaces at the index", edited[2].name, "bb"); eq("put does not touch the original", full[2].name, "b")
eq("put at a missing index", select(2, L.put(full, 9, "x", "2026-01-01")), "missing")
eq("remove", #L.remove(full, 2), 2); eq("remove keeps the order", L.remove(full, 1)[1].name, "b")

-- which countdown the widgets show
local tdy = today(2026, 10, 16)
local list = { { name = "past", date = "2026-10-01" }, { name = "far", date = "2027-01-01" }, { name = "near", date = "2026-10-20" } }
eq("main: nearest upcoming", list[L.main_index(list, tdy)].name, "near")
eq("main: today beats the future", L.main_index({ { name = "x", date = "2026-10-20" }, { name = "t", date = "2026-10-16" } }, tdy), 2)
eq("main: only past -> the most recent", L.main_index({ { name = "old", date = "2026-01-01" }, { name = "rec", date = "2026-10-10" } }, tdy), 2)
eq("main: none", L.main_index({}, tdy), nil)

-- texts
local d = L.describe({ name = "Férias", date = "2026-12-25" }, tdy, t)
eq("future short", d.short, "70 dias"); eq("future long", d.long, "faltam 70 dias para Férias"); eq("future number", d.number, "70")
eq("one day", L.describe({ name = "X", date = "2026-10-17" }, tdy, t).long, "falta 1 dia para X")
eq("one day short", L.describe({ name = "X", date = "2026-10-17" }, tdy, t).short, "1 dia")
local dt = L.describe({ name = "X", date = "2026-10-16" }, tdy, t)
eq("today short", dt.short, "hoje"); eq("today long", dt.long, "hoje: X"); eq("today kind", dt.kind, "today")
local dp = L.describe({ name = "X", date = "2026-10-13" }, tdy, t)
eq("past short", dp.short, "há 3 dias"); eq("past long", dp.long, "há 3 dias: X"); eq("past number", dp.number, "-3")
eq("past one day", L.describe({ name = "X", date = "2026-10-15" }, tdy, t).short, "há 1 dia")

-- the notification of the day
local ev = L.today_events({ { name = "Férias", date = "2026-10-16" }, { name = "Outra", date = "2026-10-17" } }, tdy, t)
eq("one event today", #ev, 1); eq("event title", ev[1].title, "Hoje: Férias"); eq("event prio", ev[1].prio, "alta")
eq("event key carries the date", ev[1].key, "hoje:2026-10-16:Férias")
eq("none the day before", #L.today_events({ { name = "Férias", date = "2026-10-16" } }, today(2026, 10, 15), t), 0)
