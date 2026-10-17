-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (C) 2026 Tinta contributors
-- Tests of the reference app (plain Lua, no KOReader). Run from the repo root:
--   luajit tinta.koplugin/apps/_modelo/tests/run.lua        (QUIET=1 prints only failures and the total)
-- tests/apprunner.lua gives every suite T (T.check, T.eq, T.ctx = a fake ctx, T.L = the pt texts).
local here = (arg and arg[0] or ""):match("^(.*)/[^/]*$") or "."
package.path = here .. "/../../../tests/?.lua;" .. package.path
require("apprunner").run("_modelo", here, { "logic", "app", "strings", "view" })
