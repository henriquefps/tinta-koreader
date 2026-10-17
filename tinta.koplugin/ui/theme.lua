-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (C) 2026 Tinta contributors
-- Tinta: every measure and font size of the interface (spec 6.1), as functions of the screen.
-- Pure table (no KOReader require): the pure helpers and their tests read it too. No loose numbers in screens.
--
-- BASE holds the design, in px of the 600x800 portrait / 800x600 landscape layout (the KT3: 167 ppi). T.configure(W, H)
-- (called by ui/geom.regions for the real screen) computes ONE scale s = min(W / 600, H / 800) (swapped in landscape),
-- the content box (the 3:4 area centred on the screen, white letterbox around it, origin T.ox, T.oy, size T.BW x T.BH)
-- and rewrites every scaled measure of T in place: T.SB_H, T.FONT_BODY... always read T.X at call time, never cache
-- it at load. On the KT3 s = 1 and every value equals BASE. T.px(n) / T.px1(n) scale a one-off design measure.
local BASE = {
    FONT = "cfont",              -- KOReader's UI font (Noto Sans)
    DESIGN_W = 600, DESIGN_H = 800,   -- portrait design box; landscape swaps them

    -- status bar (6.2)
    SB_H = 48,
    SB_BORDER = 2,
    SB_PAD = 12,                 -- left/right padding
    SB_GAP = 12,                 -- between items

    -- navigation bar (6.3)
    NAV_H = 72,
    NAV_DIV = 2,                 -- dividers and top border
    NAV_BUTTONS = 4,
    HANDLE_W = 120,              -- "gestures only" handle
    HANDLE_H = 6,
    HANDLE_BOTTOM = 8,

    -- spacing
    MARGIN = 8,
    GAP = 8,
    ROW_GAP = 4,                 -- between list rows

    -- text sizes
    FONT_MIN = 20,
    FONT_BODY = 22,
    FONT_CLOCK = 26,
    FONT_TITLE = 26,             -- app header, dialog title
    FONT_PRIMARY = 26,           -- widget main line
    FONT_PRIMARY_BIG = 32,       -- widget main line on 4x4
    FONT_WNAME = 22,             -- widget name
    FONT_STAT = 44,              -- statistic blocks
    FONT_HUGE = 72,              -- Bateria percentage

    -- touch and borders
    TOUCH = 64,                  -- minimum touch target height
    BORDER = 2,
    BORDER_SEL = 4,              -- selection and unread
    BORDER_DIALOG = 3,
    RADIUS = 4,
    RADIUS_OVERLAY = 6,          -- banner and dialog

    -- home grid (7.1)
    GRID_PORTRAIT = { 6, 8 },    -- columns, rows
    GRID_LANDSCAPE = { 8, 6 },
    GRID_GAP = 8,

    -- widget frame (R-W2)
    WIDGET_PAD_X = 10,
    WIDGET_PAD_Y = 6,
    WIDGET_PAD_ONE = 4,          -- 1x1
    WIDGET_FOOTER_H = 30,        -- 20 px text + 2 px top border + padding
    WIDGET_ICON = 30,

    -- app header (6.4)
    HEADER_H = 48,

    -- rows, buttons, pager
    ROW_H = 64,
    ROW_PAD_X = 12,
    BTN_H = 64,
    BTN_MIN_W = 64,
    PAGER_H = 64,

    -- menu sheet (6.5)
    SHEET_ITEM_H = 60,
    SHEET_TITLE_H = 48,
    SHEET_BORDER = 3,

    -- dialog (6.9)
    DIALOG_W = 500,
    DIALOG_PAD = 18,

    -- banner and toast
    BANNER_PAD_X = 14,
    BANNER_PAD_Y = 10,
    TOAST_PAD_X = 18,
    TOAST_PAD_Y = 12,
    TOAST_ABOVE_NAV = 12,

    -- central (8.3)
    QUICK_H = 72,
    CENTRAL_PER_PAGE_PORTRAIT = 4,
    CENTRAL_PER_PAGE_LANDSCAPE = 2,

    -- organizer (7.3)
    MAP_GAP = 4,
    ORG_SIDE_W = 280,            -- landscape: controls column

    -- timings (ms)
    TOAST_MS = 2600,
    BANNER_MS = 5000,
    TICK_S = 5,                  -- scheduler tick (R-U4)
    CLOCK_S = 60,                -- status bar clock redraw when nothing else happens

    -- e-ink refresh (6.7)
    FULL_EVERY = 10,

    -- gestures (R-N3)
    EDGE_BOTTOM = 50,
    EDGE_LEFT = 50,
    EDGE_TOP = 60,
    SWIPE_MIN = 80,
    SWIPE_MAX_CROSS = 60,
    HOLD_MS = 650,
    HOLD_SLOP = 12,

    -- icons and small parts (design px)
    ICON_WIFI_W = 30, ICON_WIFI_H = 26,
    ICON_BELL_W = 24, ICON_BELL_H = 26,
    ICON_GEAR = 30,
    ICON_HOUSE_W = 26, ICON_HOUSE_H = 24,
    ICON_BARS_W = 24, ICON_BARS_H = 20,
    BAT_W = 34, BAT_H = 18, BAT_NUB = 4,
    DASH = 10, DASH_GAP = 6,     -- dashed border (R-S5)
    SECTION_H = 30,              -- kit.rows: section label
    NOTE_LINE_H = 26,            -- kit.rows: note line
}

-- keys that never scale: the font name, counts, grids, timings and refresh cadence
local FIXED = {
    FONT = true, DESIGN_W = true, DESIGN_H = true, NAV_BUTTONS = true, GRID_PORTRAIT = true, GRID_LANDSCAPE = true,
    CENTRAL_PER_PAGE_PORTRAIT = true, CENTRAL_PER_PAGE_LANDSCAPE = true,
    TOAST_MS = true, BANNER_MS = true, TICK_S = true, CLOCK_S = true, FULL_EVERY = true, HOLD_MS = true,
}
-- keys that stay at least 1 px (borders, dividers, thin marks)
local MIN1 = {
    SB_BORDER = true, NAV_DIV = true, HANDLE_H = true, BORDER = true, BORDER_SEL = true, BORDER_DIALOG = true,
    SHEET_BORDER = true, RADIUS = true, RADIUS_OVERLAY = true, DASH = true, DASH_GAP = true, BAT_NUB = true,
}

-- boxes that hold lines of text: they grow with the text size factor too, so a larger text still sits inside its row,
-- button, menu item or footer (everything else keeps the screen scale only)
local TALL = {
    ROW_H = true, BTN_H = true, SHEET_ITEM_H = true, NOTE_LINE_H = true, SECTION_H = true, WIDGET_FOOTER_H = true,
}

local T = { BASE = BASE }
local floor = math.floor

local function round(x) return floor(x + 0.5) end

-- font sizes round DOWN, never up: a text that fits its box on the KT3 then still fits at any scale (a glyph a
-- little wider than the box it was measured for would be cut with "…"). The epsilon keeps exact products exact.
-- T.text is the user's "Tamanho do texto" factor (1.0 normal): it multiplies the font sizes only, never a measure.
local function font_px(n, s) return math.max(1, floor(n * s * (T.text or 1) + 1e-6)) end

local function set_scale(s)
    T.s = s
    for k, v in pairs(BASE) do
        if type(v) == "number" and k:sub(1, 5) == "FONT_" then
            T[k] = font_px(v, s)
        elseif type(v) == "number" and not FIXED[k] then
            local n = round(v * s * (TALL[k] and T.text or 1))
            if MIN1[k] and n < 1 then n = 1 end
            T[k] = n
        else
            T[k] = v
        end
    end
end

-- design measure -> px of this screen (rounded, may be 0); px1: at least 1 (strokes)
function T.px(n) return round(n * T.s) end
function T.px1(n) return math.max(1, round(n * T.s)) end
-- design font size -> px (rounded down, see font_px)
function T.fpx(n) return font_px(n, T.s) end

-- Text size factor (6.1, setting "text_size"): 1.0 gives exactly the sizes of before. Recomputes the font sizes of the
-- current scale; returns true when it changed (the caller redraws).
function T.set_text_factor(f)
    f = tonumber(f) or 1
    if f < 0.5 or f > 3 then f = 1 end
    if f == (T.text or 1) then return false end
    T.text = f
    set_scale(T.s)
    return true
end

-- Scale and content box for a W x H screen (portrait when H >= W). Cheap when the size did not change.
function T.configure(W, H)
    if W == T.W and H == T.H then return T.s end
    local land = W > H
    local dw, dh = BASE.DESIGN_W, BASE.DESIGN_H
    if land then dw, dh = dh, dw end
    local s = math.min(W / dw, H / dh)
    set_scale(s)
    local bw, bh = math.min(W, round(dw * s)), math.min(H, round(dh * s))
    T.W, T.H = W, H
    T.BW, T.BH = bw, bh
    T.ox, T.oy = floor((W - bw) / 2), floor((H - bh) / 2)
    T.land = land
    return s
end

T.text = 1

-- the KT3 until a screen is configured
T.configure(BASE.DESIGN_W, BASE.DESIGN_H)

return T
