-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (C) 2026 Tinta contributors
-- Relógio app: texts pt (default) and en (manifest.strings, ctx.i18n). Same keys and specifiers in both
-- (apps/relogio/tests). Weekdays wd1 = Sunday (os.date wday), months mo1 = January.
return {
    pt = {
        name = "Relógio",
        wd1 = "domingo", wd2 = "segunda", wd3 = "terça", wd4 = "quarta", wd5 = "quinta", wd6 = "sexta", wd7 = "sábado",
        mo1 = "janeiro", mo2 = "fevereiro", mo3 = "março", mo4 = "abril", mo5 = "maio", mo6 = "junho",
        mo7 = "julho", mo8 = "agosto", mo9 = "setembro", mo10 = "outubro", mo11 = "novembro", mo12 = "dezembro",
        date_order = "dm",                    -- day before month; en: "md"
        date_full = "%s, %s de %s",           -- weekday, day, month
        date_day = "%s de %s",                -- day, month (second line of the narrow widget)
        wake_today = "próximo despertar %s",
        wake_day = "próximo despertar %s %s",   -- weekday, HH:MM
        wake_none = "sem despertar agendado",
        style_label = "Estilo",
        style_hint = "como a hora aparece no widget",
        style_digital = "Digital grande",
        style_data = "Digital com data",
        style_analogico = "Analógico",
        style_minimo = "Mínimo",
        style_digital_sub = "HH:MM em tamanho grande",
        style_data_sub = "hora, dia da semana e data",
        style_analogico_sub = "mostrador com ponteiros",
        style_minimo_sub = "hora e próximo despertar",
        preview = "Pré-visualização",
    },
    en = {
        name = "Clock",
        wd1 = "Sunday", wd2 = "Monday", wd3 = "Tuesday", wd4 = "Wednesday", wd5 = "Thursday", wd6 = "Friday", wd7 = "Saturday",
        mo1 = "January", mo2 = "February", mo3 = "March", mo4 = "April", mo5 = "May", mo6 = "June",
        mo7 = "July", mo8 = "August", mo9 = "September", mo10 = "October", mo11 = "November", mo12 = "December",
        date_order = "md",
        date_full = "%s, %s %s",              -- weekday, month, day
        date_day = "%s %s",                   -- month, day
        wake_today = "next wake-up %s",
        wake_day = "next wake-up %s %s",
        wake_none = "no wake-up scheduled",
        style_label = "Style",
        style_hint = "how the time looks in the widget",
        style_digital = "Big digital",
        style_data = "Digital with date",
        style_analogico = "Analog",
        style_minimo = "Minimal",
        style_digital_sub = "HH:MM in large type",
        style_data_sub = "time, weekday and date",
        style_analogico_sub = "dial with hands",
        style_minimo_sub = "time and next wake-up",
        preview = "Preview",
    },
}
