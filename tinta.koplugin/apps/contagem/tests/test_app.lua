-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (C) 2026 Tinta contributors
-- init.lua over a fake ctx: restore, editing through ctx.input, validation, the 3 limit, deleting, the notification
local T = ...
local check, eq = T.check, T.eq
local M = require("apps/contagem/init")
local A = M._A
local L = require("apps/contagem/logic")
local Settings = require("core/settings")

for _, f in ipairs(M.settings) do check("manifest: default of " .. f.key .. " validates", Settings.validate(f, f.default) == true) end
check("manifest: registry accepts it", require("core/registry").validate(M) == true)
eq("manifest: sizes", table.concat(M.sizes, ","), "2x2,4x2,1x1")
check("manifest: local", M.net == false)

local function tz_now(y, m, d, h) return L.day_number(y, m, d) * 86400 + ((h or 12) + 3) * 3600 end
local ctx = T.ctx({ now = tz_now(2026, 10, 16) })
-- the app reads the local date through os.date: run the test in UTC-3 for this part
local orig_date = os.date
os.date = function(fmt, ts) return orig_date(fmt:sub(1, 1) == "!" and fmt or ("!" .. fmt), (ts or os.time()) - 3 * 3600) end

local calls = {}
local function w() return { getSize = function() return { w = 10, h = 10 } end } end
ctx.ui = { theme = require("ui/theme"),
    text = w, textbox = w, box = function(o) return o end, space = w, vstack = w,
    rows = function(_, rows) for _, r in ipairs(rows) do calls[#calls + 1] = { r.title, r.on_tap } end; return w() end,
    row = function(o) calls[#calls + 1] = { o.title, o.on_tap, o.right }; return w() end,
    button = function(o) calls[#calls + 1] = { o.label, o.on_tap }; return w() end,
    button_row = function(specs) for _, s in ipairs(specs) do calls[#calls + 1] = s end; return w() end }
local function build(screen, args)
    calls = {}
    return M.screens[screen](ctx, args, { w = 584, h = 608, landscape = false })
end
local function tap(label) for _, s in ipairs(calls) do if s[1] == label then s[2](); return true end end return false end

ctx.data_store.items = { { name = "Férias", date = "2026-12-25" } }
M.init(ctx)
eq("init reads the store once", ctx.data_reads, 1)
build("main"); build("main")
eq("rendering does not read the store", ctx.data_reads, 1)
check("main row is the sentence", calls[1][1] == "faltam 70 dias para Férias", calls[1][1])

-- new countdown: draft, name, date, save
tap("Nova")
eq("new opens the editor", ctx.opened[1], "edit")
build("edit", {})
check("editor has Nome, Data, Salvar and no Apagar", tap("Salvar") and not tap("Apagar"))
eq("saving an empty draft is refused", ctx.toasts[#ctx.toasts], "Escreva um nome")
build("edit", {}); tap("Nome")
local inp = ctx.inputs[#ctx.inputs]
local ok, msg = inp.on_save("   ")
check("name: empty refused", ok == false and msg == "Escreva um nome")
check("name: accepted", inp.on_save("Aniversário") == true)
build("edit", {}); tap("Data")
inp = ctx.inputs[#ctx.inputs]
ok, msg = inp.on_save("2026-02-30"); check("date: impossible day refused", ok == false and msg == "Essa data não existe", msg)
ok, msg = inp.on_save("amanhã"); check("date: format refused", ok == false and msg:find("AAAA%-MM%-DD") ~= nil, msg)
check("date: accepted", inp.on_save("2026-10-20") == true)
build("edit", {}); tap("Salvar")
eq("saved: two countdowns", #A.items, 2)
eq("saved: persisted", #ctx.data_store.items, 2)
eq("saved: went back", ctx.backs, 1)
eq("saved: toast", ctx.toasts[#ctx.toasts], "Contagem salva")

-- the limit of 3
local backs = 0
ctx.back = function() backs = backs + 1 end
build("main"); tap("Nova"); build("edit", {})
M.screens.edit(ctx, {}, { w = 584, h = 608 })
A.draft.name, A.draft.date = "Terceira", "2026-11-01"
build("edit", {}); tap("Salvar")
eq("three countdowns", #A.items, 3); eq("went back after saving", backs, 1)
build("main"); tap("Nova")
eq("a fourth is refused with a toast", ctx.toasts[#ctx.toasts], "Máximo de 3 contagens")

-- edit an existing one, then delete with confirmation
build("main"); tap("faltam 70 dias para Férias")
eq("edit: opens with the index", ctx.opened[2].idx, 1)
eq("edit: draft is a copy", A.draft.name, "Férias")
build("edit", { idx = 1 })
check("edit: Apagar is there", tap("Apagar"))
check("delete: confirmation first", ctx.confirmed ~= nil and #A.items == 3)
ctx.confirmed.ok()
eq("deleted", #A.items, 2); eq("deleted: persisted", #ctx.data_store.items, 2)
eq("deleted: went back", backs, 2)

-- the editor survives a lost draft (route restored)
A.draft = nil
local res = build("edit", { idx = 1 })
check("editor rebuilds its draft from the route", res and res.body and A.draft and A.draft.idx == 1)

-- refresh: notifies on the day only
ctx.settings_store.notify_today = true
ctx.data_store.items = { { name = "Hoje", date = "2026-10-16" }, { name = "Depois", date = "2026-10-17" } }
M.init(ctx)
local done_called, notes_at_done
M.refresh(ctx, function(ok) done_called = ok; notes_at_done = #ctx.notes end)
eq("refresh: done(true)", done_called, true)
eq("refresh: notifies after done (so the first one is armed)", notes_at_done, 0)
eq("refresh: one notification", #ctx.notes, 1); eq("refresh: title", ctx.notes[1].title, "Hoje: Hoje")
ctx.settings_store.notify_today = false
M.refresh(ctx, function() end)
eq("refresh: setting off, no notification", #ctx.notes, 1)

os.date = orig_date
