-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (C) 2026 Tinta contributors
local T = ...
local H = require("uistub").install()
local M = require("apps/contagem/init")
local A = M._A
local L = require("apps/contagem/logic")
local ctx = T.ctx({ now = L.day_number(2026, 10, 16) * 86400 + 15 * 3600 })
ctx.ui = H.kit
local orig_date = os.date
os.date = function(fmt, ts) return orig_date(fmt:sub(1, 1) == "!" and fmt or ("!" .. fmt), (ts or os.time()) - 3 * 3600) end
local sets = {
    empty = {},
    one = { { name = "Férias", date = "2026-12-25" } },
    three = { { name = "Férias de verão em família", date = "2026-12-25" }, { name = "Aniversário", date = "2026-10-16" },
        { name = "Mudança", date = "2026-09-01" } },
}
for _, kind in ipairs({ "empty", "one", "three" }) do
    ctx.data_store.items = sets[kind]
    M.init(ctx)
    for _, orient in ipairs({ "portrait", "landscape" }) do
        for _, size in ipairs(M.sizes) do
            for _, inv in ipairs({ false, true }) do
                local box = H.cell(size, orient, inv)
                local name = ("widget %s %s %s%s"):format(kind, size, orient, inv and " inverted" or "")
                H.widget(T, name, function() return M.widget(ctx, size, box) end, box)
                if kind == "empty" and size ~= "1x1" then T.check(name .. ": placeholder", H.has("toque para criar")) end
                if kind == "one" and size == "1x1" then T.check(name .. ": just N", H.has("70")) end
                if kind == "one" and size ~= "1x1" then T.check(name .. ": N days", H.has("70 dias")) end
                if kind == "three" and size == "1x1" then T.check(name .. ": today", H.has("hoje")) end
            end
        end
    end
    for _, b in ipairs({ { w = 584, h = 608, landscape = false }, { w = 784, h = 408, landscape = true } }) do
        local name = ("main %s %s"):format(kind, b.landscape and "landscape" or "portrait")
        H.screen(T, name, function() return M.screens.main(ctx, nil, b) end, b)
        T.check(name .. ": Nova", H.has("Nova"))
        if kind == "one" then T.check(name .. ": sentence", H.has("faltam 70 dias para Férias")) end
        if kind == "three" then T.check(name .. ": today and past rows", H.has("hoje: Aniversário") and H.has("há 45 dias: Mudança")) end
        if kind == "empty" then T.check(name .. ": empty text", H.has("Nenhuma contagem ainda.")) end
    end
end
for _, idx in ipairs({ false, 1 }) do
    for _, b in ipairs({ { w = 584, h = 608, landscape = false }, { w = 784, h = 408, landscape = true } }) do
        ctx.data_store.items = sets.one
        M.init(ctx)
        A.draft = idx and { idx = 1, name = "Férias", date = "2026-12-25" } or { idx = nil, name = "Novo" }
        local name = ("edit %s %s"):format(idx and "existing" or "new", b.landscape and "landscape" or "portrait")
        H.screen(T, name, function() return M.screens.edit(ctx, idx and { idx = 1 } or {}, b) end, b)
        T.check(name .. ": Salvar", H.has("Salvar"))
        if idx then T.check(name .. ": Apagar and the sentence", H.has("Apagar") and H.has("faltam 70 dias para Férias")) end
    end
end
os.date = orig_date
