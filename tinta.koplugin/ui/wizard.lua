-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (C) 2026 Tinta contributors
-- Tinta: first-run wizard (7.5). Four short screens on top of Home: 1 welcome + language, 2 Wi-Fi, 3 which apps go
-- to Home, 4 sleep. "Pular tudo" on every screen ends it without writing a layout (the default one applies);
-- "Concluir" writes the Home and sleep layouts. Either way the wizard never shows again (meta first_run_done). Settings
-- of the language, Wi-Fi and sleep screens apply as soon as they are tapped (they are the same ones as in Sistema).
local Button = require("ui/button")
local Draw = require("ui/draw")
local Kit = require("ui/kit")
local Row = require("ui/row")
local S = require("ui/strings")
local T = require("ui/theme")
local W = require("ui/wizlogic")

local M = {}

-- route for the window to push: { kind = "wizard", step, sel }
function M.start(win)
    local host = win.host
    local cand = W.candidates(host:apps(), function(id) return host:isProtected(id) end)
    return { kind = "wizard", step = 1, sel = W.initial(cand, host:defaultLayout("home")), page = 0 }
end

-- writes the layouts of the chosen apps (valid: known apps, sizes the apps declare)
function M.apply(host, sel)
    local home, sleep = W.layouts(sel, host:apps(), host:defaultLayout("home"), host:defaultLayout("sleep"),
        function(id) return host:isProtected(id) end)
    host:saveLayout("home", home)
    host:saveLayout("sleep", sleep)
    return home, sleep
end

-- leaves the wizard: back to Home; with `apply` the layouts are written first
function M.close(win, r, apply)
    local host = win.host
    if apply then pcall(M.apply, host, r.sel) end
    host:finishFirstRun()
    win:closeOverlays(true)
    win.stack = { win.stack[1] }
    if apply then win:showToast(S.t("wz_done_toast")) end
    win:render("full")
end

local function go(win, r, step)
    r.step, r.page = step, 0
    win:render("full")
end

local function cycle_row(host, win, key, title, text_of)
    return { title = title, right = text_of(host:get(key)),
        on_tap = function() host:cycle(key); win:render("partial") end }
end

function M.build(win, regions, r)
    local host = win.host
    local box = win:bodyBox(regions)
    local n = #W.STEPS
    local step = math.max(1, math.min(r.step or 1, n))
    local id = W.STEPS[step]
    local text = Draw.textbox(S.t("wz_" .. id .. "_text"), T.FONT_BODY, box.w, nil)
    local text_h = text:getSize().h
    local list_box = { w = box.w, h = box.h - T.BTN_H - T.GAP - text_h - T.GAP, landscape = box.landscape }
    local content
    if id == "welcome" then
        local lang = S.get_lang()
        content = Row.new{ w = box.w, title = S.t("wz_lang"), sub = S.LANG_NAMES[lang] or lang, right = lang,
            on_tap = function() host:cycle("lang"); win:render("full") end }
    elseif id == "wifi" then
        local st = host:wifiState()
        local on = st ~= "off"
        content = Row.new{ w = box.w, title = S.t("wz_wifi_state_" .. st), right = S.t(on and "wz_wifi_turn_off" or "wz_wifi_turn_on"),
            on_tap = function() host:toggleWifi(); win:render("partial") end }
    elseif id == "apps" then
        local rows = {}
        for _, app in ipairs(W.candidates(host:apps(), function(a) return host:isProtected(a) end)) do
            local on = r.sel[app] == true
            rows[#rows + 1] = { title = host:appName(app), right = S.t(on and "wz_app_on" or "wz_app_off"), inv = on,
                on_tap = function() r.sel[app] = (not on) or nil; win:render("partial") end }
        end
        content = Kit.rows(list_box, rows)
    else
        local rows = {
            cycle_row(host, win, "idle_mode", S.t("wz_idle"), function(v) return S.t("wz_idle_" .. tostring(v)) end),
            cycle_row(host, win, "wake", S.t("wz_wake"), function(v) return S.t("wz_wake_" .. tostring(v)) end),
        }
        local items = {}
        for i, row in ipairs(rows) do items[i] = Row.new{ w = box.w, title = row.title, right = row.right, on_tap = row.on_tap } end
        content = Draw.vstack(items, T.ROW_GAP)
    end
    local specs = { { S.t("wz_skip"), function() M.close(win, r, false) end } }
    if step > 1 then specs[#specs + 1] = { S.t("wz_back"), function() go(win, r, step - 1) end } end
    if step < n then
        specs[#specs + 1] = { S.t("wz_next"), function() go(win, r, step + 1) end, inv = true }
    else
        specs[#specs + 1] = { S.t("wz_finish"), function() M.close(win, r, true) end, inv = true }
    end
    local buttons = Button.row(specs, box.w, T.BTN_H)
    -- the buttons stay at the bottom of the box whatever the middle holds
    local mid_h = box.h - T.BTN_H - T.GAP
    local body = Draw.vstack({
        Draw.box{ w = box.w, h = mid_h, child = Draw.vstack({ text, content }, T.GAP) },
        buttons,
    }, T.GAP)
    return win:frameScreen(regions, S.t("wz_title"), S.t("wz_step", step, n), nil, Draw.box{ w = box.w, h = box.h, child = body })
end

return M
