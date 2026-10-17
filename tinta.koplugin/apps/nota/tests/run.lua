-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (C) 2026 Tinta contributors
-- Nota tests (plain Lua, no KOReader). Run from the repo root: luajit tinta.koplugin/apps/nota/tests/run.lua
local here = (arg and arg[0] or ""):match("^(.*)/[^/]*$") or "."
package.path = here .. "/../../../tests/?.lua;" .. package.path
require("apprunner").run("nota", here, { "logic", "app", "strings", "view" })
