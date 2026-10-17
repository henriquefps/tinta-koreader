-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (C) 2026 Tinta contributors
-- Nota rápida (10.7): one sticky note typed with the KOReader keyboard (ctx.input). Local, no network. The text lives
-- in ctx.data ("text") and is read once, at init; it is never logged or put in a notification. Widgets 2x2, 4x2,
-- 2x4 and 4x4 show it wrapped and cut with "…"; tapping one opens the screen with Editar / Limpar (confirmed).
local Logic = require("apps/nota/logic")
local Strings = require("apps/nota/strings")
local View = require("apps/nota/view")

local A = { text = nil, loaded = false }

local function text(ctx)
    if not A.loaded then
        local v = ctx.data:get("text")
        A.text = type(v) == "string" and v or ""
        A.loaded = true
    end
    return A.text
end

local function store_text(ctx, s)
    A.text, A.loaded = s, true
    ctx.data:set("text", s ~= "" and s or nil)
end

local function max_chars(ctx) return Logic.max_chars(ctx.settings:get("max_chars")) end
local function big(ctx) return ctx.settings:get("big_text") == true end

local function actions(ctx)
    local t = ctx.i18n.t
    local act = {}
    function act.edit()
        local max = max_chars(ctx)
        ctx.input(t("edit_title"), text(ctx), t("edit_hint"), function(input)
            local s, reason, n = Logic.normalize(input, max)
            if not s then return false, t(reason, n, max) end
            store_text(ctx, s)
            return true
        end, { multiline = true })
    end
    function act.clear()
        ctx.confirm(t("clear_title"), t("clear_text"), t("clear_ok"), function()
            store_text(ctx, "")
            ctx.toast(t("cleared"))
            ctx.redraw()
        end)
    end
    return act
end

return {
    id = "nota",
    name = "Nota",
    names = { pt = Strings.pt.name, en = Strings.en.name },
    short = "Nota",
    version = 1,
    api = 1,                -- Tinta app API this app was written for (5.1)
    sensitive = true,       -- hidden on the sleep page until the user allows it (8.5)
    sizes = { "2x2", "4x2", "2x4", "4x4" },
    net = false,
    defaults = {},
    settings = {
        { key = "max_chars", label = Strings.pt.set_max, type = "number", default = Logic.MAX_DEFAULT, min = 50, max = 2000 },
        { key = "big_text", label = Strings.pt.set_big, type = "bool", default = false },
    },
    strings = Strings,

    init = function(ctx)
        A.loaded = false
        text(ctx)
    end,

    widget = function(ctx, size, box)
        return View.widget(ctx, size, box, Logic.view(text(ctx), ctx.i18n.t), big(ctx), ctx.i18n.t)
    end,

    screens = {
        main = function(ctx, args, box)
            return View.screen(ctx, box, Logic.view(text(ctx), ctx.i18n.t), big(ctx), actions(ctx), ctx.i18n.t)
        end,
    },

    _A = A,       -- tests only
}
