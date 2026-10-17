-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (C) 2026 Tinta contributors
local T = ...
local JSON = require("core/json")
local eq, same, check = T.eq, T.same, T.check

eq("json: number int", JSON.encode(42), "42")
eq("json: number float", JSON.encode(1.5), "1.5")
eq("json: string escapes", JSON.encode('a"b\\c\n'), '"a\\"b\\\\c\\n"')
eq("json: bool", JSON.encode(true), "true")
eq("json: array", JSON.encode({ 1, "a", false }), '[1,"a",false]')
eq("json: object sorted keys", JSON.encode({ b = 1, a = 2 }), '{"a":2,"b":1}')
eq("json: nested", JSON.encode({ route = { "project", { id = "9f" } } }), '{"route":["project",{"id":"9f"}]}')
check("json: function rejected", not pcall(JSON.encode, { f = print }))
local cyc = {}; cyc.self = cyc
check("json: cycle rejected", not pcall(JSON.encode, cyc))
check("json: NaN rejected", not pcall(JSON.encode, 0 / 0))

same("json: decode object", JSON.decode('{"a":1,"b":[true,false,"x"],"c":{"d":-2.5e1}}'),
    { a = 1, b = { true, false, "x" }, c = { d = -25 } })
eq("json: decode unicode escape", JSON.decode('"\\u00e9\\u2026"'), "é…")
eq("json: decode surrogate pair", JSON.decode('"\\ud83d\\ude00"'), "\240\159\152\128")
eq("json: decode utf8 passthrough", JSON.decode('"Notificações"'), "Notificações")
eq("json: decode null -> nil", JSON.decode("null"), nil)
same("json: decode empty array", JSON.decode("[]"), {})
same("json: decode whitespace", JSON.decode(' { "a" : [ 1 , 2 ] } '), { a = { 1, 2 } })
local v, err = JSON.decode("{bad")
check("json: bad input -> nil, err", v == nil and type(err) == "string", err)
check("json: trailing data -> nil", JSON.decode("1 2") == nil)
check("json: non-string -> nil", JSON.decode(nil) == nil)
local big = { title = "projeto precisa de você", list = { 1, 2, 3 }, flag = false, n = 1234567890 }
same("json: round trip", JSON.decode(JSON.encode(big)), big)
