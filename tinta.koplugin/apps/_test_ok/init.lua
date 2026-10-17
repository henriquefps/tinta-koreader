-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (C) 2026 Tinta contributors
-- Fake test app (stage 1, 16.3): exercises the app contract without a network. Local refresh (counter in
-- ctx.data, last value in ctx.cache), widgets in four sizes, a main screen with buttons for notifications
-- (high, normal, same key again = dedup), confirmation, toast, a second screen, attention on/off, a paged
-- list, and a button whose callback throws (R-E1: the Tinta must stay open). Generated settings (R-C1).
-- Loaded only while the Tinta setting dev_apps is on.
return {
    id = "_test_ok",
    name = "Teste OK",
    short = "OK",
    version = 1,
    api = 1,                -- Tinta app API this app was written for (5.1)
    sizes = { "2x2", "4x2", "4x4", "1x1" },
    net = false,
    defaults = { interval = 60, window = nil },
    settings = {
        { key = "url", label = "Servidor de teste", type = "url", default = "http://192.0.2.101:9999" },
        { key = "token", label = "Token de teste", type = "token" },
        { key = "limit", label = "Limite", type = "number", default = 5, min = 1, max = 20 },
        { key = "at", label = "Horário", type = "time", default = "07:30" },
        { key = "mode", label = "Modo", type = "choice", default = "a",
          choices = { { value = "a", label = "modo A" }, { value = "b", label = "modo B" } } },
        { key = "flag", label = "Opção", type = "bool", default = false },
    },
    notifications = {
        { type = "alta", label = "teste alta" },
        { type = "normal", label = "teste normal" },
    },

    init = function(ctx)
        ctx.log("init")
    end,

    refresh = function(ctx, done)
        local n = (ctx.data:get("count") or 0) + 1
        ctx.data:set("count", n)
        ctx.cache:put({ count = n, at = ctx.now() })
        done(true)
    end,

    attention = function(ctx)
        return ctx.data:get("attention") == true
    end,

    widget = function(ctx, size, box)
        local ui = ctx.ui
        local c = ctx.cache:get() or {}
        local n = c.count or 0
        if size == "1x1" then
            return ui.basic(box, { short = "OK", number = tostring(n) })
        end
        local spec = { title = "Teste OK", primary = ("%d atualizações"):format(n),
            secondary = c.at and ("última às " .. os.date("%H:%M:%S", c.at)) or "ainda não atualizou" }
        if box.cols >= 4 then
            spec.lines = { { "contador", tostring(n) }, { "atenção", ctx.data:get("attention") and "sim" or "não" } }
            if box.rows >= 4 then
                spec.lines[3] = { "tamanho", size }
                spec.lines[4] = { "caixa", box.w .. "×" .. box.h }
            end
        end
        return ui.basic(box, spec)
    end,

    screens = {
        main = function(ctx, args, box)
            local ui = ctx.ui
            local T = ui.theme
            local w = box.w
            local function key(k) return k .. ":" .. os.time() end
            local buttons = {
                { "Notificação alta", function()
                    ctx.notify{ key = key("alta"), type = "alta", prio = "alta", title = "Teste: prioridade alta",
                        body = "aberta leva ao detalhe 7", route = { "detail", { n = 7 } } }
                end },
                { "Notificação normal", function()
                    ctx.notify{ key = key("normal"), type = "normal", prio = "normal", title = "Teste: prioridade normal",
                        body = "sem rota: abre a tela principal" }
                end },
                { "Mesma key (dedup)", function()
                    ctx.notify{ key = "fixa", type = "normal", prio = "normal", title = "Teste: key fixa",
                        body = "só aparece uma vez (R-T1)" }
                    ctx.toast("Enviada key 'fixa'")
                end },
                { "Confirmar", function()
                    ctx.confirm("Executar a ação de teste?", "Nada é enviado a servidor nenhum.", "Executar",
                        function() ctx.toast("Ação de teste executada") end)
                end },
                { "Aviso curto", function() ctx.toast("Aviso de teste") end },
                { "Alternar atenção", function()
                    ctx.data:set("attention", not ctx.data:get("attention"))
                    ctx.toast(ctx.data:get("attention") and "Widget invertido" or "Widget normal")
                end },
                { "Abrir detalhe", function() ctx.open("detail", { n = 1 }) end },
                { "Botão que falha", function() error("falha de propósito no callback (R-E1)") end },
            }
            -- two buttons per line
            local lines = {}
            for i = 1, #buttons, 2 do
                local pair = { buttons[i] }
                if buttons[i + 1] then pair[2] = buttons[i + 1] end
                lines[#lines + 1] = ui.button_row(pair, w)
            end
            local top = ui.vstack(lines, T.GAP)
            local th = #lines * (T.BTN_H + T.GAP)
            local items = {}
            for i = 1, 23 do items[i] = i end
            local list = ui.paged({ w = w, h = box.h - th, landscape = box.landscape }, items, function(i, rw, rh)
                return ui.row{ w = rw, h = rh, title = "Linha " .. i, sub = "lista paginada (6.6)", right = tostring(i),
                    inv = i % 7 == 0 }
            end, { two_cols = true })
            return ui.vstack({ top, list }, 0)
        end,

        detail = function(ctx, args, box)
            local ui = ctx.ui
            local n = args and args.n or 0
            return {
                title = "Detalhe " .. tostring(n),
                body = ui.vstack({
                    ui.textbox("Segunda tela da app de teste. Voltar desempilha; Início limpa a pilha. Aberta por "
                        .. "notificação, a pilha fica Início → esta tela (R-N5).", ui.theme.FONT_BODY, box.w),
                    ui.button{ label = "Abrir detalhe " .. (n + 1), w = ui.theme.px(300), on_tap = function() ctx.open("detail", { n = n + 1 }) end },
                }, ui.theme.GAP),
            }
        end,
    },
}
