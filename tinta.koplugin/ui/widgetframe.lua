-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (C) 2026 Tinta contributors
-- Tinta: widget frame (R-W2): border, inversion when the app needs attention, dashed border when the last
-- refresh failed with older data (R-S5), and the standard footer (R-W4). The app draws only the inside, in
-- the box M.body_box gives it (R-W1). Also the standard inside (M.basic) and the error widget (R-E2).
local Draw = require("ui/draw")
local Org = require("ui/orglogic")
local T = require("ui/theme")

local M = {}

local function is_one(size) return size == "1x1" end

-- box the app draws in: { w, h, inv, size, cols, rows, big }
function M.body_box(w, h, size, inv)
    local cols, rows = Org.parse_size(size)
    if is_one(size) then
        local p = T.BORDER + T.WIDGET_PAD_ONE
        return { w = w - 2 * p, h = h - 2 * p, inv = inv or false, size = size, cols = 1, rows = 1, big = false }
    end
    return {
        w = w - 2 * (T.BORDER + T.WIDGET_PAD_X),
        h = h - 2 * (T.BORDER + T.WIDGET_PAD_Y) - T.WIDGET_FOOTER_H,
        inv = inv or false, size = size, cols = cols or 2, rows = rows or 2,
        big = (cols or 0) >= 4 and (rows or 0) >= 4,
    }
end

local function footer(w, left, right, fg)
    local rw = 0
    local parts = {}
    if right and right ~= "" then
        local r = Draw.text(right, T.FONT_MIN, false, math.floor(w * 0.5), fg)
        rw = r:getSize().w + T.GAP
        parts[2] = Draw.box{ w = rw, h = T.WIDGET_FOOTER_H - T.BORDER - T.px(3), align = "right", valign = "center", child = r }
    end
    parts[1] = Draw.box{ w = w - rw, h = T.WIDGET_FOOTER_H - T.BORDER - T.px(3), valign = "center",
        child = Draw.text(left or "", T.FONT_MIN, false, w - rw, fg) }
    return Draw.vstack({ Draw.Fill:new{ w = w, h = T.BORDER, color = fg }, Draw.space(w, T.px(3)), Draw.hstack(parts, 0) }, 0)
end

-- opts = { w, h, size, inv, stale, body, footer_left, footer_right, on_tap, on_hold }
-- body: the app's widget (built for M.body_box), or nil (empty)
function M.new(opts)
    local w, h, inv = math.floor(opts.w), math.floor(opts.h), opts.inv or false
    local fg = Draw.fg(inv)
    local bb = M.body_box(w, h, opts.size, inv)
    local child
    if is_one(opts.size) then
        child = opts.body and Draw.box{ w = bb.w, h = bb.h, align = "center", valign = "center", child = opts.body } or nil
        return Draw.box{ w = w, h = h, bg = Draw.bg(inv), border = T.BORDER, border_color = Draw.BLACK, radius = T.RADIUS,
            dashed = opts.stale and not inv, pad_x = T.WIDGET_PAD_ONE, pad_y = T.WIDGET_PAD_ONE,
            child = child, on_tap = opts.on_tap, on_hold = opts.on_hold }
    end
    local body = Draw.box{ w = bb.w, h = bb.h, child = opts.body }
    local parts = { body }
    if opts.footer_left or opts.footer_right then
        parts[2] = footer(bb.w, opts.footer_left, opts.footer_right, fg)
    else
        parts[2] = Draw.space(bb.w, T.WIDGET_FOOTER_H)
    end
    return Draw.box{ w = w, h = h, bg = Draw.bg(inv), border = T.BORDER, border_color = Draw.BLACK, radius = T.RADIUS,
        dashed = opts.stale and not inv, pad_x = T.WIDGET_PAD_X, pad_y = T.WIDGET_PAD_Y,
        child = Draw.vstack(parts, 0), on_tap = opts.on_tap, on_hold = opts.on_hold }
end

---------------------------------------------------------------- standard inside

-- spec = { title, icon (widget or nil), primary, secondary, lines = { { left, right }, ... }, note }
-- Stacks what fits in box.h, in this order: head, primary, secondary, lines, note (R-W3).
function M.basic(box, spec)
    local w, fg = box.w, Draw.fg(box.inv)
    if box.size == "1x1" then
        local parts = {}
        if spec.icon then parts[#parts + 1] = spec.icon end
        if spec.number and spec.number ~= "" then parts[#parts + 1] = Draw.text(spec.number, T.FONT_PRIMARY, true, w, fg) end
        if #parts == 0 then parts[1] = Draw.text(spec.short or spec.title or "?", T.FONT_MIN, true, w, fg) end
        return Draw.vstack(parts, T.px(2), "center")
    end
    local items = {}
    if spec.title then
        local head = { Draw.text(spec.title, T.FONT_WNAME, true, w - (spec.icon and (T.WIDGET_ICON + T.GAP) or 0), fg) }
        if spec.icon then
            local tw = head[1]:getSize().w
            head[2] = Draw.space(math.max(0, w - tw - T.WIDGET_ICON), 1)
            head[3] = spec.icon
        end
        items[#items + 1] = Draw.hstack(head, 0)
    end
    if spec.primary and spec.primary ~= "" then
        items[#items + 1] = Draw.text(spec.primary, box.big and T.FONT_PRIMARY_BIG or T.FONT_PRIMARY, true, w, fg)
    end
    if spec.secondary and spec.secondary ~= "" then
        items[#items + 1] = Draw.text(spec.secondary, T.FONT_MIN, false, w, fg)
    end
    for _, l in ipairs(spec.lines or {}) do
        local r = l[2] and l[2] ~= "" and Draw.text(l[2], T.FONT_MIN, false, math.floor(w * 0.4), fg) or nil
        local rw = r and (r:getSize().w + T.GAP) or 0
        local row = { Draw.box{ w = w - rw, h = T.px(28), valign = "center", child = Draw.text(l[1], T.FONT_MIN, false, w - rw, fg) } }
        if r then row[2] = Draw.box{ w = rw, h = T.px(28), align = "right", valign = "center", child = r } end
        items[#items + 1] = Draw.vstack({ Draw.Fill:new{ w = w, h = T.BORDER, color = fg }, Draw.hstack(row, 0) }, T.px(1))
    end
    if spec.note and spec.note ~= "" then items[#items + 1] = Draw.text(spec.note, T.FONT_MIN, false, w, fg) end
    -- keep what fits (2 px between lines, scaled)
    local out, used = {}, 0
    for _, it in ipairs(items) do
        local ih = it:getSize().h
        if used + ih > box.h and #out > 0 then
            if it.free then it:free() end
        else
            out[#out + 1] = it
            used = used + ih + T.px(2)
        end
    end
    return Draw.vstack(out, T.px(2))
end

-- R-E2: "Nome · erro na app" in the same size
function M.error_body(box, name, text)
    if box.size == "1x1" then return Draw.text("!", T.FONT_PRIMARY, true, box.w, Draw.fg(box.inv)) end
    return Draw.textbox(text or name, T.FONT_BODY, box.w, box.h, true, Draw.fg(box.inv))
end

return M
