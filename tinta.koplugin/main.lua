-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (C) 2026 Tinta contributors
-- Tinta: KOReader plugin entry point (D1). Adds "Tinta" to the KOReader menu and a Dispatcher action for
-- gestures and profiles (R-N4), and opens / closes the Tinta. Everything else lives in ui/host.lua (the
-- controller), ui/screen.lua (the window), core/ (logic) and apps/.
local DataStorage = require("datastorage")
local Dispatcher = require("dispatcher")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local logger = require("logger")

-- plugin directory: set by KOReader's plugin loader; falls back to this file's folder
local function plugin_dir(self)
    if self.path then return self.path end
    local src = debug.getinfo(1, "S").source or ""
    return src:match("^@(.*)/[^/]*$") or "."
end

local Tinta = WidgetContainer:extend{
    name = "tinta",
    is_doc_only = false,
}

-- action "Tinta" in KOReader's gesture / quick menu / profile pickers (Settings > Taps and gestures)
function Tinta:onDispatcherRegisterActions()
    Dispatcher:registerAction("tinta_open", {
        category = "none", event = "OpenTinta", title = "Tinta", general = true,
    })
end

function Tinta:init()
    -- the old plugins/portal.koplugin is still installed: it keeps running alone until it is deleted (docs/sdk.md)
    if require("core/migrate").legacy_plugin_present(plugin_dir(self)) then
        logger.warn("Tinta: plugins/portal.koplugin is still installed; Tinta stays off until it is deleted")
        return
    end
    self:onDispatcherRegisterActions()
    self.ui.menu:registerToMainMenu(self)
end

function Tinta:addToMainMenu(menu_items)
    menu_items.tinta = {
        text = "Tinta",
        sorting_hint = "more_tools",
        callback = function() self:open() end,
    }
end

function Tinta:onOpenTinta()
    self:open()
    return true
end

function Tinta:open()
    local Host = require("ui/host")
    if Host:isOpen() then return end
    local ok, err = xpcall(function()
        Host:open{
            plugin_dir = plugin_dir(self),
            db_path = DataStorage:getDataDir() .. "/tinta.sqlite3",
            data_dir = DataStorage:getDataDir(),
        }
    end, debug.traceback)
    if not ok then
        logger.err("Tinta: open failed:", err)
        pcall(function() Host:close() end)
        local InfoMessage = require("ui/widget/infomessage")
        UIManager:show(InfoMessage:new{ text = "Tinta: " .. tostring(err):match("[^\n]*") })
    end
end

return Tinta
