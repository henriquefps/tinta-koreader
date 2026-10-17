-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (C) 2026 Tinta contributors
-- Texts of the app, pt (default) and en. ctx.i18n.t("key", ...) picks Tinta language, falls back to pt, then to
-- the key. Both tables must have the same keys and the same format specifiers (the test checks it with
-- I18n.check_tables). Plain data: no require here (R-A1).
return {
    pt = {
        name = "Modelo",
        description = "App de exemplo do SDK",
        set_limit = "Avisar a cada N atualizações",
        notif_limit = "Limite atingido",
        n_limit_title = "Modelo: %d atualizações",
        n_limit_body = "Chegou ao limite de %d",
        primary = "%d atualizações",
        never = "ainda não atualizou",
        last = "última às %s",
        line_limit = "avisa a cada",
        line_limit_value = "%d",
        btn_reset = "Zerar",
        confirm_title = "Zerar o contador?",
        confirm_text = "O contador volta para 0.",
        confirm_ok = "Zerar",
        toast_reset = "Contador zerado",
    },
    en = {
        name = "Template",
        description = "SDK example app",
        set_limit = "Notify every N refreshes",
        notif_limit = "Limit reached",
        n_limit_title = "Template: %d refreshes",
        n_limit_body = "Reached the limit of %d",
        primary = "%d refreshes",
        never = "no refresh yet",
        last = "last at %s",
        line_limit = "notifies every",
        line_limit_value = "%d",
        btn_reset = "Reset",
        confirm_title = "Reset the counter?",
        confirm_text = "The counter goes back to 0.",
        confirm_ok = "Reset",
        toast_reset = "Counter reset",
    },
}
