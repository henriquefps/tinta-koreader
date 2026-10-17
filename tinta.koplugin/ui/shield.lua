-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (C) 2026 Tinta contributors
-- Tinta: a short-lived invisible window that swallows touch gestures. Shown right after the Tinta closes: the
-- e-ink panel still shows the Tinta for a moment while FileManager / the reader below repaint, and a tap on
-- what the user still sees must not land on a file, a title-bar icon or a menu of the screen underneath.
local Device = require("device")
local Geom = require("ui/geometry")
local InputContainer = require("ui/widget/container/inputcontainer")
local UIManager = require("ui/uimanager")
local Screen = Device.screen

local M = { DURATION = 0.8 }

local Shield = InputContainer:extend{
    name = "tinta_shield",
    invisible = true,     -- UIManager neither paints nor refreshes it
}

function Shield:init()
    self.dimen = Geom:new{ x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight() }
end

-- every touch gesture (tap, swipe, hold, pan, ...) ends here
function Shield:onGesture() return true end

-- one shield at a time; ms defaults to M.DURATION seconds * 1000
function M.show(ms)
    if M.current then UIManager:close(M.current); M.current = nil end
    local shield = Shield:new{}
    M.current = shield
    UIManager:show(shield)
    UIManager:scheduleIn((ms and ms / 1000) or M.DURATION, function()
        if M.current == shield then M.current = nil end
        UIManager:close(shield)
    end)
end

return M
