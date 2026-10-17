-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (C) 2026 Tinta contributors
local T = ...
local FirstRun = require("core/firstrun")
local Settings = require("core/settings")
local Store = require("core/store")
local eq, check = T.eq, T.check

local IDS = { "alfa", "beta", "bateria" }

-- a fresh store (core/settings writes idle_mode on creation)
local s = Store.memory()
Settings.new({ store = s }):migrate()
check("firstrun: a fresh store needs the wizard", FirstRun.needed(s, IDS) == true)

-- every sign of an existing install means "done" (the KT3 must never see the wizard)
local signs = {
    home_layout = function(st) st:layout_set("home", { { app = "alfa", size = "4x4" } }) end,
    sleep_layout = function(st) st:layout_set("sleep", {}) end,
    legacy_mark = function(st) st:meta_set("legacy_imported:alfa", 123) end,
    version_mark = function(st) st:meta_set("app_version:bateria", 1) end,
    tinta_setting = function(st) st:set("portal", "banner", false) end,
    done = function(st) st:meta_set("first_run_done", "1") end,
}
for name, apply in pairs(signs) do
    local st = Store.memory()
    Settings.new({ store = st }):migrate()
    apply(st)
    check("firstrun: " .. name .. " means existing", FirstRun.needed(st, IDS) == false)
end

-- marks of apps that are not in the folder list do not count (a removed app's leftovers)
local st = Store.memory()
Settings.new({ store = st }):migrate()
st:meta_set("app_version:ghost", 1)
check("firstrun: marks of unknown apps are ignored", FirstRun.needed(st, IDS) == true)

-- pending survives the marks the first open writes, until done or a layout is saved
FirstRun.mark_pending(st)
st:meta_set("app_version:alfa", 1)
st:meta_set("legacy_imported:alfa", 1)
st:set("portal", "lang", "en")
check("firstrun: pending stays fresh after the first open's writes", FirstRun.needed(st, IDS) == true)
st:layout_set("home", {})
check("firstrun: a layout saved while pending ends it", FirstRun.needed(st, IDS) == false)
FirstRun.mark_done(st, "42")
eq("firstrun: done is recorded", st:meta_get("first_run_done"), "42")
eq("firstrun: done clears pending", st:meta_get("first_run_pending"), nil)
check("firstrun: done is final", FirstRun.needed(st, IDS) == false)
