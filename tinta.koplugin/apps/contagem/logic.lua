-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (C) 2026 Tinta contributors
-- Contagem regressiva (10.8), pure (R-A1): date parsing and validation, day arithmetic in LOCAL time (a civil
-- calendar, no time-zone or DST arithmetic on timestamps: only the local date of `now` is read), the list of up
-- to 3 countdowns and the texts. Dates are "YYYY-MM-DD". `date` is an os.date-like function (tests pass a fixed
-- UTC-3 clock); nothing here reads the clock.
local M = {}

M.MAX_ITEMS = 3
M.NAME_MAX = 40

-- days since 1970-01-01 of a civil date (proleptic Gregorian; Howard Hinnant's days_from_civil)
function M.day_number(y, m, d)
    if m <= 2 then y = y - 1 end
    local era = math.floor(y / 400)
    local yoe = y - era * 400
    local mp = (m + 9) % 12
    local doy = math.floor((153 * mp + 2) / 5) + d - 1
    local doe = yoe * 365 + math.floor(yoe / 4) - math.floor(yoe / 100) + doy
    return era * 146097 + doe - 719468
end

function M.leap(y) return (y % 4 == 0 and y % 100 ~= 0) or y % 400 == 0 end

function M.days_in_month(y, m)
    if m == 2 then return M.leap(y) and 29 or 28 end
    return (m == 4 or m == 6 or m == 9 or m == 11) and 30 or 31
end

-- "2026-12-25" (also "2026-1-5") -> "2026-12-25", y, m, d; nil, "format" | "range" otherwise
function M.parse_date(s)
    if type(s) ~= "string" then return nil, "format" end
    local y, m, d = s:match("^%s*(%d%d%d%d)%-(%d%d?)%-(%d%d?)%s*$")
    if not y then return nil, "format" end
    y, m, d = tonumber(y), tonumber(m), tonumber(d)
    if y < 1900 or y > 2200 or m < 1 or m > 12 or d < 1 or d > M.days_in_month(y, m) then return nil, "range" end
    return string.format("%04d-%02d-%02d", y, m, d), y, m, d
end

-- the local date of `now`: { y, m, d }
function M.today(now, date)
    local t = (date or os.date)("*t", now)
    return { y = t.year, m = t.month, d = t.day }
end

-- whole days from today to the date: positive = in the future, 0 = today, negative = past. nil for a bad date.
function M.days_until(date_str, today)
    local ok, y, m, d = M.parse_date(date_str)
    if not ok then return nil end
    return M.day_number(y, m, d) - M.day_number(today.y, today.m, today.d)
end

-- name typed by the user -> trimmed name; nil, "empty" | "too_long"
function M.parse_name(s)
    if type(s) ~= "string" then return nil, "empty" end
    s = s:gsub("%s+", " "):gsub("^ ", ""):gsub(" $", "")
    if s == "" then return nil, "empty" end
    local _, n = s:gsub("[^\128-\191]", "")
    if n > M.NAME_MAX then return nil, "too_long" end
    return s
end

-- "25/12/2026" (pt) or "2026-12-25" (en)
function M.format_date(date_str, lang)
    local ok, y, m, d = M.parse_date(date_str)
    if not ok then return tostring(date_str or "") end
    if lang == "en" then return string.format("%04d-%02d-%02d", y, m, d) end
    return string.format("%02d/%02d/%04d", d, m, y)
end

---------------------------------------------------------------- the list

-- the stored list -> a clean list (valid items only, at most MAX_ITEMS), never throws
function M.sanitize(raw)
    local out = {}
    if type(raw) ~= "table" then return out end
    for _, it in ipairs(raw) do
        if #out >= M.MAX_ITEMS then break end
        if type(it) == "table" then
            local name = M.parse_name(it.name)
            local date = M.parse_date(it.date)
            if name and date then out[#out + 1] = { name = name, date = date } end
        end
    end
    return out
end

-- a new list with the item added (idx nil) or replaced at idx; nil, reason when invalid or full
function M.put(items, idx, name, date_str)
    local n, rn = M.parse_name(name)
    if not n then return nil, "name_" .. rn end
    local d, rd = M.parse_date(date_str)
    if not d then return nil, "date_" .. rd end
    local out = {}
    for i, it in ipairs(items) do out[i] = it end
    if idx then
        if not out[idx] then return nil, "missing" end
        out[idx] = { name = n, date = d }
    else
        if #out >= M.MAX_ITEMS then return nil, "full" end
        out[#out + 1] = { name = n, date = d }
    end
    return out
end

function M.remove(items, idx)
    local out = {}
    for i, it in ipairs(items) do if i ~= idx then out[#out + 1] = it end end
    return out
end

-- index of the countdown the widgets show: the nearest one today or later, else the most recent past one
function M.main_index(items, today)
    local best, best_d
    for i, it in ipairs(items) do
        local d = M.days_until(it.date, today)
        if d and d >= 0 and (not best_d or best_d < 0 or d < best_d) then best, best_d = i, d end
    end
    if best then return best end
    for i, it in ipairs(items) do
        local d = M.days_until(it.date, today)
        if d and (not best_d or d > best_d) then best, best_d = i, d end
    end
    return best
end

---------------------------------------------------------------- texts

-- t(key, ...) of the app's strings. Returns { days, kind = "future"|"today"|"past", count, short, long }
--   short: "12 dias" / "hoje" / "há 3 dias"      long: "faltam 12 dias para Férias" / "hoje: Férias" / "há 3 dias: Férias"
function M.describe(item, today, t)
    local d = M.days_until(item.date, today)
    if d == nil then return { kind = "bad", short = "?", long = item.name, number = "?" } end
    if d == 0 then
        return { days = 0, kind = "today", count = 0, short = t("today"), long = t("long_today", item.name), number = t("today") }
    end
    local n = math.abs(d)
    if d > 0 then
        return { days = d, kind = "future", count = n, short = t(n == 1 and "days_one" or "days_many", n),
            long = n == 1 and t("long_future_one", item.name) or t("long_future_many", n, item.name), number = tostring(n) }
    end
    return { days = d, kind = "past", count = n, short = t(n == 1 and "ago_one" or "ago_many", n),
        long = t("long_past", t(n == 1 and "ago_one" or "ago_many", n), item.name), number = "-" .. n }
end

-- notifications of the day: one per countdown that is today. Returns a list of { key, type, prio, title, body }
function M.today_events(items, today, t)
    local out = {}
    for _, it in ipairs(items) do
        if M.days_until(it.date, today) == 0 then
            out[#out + 1] = { key = "hoje:" .. it.date .. ":" .. it.name, type = "hoje", prio = "alta",
                title = t("n_today_title", it.name), body = t("n_today_body") }
        end
    end
    return out
end

return M
