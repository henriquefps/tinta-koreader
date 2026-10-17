-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (C) 2026 Tinta contributors
-- Which apps the headless UI tests lean on. tests/private_apps.lua (not in the public tree) names extra apps the
-- maintainers keep out of the repository; without it the tests use bundled apps and the public KT3 baseline.
local ok, P = pcall(dofile, "tests/private_apps.lua")
if ok and type(P) == "table" then return P end
return {
    private = false,
    a = "relogio", b = "nota",          -- two bundled apps that take a 4x4 widget
    b_name = "Nota",
    ext = { "timer", "nota" },         -- bundled apps re-deployed as tinta-apps/<id>/ to test the external-apps path
    screens = {},
    checked = { "bateria" }, drop = "bateria", drop_name = "Bateria",
    exp_home = "notificacoes,sistema,relogio", exp_sleep = "notificacoes",
    sens2 = nil,
    smokes = {},                       -- extra UI smokes: { name, file }
    baseline = "tests/fixtures/kt3-trace-public.txt",
}
