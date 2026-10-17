-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (C) 2026 Tinta contributors
-- Contagem regressiva (10.8): "faltam N dias para <nome>" up to a date the user sets (name + date, validated), "hoje"
-- on the day and "há N dias" after it; up to 3 countdowns. Local, no network. Days are counted on the local calendar
-- date (logic.lua), so DST or the time zone never shift them. The list lives in ctx.data ("items"), read once at
-- init and written through. The hourly refresh only notifies on the day (setting "Avisar no dia").
local Logic = require("apps/contagem/logic")
local Strings = require("apps/contagem/strings")
local View = require("apps/contagem/view")

local A = { items = nil, draft = nil }

local function items(ctx)
    if not A.items then A.items = Logic.sanitize(ctx.data:get("items")) end
    return A.items
end

local function save(ctx) ctx.data:set("items", A.items) end

local function lang(ctx) return ctx.i18n.lang() end

local function actions(ctx)
    local t = ctx.i18n.t
    local act = {}
    function act.new()
        if #items(ctx) >= Logic.MAX_ITEMS then return ctx.toast(t("err_full")) end
        A.draft = { idx = nil }
        ctx.open("edit", {})
    end
    function act.edit(idx)
        local it = items(ctx)[idx]
        if not it then return ctx.toast(t("err_missing")) end
        A.draft = { idx = idx, name = it.name, date = it.date }
        ctx.open("edit", { idx = idx })
    end
    function act.name()
        local d = A.draft
        ctx.input(t("input_name"), d.name or "", t("input_name_hint"), function(text)
            local n, why = Logic.parse_name(text)
            if not n then return false, t("err_name_" .. why) end
            d.name = n
            return true
        end)
    end
    function act.date()
        local d = A.draft
        ctx.input(t("input_date"), d.date or "", t("input_date_hint"), function(text)
            local s, why = Logic.parse_date(text)
            if not s then return false, t("err_date_" .. why) end
            d.date = s
            return true
        end)
    end
    function act.save()
        local d = A.draft
        local list, why = Logic.put(items(ctx), d.idx, d.name, d.date)
        if not list then return ctx.toast(t("err_" .. why)) end
        A.items = list
        A.draft = nil
        save(ctx)
        ctx.toast(t("saved"))
        ctx.back()
    end
    function act.delete()
        local d = A.draft
        local it = d.idx and items(ctx)[d.idx]
        if not it then return end
        ctx.confirm(t("delete_title"), t("delete_text", it.name), t("btn_delete"), function()
            A.items = Logic.remove(items(ctx), d.idx)
            A.draft = nil
            save(ctx)
            ctx.toast(t("deleted"))
            ctx.back()
        end)
    end
    return act
end

return {
    id = "contagem",
    name = "Contagem",
    names = { pt = Strings.pt.name, en = Strings.en.name },
    short = "Contagem",
    version = 1,
    api = 1,                -- Tinta app API this app was written for (5.1)
    sizes = { "2x2", "4x2", "1x1" },
    net = false,
    defaults = { interval = 3600, window = nil },
    settings = {
        { key = "notify_today", label = Strings.pt.set_notify, type = "bool", default = true },
    },
    notifications = {
        { type = "hoje", label = Strings.pt.notif_today },
    },
    strings = Strings,

    init = function(ctx)
        A.items, A.draft = nil, nil
        items(ctx)
    end,

    -- only the day itself notifies (once per countdown: the key carries the date); done() goes first so the
    -- notifications of the first refresh of a session are armed (core/notify 8.6) and not just recorded
    refresh = function(ctx, done)
        local events = {}
        if ctx.settings:get("notify_today") == true then
            events = Logic.today_events(items(ctx), Logic.today(ctx.now()), ctx.i18n.t)
        end
        done(true)
        for _, n in ipairs(events) do ctx.notify(n) end
    end,

    widget = function(ctx, size, box)
        return View.widget(ctx, size, box, items(ctx), Logic.today(ctx.now()), ctx.i18n.t, lang(ctx))
    end,

    screens = {
        main = function(ctx, args, box)
            return View.main(ctx, box, items(ctx), Logic.today(ctx.now()), actions(ctx), ctx.i18n.t, lang(ctx))
        end,
        edit = function(ctx, args, box)
            if not A.draft then
                local it = args and args.idx and items(ctx)[args.idx]
                A.draft = it and { idx = args.idx, name = it.name, date = it.date } or { idx = nil }
            end
            return View.edit(ctx, box, A.draft, Logic.today(ctx.now()), actions(ctx), ctx.i18n.t, lang(ctx))
        end,
    },

    _A = A,       -- tests only
}
