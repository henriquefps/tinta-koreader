-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (C) 2026 Tinta contributors
-- Contagem: widgets (2x2, 4x2, 1x1) and the screens (list of up to 3 countdowns, editor). Built from ctx.ui inside the
-- box the core gives (R-W1); no KOReader group is measured (R-L1). `today` is Logic.today(now), read once per render.
local Logic = require("apps/contagem/logic")

local M = {}

-- items: the list; today: { y, m, d }; L: translator; lang: "pt" | "en"
function M.widget(ctx, size, box, items, today, L, lang)
    local ui = ctx.ui
    local i = Logic.main_index(items, today)
    if not i then
        if size == "1x1" then return ui.basic(box, { short = L("name") }) end
        return ui.basic(box, { title = L("name"), secondary = L("empty_widget") })
    end
    local d = Logic.describe(items[i], today, L)
    if size == "1x1" then return ui.basic(box, { number = d.number, short = items[i].name }) end
    local when = L(d.kind == "past" and "since" or "on_date", Logic.format_date(items[i].date, lang))
    local spec = { title = items[i].name, primary = d.short, secondary = when }
    if box.cols >= 4 then
        spec.secondary = d.long
        spec.lines = {}
        for k, it in ipairs(items) do
            if k ~= i then spec.lines[#spec.lines + 1] = { it.name, Logic.describe(it, today, L).short } end
        end
    end
    return ui.basic(box, spec)
end

-- act = { new(), edit(idx) }
function M.main(ctx, box, items, today, act, L, lang)
    local ui = ctx.ui
    local T = ui.theme
    local w = box.w
    local list_h = box.h - T.BTN_H - T.GAP
    local body
    if #items == 0 then
        body = ui.box{ w = w, h = list_h, align = "center", valign = "center",
            child = ui.textbox(L("empty_screen"), T.FONT_BODY, w - T.px(16), nil, false, nil, "center") }
    else
        local rows = {}
        for i, it in ipairs(items) do
            local d = Logic.describe(it, today, L)
            rows[i] = { title = d.long, sub = Logic.format_date(it.date, lang), right = d.short, on_tap = function() act.edit(i) end }
        end
        body = ui.rows({ w = w, h = list_h, landscape = box.landscape }, rows, { two_cols = false })
    end
    local full = #items >= Logic.MAX_ITEMS
    return { body = ui.vstack({ ui.box{ w = w, h = list_h, child = body },
        ui.button{ label = L("btn_new"), w = w, inv = not full, on_tap = act.new } }, T.GAP) }
end

-- draft = { idx, name, date }; act = { name(), date(), save(), delete() }
function M.edit(ctx, box, draft, today, act, L, lang)
    local ui = ctx.ui
    local T = ui.theme
    local w = box.w
    local function row(label, value, on_tap)
        return ui.row{ w = w, h = T.ROW_H, title = label, right = value, on_tap = on_tap }
    end
    local parts = {
        row(L("btn_name"), draft.name or L("field_unset"), act.name),
        row(L("btn_date"), draft.date and Logic.format_date(draft.date, lang) or L("field_unset"), act.date),
    }
    local name = Logic.parse_name(draft.name)
    if name and draft.date and Logic.parse_date(draft.date) then
        local d = Logic.describe({ name = name, date = draft.date }, today, L)
        parts[#parts + 1] = ui.box{ w = w, h = T.px(70), valign = "center", child = ui.textbox(d.long, T.fpx(24), w, T.px(70), true) }
    end
    local specs = { { L("btn_save"), act.save, inv = true } }
    if draft.idx then specs[2] = { L("btn_delete"), act.delete } end
    parts[#parts + 1] = ui.button_row(specs, w)
    return { title = L(draft.idx and "edit_title" or "edit_new"), body = ui.vstack(parts, T.GAP) }
end

return M
