-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (C) 2026 Tinta contributors
-- Tinta: first run (spec 7.5), sleep-page privacy (8.5) and text size (6.1), on the headless UI smoke's stubs.
-- tests/tinta_ui_smoke.lua hands over to the scenario below instead of its own flow:
--   * the wizard never shows on an existing install (a saved layout, a legacy import, an app version mark, a saved
--     Tinta setting, first_run_done), and shows on a fresh one;
--   * it walks the four screens (language, Wi-Fi, apps, sleep), writes a valid layout, and never comes back;
--   * "Pular tudo" writes no layout and never comes back; leaving it any other way counts as done;
--   * an app with `sensitive = true` (Nota) is a placeholder with its name on the sleep page of a fresh install,
--     keeps showing on an install that existed before the option, and the strip can hide titles;
--   * with large text every widget of Home keeps its texts inside its box.
--   luajit tests/tinta_ui_firstrun.lua       (from the repo root; also run by tests/tinta_ui_scales.lua)
_G.SMOKE_SCENARIO = function(x)
    local TA = dofile("tests/testapps.lua")   -- apps the flows lean on (private ones when in the tree)
    local S2 = TA.sens2 or "bateria"          -- a second app with sensitive = true, when there is one
    local Host, check, step, tap_text, contains_text = x.Host, x.check, x.step, x.tap_text, x.contains_text
    local Store = require("core/store")
    local FirstRun = require("core/firstrun")
    local T = require("ui/theme")

    Host:close(); x.run_scheduled(1)           -- the smoke opened the Tinta with the fake test apps; this scenario opens its own
    Host.DEFAULTS.dev_apps = false

    -- every open of this scenario uses the store it is given (the real one would be a SQLite file that persists)
    local shared
    local real_open = Store.open
    Store.open = function() return shared, nil end
    local function fresh() shared = Store.memory(); return shared end
    local function open(opts)
        local win = x.open(opts or { first_run = true })
        return win
    end
    local function route_kinds(win)
        local k = {}
        for i, r in ipairs(win.stack) do k[i] = r.kind end
        return table.concat(k, ">")
    end
    local function names(list) local o = {} for i, it in ipairs(list or {}) do o[i] = it.app end return table.concat(o, ",") end

    ---------------------------------------------------------------- existing installs never see it
    local existing = {
        ["a saved home layout"] = function(s) s:layout_set("home", { { app = TA.a, size = "4x4" } }) end,
        ["a saved sleep layout"] = function(s) s:layout_set("sleep", { { app = TA.a, size = "4x4" } }) end,
        ["a legacy import mark"] = function(s) s:meta_set("legacy_imported:" .. TA.a, "1") end,
        ["an app version mark"] = function(s) s:meta_set("app_version:" .. TA.b, 1) end,
        ["a saved tinta setting"] = function(s) s:set("portal", "lang", "en") end,
        ["first_run_done"] = function(s) s:meta_set("first_run_done", "1") end,
    }
    local order = {}
    for k in pairs(existing) do order[#order + 1] = k end
    table.sort(order)
    for _, name in ipairs(order) do
        local s = fresh()
        existing[name](s)
        local win = open()
        check("existing install (" .. name .. "): no wizard", route_kinds(win) == "home" and not Host.first_run, route_kinds(win))
        check("existing install (" .. name .. "): not marked pending", s:meta_get("first_run_pending") == nil)
        x.close()
    end
    -- the pure rule too (ids are the app folders)
    do
        local s = fresh()
        check("rule: an empty store is fresh", FirstRun.needed(s, { TA.a, TA.b }) == true)
        s:set("portal", "idle_mode", "battery")   -- what core/settings writes on creation
        check("rule: the seeded idle_mode alone is still fresh", FirstRun.needed(s, { TA.a }) == true)
        s:set("portal", "wake", 900)
        check("rule: any other saved Tinta setting means existing", FirstRun.needed(s, { TA.a }) == false)
        local p = fresh()
        FirstRun.mark_pending(p)
        p:meta_set("app_version:" .. TA.a, 1)   -- written by the first open itself
        check("rule: pending stays fresh even with the marks the first open wrote", FirstRun.needed(p, { TA.a }) == true)
        p:layout_set("home", {})
        check("rule: a saved layout ends it", FirstRun.needed(p, { TA.a }) == false)
        FirstRun.mark_done(p, "5")
        check("rule: done", p:meta_get("first_run_done") == "5" and p:meta_get("first_run_pending") == nil)
    end
    -- the dev mode of the smoke (fake test apps) never shows it either
    do
        local s = fresh()
        Host.DEFAULTS.dev_apps = true
        local win = x.open({})
        check("dev apps: no wizard", route_kinds(win) == "home")
        x.close()
        Host.DEFAULTS.dev_apps = false
    end

    ---------------------------------------------------------------- fresh install: the walk
    local s = fresh()
    local win = open()
    check("fresh: the wizard opens over Home", route_kinds(win) == "home>wizard" and Host.first_run == true, route_kinds(win))
    check("fresh: pending is recorded", s:meta_get("first_run_pending") == "1")
    check("fresh: the layouts are not written yet", s:layout_get("home") == nil and s:layout_get("sleep") == nil)
    step("wizard 1: welcome", function() win:render("full") end)
    check("wizard 1: welcome text and language", contains_text(win[1], "Bem-vindo à Tinta") and contains_text(win[1], "Idioma"))
    check("wizard 1: step counter", contains_text(win[1], "1 de 4"))
    step("wizard 1: language to English", function() check("tap language", tap_text("Idioma")) end)
    check("wizard 1: English", Host:get("lang") == "en" and contains_text(win[1], "Welcome to Tinta"))
    step("wizard 1: language back", function() tap_text("Language") end)
    check("wizard 1: Português", Host:get("lang") == "pt" and contains_text(win[1], "Bem-vindo"))
    step("wizard: next to Wi-Fi", function() check("tap Próximo", tap_text("Próximo")) end)
    check("wizard 2: Wi-Fi", win:current().step == 2 and contains_text(win[1], "Wi-Fi ligado"))
    step("wizard 2: turn Wi-Fi off", function() check("tap Desligar", tap_text("Desligar")) end)
    check("wizard 2: it went off through NetworkMgr", Host:wifiState() == "off" and contains_text(win[1], "Wi-Fi desligado"))
    step("wizard 2: turn Wi-Fi on", function() check("tap Ligar", tap_text("Ligar o Wi-Fi")) end)
    check("wizard 2: it is on", Host:wifiState() == "on" and contains_text(win[1], "Wi-Fi ligado"))
    step("wizard: next to Apps", function() tap_text("Próximo") end)
    check("wizard 3: Apps", win:current().step == 3 and contains_text(win[1], "Quais apps ficam no Início"))
    check("wizard 3: the default Home apps start checked", (function() for _, id in ipairs(TA.checked) do if not win:current().sel[id] then return false end end return true end)())
    check("wizard 3: Sistema and Notificações are not offered", not contains_text(win[1], "Notificações")
        and not require("ui/wizlogic").candidates(Host:apps(), function(id) return Host:isProtected(id) end)[100]
        and (function() for _, id in ipairs(require("ui/wizlogic").candidates(Host:apps(), function(id) return Host:isProtected(id) end)) do
            if id == "sistema" or id == "notificacoes" then return false end end return true end)())
    check("wizard 3: the server note is there", contains_text(win[1], "Sistema → Apps"))
    step("wizard 3: drop an app", function() check("tap " .. TA.drop_name, tap_text(TA.drop_name)) end)
    step("wizard 3: next page of the list", function() if not contains_text(win[1], "Relógio") then check("tap ›", tap_text("›")) end end)
    step("wizard 3: add Relógio", function() check("tap Relógio", tap_text("Relógio")) end)
    check("wizard 3: the choice", not win:current().sel[TA.drop] and win:current().sel.relogio)
    step("wizard: back to Wi-Fi", function() tap_text("Anterior") end)
    step("wizard: forward again", function() tap_text("Próximo") end)
    check("wizard 3: the list starts on its first page again", win:current().page == 0)
    check("wizard 3: the choice survives going back", win:current().step == 3 and not win:current().sel[TA.drop] and win:current().sel.relogio)
    step("wizard: next to Repouso", function() tap_text("Próximo") end)
    check("wizard 4: Repouso rows", win:current().step == 4 and contains_text(win[1], "Dormir sozinho") and contains_text(win[1], "Atualizar a tela"))
    check("wizard 4: the last step finishes", contains_text(win[1], "Concluir") and not contains_text(win[1], "Próximo"))
    local idle0 = Host:get("idle_mode")
    step("wizard 4: sleep by itself cycles", function() tap_text("Dormir sozinho") end)
    check("wizard 4: idle_mode changed", Host:get("idle_mode") ~= idle0)
    local wake0 = Host:get("wake")
    step("wizard 4: refresh cycles", function() tap_text("Atualizar a tela") end)
    check("wizard 4: wake changed", Host:get("wake") ~= wake0)
    step("wizard: finish", function() check("tap Concluir", tap_text("Concluir")) end)
    check("finish: back on Home", route_kinds(win) == "home")
    check("finish: first_run_done set, pending cleared", s:meta_get("first_run_done") ~= nil and s:meta_get("first_run_pending") == nil)
    local home, sleep = s:layout_get("home"), s:layout_get("sleep")
    check("finish: Home layout written with the choice", home ~= nil and names(home) == TA.exp_home, names(home))
    check("finish: sleep layout written (no dropped app, no Sistema)", sleep ~= nil and names(sleep) == TA.exp_sleep, names(sleep))
    local valid = true
    for _, page in ipairs({ home, sleep }) do
        for _, it in ipairs(page) do
            local m = Host:app(it.app)
            local ok = false
            for _, sz in ipairs(m and m.sizes or {}) do if sz == it.size then ok = true end end
            if not ok then valid = false end
        end
    end
    check("finish: every item is a registered app at a size it declares", valid)
    step("finish: Home shows the chosen apps", function() win:render("full") end)
    check("finish: Relógio on Home, the dropped app not", (function()
        local has = {}
        for _, it in ipairs(Host:packedPages("home", 6, 8)[1]) do has[it.app] = true end
        return has.relogio and not has[TA.drop]
    end)())
    check("finish: the Home is not empty", #Host:packedPages("home", 6, 8)[1] > 0)
    x.close()
    win = open()
    check("reopen: the wizard never comes back", route_kinds(win) == "home" and not Host.first_run)
    x.close()

    ---------------------------------------------------------------- skipped, or left any other way
    s = fresh()
    win = open()
    step("wizard: next to Wi-Fi (to skip from step 2)", function() tap_text("Próximo") end)
    step("wizard: Pular tudo", function() check("tap Pular tudo", tap_text("Pular tudo")) end)
    check("skip: back on Home, done, no layout written (the default applies)",
        route_kinds(win) == "home" and s:meta_get("first_run_done") ~= nil and s:layout_get("home") == nil and s:layout_get("sleep") == nil)
    check("skip: the default Home shows", #Host:packedPages("home", 6, 8)[1] > 0)
    x.close()
    win = open()
    check("skip: never comes back", route_kinds(win) == "home")
    x.close()

    s = fresh()
    win = open()
    x.close()
    win = open()
    check("closed in the middle: it comes back (even though the first open registered the apps)", route_kinds(win) == "home>wizard", route_kinds(win))
    step("wizard: the Início button", function() win:goHome() end)
    check("left by the navigation bar: done", route_kinds(win) == "home" and s:meta_get("first_run_done") ~= nil and not Host.first_run)
    x.close()
    s = fresh()
    win = open()
    win:back()
    check("left by the back gesture: done", route_kinds(win) == "home" and s:meta_get("first_run_done") ~= nil)
    x.close()

    ---------------------------------------------------------------- sleep-page privacy (8.5)
    -- a fresh install: the sensitive apps start hidden, the others shown
    s = fresh()
    win = open()
    tap_text("Pular tudo")
    check("privacy: the sensitive apps start hidden on a fresh install", Host:sleepVisible("nota") == false and (not TA.sens2 or Host:sleepVisible(TA.sens2) == false))
    check("privacy: the others start shown", Host:sleepVisible("bateria") == true and Host:sleepVisible(TA.a) == true)
    local nctx = Host.c.registry:ctx("nota")
    nctx.data:set("text", "segredo da nota")
    require("apps/nota/init")._A.loaded = false
    Host:saveLayout("sleep", { { app = "nota", size = "2x2" }, { app = S2, size = "2x4" }, { app = "bateria", size = "2x2" },
        { app = "notificacoes", size = "4x2" } })
    Host:saveLayout("home", { { app = "nota", size = "2x2" } })
    step("privacy: Home still shows the note", function() win:render("full") end)
    check("privacy: the note is on Home", contains_text(win[1], "segredo da nota"))
    Host.sleeping = true
    step("privacy: sleep page", function() win:render("full") end)
    check("privacy: Nota is a placeholder with its name, its text is not drawn", contains_text(win[1], "Nota") and not contains_text(win[1], "segredo"))
    check("privacy: a second sensitive app is a placeholder too", not TA.sens2 or contains_text(win[1], TA.b_name))
    check("privacy: a shown app still draws (Bateria)", contains_text(win[1], "%") or contains_text(win[1], "Bateria"))
    check("privacy: a placeholder has no refresh footer", not contains_text(win[1], "atualizado 10:00 atualizado 10:00"))
    Host:setSleepVisible("nota", true)
    step("privacy: Nota allowed", function() win:render("full") end)
    check("privacy: allowed, the note shows", contains_text(win[1], "segredo da nota"))
    Host.sleeping = false
    Host:setSleepVisible("nota", false)
    -- Sistema → Apps → Nota has the row and it toggles
    step("privacy: Sistema → Apps → Nota", function() win:goHome(); win:openApp("sistema", "app", { id = "nota" }) end)
    check("privacy: the row says oculto", contains_text(win[1], "Mostrar na página de repouso") and contains_text(win[1], "oculto"))
    step("privacy: tap the row", function() check("tap row", tap_text("Mostrar na página de repouso")) end)
    check("privacy: now shown", Host:sleepVisible("nota") == true and contains_text(win[1], "sim"))
    -- the strip
    win:goHome()
    Host:emit("sistema", { key = "s1", prio = "alta", title = "Titulo reservado" })
    win:clearBanner()   -- the awake banner (R-T5) is not part of the sleep page
    Host.sleeping = true
    step("strip: titles shown", function() win:render("full") end)
    check("strip: with the title", contains_text(win[1], "1 não lida: Titulo reservado"))
    Host:set("sleep_titles", "hide")
    step("strip: titles hidden", function() win:render("full") end)
    check("strip: count only", contains_text(win[1], "1 não lida") and not contains_text(win[1], "Titulo reservado"),
        tostring(contains_text(win[1], "1 não lida")))
    Host:emit("sistema", { key = "s2", prio = "alta", title = "Outro titulo" })
    win:clearBanner()
    win:render("full")
    check("strip: several, count only", contains_text(win[1], "2 não lidas") and not contains_text(win[1], "Outro titulo"))
    Host.sleeping = false
    step("strip: Sistema → Repouso has the setting", function() win:goHome(); win:openApp("sistema", "sleep") end)
    check("strip: row 'Títulos na tela de repouso' = esconder", contains_text(win[1], "Títulos na tela de repouso") and contains_text(win[1], "esconder"))
    x.close()

    -- an install that existed before the option keeps its sleep page: nothing becomes a placeholder
    s = fresh()
    s:layout_set("home", { { app = TA.b, size = "2x4" } })
    win = open()
    check("privacy: an existing install keeps showing the sensitive apps on the sleep page",
        Host:sleepVisible("nota") == true and Host:sleepVisible(S2) == true)
    x.close()
    -- ...and an explicit choice is never overwritten
    s = fresh()
    s:layout_set("home", { { app = TA.b, size = "2x4" } })
    s:set("nota", "sleep_show", "hidden")
    win = open()
    check("privacy: a saved choice survives", Host:sleepVisible("nota") == false and Host:sleepVisible(S2) == true)
    x.close()

    ---------------------------------------------------------------- text size (6.1)
    s = fresh()
    s:layout_set("home", { { app = TA.a, size = "4x4" }, { app = TA.b, size = "2x4" }, { app = "bateria", size = "2x2" },
        { app = "relogio", size = "2x2" }, { app = "timer", size = "2x2" }, { app = "nota", size = "2x2" }, { app = "contagem", size = "2x2" },
        { app = "repouso", size = "2x2" }, { app = "notificacoes", size = "2x2" }, { app = "sistema", size = "1x1" } })
    win = open()
    local function boxes_ok(label)
        win:render("full")
        x.paint()
        local bad, n = {}, 0
        local tr = x.trace()
        for _, b in ipairs(win.hot) do
            if b.painted and b.on_hold and b.layer == 0 then   -- the widget frames of Home
                n = n + 1
                for _, l in ipairs(tr) do
                    local kind, tx, ty, tw, th = l:match("^([TX]) (%-?%d+) (%-?%d+) (%-?%d+) (%-?%d+) ")
                    tx, ty, tw, th = tonumber(tx), tonumber(ty), tonumber(tw), tonumber(th)
                    if kind and tx >= b.dimen.x and tx < b.dimen.x + b.w and ty >= b.dimen.y and ty < b.dimen.y + b.h then
                        if tx + tw > b.dimen.x + b.w or ty + th > b.dimen.y + b.h then
                            bad[#bad + 1] = ("%s %s at %d,%d %dx%d in box %d,%d %dx%d"):format(kind, l:sub(1, 60), tx, ty, tw, th, b.dimen.x, b.dimen.y, b.w, b.h)
                        end
                    end
                end
            end
        end
        check(label .. ": the widgets are on Home", n >= 8, n)
        return bad
    end
    local normal_bad = boxes_ok("text normal")
    check("text normal: every text inside its widget", #normal_bad == 0, normal_bad[1])
    check("text size: starts normal", T.text == 1 and Host:get("text_size") == "normal")
    local body0, wname0, row0 = T.FONT_BODY, T.FONT_WNAME, T.ROW_H
    local sb0, nav0, bd0, gap0 = T.SB_H, T.NAV_H, T.BORDER, T.GRID_GAP
    Host:set("text_size", "large")
    local function want(base) return math.floor(base * T.s * 1.15 + 1e-6) end   -- the screen scale, then the factor
    check("text size: large applies 1.15 to the fonts", T.text == 1.15 and T.FONT_BODY == want(T.BASE.FONT_BODY)
        and T.FONT_WNAME == want(T.BASE.FONT_WNAME) and T.FONT_BODY > body0, T.FONT_BODY)
    check("text size: only fonts and the boxes of text lines grow (not the status bar, grid or borders)",
        T.SB_H == sb0 and T.NAV_H == nav0 and T.BORDER == bd0 and T.GRID_GAP == gap0 and T.ROW_H > row0)
    local large_bad = boxes_ok("text large")
    check("text large: every text inside its widget (R-W1)", #large_bad == 0, large_bad[1])
    Host:set("text_size", "normal")
    check("text size: back to normal gives the exact sizes", T.FONT_BODY == body0 and T.FONT_WNAME == wname0 and T.ROW_H == row0)
    check("text size: an invalid value is refused", select(2, Host:set("text_size", "enorme")) == "choice" and T.text == 1)
    -- saved large: applied at open
    Host:set("text_size", "large")
    x.close()
    win = open()
    check("text size: a saved 'grande' applies when the Tinta opens", T.text == 1.15 and T.FONT_BODY == want(T.BASE.FONT_BODY))
    step("text size: Sistema → Tela e navegação", function() win:goHome(); win:openApp("sistema", "screen") end)
    check("text size: the row says grande", contains_text(win[1], "Tamanho do texto") and contains_text(win[1], "grande"))
    step("text size: the popup picks normal", function()
        check("tap row", tap_text("Tamanho do texto"))
        check("popup is up", win.picker ~= nil)
        check("tap normal", tap_text("normal"))
    end)
    check("text size: normal again from the screen", Host:get("text_size") == "normal" and T.text == 1)
    x.close()
    Store.open = real_open
end
dofile("tests/tinta_ui_smoke.lua")
