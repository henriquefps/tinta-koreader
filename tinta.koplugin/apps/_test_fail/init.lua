-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (C) 2026 Tinta contributors
-- Fake test app that fails on purpose (stage 1, 16.3) to prove error isolation: widget() and the main screen
-- throw (R-E2: "Teste falha · erro na app" widget, error screen with Voltar), attention() throws (widget
-- stays normal), refresh() throws every time (R-E4: after 3 in a row the header says "erro na app" and
-- automatic refresh stops until a manual "Atualizar"). The Tinta must never close (R-E1).
return {
    id = "_test_fail",
    name = "Teste falha",
    short = "Falha",
    version = 1,
    api = 1,                -- Tinta app API this app was written for (5.1)
    sizes = { "2x2", "1x1" },
    net = false,
    defaults = { interval = 30 },
    settings = {},
    notifications = {},

    init = function(ctx)
        ctx.log("init (the next calls fail on purpose)")
    end,

    refresh = function(ctx, done)
        error("refresh falhou de propósito")
    end,

    attention = function(ctx)
        error("attention falhou de propósito")
    end,

    widget = function(ctx, size, box)
        error("widget falhou de propósito")
    end,

    screens = {
        main = function(ctx, args, box)
            error("tela falhou de propósito")
        end,
    },
}
