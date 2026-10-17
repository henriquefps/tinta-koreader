-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (C) 2026 Tinta contributors
-- Tinta: controller of an open Tinta. Opens the core services (through ui/core, the only door to core/),
-- loads the apps, owns the window, the scheduler tick, refresh batches, notifications (banner, opening),
-- Wi-Fi, rotation and the tinta-wide settings. A singleton module: the system apps (notificacoes, sistema)
-- and ui/kit reach the Tinta through it (Host.window, Host:...).
local Device = require("device")
local Event = require("ui/event")
local NetworkMgr = require("ui/network/manager")
local UIManager = require("ui/uimanager")
local logger = require("logger")
local Screen = Device.screen

local Org = require("ui/orglogic")
local Wakereq = require("device/wakereq")
local S = require("ui/strings")
local T = require("ui/theme")

local C   -- ui/core, required on open (it requires core/)

local Host = {
    window = nil,
    c = nil,              -- core services (ui/core.open)
    plugin_dir = nil,
}

-- Tinta settings that core/settings does not declare (its TINTA_DEFAULTS has the rest)
Host.DEFAULTS = {
    dev_apps = false,     -- load apps/_test_* (development only; the headless smoke turns it on)
}

local function now() return os.time() end

---------------------------------------------------------------- open / close

function Host:isOpen() return self.window ~= nil end

-- Guard for the bell-tap crash (docs/investigacao-crash-sino.md): KOReader's IconButton flashes its icon on tap
-- with UIManager:widgetInvert(self.image, self.dimen.x, ...), which throws when the button was never painted
-- (image.dimen nil); an unpainted button also keeps its gesture range at the screen origin, the top-left
-- corner, where the tinta's clock and bell are. While KOReader runs after the Tinta was opened once, such a
-- tap is swallowed instead of crashing, and logged with what is needed to find the button's owner.
local function guardIconButton()
    local ok, IconButton = pcall(require, "ui/widget/iconbutton")
    if not ok or type(IconButton) ~= "table" or IconButton._tinta_guard then return end
    IconButton._tinta_guard = true
    local function painted(btn) return btn.image and btn.image.dimen and btn.dimen and btn.dimen.x end
    local function report(btn, what)
        local st, names = UIManager._window_stack or {}, {}
        for i, e in ipairs(st) do
            local w = e.widget
            names[i] = tostring(w and (w.name or w.title or (w == Host.window and "tinta")) or w)
        end
        logger.warn("Tinta guard: unpainted IconButton", what, "icon=", tostring(btn.icon),
            "has_callback=", btn.callback ~= nil, "stack=", table.concat(names, " > "), debug.traceback("", 2))
    end
    for _, name in ipairs({ "onTapIconButton", "onHoldIconButton" }) do
        local orig = IconButton[name]
        if type(orig) == "function" then
            IconButton[name] = function(btn, ...)
                if not painted(btn) then report(btn, name); return true end
                return orig(btn, ...)
            end
        end
    end
end

-- opts = { plugin_dir, db_path }
function Host:open(opts)
    if self.window then return end
    guardIconButton()
    C = require("ui/core")
    self.plugin_dir = opts.plugin_dir
    self.data_dir = opts.data_dir
    self.sleeping = false
    self.wake_reqs = Wakereq.new()
    -- one-time move of the Portal-named files (database, battery log, power log) before the store opens
    local moved, move_errors = require("core/migrate").run(opts.data_dir, opts.fs)
    local Kit = require("ui/kit")
    local ok_net, Net = pcall(require, "device/net")
    self.c = C.open{
        db_path = opts.db_path, now = now,
        log = function(app, level, msg) self:log(app, level, msg) end,
        on_new = function(n) self:onNotification(n) end,
        -- what ui adds to the core part of ctx (5.2)
        extra_ctx = function(id)
            return {
                ui = Kit,
                net = ok_net and Net or nil,
                open = function(screen, args) if self.window then self.window:openApp(id, screen, args) end end,
                confirm = function(title, text, ok_label, fn)
                    if self.window then self.window:confirm{ title = title, text = text, ok_label = ok_label, on_ok = fn, owner = id } end
                end,
                toast = function(text) if self.window then self.window:showToast(text) end end,
                -- choice popup (6.10): options = values or { value, label?, sub? }; on_pick(value) runs after the tap
                choose = function(title, options, current, on_pick)
                    if self.window then
                        self.window:pick{ title = title, options = options, current = current, on_pick = on_pick, owner = id }
                    end
                end,
                redraw = function() self:redraw() end,
                back = function() if self.window then self.window:back() end end,
                -- text input with the KOReader keyboard (11.7 / CORE_CALLS): on_save(text) -> true | false, message
                input = function(title, value, hint, on_save, opts)
                    if self.window then self:input(title, value, hint, on_save, opts) end
                end,
                -- wake request (11.7): the Tinta is awake at ts, even from sleep; nil cancels
                wake_at = function(ts) self:wakeRequest(id, ts) end,
            }
        end,
    }
    if #moved > 0 then self:log(nil, "info", "Tinta: renamed from Portal: " .. table.concat(moved, ", ")) end
    for _, e in ipairs(move_errors) do self:log(nil, "error", "Tinta: rename from Portal failed: " .. e) end
    self:applyLang()
    self:applyTextSize()
    -- 7.5: the first-run check runs once, before the apps register (the fake test apps of the smoke never see it,
    -- unless a test asks with opts.first_run = true)
    self.detect_first_run = opts.first_run == true or (opts.first_run ~= false and not self:get("dev_apps"))
    self.first_run = false
    self:loadApps()
    C.import_legacy(self.c)     -- R-B5, 16.4: once per app (manifest.import_legacy), before init
    pcall(C.privacy_init, self.c, self.first_run)   -- 8.5: existing installs keep what their sleep page showed
    C.init_apps(self.c)
    self.bg_ids = C.background_ids(self.c)
    self.bg_last = nil
    self:hookBattery()
    self:enterOrientation()
    local Window = require("ui/screen")
    self.window = Window:new{ host = self }
    if self.first_run then self.window:startWizard() end
    self.window:render("full")
    UIManager:show(self.window, "full")
    self:attachSleep(opts)
    self:startTick()
    UIManager:nextTick(function() if self.window then self:tick(true) end end)
end

-- Close order (rotation safety, docs/arquitetura.md 6.8): the rotation KOReader had is restored while the
-- Tinta still covers the screen and is still the input target; only then the window closes. FileManager /
-- the reader are never rebuilt (set_rotation sends no SetRotationMode), so none of their widgets is
-- unpainted when they become the top window; a short input shield also swallows the taps aimed at the Tinta
-- that is still on the e-ink panel while the screen below repaints.
function Host:close()
    local win = self.window
    if not win then return end
    self:restoreRotation()
    UIManager:close(win)
end

-- called by the window's onCloseWidget
function Host:onWindowClosed(win)
    if win ~= self.window then return end
    self:stopTick()
    self:detachSleep()
    self:cancelWakeTimer()
    self.wake_reqs = nil
    self.window = nil
    self.battery_eta = nil
    self.input_dialog = nil
    C.close(self.c)
    self.c = nil
    -- closed by something other than Host:close (KOReader exiting, an error): restore here, never leave the
    -- rotation to a later tick
    self:restoreRotation()
    UIManager:setDirty("all", "full")
    self:shield()
end

function Host:applyLang()
    local lang = self:get("lang") or "pt"
    S.set_lang(lang)
    C.set_lang(self.c, lang)
end

---------------------------------------------------------------- apps

-- registration order: system apps first, then the rest by name (= organizer and Sistema order)
local LOAD_RANK = { notificacoes = 1, sistema = 2 }
local function loadOrder(a, b)
    local ra, rb = LOAD_RANK[a] or 9, LOAD_RANK[b] or 9
    if ra ~= rb then return ra < rb end
    return a < b
end

-- loads apps/<id>/init.lua of every folder in apps/ and <data dir>/tinta-apps/<id>/init.lua (folders starting
-- with "_" only with dev_apps). An external app whose id is a bundled one's is refused. Folders of removed apps (10.5, the removed list) are skipped, so a plugin update that copies the whole folder does not
-- bring them back. An app that needs a newer Tinta (5.1) or that was turned off (10.5) is not registered; the
-- registry keeps it for Sistema → Apps and the launcher.
function Host:loadApps()
    local lfs = require("libs/libkoreader-lfs")
    local Ext = require("core/extapps")
    local dir = self:appsDir()
    local ids = {}
    local bundled = {}          -- every folder of apps/ (even a removed one): an external app cannot take its id
    local removed = {}
    self.app_roots = {}         -- id -> the folder it was loaded from (removal deletes inside that one only)
    for _, id in ipairs(C.removed_ids(self.c)) do removed[id] = true end
    local ok_dir = pcall(function()
        for name in lfs.dir(dir) do
            if name:match("^[a-z0-9_]+$") and lfs.attributes(dir .. "/" .. name .. "/init.lua", "mode") == "file" then
                bundled[name] = true
                if removed[name] then
                    self:log(name, "info", "apps: skipped (removed)")
                elseif name:sub(1, 1) ~= "_" or self:get("dev_apps") then
                    ids[#ids + 1] = name
                    self.app_roots[name] = dir
                end
            end
        end
    end)
    if not ok_dir then self:log(nil, "error", "apps: cannot list " .. dir) end
    -- <data dir>/tinta-apps/<id>/init.lua: same rules, loaded after the bundled ones
    local ext_dir = self:externalAppsDir()
    local ext_ids = {}
    local found, ext_ok = Ext.scan(ext_dir, { dir = lfs.dir, is_file = function(p) return lfs.attributes(p, "mode") == "file" end })
    if ext_dir and not ext_ok and lfs.attributes(ext_dir, "mode") == "directory" then
        self:log(nil, "error", "apps: cannot list " .. ext_dir)
    end
    for _, name in ipairs(found) do
        if bundled[name] then
            self:log(name, "warn", "apps: external app refused, a bundled app has the same id (" .. ext_dir .. "/" .. name .. ")")
        elseif removed[name] then
            self:log(name, "info", "apps: skipped (removed)")
        elseif name:sub(1, 1) ~= "_" or self:get("dev_apps") then
            ids[#ids + 1] = name
            ext_ids[#ext_ids + 1] = name
            self.app_roots[name] = ext_dir
        end
    end
    if ext_dir then Ext.install(ext_dir, ext_ids) end
    table.sort(ids, loadOrder)
    if self.detect_first_run then
        self.detect_first_run = false
        self.first_run = C.first_run_needed(self.c, ids)
    end
    for _, id in ipairs(ids) do
        local ok, manifest = pcall(require, "apps/" .. id .. "/init")
        if ok and type(manifest) == "table" then
            local rok, rerr = pcall(C.register, self.c, manifest)
            if not rok then self:log(id, "error", "register: " .. tostring(rerr)) end
        else
            self:log(id, "error", "load: " .. tostring(manifest):match("[^\n]*"))
        end
    end
end

function Host:appsDir() return (self.plugin_dir or ".") .. "/apps" end
-- <KOReader data dir>/tinta-apps: apps that live outside the plugin folder (nil without a data dir)
function Host:externalAppsDir() return require("core/extapps").dir_of(self.data_dir) end

-- apps that are not loaded (turned off, or needing a newer Tinta): C.inactive_list entries
function Host:inactiveApps() return self.c and C.inactive_list(self.c) or {} end

-- the list of background ids and the battery hook follow the apps that are loaded
function Host:reloadHooks()
    self.bg_ids = C.background_ids(self.c)
    self:hookBattery()
end

-- 10.5 "Ativada / Desativada": takes effect at once. Returns true | nil, reason ("protected" | "unknown" | ...)
function Host:setAppEnabled(id, on)
    if not self.c then return nil, "closed" end
    if on then
        local entry = C.inactive(self.c, id)
        if not entry or entry.why ~= "disabled" then
            if C.is_disabled(self.c, id) then C.set_disabled(self.c, id, false) end
            return nil, "unknown"
        end
        C.set_disabled(self.c, id, false)
        local ok, why = C.register(self.c, entry.manifest)
        if not ok then return nil, why end
        C.sort_apps(self.c, loadOrder)
        C.import_legacy(self.c)
        C.init_app(self.c, id)
    else
        local ok, why = C.set_disabled(self.c, id, true)
        if not ok then return nil, why end
    end
    self:reloadHooks()
    return true
end

-- device file system for core/appfiles
local function deviceFs()
    local lfs = require("libs/libkoreader-lfs")
    return {
        dir = function(p) return lfs.dir(p) end,
        link = function(p) return lfs.symlinkattributes(p, "mode") == "link" end,
        is_dir = function(p) return lfs.attributes(p, "mode") == "directory" end,
        remove = function(p) return os.remove(p) end,
        rmdir = function(p) return lfs.rmdir(p) end,
    }
end

-- 10.5 "Remover app" (the caller confirmed): deletes apps/<id>/ of the plugin and clears the store data.
-- Returns true | nil, reason. Never touches anything but the folder of that id inside the apps/ (or tinta-apps/)
-- it was loaded from.
function Host:removeApp(id)
    if not self.c then return nil, "closed" end
    local ok, err = C.remove_app(self.c, id, deviceFs(), (self.app_roots or {})[id] or self:appsDir())
    if not ok then
        self:log(id, "warn", "apps: remove refused: " .. tostring(err))
        return nil, err
    end
    self:log(id, "info", "apps: removed")
    self:reloadHooks()
    return true
end

function Host:tintaVersion() return C.TINTA_VERSION end
function Host:apiVersion() return C.API_VERSION end
-- the apps that cannot be turned off or removed (notificacoes, sistema)
function Host:isProtected(id) return C.is_protected(id) end

function Host:removedApps() return self.c and C.removed_ids(self.c) or {} end
function Host:restoreRemoved() if self.c then C.clear_removed(self.c) end end

-- R-S1: the status bar estimate comes from the Bateria app (manifest.battery_eta(ctx, b) -> "~17h" | nil)
function Host:hookBattery()
    self.battery_eta = nil
    if not self.c or not C.has(self.c, "bateria", "battery_eta") then return end
    self.battery_eta = function(b)
        if not self.c then return nil end
        local ok, eta = C.call(self.c, "bateria", "battery_eta", b)
        if ok and type(eta) == "string" then return eta end
        return nil
    end
end

function Host:apps() return self.c and C.list_apps(self.c) or {} end
function Host:app(id) return id and self.c and C.app(self.c, id) or nil end

function Host:appIds()
    local out = {}
    for _, m in ipairs(self:apps()) do out[#out + 1] = m.id end
    return out
end

function Host:knownSet()
    local out = {}
    for _, m in ipairs(self:apps()) do out[m.id] = m end
    return out
end

-- display name in the current language (manifest.names = { pt, en } when present)
function Host:appName(id)
    local m = self:app(id) or (self.c and C.inactive(self.c, id))
    if not m then return id end
    return (type(m.names) == "table" and m.names[S.get_lang()]) or m.name or id
end

function Host:callWidget(id, size, box) return C.call(self.c, id, "widget", size, box) end

-- screens get (ctx, args, box); box = the body area under the app header
function Host:callScreen(id, screen, args, box)
    local m = self:app(id)
    if not m or type(m.screens) ~= "table" or type(m.screens[screen or "main"]) ~= "function" then return false, "missing" end
    return C.call(self.c, id, "screens." .. (screen or "main"), args, box)
end

-- protected app callback (window taps, dialogs): R-E1, logged R-E3
function Host:callAppFn(id, fn, label, ...)
    if id and self.c and self:app(id) then return C.call_fn(self.c, id, fn, label, ...) end
    local ok, err = xpcall(fn, debug.traceback, ...)
    if not ok then self:logError(id, label or "callback", err) end
    return ok, err
end

function Host:attention(id)
    local m = self:app(id)
    if not m or not m.attention then return false end
    local ok, v = C.call(self.c, id, "attention")
    return ok and v == true
end

---------------------------------------------------------------- app state texts (R-W4, 6.4, R-S5)

function Host:interval(id)
    local m = self:app(id)
    if not m or not m.refresh then return nil end
    return tonumber(C.interval(self.c, id)) or 0
end

function Host:cycleInterval(id) return C.cycle_interval(self.c, id) end
function Host:setInterval(id, v) return C.set_interval(self.c, id, v) end
-- the intervals of R-U1 as popup options { value, label }
function Host:intervalOptions()
    local out = {}
    for i, v in ipairs(C.intervals()) do out[i] = { value = v, label = self:every(v) } end
    return out
end

-- Choice popup (6.10) for a Tinta choice setting: the CHOICES list of the key, `label(v)` per value, a pick saves it
-- (through Host:set, which applies language and text size) and redraws. `after` overrides the redraw.
function Host:pickSetting(title, key, label, after, sub)
    if not self.window then return end
    local options = {}
    for i, v in ipairs(self:choices(key) or {}) do options[i] = { value = v, label = label(v), sub = sub and sub(v) or nil } end
    self.window:pick{ title = title, options = options, current = self:get(key), owner = "sistema",
        on_pick = function(v)
            self:set(key, v)
            if after then after() else self:redraw() end
        end }
end
function Host:appWindow(id) return C.window(self.c, id) end
function Host:status(id) return C.status(self.c, id, now()) end
function Host:state(id) return C.state(self.c, id) end
function Host:nextRun(id) return C.next_run(self.c, id, now()) end

function Host:widgetFooter(id, narrow)
    local m = self:app(id)
    if m and m.footer then
        local ok, l, r = C.call(self.c, id, "footer", narrow)
        if ok then return l, r end
    end
    return C.footer(self.c, self:status(id), narrow, now())
end

-- text, emphasis ("busy" | "err" | nil)
function Host:headerText(id)
    local st = self:status(id)
    if st.kind == "none" then return "", nil end
    local emph = (st.kind == "busy" and "busy") or ((st.kind == "error" or st.kind == "failed") and "err") or nil
    return C.header(self.c, st, now()), emph
end

-- R-S5: failed with older data
function Host:isStale(id)
    local st = self:status(id)
    return st.kind == "failed" and st.last_ok ~= nil
end

function Host:hm(t) return t and C.hm(self.c, t) or "--:--" end
function Host:ago(t) return C.ago(self.c, now(), t) end
function Host:every(sec) return C.every(self.c, sec) end

---------------------------------------------------------------- Tinta settings

function Host:get(key)
    local v = self.c and C.tinta(self.c, key)
    if v == nil then v = Host.DEFAULTS[key] end
    return v
end

function Host:set(key, value)
    local ok, err = C.set_tinta(self.c, key, value)
    if key == "lang" then self:applyLang() end
    if key == "text_size" then self:applyTextSize() end
    return ok, err
end

function Host:cycle(key)
    local v = C.cycle_tinta(self.c, key)
    if key == "lang" then self:applyLang() end
    if key == "text_size" then self:applyTextSize() end
    return v
end

-- 6.1: the "Tamanho do texto" factor on the theme's font sizes. The caller re-renders (the window reads T at build).
function Host:applyTextSize()
    return T.set_text_factor(C.text_factor(self:get("text_size")))
end

-- 7.5: the wizard ended (finished or skipped): never shown again
function Host:finishFirstRun()
    self.first_run = false
    if self.c then C.first_run_done(self.c, tostring(now())) end
end

function Host:choices(key) return C.choices(self.c, key) end

function Host:quietOn()
    local q = self:get("quiet")
    if type(q) == "table" then return q.enabled ~= false end
    return q and true or false
end

function Host:toggleQuiet()
    local q = self:get("quiet")
    local from = type(q) == "table" and q.from or "23:00"
    local to = type(q) == "table" and q.to or "07:00"
    self:set("quiet", { enabled = not self:quietOn(), from = from, to = to })
end

function Host:fullEvery() return tonumber(self:get("full_every")) or T.FULL_EVERY end

function Host:isSleeping() return self.sleeping == true end

---------------------------------------------------------------- app settings (R-C1)

function Host:appSetting(id, key) return C.app_get(self.c, id, key) end
function Host:setAppSetting(id, key, v) return C.app_set_field(self.c, id, key, v) end
function Host:appSettingText(id, key, L) return C.app_display(self.c, id, key, L) end

---------------------------------------------------------------- layout

function Host:layout(page)
    local list = C.load_layout(self.c, page)
    if type(list) ~= "table" then list = C.default_layout(self.c, page) or {} end
    list = Org.copy(list)
    if page == "home" and self:get("dev_apps") then
        -- stage 1: the fake test apps show up on home until hidden
        for _, m in ipairs(self:apps()) do
            if m.id:sub(1, 1) == "_" and not Org.find(list, m.id) then
                list[#list + 1] = { app = m.id, size = (m.sizes or {})[1] or "2x2" }
            end
        end
    end
    return list
end

function Host:saveLayout(page, list) C.save_layout(self.c, page, list) end

-- the layout of a page when nothing was saved (7.2); the first-run wizard starts from it
function Host:defaultLayout(page) return C.default_layout(self.c, page) or {} end

-- visible items with the sizes the apps support, packed into pages. Items of apps that are not registered
-- (apps of a later stage in the default layout) stay in the saved list and are not shown.
function Host:packList(list, cols, rows)
    local known = self:knownSet()
    local items = Org.visible(list, known)
    for _, it in ipairs(items) do it.size = Org.effective_size(it.size, known[it.app].sizes) end
    local pages = C.pack(self.c, items, cols, rows)
    if type(pages) ~= "table" or #pages == 0 then pages = { {} } end
    return pages
end

function Host:packedPages(page, cols, rows) return self:packList(self:layout(page), cols, rows) end

-- R-U4: apps visible on Home (every page of the home layout, so a second page does not go stale)
function Host:visibleIds()
    local Geom = require("ui/geom")
    local cols, rows = Geom.grid_dims(Screen:getWidth(), Screen:getHeight())
    local seen, out = {}, {}
    for _, p in ipairs(self:packedPages("home", cols, rows)) do
        for _, it in ipairs(p) do
            if not seen[it.app] then seen[it.app] = true; out[#out + 1] = it.app end
        end
    end
    return out
end

---------------------------------------------------------------- Wi-Fi state

function Host:wifiState()
    local on, connected = false, false
    pcall(function() on = NetworkMgr:isWifiOn() == true end)
    pcall(function() connected = NetworkMgr:isConnected() == true end)
    if on and connected then return "on" end
    if on or NetworkMgr.pending_connection then return "connecting" end
    return "off"
end

function Host:online()
    local ok, v = pcall(function() return NetworkMgr:isOnline() end)
    return ok and v == true
end

---------------------------------------------------------------- refresh (R-U4..R-U8)

-- source of an app for the Sistema rules: { id, name, host }
function Host:sourceOf(m)
    if type(m.source) ~= "table" or not m.source.id then return nil end
    local url = C.app_get(self.c, m.id, m.source.url_key or "url")
    local host = type(url) == "string" and url:match("^%a[%w+.-]*://([^/%?#]+)") or nil
    return { id = m.source.id, name = m.source.name or m.source.id, host = host }
end

-- runs `ids` (already chosen by the scheduler or by Scheduler.manual); manual shows the result toast
function Host:run(ids, manual, skipped_net, on_done)
    local win = self.window
    local pending, started, net_fail = 0, 0, false
    local looping = true
    local function finish()
        if on_done then
            local f = on_done
            on_done = nil
            f()
            return
        end
        if not self.window then return end
        if manual then
            if started == 0 and skipped_net then win:showToast(S.t("toast_no_wifi"))
            elseif started == 0 then win:showToast(S.t("toast_nothing"))
            elseif net_fail then win:showToast(S.t("toast_server_down"))
            else win:showToast(S.t("toast_updated")) end
        else
            self:redraw()
        end
    end
    -- R-B2: the synchronous part of the cycle in one transaction
    C.transaction(self.c, function()
        for _, id in ipairs(ids) do
            local m = self:app(id)
            local src = m and self:sourceOf(m)
            local t0 = now()
            pending = pending + 1
            local ok_start = C.refresh(self.c, id, function(ok, _, kind)
                if not self.c then return end
                if src and kind == "net" then C.source_result(self.c, src, ok, ok and (now() - t0) * 1000 or nil) end
                if not ok and kind == "net" then net_fail = true end
                pending = pending - 1
                if not looping then
                    if pending == 0 then finish() elseif not on_done then self:redraw() end
                end
            end, manual)
            if ok_start then started = started + 1 else pending = pending - 1 end
        end
    end)
    looping = false
    if pending == 0 then finish() elseif not on_done then self:redraw() end
end

-- manual refresh of `ids` (R-U7): ignores interval, window, quiet; skips network apps without Wi-Fi (R-U5)
function Host:refresh(ids, reason)
    if not self.c or not self.window then return end
    local run, skipped = C.manual(self.c, ids, self:online())
    self:run(run or {}, reason == "manual", skipped ~= nil and #skipped > 0)
end

function Host:refreshCurrent()
    local win = self.window
    if not win then return end
    local id = win:currentApp()
    if id and self:interval(id) ~= nil then return self:refresh({ id }, "manual") end
    if win:isHome() then return self:refresh(self:visibleIds(), "manual") end
    win:showToast(S.t("toast_nothing"))
end

function Host:refreshAll() self:refresh(self:appIds(), "manual") end

---------------------------------------------------------------- tick (R-U4)

function Host:startTick()
    self:stopTick()
    self.last_minute = self.last_minute or os.date("%H:%M")
    self.tick_cb = function()
        self.tick_cb = nil
        if not self.window then return end
        local ok, err = xpcall(function() self:tick() end, debug.traceback)
        if not ok then self:logError(nil, "tick", err) end
        if self.window then self:startTick() end
    end
    UIManager:scheduleIn(T.TICK_S, self.tick_cb)
end

function Host:stopTick()
    if self.tick_cb then UIManager:unschedule(self.tick_cb); self.tick_cb = nil end
end

-- due apps are refreshed (with the ones due in the next 2 min); otherwise the clock is redrawn each minute
function Host:tick(force_redraw)
    if self:isSleeping() or not self.c then return end
    if self:idleDue() then return self:sleepNow("idle") end       -- R-P4
    self:background()
    local due = C.due(self.c, self:visibleIds(), now(), self:online())
    if #due > 0 then
        self:run(due, false)
    else
        local minute = os.date("%H:%M")
        if force_redraw or minute ~= self.last_minute then
            self.last_minute = minute
            self:redraw()
        end
    end
end

-- Background jobs (manifest.background, e.g. Bateria's log): every BACKGROUND_S while the Tinta is open, on any
-- screen. kind = "sleep" | "sched" | "button" forces a call at a sleep hook point (device/sleep.lua) and restarts
-- the minute. Protected, never raises; cheap when no app declares one.
Host.BACKGROUND_S = 60
function Host:background(kind)
    if not self.c or not self.bg_ids or #self.bg_ids == 0 then return end
    local t = now()
    if not kind and self.bg_last and t >= self.bg_last and t - self.bg_last < Host.BACKGROUND_S then return end
    self.bg_last = t
    local ok, err = pcall(C.background, self.c, self.bg_ids, t, kind)
    if not ok then self:logError(nil, "background", err) end
end

function Host:redraw()
    if self.window then self.window:render("partial") end
end

-- any touch (for the idle timer of stage 3)
function Host:touched() self.last_touch = now() end

---------------------------------------------------------------- status bar

function Host:battery()
    local ok, b = pcall(function()
        local pd = Device:getPowerDevice()
        if not pd or not pd.getCapacity then return nil end
        return { pct = pd:getCapacity(), charging = pd.isCharging and pd:isCharging() or false }
    end)
    if not ok or not b then return nil end
    -- estimate: the Bateria app (stage 2) can set Host.battery_eta = fn(b) -> "~17h"
    if self.battery_eta then
        local eok, eta = pcall(self.battery_eta, b)
        if eok then b.eta = eta end
    end
    return b
end

function Host:statusInfo()
    local info = { time = os.date("%H:%M"), unread = self:unreadCount(), wifi = self:wifiState(), bat = self:battery() }
    if self:isSleeping() and self.sleep_info then
        info.sleep_text = self.sleep_info.text
            or S.t("sleep_status", self.sleep_info.at or "--:--", self.sleep_info.next or "--:--")
    end
    return info
end

---------------------------------------------------------------- menu sheet (6.5)

function Host:menuItems(win)
    local items = {}
    local id = win:currentApp()
    local m = id and self:app(id)
    local function close_then(fn) return function() win:closeOverlays(true); fn() end end
    items[#items + 1] = { S.t("menu_apps"), nil, function() win:openLauncher() end }
    if m and m.refresh then
        local name = self:appName(id)
        items[#items + 1] = { S.t("menu_refresh_app", name), nil, close_then(function() self:refresh({ id }, "manual") end) }
        items[#items + 1] = { S.t("menu_interval"), self:every(self:interval(id)), function()
            win:pick{ title = S.t("menu_interval"), options = self:intervalOptions(), current = self:interval(id), owner = id,
                on_pick = function(v) self:setInterval(id, v) end }
        end }
    end
    if win:isHome() then
        items[#items + 1] = { S.t("menu_organize"), nil, function() win:openOrganizer("home") end }
    end
    items[#items + 1] = { S.t("menu_refresh_all"), nil, close_then(function() self:refreshAll() end) }
    -- the sheet fits 7 items in landscape with the bar: on an app screen with refresh items, Apps would push
    -- "Dormir agora" out, so the center (also the bell, the top swipe and Apps → Notificações) gives way there
    if not (m and m.refresh) then
        items[#items + 1] = { S.t("menu_central"), nil, function() win:openCentral() end }
    end
    items[#items + 1] = { S.t("menu_system"), nil, function() win:openApp("sistema") end }
    items[#items + 1] = { S.t("menu_sleep"), nil, close_then(function() self:sleepNow() end) }
    local title = (m and not win:isHome()) and S.t("menu_title_app", self:appName(id)) or S.t("menu_title_home")
    return title, items
end

---------------------------------------------------------------- notifications (8.2-8.4)

function Host:notifications(opts)
    if not self.c then return {} end
    local ok, list = pcall(C.notifications, self.c, opts)
    return ok and type(list) == "table" and list or {}
end

-- central page (0-based): items, page, pages
function Host:notificationPage(page, per)
    local ok, items, p, pages = pcall(C.notif_page, self.c, page, per)
    if not ok then return {}, 0, 1 end
    return items, p, pages
end

function Host:notificationCount()
    local ok, n = pcall(C.notif_count, self.c)
    return ok and tonumber(n) or 0
end

function Host:unreadCount()
    if not self.c then return 0 end
    local ok, n = pcall(C.unread_count, self.c)
    return ok and tonumber(n) or 0
end

-- on_new from core/notify: banner (R-T5) or at least the bell (R-T6)
function Host:onNotification(n)
    if not self.window or not n then return end
    if self:get("banner") and not self:isSleeping() then
        local head, title = C.banner_lines(self.c, n, self:appName(n.app))
        self.window:showBanner{ head = head, title = title, on_tap = function() self:openNotification(n) end }
    else
        self:redraw()
    end
end

-- 8.4: marks read, stack Home -> destination, full refresh. The app's on_route(ctx, route) wins when present.
function Host:openNotification(n)
    local win = self.window
    if not win or not n then return end
    local dest = C.open_notification(self.c, n.id) or { app = n.app, screen = "main" }
    local m = self:app(dest.app)
    if not m then return win:resetTo({}) end
    if m.on_route and type(n.route) == "table" then
        win:resetTo({})
        if C.call(self.c, dest.app, "on_route", n.route) then return end
    end
    local screen = dest.screen or "main"
    if type(m.screens) ~= "table" or type(m.screens[screen]) ~= "function" then screen = "main" end
    win:resetTo({ { kind = "app", app = dest.app, screen = screen, args = dest.args } })
end

function Host:markAllRead() pcall(C.mark_all_read, self.c); self:redraw() end
function Host:clearNotifications() pcall(C.clear_notifications, self.c); self:redraw() end
function Host:getPref(app) local ok, v = pcall(C.notify_pref, self.c, app); return ok and v or "alta" end
function Host:setPref(app, v) pcall(C.set_notify_pref, self.c, app, v) end
function Host:emit(app, n) return C.emit(self.c, app, n) end
function Host:sleepSummary()
    local ok, s = pcall(C.sleep_summary, self.c, self:get("sleep_shows"), self:get("sleep_titles") == "hide")
    return ok and s or nil
end

-- 8.5: does the app show its content on the sleep page? (no: a placeholder with its name)
function Host:sleepVisible(id) local ok, v = pcall(C.sleep_visible, self.c, id); return not ok or v ~= false end
-- sleep page: draw a placeholder instead of the app? Also the notification widget, when titles are hidden (it lists them)
function Host:sleepPlaceholder(id)
    return not self:sleepVisible(id) or (id == "notificacoes" and self:get("sleep_titles") == "hide")
end
function Host:setSleepVisible(id, visible) pcall(C.set_sleep_visible, self.c, id, visible) end
function Host:sourceState(id) local ok, s = pcall(C.source_state, self.c, id); return ok and s or nil end

---------------------------------------------------------------- Wi-Fi, rotation, sleep

function Host:toggleWifi()
    local win = self.window
    if self:wifiState() == "off" then
        if win then win:showToast(S.t("toast_wifi_on")) end
        pcall(function() NetworkMgr:toggleWifiOn(function() self:redraw() end, false, false) end)
        pcall(C.set_tinta, self.c, "wifi", true)
    else
        pcall(function() NetworkMgr:toggleWifiOff(function() self:redraw() end, false) end)
        pcall(C.set_tinta, self.c, "wifi", false)
        if win then win:showToast(S.t("toast_wifi_off")) end
    end
end

-- Only the framebuffer rotates. KOReader's SetRotationMode broadcast is NOT sent: FileManager:onSetRotationMode
-- would rebuild its whole TitleBar under the fullscreen Tinta (new IconButtons have dimen = nil until painted,
-- and a tap that reaches them crashes in UIManager:widgetInvert), the reader would re-layout the document, and
-- both again on restore. The Tinta builds its own widgets from Screen:getWidth()/getHeight(), and the restore
-- puts back the rotation FM / the reader were built for, so their widget trees stay valid.
local function set_rotation(mode)
    pcall(function()
        if Screen:getRotationMode() ~= mode then Screen:setRotationMode(mode) end
    end)
end

-- KOReader rotation modes: 0 upright, 1 clockwise, 2 upside down, 3 counter-clockwise
function Host:applyOrientation()
    if not Screen.getRotationMode or not Screen.setRotationMode then return end
    local want_land = self:get("landscape") == true
    local is_land = Screen:getWidth() > Screen:getHeight()
    if want_land == is_land then return end
    set_rotation(want_land and (Screen.DEVICE_ROTATED_CLOCKWISE or 1) or (Screen.DEVICE_ROTATED_UPRIGHT or 0))
end

function Host:enterOrientation()
    local ok, cur = pcall(Screen.getRotationMode, Screen)
    self.prev_rotation = ok and cur or nil
    self:applyOrientation()
end

-- 6.8: back to the rotation KOReader had before the Tinta opened
function Host:restoreRotation()
    local prev = self.prev_rotation
    self.prev_rotation = nil
    if prev == nil then return end
    local ok, cur = pcall(Screen.getRotationMode, Screen)
    if ok and cur ~= prev then
        set_rotation(prev)
        UIManager:setDirty("all", "full")
    end
end

-- Swallows touch gestures for `ms` after the Tinta closes (see Host:close).
function Host:shield(ms)
    local ok, Shield = pcall(require, "ui/shield")
    if ok then pcall(Shield.show, ms) end
end

-- "Girar" (central, Sistema): the saved layout stays, only the packing changes (6.8)
function Host:rotate()
    self:set("landscape", not (self:get("landscape") == true))
    self:applyOrientation()
    if self.window then
        self:closeInput()
        self.window:closeOverlays(true)
        for _, r in ipairs(self.window.stack) do r.page = 0 end
        self.window:render("full")
    end
end

---------------------------------------------------------------- sleep (11, device/sleep.lua)

-- device/sleep.lua sets Host.enter_sleep on attach (R-P4: "Dormir agora" and the idle timer call this)
function Host:sleepNow(reason)
    if self.enter_sleep and self.window and not self.sleeping then return self.enter_sleep(reason or "now") end
    if self.window and not self.sleeping then self.window:showToast(S.t("toast_sleep_later")) end
end

function Host:attachSleep(opts)
    self.last_touch = now()
    local ok, Sleep = pcall(require, "device/sleep")
    if not ok then self:log(nil, "warn", "sleep: " .. tostring(Sleep):match("[^\n]*")); return end
    self.sleep = Sleep
    local dir = opts.data_dir
    local aok, err = pcall(Sleep.attach, self, {
        log_path = dir and (dir .. "/tinta-power.log") or nil,
        measure_path = dir and (dir .. "/tinta-wake-test") or nil,
    })
    if not aok then self:log(nil, "error", "sleep attach: " .. tostring(err):match("[^\n]*")) end
end

function Host:detachSleep()
    if self.sleep then pcall(self.sleep.detach) end
    self.sleep = nil
    self.enter_sleep = nil
    self.sleeping = false
    self.sleep_info = nil
end

-- R-P4: true when the idle timer says to sleep now (never with a text dialog open: its keys are not touches)
function Host:idleDue()
    if not self.c or self.sleeping or self.input_dialog or not self.enter_sleep then return false end
    return C.idle_due(self.c, self.last_touch, now(), function() return self:plugged() end)
end

-- true while the Kindle is on USB/charger (10.5 "só na bateria"). Called only when the idle time is due in the mode
-- "battery" (see core Power.idle_due), never per tick. Device/battery.lua explains the sources and their limits.
function Host:plugged()
    local ok, Battery = pcall(require, "device/battery")
    if not ok then return false end
    local _, pd = pcall(Device.getPowerDevice, Device)
    local pok, v = pcall(Battery.plugged, { powerd = type(pd) == "table" and pd or nil })
    return pok and v == true
end
function Host:wakeTarget(from) return C.next_wakeup(self.c, from) end

---------------------------------------------------------------- wake requests (11.7, ctx.wake_at)

-- an app asks to be refreshed at `ts`, awake (UIManager timer) or asleep (device/sleep.lua merges it into the
-- RTC target and Host:wakePlan adds the app to the wake-up batch). ts = nil cancels.
function Host:wakeRequest(id, ts)
    if not self.wake_reqs then return end
    Wakereq.set(self.wake_reqs, id, ts)
    self:armWakeTimer()
end

-- earliest request after `from` (device/sleep.lua: next RTC target)
function Host:nextWakeRequest(from)
    if not self.wake_reqs then return nil end
    return (Wakereq.next(self.wake_reqs, from))
end

function Host:cancelWakeTimer()
    if self.wake_cb then UIManager:unschedule(self.wake_cb); self.wake_cb = nil end
end

-- awake: one UIManager timer for the earliest request; when it fires the due apps are refreshed (once)
function Host:armWakeTimer()
    self:cancelWakeTimer()
    if not self.window or not self.wake_reqs then return end
    local ts = Wakereq.earliest(self.wake_reqs)
    if not ts then return end
    self.wake_cb = function()
        self.wake_cb = nil
        if not self.window or not self.wake_reqs or self.sleeping then return end   -- asleep: wakePlan handles it
        local ids = Wakereq.due(self.wake_reqs, now(), 0)
        Wakereq.consume(self.wake_reqs, ids)
        if #ids > 0 then self:refresh(ids, "auto") end
        self:armWakeTimer()
    end
    UIManager:scheduleIn(math.max(1, ts - now()), self.wake_cb)
end
function Host:rtcSeconds(target, from) return C.rtc_seconds(self.c, target, from) end
function Host:classifyWakeup(o) return C.classify_wakeup(self.c, o) end
function Host:wifiTimeout() return C.WIFI_TIMEOUT end

-- R-P5: menus, dialogs, text input and hold timers are closed before the sleep page is drawn
function Host:beforeSleep()
    self:closeInput()
    local win = self.window
    if win then
        win:cancelHold()
        win:closeOverlays(true)
    end
end

-- R-S4: "Repouso · atualizado HH:MM · próxima HH:MM"
function Host:setSleepInfo(updated_at, next_at)
    self.sleep_info = { text = C.sleep_bar(self.c, updated_at, next_at), at = os.date("%H:%M", updated_at), next_at = next_at }
end

-- the sleep page, full refresh (R-P5, R-P6)
function Host:drawSleep()
    if self.window then self.window:render("full") end
end

-- R-P6: the apps of the sleep layout that are due on a wake-up: ids, needs_net
function Host:wakePlan(t)
    if not self.c then return {}, false end
    local known = self:knownSet()
    local ids, seen = {}, {}
    for _, it in ipairs(self:layout("sleep")) do
        if not it.hidden and known[it.app] and not seen[it.app] then seen[it.app] = true; ids[#ids + 1] = it.app end
    end
    local picked, need_net = C.wake_plan(self.c, ids, t)
    -- 11.7: apps with a wake request that is due run in this batch too (their own end time, quiet hours or not)
    if self.wake_reqs then
        local due = Wakereq.due(self.wake_reqs, t, Wakereq.SLACK)
        Wakereq.consume(self.wake_reqs, due)
        local have = {}
        for _, id in ipairs(picked) do have[id] = true end
        for _, id in ipairs(due) do
            if known[id] and not have[id] then have[id] = true; picked[#picked + 1] = id end
        end
    end
    return picked, need_net
end

-- refreshes `ids` without intermediate redraws (the sleep page is drawn once, at the end) and calls done()
function Host:sleepRefresh(ids, done)
    if not self.c then return done() end
    self:run(ids, false, false, done)
end

-- R-P7: the power button woke the Kindle: back to the screen the Tinta had (the stack is untouched), Wi-Fi as
-- it was, idle timer restarted, due apps refreshed
function Host:afterWake(wifi_was_on)
    self.sleep_info = nil
    self.last_touch = now()
    local win = self.window
    if not win then return end
    win:updateDimen()
    win:render("full")
    self:armWakeTimer()
    if wifi_was_on and self:wifiState() == "off" then
        pcall(function() NetworkMgr:enableWifi(function() self:redraw() end, false) end)
    end
    UIManager:nextTick(function() if self.window and not self.sleeping then self:tick(true) end end)
end

---------------------------------------------------------------- text input (R-C1, R-C2)

-- InputDialog; on_save(text) returns true to close, or false, message to keep it open
function Host:input(title, value, hint, on_save, opts)
    opts = opts or {}
    local InputDialog = require("ui/widget/inputdialog")
    local L = S.make(require("apps/sistema/strings"))
    local dialog
    dialog = InputDialog:new{
        title = title,
        input = value or "",
        input_hint = hint,
        input_type = opts.number and "number" or nil,
        allow_newline = opts.multiline or nil,
        text_type = opts.password and "password" or nil,
        buttons = { {
            { text = S.t("btn_cancel"), id = "close", callback = function()
                self.input_dialog = nil
                UIManager:close(dialog)
            end },
            { text = L("btn_save"), is_enter_default = true, callback = function()
                local ok, msg = on_save(dialog:getInputText())
                if ok then
                    self.input_dialog = nil
                    UIManager:close(dialog)
                    self:redraw()
                elseif msg and self.window then
                    self.window:showToast(msg)
                end
            end },
        } },
    }
    self.input_dialog = dialog
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

-- closes the text input when one is open (rotation, sleep)
function Host:closeInput()
    local d = self.input_dialog
    self.input_dialog = nil
    if d then pcall(UIManager.close, UIManager, d) end
end

---------------------------------------------------------------- data export and backup (Sistema → Dados)

-- koreader/ (where the diagnostic and the backups are written)
function Host:dataDir() return self.data_dir end

-- { tinta = {..}, apps = { id = {..} } }: saved settings with every secret shown as "<redacted>"
function Host:redactedSettings()
    local out = { tinta = C.redacted_scope(self.c, "portal"), apps = {} }
    for _, m in ipairs(self:apps()) do out.apps[m.id] = C.redacted_scope(self.c, m.id) end
    return out
end

-- env for apps/sistema/backup: the settings object, layout access and the installed apps with their versions
function Host:backupEnv()
    local env = C.backup_env(self.c)
    env.apps = {}
    for _, m in ipairs(self:apps()) do env.apps[#env.apps + 1] = { id = m.id, version = m.version } end
    env.now = now()
    env.api_version = C.api_version()
    return env
end

-- after a restore: language, orientation and every screen are rebuilt from the saved settings
function Host:reloadAfterRestore()
    self:applyLang()
    self:applyTextSize()
    self:applyOrientation()
    if self.window then
        self:closeInput()
        self.window:closeOverlays(true)
        self.window.stack = { self.window.stack[1] }
        for _, r in ipairs(self.window.stack) do r.page = 0 end
        self.window:render("full")
    end
end

---------------------------------------------------------------- log (R-E3)

function Host:log(app, level, msg)
    msg = tostring(msg or "")
    if level == "error" or level == "warn" then logger.warn("Tinta", app or "-", msg)
    elseif level ~= "debug" then logger.info("Tinta", app or "-", msg) end
    if self.c and level ~= "debug" then pcall(C.log, self.c, app, level, msg) end
end

-- errors outside registry:call (render, tick): first line + first frame (R-E3)
function Host:logError(app, where, err)
    if self.c and pcall(C.log_error, self.c, app, where, err) then return end
    logger.warn("Tinta", app or "-", where, tostring(err))
end

function Host:logTail(n)
    local ok, lines = pcall(C.log_list, self.c, 0, n)
    return ok and type(lines) == "table" and lines or {}
end

-- { bytes, notifications, log }
function Host:stats()
    local ok, s = pcall(C.stats, self.c)
    if not ok or type(s) ~= "table" then return {} end
    return { bytes = s.size_bytes, notifications = s.notifications, log = s.log }
end

return Host
