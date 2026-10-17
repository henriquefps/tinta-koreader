-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (C) 2026 Tinta contributors
-- logic.lua: decoding the answer, the threshold rule, formatting and the view model
local T = ...
local Logic = require("apps/_exemplo_json/logic")

-- parse
local r = Logic.parse({ value = 42, label = "Queue", unit = "items", extra = "ignored" })
T.check("parse: keeps value, label and unit", r and r.value == 42 and r.label == "Queue" and r.unit == "items")
T.check("parse: nothing else is kept", r.extra == nil)
T.eq("parse: numeric string", Logic.parse({ value = "7.5" }).value, 7.5)
T.check("parse: label and unit are optional", Logic.parse({ value = 1 }).label == nil and Logic.parse({ value = 1 }).unit == nil)
for name, body in pairs({ ["not a table"] = "x", ["nil"] = false, ["no value"] = { label = "a" }, ["text value"] = { value = "abc" },
    ["nan"] = { value = 0 / 0 }, ["inf"] = { value = math.huge }, ["list"] = { 1, 2 } }) do
    local got, why = Logic.parse(body or nil)
    T.check("parse: refuses " .. name, got == nil and why == "bad_shape")
end
T.eq("parse: label cut at the limit", #Logic.parse({ value = 1, label = string.rep("x", 100) }).label, Logic.MAX_LABEL)
T.eq("parse: control characters become spaces", Logic.parse({ value = 1, label = "a\nb\tc" }).label, "a b c")
T.check("parse: blank label is nil", Logic.parse({ value = 1, label = "   " }).label == nil)

-- threshold and crossing
T.eq("threshold: invalid is 0", Logic.threshold("abc"), 0)
T.eq("threshold: negative is 0", Logic.threshold(-3), 0)
T.eq("threshold: nil is 0", Logic.threshold(nil), 0)
T.eq("threshold: string number", Logic.threshold("12"), 12)
T.eq("threshold: capped", Logic.threshold(1e12), Logic.MAX_THRESHOLD)
local over, fire = Logic.crossed(false, 10, 5)
T.check("crossed: up -> notify", over == true and fire == true)
over, fire = Logic.crossed(true, 10, 5)
T.check("crossed: still over -> no new notification", over == true and fire == false)
over, fire = Logic.crossed(true, 3, 5)
T.check("crossed: back under -> re-armed", over == false and fire == false)
over, fire = Logic.crossed(nil, 5, 5)
T.check("crossed: equal to the threshold counts, first reading too", over == true and fire == true)
over, fire = Logic.crossed(false, 999, 0)
T.check("crossed: threshold 0 means never", over == false and fire == false)

-- format and host
T.eq("format: integer", Logic.format_value(42), "42")
T.eq("format: float", Logic.format_value(3.456), "3.5")
T.eq("format: negative", Logic.format_value(-2), "-2")
T.eq("host: https", Logic.host("https://example.com/a/b.json"), "example.com")
T.eq("host: port", Logic.host("http://192.0.2.10:8080/x"), "192.0.2.10:8080")
T.check("host: not a url", Logic.host("nope") == nil and Logic.host(nil) == nil)

-- view model
local function t(key, ...) return T.L(key, ...) end
local function clock(at) return T.utc("%H:%M", at) end
local vm = Logic.view(nil, "https://example.com/s.json", 0, t, clock)
T.check("view: before the first refresh", vm.primary == T.L("empty") and vm.secondary == T.L("never") and vm.big == "—")
T.eq("view: host", vm.host, "example.com")
T.eq("view: alert off", vm.limit, T.L("alert_off"))
vm = Logic.view({ value = 42, label = "Queue", unit = "items", at = 1792000000 }, "http://h:1/x", 40, t, clock)
T.check("view: value with unit", vm.primary == "42 items" and vm.big == "42" and vm.label == "Queue")
T.eq("view: time", vm.secondary, T.L("at", clock(1792000000)))
T.check("view: over the threshold", vm.over == true and vm.limit == "40")
vm = Logic.view({ value = 1 }, nil, 40, t, clock)
T.check("view: no unit, default label, no host", vm.primary == "1" and vm.label == T.L("name") and vm.host == T.L("no_host") and vm.over == false)
