-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (C) 2026 Tinta contributors
-- Sistema app: screens of 10.5. Each returns { title, meta, body } for the box it gets (lists are paged and
-- become two columns in landscape, ctx.ui.rows). Changes are saved at once and the screen redraws.
-- Settings, validation (R-C1..R-C3), intervals and server state come from core/ through ui/host.
local Host = require("ui/host")
local S = require("ui/strings")
local SysLogic = require("apps/sistema/logic")
local SysStrings = require("apps/sistema/strings")
local Backup = require("apps/sistema/backup")
local Dados = require("apps/sistema/dados")

local L = S.make(SysStrings)

local M = { screens = {} }
local screens = M.screens

local function redraw() Host:redraw() end

local function onoff(v, fem) return L(v and (fem and "on_f" or "on") or (fem and "off_f" or "off")) end

-- popup options { value, label } for the values of a Tinta choice setting; label(v) is the text of a value
local function options_of(values, label)
    local out = {}
    for i, v in ipairs(values) do out[i] = { value = v, label = label(v) } end
    return out
end

local function window_text(w)
    if type(w) ~= "table" or not w.from then return nil end
    return L(w.weekdays and "window_weekdays" or "window", w.from, w.to or "")
end

-- "5 min" | "nunca": the idle-sleep value for the Sistema main row
local function idle_text()
    if Host:get("idle_mode") == "never" then return L("never") end
    return L("n_min", Host:get("idle_sleep") or 5)
end

local function wifi_text(w)
    return L(w == "on" and "wifi_connected" or w == "connecting" and "wifi_connecting" or "wifi_off")
end

local function down_count()
    local n = 0
    for _, src in ipairs(SysLogic.sources(Host:apps())) do
        local st = Host:sourceState(src.id)
        if st and st.down then n = n + 1 end
    end
    return n
end

---------------------------------------------------------------- Sistema

screens.main = function(ctx, args, box)
    local w = Host:wifiState()
    local nsrc = #SysLogic.sources(Host:apps())
    local down = down_count()
    local stats = Host:stats()
    local rows = {
        { title = L("wifi"), sub = wifi_text(w), right = L(w == "off" and "wifi_turn_on" or "wifi_turn_off"),
          on_tap = function() Host:toggleWifi() end },
        { title = L("organize"), sub = L("organize_sub"), right = "›", on_tap = function() Host.window:openOrganizer("home") end },
        { title = L("notifications"), sub = L("notifications_sub"), right = "›", on_tap = function() ctx.open("notifs") end },
        { title = L("updates"), sub = L(Host:quietOn() and "updates_sub_quiet" or "updates_sub"), right = "›",
          on_tap = function() ctx.open("updates") end },
        { title = L("sleep"), sub = L("sleep_sub", idle_text(), L("wake_" .. tostring(Host:get("wake") or "schedule"))),
          right = "›", on_tap = function() ctx.open("sleep") end },
        { title = L("connections"), sub = nsrc == 0 and L("conn_none") or down > 0 and L("conn_down", down) or L("conn_all_ok"),
          right = "›", inv = down > 0, on_tap = function() ctx.open("conn") end },
        { title = L("screen"), sub = L(Host:get("nav") == "gestures" and "nav_gestures" or "nav_bar") .. " · "
            .. L(Host:get("landscape") and "landscape" or "portrait"), right = "›",
          on_tap = function() ctx.open("screen") end },
        { title = L("apps"), sub = L("apps_sub"), right = "›", on_tap = function() ctx.open("apps") end },
        { title = L("data"), sub = L("db_file") .. " · " .. SysLogic.size_text(stats.bytes, S.get_lang()), right = "›",
          on_tap = function() ctx.open("data") end },
        { title = L("exit"), sub = L("exit_sub"), right = "›", on_tap = function() Host:close() end },
    }
    return { title = Host:appName("sistema"), meta = "", body = ctx.ui.rows(box, rows) }
end

---------------------------------------------------------------- Notificações (preferences, R-T2, R-T5, R-T11)

local function types_text(m)
    if m.id == "sistema" then return L("n_types") end
    local t = {}
    for _, n in ipairs(m.notifications or {}) do
        t[#t + 1] = type(n) == "table" and (n.label or n.type) or tostring(n)
    end
    if #t == 0 then return L("notif_types_none") end
    return table.concat(t, ", ")
end

screens.notifs = function(ctx, args, box)
    local prio_options = options_of(Host:choices("notify_pref") or { "alta", "normal", "desligada" }, function(v) return L("prio_" .. v) end)
    local rows = {}
    for _, m in ipairs(Host:apps()) do
        if m.id ~= "notificacoes" then
            local pref = Host:getPref(m.id)
            rows[#rows + 1] = { title = Host:appName(m.id), sub = types_text(m), right = L("prio_" .. pref),
                on_tap = function() ctx.choose(Host:appName(m.id), prio_options, pref, function(v) Host:setPref(m.id, v); redraw() end) end }
        end
    end
    rows[#rows + 1] = { title = L("banner"), sub = L("banner_sub"), right = onoff(Host:get("banner")),
        on_tap = function() Host:set("banner", not Host:get("banner")); redraw() end }
    rows[#rows + 1] = { title = L("sleep_shows"), sub = L("sleep_shows_sub"), right = L("shows_" .. (Host:get("sleep_shows") or "alta")),
        on_tap = function() Host:pickSetting(L("sleep_shows"), "sleep_shows", function(v) return L("shows_" .. v) end) end }
    return { title = L("notifications"), meta = "", body = ctx.ui.rows(box, rows) }
end

---------------------------------------------------------------- Atualizações (R-U1, R-U2, R-U3)

screens.updates = function(ctx, args, box)
    local now = os.time()
    local rows = {}
    local interval_options = Host:intervalOptions()
    for _, m in ipairs(Host:apps()) do
        if m.refresh then
            local interval = Host:interval(m.id)
            local sub
            if interval == 0 then sub = L("manual_only")
            else
                local nxt = Host:nextRun(m.id)
                local left = nxt and (nxt - now) or nil
                if not left then sub = L("manual_only")
                elseif left <= 0 then sub = L("next_now")
                elseif left < 60 then sub = L("next_in_s", left)
                else sub = L("next_in_min", math.floor(left / 60 + 0.5)) end
            end
            if not m.net then sub = L("local_app") .. " · " .. sub end
            local wt = window_text(Host:appWindow(m.id))
            if wt then sub = sub .. " · " .. wt end
            rows[#rows + 1] = { title = Host:appName(m.id), sub = sub, right = Host:every(interval),
                on_tap = function()
                    ctx.choose(Host:appName(m.id), interval_options, interval, function(v) Host:setInterval(m.id, v); redraw() end)
                end }
        end
    end
    rows[#rows + 1] = { title = L("quiet"), sub = L("quiet_sub"), right = onoff(Host:quietOn()),
        on_tap = function() Host:toggleQuiet(); redraw() end }
    return { title = L("updates"), meta = "", body = ctx.ui.rows(box, rows) }
end

---------------------------------------------------------------- Repouso (10.5, 11.4)

screens.sleep = function(ctx, args, box)
    local n = 0
    for _, it in ipairs(Host:layout("sleep")) do if not it.hidden and Host:app(it.app) then n = n + 1 end end
    local mode = Host:get("idle_mode") or "battery"
    local wake = Host:get("wake") or "schedule"
    local rows = {
        { section = L("sec_when") },
        { title = L("idle"), sub = L("idle_sub_" .. mode), right = L("mode_" .. mode),
          on_tap = function()
              Host:pickSetting(L("idle"), "idle_mode", function(v) return L("mode_" .. v) end, nil, function(v) return L("idle_sub_" .. v) end)
          end },
        { title = L("sleep_now"), sub = L("sleep_now_sub"), right = "›", on_tap = function() Host:sleepNow() end },
        { section = L("sec_while") },
        { title = L("wake_screen"), sub = L("wake_screen_sub"), right = L("wake_" .. tostring(wake)),
          on_tap = function() Host:pickSetting(L("wake_screen"), "wake", function(v) return L("wake_" .. tostring(v)) end) end },
    }
    if mode ~= "never" then
        -- the minutes row only when the mode can sleep by itself; it sits right after the mode row
        table.insert(rows, 3, { title = L("idle_after"), sub = L("idle_after_sub"), right = L("n_min", Host:get("idle_sleep") or 5),
            on_tap = function() Host:pickSetting(L("idle_after"), "idle_sleep", function(v) return L("n_min", v) end) end })
    end
    if wake == "schedule" then
        -- the fixed bands of 11.4: plain text, not a row (nothing to tap)
        rows[#rows + 1] = { note = { L("sched_l1"), L("sched_l2"), L("sched_l3"), L("sched_l4") } }
    end
    rows[#rows + 1] = { title = L("sleep_titles"), sub = L("sleep_titles_sub"),
        right = L("titles_" .. (Host:get("sleep_titles") or "show")),
        on_tap = function() Host:pickSetting(L("sleep_titles"), "sleep_titles", function(v) return L("titles_" .. v) end) end }
    rows[#rows + 1] = { title = L("sleep_page"), sub = L("sleep_page_sub", n), right = "›",
        on_tap = function() Host.window:openOrganizer("sleep") end }
    return { title = L("sleep"), meta = "", body = ctx.ui.rows(box, rows) }
end

---------------------------------------------------------------- Conexões (8.6)

local function local_ip()
    local ok, ip = pcall(function()
        local NetworkMgr = require("ui/network/manager")
        local iface = NetworkMgr:getNetworkInterfaceName() or "wlan0"
        if not tostring(iface):match("^[%w%-]+$") then return nil end
        local p = io.popen("ip -4 addr show " .. iface .. " 2>/dev/null")
        if not p then return nil end
        local out = p:read("*a")
        p:close()
        return out and out:match("inet (%d+%.%d+%.%d+%.%d+)")
    end)
    return ok and ip or nil
end

screens.conn = function(ctx, args, box)
    local rows = {}
    for _, src in ipairs(SysLogic.sources(Host:apps())) do
        local m = Host:app(src.apps[1])
        local s = m and Host:sourceOf(m) or {}
        local st = Host:sourceState(src.id)
        local last_ok
        for _, id in ipairs(src.apps) do
            local a = Host:state(id) or {}
            if a.last_ok and (not last_ok or a.last_ok > last_ok) then last_ok = a.last_ok end
        end
        local down = st and st.down
        local sub
        if down then
            sub = last_ok and L("conn_down_since", Host:hm(st.down_since), Host:ago(last_ok))
                or L("conn_down_since_never", Host:hm(st.down_since))
        elseif last_ok then
            local ms = st and st.latency and math.floor(st.latency + 0.5)
            sub = ms and L("conn_ok_ms", Host:ago(last_ok), ms) or L("conn_ok", Host:ago(last_ok))
        else
            sub = L("conn_unknown")
        end
        rows[#rows + 1] = { title = src.name, sub = (s.host and (s.host .. " · ") or "") .. sub, right = down and "✕" or "●", inv = down }
    end
    local w = Host:wifiState()
    local ip = w == "on" and local_ip() or nil
    rows[#rows + 1] = { title = L("wifi"), sub = ip and L("conn_wifi_ip", ip) or wifi_text(w), right = w == "on" and "●" or "✕" }
    local ui = ctx.ui
    local T = ui.theme
    local note = ui.textbox(L("conn_note"), T.FONT_MIN, box.w, T.px(60))
    local list_box = { w = box.w, h = box.h - note:getSize().h - T.GAP, landscape = false }
    return { title = L("connections"), meta = "", body = ui.vstack({ ui.rows(list_box, rows, { two_cols = false }), note }, T.GAP) }
end

---------------------------------------------------------------- Tela e navegação (R-N2, 6.8, R-R2)

screens.screen = function(ctx, args, box)
    local nav = Host:get("nav")
    local land = Host:get("landscape") == true
    local lang = S.get_lang()
    local rows = {
        { title = L("navigation"), sub = L("navigation_sub"), right = L(nav == "gestures" and "nav_gestures" or "nav_bar"),
          on_tap = function()
              Host:pickSetting(L("navigation"), "nav", function(v) return L(v == "gestures" and "nav_gestures" or "nav_bar") end,
                  function() Host.window:render("full") end)
          end },
        { title = L("orientation"), sub = L("orientation_sub"), right = L(land and "landscape" or "portrait"),
          on_tap = function() Host:rotate() end },
        { title = L("full_refresh"), sub = L("full_refresh_sub"), right = L("every_n", Host:fullEvery()) },
        { title = L("lang"), sub = S.LANG_NAMES[lang] or lang, right = lang,
          on_tap = function()
              Host:pickSetting(L("lang"), "lang", function(v) return S.LANG_NAMES[v] or v end, function() Host.window:render("full") end)
          end },
        { title = L("text_size"), sub = L("text_size_sub"), right = L("text_" .. (Host:get("text_size") or "normal")),
          on_tap = function()
              Host:pickSetting(L("text_size"), "text_size", function(v) return L("text_" .. v) end, function() Host.window:render("full") end)
          end },
    }
    return { title = L("screen"), meta = "", body = ctx.ui.rows(box, rows, { two_cols = false }) }
end

---------------------------------------------------------------- Apps (settings of each app, R-C1..R-C4)

screens.apps = function(ctx, args, box)
    local rows = {}
    for _, m in ipairs(Host:apps()) do
        local n = #(m.settings or {}) + (m.refresh and 1 or 0)
        rows[#rows + 1] = { title = Host:appName(m.id), sub = n > 0 and L("app_settings_n", n) or L("app_settings_none"), right = "›",
            on_tap = function() ctx.open("app", { id = m.id }) end }
    end
    -- 5.1, 10.5: apps that are not loaded stay in the list (turned off, or needing a newer Tinta)
    for _, e in ipairs(Host:inactiveApps()) do
        local needs = e.why ~= "disabled"
        rows[#rows + 1] = { title = Host:appName(e.id), sub = needs and L("app_needs_newer") or L("app_off_sub"), right = "›", dim = true,
            on_tap = function() ctx.open("app", { id = e.id }) end }
    end
    local removed = Host:removedApps()
    if #removed > 0 then
        rows[#rows + 1] = { title = L("apps_restore"), sub = L("apps_restore_sub", #removed), right = "›",
            on_tap = function() Host:restoreRemoved(); ctx.toast(L("restored_toast")); redraw() end }
    end
    if #rows == 0 then rows[1] = { title = L("apps"), sub = L("app_settings_none") } end
    return { title = L("apps"), meta = "", body = ctx.ui.rows(box, rows) }
end

local function choice_label(f, v)
    for _, ch in ipairs(f.choices or {}) do
        if type(ch) == "table" and ch.value == v then return ch.label or tostring(v) end
        if ch == v then return tostring(v) end
    end
    return v ~= nil and tostring(v) or ""
end

screens.app = function(ctx, args, box)
    local id = args and args.id
    local m = id and Host:app(id)
    local off = id and SysLogic.find(Host:inactiveApps(), id)
    if not m and not off then return { title = L("apps"), body = ctx.ui.text(S.t("app_missing", tostring(id))) } end
    local rows = {}
    -- 10.5: turned on / off, and removal
    local manifest = m or off.manifest or {}
    local protected = Host:isProtected(id)
    if off and off.why ~= "disabled" then
        rows[#rows + 1] = { title = L("app_needs_newer"),
            sub = off.why == "api" and L("app_needs_api", tonumber(off.api) or 1, Host:apiVersion())
                or L("app_needs_min", tostring(off.min_tinta or off.min_portal), Host:tintaVersion()) }
    else
        rows[#rows + 1] = { title = L("app_state"), sub = L(protected and "app_state_sys" or "app_state_sub"),
            right = L(off and "app_off" or "app_on"),
            on_tap = not protected and function()
                local ok, why = Host:setAppEnabled(id, off ~= nil)
                if not ok then ctx.toast(L("toggle_failed", tostring(why))) end
                redraw()
            end or nil }
    end
    if not m then
        -- not loaded: nothing to configure; only removal below
    elseif m.refresh then
        rows[#rows + 1] = { title = L("interval"), sub = L("interval_sub"), right = Host:every(Host:interval(id)),
            on_tap = function()
                ctx.choose(L("interval"), Host:intervalOptions(), Host:interval(id), function(nv) Host:setInterval(id, nv); redraw() end)
            end }
    end
    if m then
        -- 8.5: the core handles this option for every app; `sensitive` apps start hidden
        local shown = Host:sleepVisible(id)
        rows[#rows + 1] = { title = L("app_sleep_show"), sub = L("app_sleep_show_sub"), right = L(shown and "sleep_shown" or "sleep_hidden"),
            on_tap = function() Host:setSleepVisible(id, not shown); redraw() end }
    end
    for _, f in ipairs((m or {}).settings or {}) do
        local v = Host:appSetting(id, f.key)
        local right = f.type == "choice" and choice_label(f, v) or Host:appSettingText(id, f.key, L)
        local row = { title = f.label or f.key, sub = f.type == "token" and L("token_keep") or (f.hint or ""), right = right }
        if f.type == "bool" then
            row.on_tap = function() Host:setAppSetting(id, f.key, not v); redraw() end
        elseif f.type == "choice" and type(f.choices) == "table" and #f.choices > 0 then
            local options = {}
            for i, ch in ipairs(f.choices) do
                options[i] = type(ch) == "table" and { value = ch.value, label = ch.label or tostring(ch.value) } or { value = ch, label = tostring(ch) }
            end
            row.on_tap = function()
                ctx.choose(f.label or f.key, options, v, function(nv) Host:setAppSetting(id, f.key, nv); redraw() end)
            end
        else
            row.on_tap = function()
                -- R-C2: a token is never shown; the box opens empty and empty keeps the current one
                local current = f.type == "token" and "" or (v ~= nil and tostring(v) or "")
                Host:input(f.label or f.key, current, f.type == "token" and L("token_keep") or tostring(f.default or ""),
                    function(text)
                        local value = text
                        if f.type == "number" then value = tonumber(text) or text end
                        local ok, err = Host:setAppSetting(id, f.key, value)
                        if not ok then return false, L("invalid", tostring(err or text)) end
                        return true
                    end, { number = f.type == "number", password = f.type == "token" })
            end
        end
        rows[#rows + 1] = row
    end
    if not (manifest.system or protected) then
        rows[#rows + 1] = { title = L("app_remove"), sub = L("app_remove_sub"), right = "›",
            on_tap = function()
                local name = Host:appName(id)
                ctx.confirm(L("remove_title", name), L("remove_text"), L("remove_ok"), function()
                    local ok, why = Host:removeApp(id)
                    if ok then
                        ctx.toast(L("removed_toast", name))
                        ctx.back()
                    else
                        ctx.toast(L("remove_failed", tostring(why)))
                    end
                end)
            end }
    end
    return { title = Host:appName(id), meta = "", body = ctx.ui.rows(box, rows) }
end

---------------------------------------------------------------- Dados

local function message(key, ...) return key and Host.window and Host.window:showToast(L(key, ...)) end

screens.data = function(ctx, args, box)
    local stats = Host:stats()
    local rows = {
        { title = L("db_size"), sub = L("db_file"), right = SysLogic.size_text(stats.bytes, S.get_lang()) },
        { title = L("counts"), sub = L("counts_sub", tonumber(stats.notifications) or 0, tonumber(stats.log) or 0) },
        { title = L("log"), sub = L("log_open_sub"), right = "›", on_tap = function() ctx.open("log") end },
        { title = L("export_diag"), sub = L("export_diag_sub"), right = "›", on_tap = function()
            local name, err = Dados.exportDiagnostic(SysLogic.VERSION)
            if name then Host.window:showToast(name) else Host:log("sistema", "warn", "diagnostic: " .. tostring(err)); message("diag_fail") end
        end },
        { title = L("backup"), sub = L("backup_sub"), right = "›", on_tap = function()
            local name, err = Dados.exportBackup(SysLogic.VERSION)
            if name then Host.window:showToast(name) else Host:log("sistema", "warn", "backup: " .. tostring(err)); message("backup_fail") end
        end },
        { title = L("restore"), sub = L("restore_sub"), right = "›", on_tap = function() ctx.open("restore") end },
    }
    return { title = L("data"), meta = "", body = ctx.ui.rows(box, rows) }
end

-- the Tinta log (what Dados used to show under the counts)
screens.log = function(ctx, args, box)
    local ui = ctx.ui
    local T = ui.theme
    local lines = Host:logTail(500)
    local body
    if #lines == 0 then
        body = ui.text(L("log_empty"), T.FONT_MIN, false, box.w)
    else
        body = ui.paged(box, lines, function(l, w, h)
            local when = l.at and os.date("%d/%m %H:%M", l.at) or ""
            return ui.box{ w = w, h = h, border = T.BORDER, radius = T.RADIUS, pad_x = T.px(8), valign = "center",
                child = ui.vstack({
                    ui.text(when .. " · " .. (l.app or "tinta") .. " · " .. (l.level or ""), T.FONT_MIN, true, w - T.px(20)),
                    ui.text(l.msg or "", T.FONT_MIN, false, w - T.px(20)),
                }, 0) }
        end, { item_h = T.ROW_H })
    end
    return { title = L("log"), meta = "", body = body }
end

-- backups found in koreader/, newest first; a tap confirms, then restores
screens.restore = function(ctx, args, box)
    local names = Dados.backupFiles()
    local rows = {}
    for _, name in ipairs(names) do
        rows[#rows + 1] = { title = Backup.label(name), sub = name, right = "›", on_tap = function()
            ctx.confirm(L("restore_title"), L("restore_text", name), L("restore_ok"), function()
                local res, err = Dados.restore(name)
                if res then
                    local skipped = res.skipped + res.apps_newer
                    Host.window:showToast(skipped > 0 and L("restore_done_skipped", res.applied, skipped) or L("restore_done", res.applied))
                else
                    message(err == "newer" and "restore_newer" or err == "format" and "restore_bad" or "restore_read")
                end
            end)
        end }
    end
    if #rows == 0 then rows[1] = { title = L("restore"), sub = L("restore_none") } end
    return { title = L("restore"), meta = "", body = ctx.ui.rows(box, rows) }
end

return M
