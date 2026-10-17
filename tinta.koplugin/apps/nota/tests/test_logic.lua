-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (C) 2026 Tinta contributors
local T = ...
local check, eq = T.check, T.eq
local L = require("apps/nota/logic")

eq("normalize trims", L.normalize("  olá  \n", 100), "olá")
eq("normalize CRLF", L.normalize("a\r\nb\rc", 100), "a\nb\nc")
eq("normalize trailing blanks on lines", L.normalize("a  \nb\t\nc", 100), "a\nb\nc")
eq("normalize collapses blank runs", L.normalize("a\n\n\n\n\nb", 100), "a\n\nb")
eq("normalize empty", L.normalize("   ", 100), "")
eq("normalize nil", L.normalize(nil, 100), "")
local s, reason, n = L.normalize(("x"):rep(11), 10)
eq("too long: nil", s, nil); eq("too long: reason", reason, "too_long"); eq("too long: count", n, 11)
eq("exactly the max is fine", L.normalize(("x"):rep(10), 10), ("x"):rep(10))
eq("counts characters, not bytes", L.normalize(("é"):rep(10), 10), ("é"):rep(10))
eq("utf8 len", L.len("ação"), 4)
eq("head keeps whole characters", L.head("ação", 2), "aç")
eq("head of more than the text", L.head("ab", 5), "ab")
eq("head 0", L.head("ab", 0), "")

eq("preview short is unchanged", L.preview("abc", 10), "abc")
eq("preview cuts with an ellipsis", L.preview("abcdefghij", 5), "abcd…")
eq("preview drops spaces before the cut", L.preview("abc  defgh", 6), "abc…")
eq("preview of utf8", L.preview("ééééé", 3), "éé…")
eq("preview nil", L.preview(nil), "")
check("preview of a long note is bounded", L.len(L.preview(("a "):rep(5000))) <= L.PREVIEW)

eq("max_chars default", L.max_chars(nil), L.MAX_DEFAULT)
eq("max_chars too small", L.max_chars(10), L.MAX_DEFAULT)
eq("max_chars too big", L.max_chars(5000), L.MAX_DEFAULT)
eq("max_chars ok", L.max_chars(300), 300)

local t = T.L
local v = L.view("", t)
eq("view empty", v.empty, true); eq("view empty text", v.text, "toque para escrever")
local v2 = L.view("ação", t)
eq("view note", v2.text, "ação"); eq("view count", v2.count, 4); eq("view not empty", v2.empty, false)
