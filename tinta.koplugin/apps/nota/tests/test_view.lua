-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (C) 2026 Tinta contributors
local T = ...
local H = require("uistub").install()
local M = require("apps/nota/init")
local A = M._A
local ctx = T.ctx()
ctx.ui = H.kit
M.init(ctx)
local LONG = ("lembrar de comprar pão e leite, ligar para o dentista às 14h, pagar a conta de luz. "):rep(12)
local notes = { empty = "", short = "ligar para o dentista", long = LONG }
for _, kind in ipairs({ "empty", "short", "long" }) do
    ctx.data_store.text = notes[kind] ~= "" and notes[kind] or nil
    A.loaded = false
    for _, big in ipairs({ false, true }) do
        ctx.settings_store.big_text = big
        for _, orient in ipairs({ "portrait", "landscape" }) do
            for _, size in ipairs(M.sizes) do
                for _, inv in ipairs({ false, true }) do
                    local box = H.cell(size, orient, inv)
                    local name = ("widget %s %s %s%s%s"):format(kind, size, orient, inv and " inverted" or "", big and " big" or "")
                    H.widget(T, name, function() return M.widget(ctx, size, box) end, box)
                    T.check(name .. ": title", H.has("Nota"))
                    if kind == "empty" then T.check(name .. ": placeholder", H.has("toque para escrever")) end
                    if kind == "short" then T.check(name .. ": text", H.has("ligar para o dentista")) end
                    if kind == "long" then
                        local cut = false
                        for _, tx in ipairs(H.texts) do if tostring(tx):find("…", 1, true) then cut = true end end
                        T.check(name .. ": long text is cut with …", cut)
                    end
                end
            end
        end
        for _, b in ipairs({ { w = 584, h = 608, landscape = false }, { w = 784, h = 408, landscape = true } }) do
            local name = ("screen %s %s%s"):format(kind, b.landscape and "landscape" or "portrait", big and " big" or "")
            H.screen(T, name, function() return M.screens.main(ctx, nil, b) end, b)
            T.check(name .. ": buttons", H.has(kind == "empty" and "Escrever" or "Editar"))
        end
    end
end
