-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (C) 2026 Tinta contributors
-- Bateria app: texts pt (default) and en (manifest.strings, ctx.i18n). Same keys and specifiers in both
-- (apps/bateria/tests).
return {
    pt = {
        name = "Bateria",
        no_reading = "sem leitura do medidor",
        ma = "%d mA",
        temp = "%d °C",
        -- estimate lines (screen / widget)
        left = "%s restantes",
        left_ma = "%s restantes · %s em média",
        calibrating = "calibrando a estimativa…",
        calibrating_short = "calibrando…",
        charging_eta = "⚡ carregando · %s até 100%%",
        charging_eta_short = "⚡ %s até 100%%",
        charging_calibrating = "⚡ carregando · calibrando…",
        charged = "⚡ carga completa",
        -- stat blocks
        stat_mean = "média",
        stat_full = "mAh cheia",
        stat_temp = "temperatura",
        stat_samples = "amostras",
        -- chart
        chart_empty = "Gráfico: ainda sem amostras suficientes no log.",
        chart_note = "Gráfico: %s a %s, %d%% a %d%%.",
        basis_mah = "Estimativa pelo contador de carga (mAh).",
        basis_pct = "Estimativa pela porcentagem.",
        basis_saved = "Estimativa calibrada pela descarga anterior.",
        -- notifications (8.6)
        n_low_title = "Bateria em %d%%",
        n_low_body = "%s restantes com a Tinta aberta",
        n_low_body_noeta = "conecte o carregador",
        n_full_title = "Carga completa",
        n_full_body = "pode desconectar o cabo",
        -- import (16.4)
        imported = "log antigo importado: %d linhas",
    },
    en = {
        name = "Battery",
        no_reading = "no gauge reading",
        ma = "%d mA",
        temp = "%d °C",
        left = "%s left",
        left_ma = "%s left · %s on average",
        calibrating = "calibrating the estimate…",
        calibrating_short = "calibrating…",
        charging_eta = "⚡ charging · %s to 100%%",
        charging_eta_short = "⚡ %s to 100%%",
        charging_calibrating = "⚡ charging · calibrating…",
        charged = "⚡ fully charged",
        stat_mean = "average",
        stat_full = "mAh full",
        stat_temp = "temperature",
        stat_samples = "samples",
        chart_empty = "Chart: not enough samples in the log yet.",
        chart_note = "Chart: %s to %s, %d%% to %d%%.",
        basis_mah = "Estimate from the charge counter (mAh).",
        basis_pct = "Estimate from the percentage.",
        basis_saved = "Estimate calibrated by the previous discharge.",
        n_low_title = "Battery at %d%%",
        n_low_body = "%s left with Tinta open",
        n_low_body_noeta = "plug in the charger",
        n_full_title = "Fully charged",
        n_full_body = "you can unplug the cable",
        imported = "old log imported: %d lines",
    },
}
