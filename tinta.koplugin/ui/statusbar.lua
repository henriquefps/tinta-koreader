-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (C) 2026 Tinta contributors
-- Tinta: status bar (6.2, R-S1..R-S4): clock, bell with unread count, Wi-Fi in three states, battery.
-- 48 px tall with a 2 px bottom border (design px of 6.1, scaled by ui/theme). In sleep it shows only "Repouso · atualizado HH:MM · próxima HH:MM"
-- and the battery.
local Draw = require("ui/draw")
local T = require("ui/theme")

local M = {}

local function inner_h() return T.SB_H - T.SB_BORDER end

local function zone(child, on_tap, pad)
    local s = child:getSize()
    return Draw.box{ w = s.w + 2 * (pad or T.px(6)), h = inner_h(), align = "center", valign = "center",
        child = child, on_tap = on_tap }
end

local function battery(bat)
    if not bat or not bat.pct then return nil end
    local txt = ("%d%%"):format(bat.pct)
    if bat.eta and bat.eta ~= "" then txt = txt .. " · " .. bat.eta end
    if bat.charging then txt = "⚡" .. txt end
    return Draw.hstack({ Draw.text(txt, T.FONT_BODY, true), Draw.Battery:new{ pct = bat.pct } }, T.px(6))
end

-- info = { time, unread, wifi = "on"|"connecting"|"off", bat = { pct, charging, eta }, sleep_text }
-- cb = { clock, bell, wifi, battery } (all optional)
function M.new(W, info, cb)
    cb = cb or {}
    local INNER_H = inner_h()
    local left, right = {}, {}
    if info.sleep_text then
        left[1] = zone(Draw.text(info.sleep_text, T.FONT_MIN, true, W - T.px(200)), nil, 0)
        local b = battery(info.bat)
        if b then right[1] = zone(b, nil, 0) end
    else
        left[1] = zone(Draw.text(info.time or "--:--", T.FONT_CLOCK, true), cb.clock)
        local bell = { Draw.icon_bell() }
        if (info.unread or 0) > 0 then
            bell[2] = Draw.box{ w = Draw.text_width(tostring(info.unread), T.FONT_MIN, true) + T.px(16), h = T.px(28),
                bg = Draw.BLACK, radius = T.RADIUS, align = "center", valign = "center",
                child = Draw.text(tostring(info.unread), T.FONT_MIN, true, nil, Draw.WHITE) }
        end
        left[2] = zone(Draw.hstack(bell, T.px(6)), cb.bell)
        local wifi = { Draw.icon_wifi(info.wifi or "off") }
        if info.wifi == "connecting" then wifi[2] = Draw.text("…", T.FONT_BODY, true) end
        right[1] = zone(Draw.hstack(wifi, T.px(2)), cb.wifi)
        local b = battery(info.bat)
        if b then right[2] = zone(b, cb.battery) end
    end
    -- widths are summed by hand (R-L1); the spacer takes the rest
    local used = 0
    for _, z in ipairs(left) do used = used + z.w end
    for _, z in ipairs(right) do used = used + z.w end
    -- each zone pads its content by 6 px, so neighbours end up SB_GAP (12) apart
    local zp = T.px(6)
    local spacer = Draw.space(math.max(0, W - 2 * (T.SB_PAD - zp) - used), INNER_H)
    local items = {}
    for _, z in ipairs(left) do items[#items + 1] = z end
    items[#items + 1] = spacer
    for _, z in ipairs(right) do items[#items + 1] = z end
    local row = Draw.box{ w = W, h = INNER_H, pad_x = T.SB_PAD - zp, valign = "center", child = Draw.hstack(items, 0) }
    return Draw.vstack({ row, Draw.Fill:new{ w = W, h = T.SB_BORDER } }, 0)
end

return M
