-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (C) 2026 Tinta contributors
-- Nota rápida (10.7), pure (R-A1): normalising and checking the text of the note, the cut for widgets and the
-- view model. The text is private: nothing here (or in init.lua) logs it.
local M = {}

M.MAX_DEFAULT = 500
M.PREVIEW = 400          -- characters handed to a widget's text box (a longer note is cut with "…" first)

local function utf8_len(s)
    local _, n = s:gsub("[^\128-\191]", "")
    return n
end
M.len = utf8_len

-- the first n characters of s
local function utf8_head(s, n)
    if n <= 0 then return "" end
    local count, i = 0, 1
    while i <= #s do
        local c = s:byte(i)
        if c < 0x80 or c >= 0xC0 then
            count = count + 1
            if count > n then return s:sub(1, i - 1) end
        end
        i = i + 1
    end
    return s
end
M.head = utf8_head

-- text typed by the user -> stored text. Lines end in "\n", blank edges go, runs of 3+ newlines become 2.
-- Returns text ("" = clear the note), or nil, "too_long", n (characters) when over `max`.
function M.normalize(text, max)
    if type(text) ~= "string" then return "" end
    local s = text:gsub("\r\n", "\n"):gsub("\r", "\n")
    s = s:gsub("[ \t]+\n", "\n"):gsub("\n\n\n+", "\n\n")
    s = s:gsub("^%s+", ""):gsub("%s+$", "")
    local n = utf8_len(s)
    if max and n > max then return nil, "too_long", n end
    return s
end

-- the text cut at n characters with "…" (spaces before the cut dropped)
function M.preview(text, n)
    if type(text) ~= "string" then return "" end
    n = n or M.PREVIEW
    if utf8_len(text) <= n then return text end
    return (utf8_head(text, n - 1):gsub("%s+$", "")) .. "…"
end

-- max characters from the setting (anything odd falls back to the default)
function M.max_chars(v)
    v = tonumber(v)
    if not v or v < 50 or v > 2000 then return M.MAX_DEFAULT end
    return math.floor(v)
end

-- what widgets and screen show: t = translator
function M.view(text, t)
    if type(text) ~= "string" or text == "" then
        return { empty = true, text = t("empty_widget"), count = 0 }
    end
    return { empty = false, text = text, count = utf8_len(text) }
end

return M
