-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (C) 2026 Tinta contributors
-- Tinta: headless smoke test of the KOReader UI layer against the real core/. Stubs the KOReader modules the
-- UI uses (widgets, UIManager, Device, NetworkMgr), opens the Tinta with core/ on an in-memory store and
-- drives it: every screen, overlays, gestures, organizer, rotation, the fake test apps (the failing one
-- included), notifications. Fails on any Lua error and on any paint outside the screen.
-- It is not a substitute for the device: fonts are fake (fixed width per glyph), refresh is not real.
--   luajit tests/tinta_ui_smoke.lua
-- core/ comes from tinta.koplugin/core when present (after the merge), else from TINTA_CORE_DIR (a plugin
-- folder that has core/, e.g. the core-logic worktree).
local function exists(p) local f = io.open(p, "r"); if f then f:close() end; return f ~= nil end
local core_dir = exists("tinta.koplugin/core/registry.lua") and "tinta.koplugin" or os.getenv("TINTA_CORE_DIR")
if not core_dir or not exists(core_dir .. "/core/registry.lua") then
    print("tinta ui smoke: SKIPPED (no core/: set TINTA_CORE_DIR to a plugin folder with core/)")
    os.exit(0)
end
package.path = "tinta.koplugin/?.lua;" .. core_dir .. "/?.lua;" .. package.path

-- the clock is frozen (Wednesday 2026-03-04 10:00:00 local): clocks, "next in N min" and chart axes would otherwise
-- change the width of texts between runs, and the draws of a step could not be hashed
do
    local real_time, real_date = os.time, os.date
    local frozen = real_time{ year = 2026, month = 3, day = 4, hour = 10, min = 0, sec = 0 }
    os.time = function(t) if t then return real_time(t) end return frozen end
    os.date = function(f, t) return real_date(f, t or frozen) end
end

local TA = dofile("tests/testapps.lua")   -- the apps the flows below lean on (private ones when in the tree)

local passed, failed = 0, 0
local function check(name, cond, extra)
    if cond then passed = passed + 1
    else failed = failed + 1; print("FAIL - " .. name .. (extra and (" :: " .. tostring(extra)) or "")) end
end

---------------------------------------------------------------- KOReader stubs

-- SMOKE_SCREEN=WxH runs the whole smoke on another screen (portrait size; rotating swaps it). The default 600x800 is
-- the KT3: its draws are hashed step by step and compared with the recorded baseline, tests/fixtures/kt3-trace*.txt (pixel identity, spec 6.1).
local BASE_W, BASE_H = 600, 800
do
    local w, h = (os.getenv("SMOKE_SCREEN") or ""):match("^(%d+)x(%d+)$")
    if w then BASE_W, BASE_H = tonumber(w), tonumber(h) end
end
-- SMOKE_FONT=linear: a fake font whose metrics are exactly linear in the size (0.5 em wide, 1.5 em tall), so that the
-- scales test can compare draws between sizes without rounding noise. The default font is the one of the baseline.
local LINEAR = os.getenv("SMOKE_FONT") == "linear"
local GLYPH_W, LINE_H = LINEAR and 0.5 or 0.55, LINEAR and 1.5 or 1.35
local SCREEN = { w = BASE_W, h = BASE_H, rot = 0 }
local oob = {}   -- paints outside the screen
local trace = {}   -- every draw of the step in progress (rects, borders, text): hashed for the pixel-identity check
local trunc = {}   -- texts the fake font had to cut (wider than their box): the overflow check
local outside = {}   -- non-white paints outside the content box (the letterbox must stay white)
local function paint_check(what, x, y, w, h, color)
    if w <= 0 or h <= 0 then return end
    if x < 0 or y < 0 or x + w > SCREEN.w or y + h > SCREEN.h then
        oob[#oob + 1] = ("%s %d,%d %dx%d"):format(what, x, y, w, h)
    end
    local T = require("ui/theme")
    if color ~= "W" and (x < T.ox or y < T.oy or x + w > T.ox + T.BW or y + h > T.oy + T.BH) then
        outside[#outside + 1] = ("%s %d,%d %dx%d"):format(what, x, y, w, h)
    end
end
local function tr(...) trace[#trace + 1] = table.concat({ ... }, " ") end
-- FNV-1a over the draws of a step
local function fnv(str)
    local h = 2166136261
    for i = 1, #str do h = (bit.bxor(h, str:byte(i)) * 16777619) % 4294967296 end
    return ("%08x"):format(h)
end
local hashes = {}
local function trace_reset() trace, trunc, outside = {}, {}, {} end
local function trace_hash() return fnv(table.concat(trace, "\n")) end
-- writes the step's draws, smallest tappable box and cut texts to $SMOKE_TRACE_DIR/NNN.txt (tests/tinta_ui_scales.lua reads them)
local function trace_write(i, name, min_h)
    local dir = os.getenv("SMOKE_TRACE_DIR")
    if not dir then return end
    local cut = {}
    for t, ratio in pairs(trunc) do cut[#cut + 1] = ("%.3f %s"):format(ratio, t) end   -- wanted width (or height) / box
    table.sort(cut)
    local fh = io.open(("%s/%03d.txt"):format(dir, i), "w")
    if not fh then return end
    fh:write(name, "\n", table.concat(trace, "\n"), "\n")
    fh:write("#touch ", (min_h == nil or min_h == math.huge) and "-" or tostring(min_h), "\n")
    for _, t in ipairs(cut) do fh:write("#cut ", t, "\n") end
    fh:close()
end
local function digits0(s) return (tostring(s):gsub("%d", "0")) end   -- clocks and counters change between runs

local function preload(name, mod) package.preload[name] = function() return mod end end

local Geom = {}
Geom.__index = Geom
function Geom:new(o) o = o or {}; o.x, o.y, o.w, o.h = o.x or 0, o.y or 0, o.w or 0, o.h or 0; return setmetatable(o, Geom) end
preload("ui/geometry", Geom)

local Widget = {}
function Widget:extend(o) o = o or {}; setmetatable(o, self); self.__index = self; return o end
function Widget:new(o) o = self:extend(o); if o._init then o:_init() end; if o.init then o:init() end; return o end
function Widget:getSize() return self.dimen or Geom:new{} end
function Widget:paintTo() end
function Widget:free() end
function Widget:handleEvent(ev) if self[ev.handler] then return self[ev.handler](self, unpack(ev.args or {})) end end
preload("ui/widget/widget", Widget)

local InputContainer = Widget:extend{}
preload("ui/widget/container/inputcontainer", InputContainer)
local WidgetContainer = Widget:extend{}
preload("ui/widget/container/widgetcontainer", WidgetContainer)

preload("ffi/blitbuffer", { COLOR_BLACK = "B", COLOR_WHITE = "W", COLOR_DARK_GRAY = "G" })

local Font = { getFace = function(_, name, size) return { name = name, size = size } end }
preload("ui/font", Font)

-- fake text: 0.55 x size per character, height 1.35 x size (SMOKE_FONT=linear below), honours max_width like TextWidget
local function utf8len(s) local _, n = tostring(s):gsub("[^\128-\191]", ""); return n end
local TextWidget = Widget:extend{}
function TextWidget:init()
    local w = math.floor(utf8len(self.text) * self.face.size * GLYPH_W)
    if self.max_width and w > self.max_width then self._cut = w / self.max_width; w = self.max_width end
    self._w, self._h = w, math.floor(self.face.size * LINE_H)
end
function TextWidget:getSize() return Geom:new{ w = self._w, h = self._h } end
function TextWidget:paintTo(_, x, y)
    paint_check("text '" .. tostring(self.text):sub(1, 20) .. "'", x, y, self._w, self._h, "B")
    tr("T", x, y, self._w, self._h, self.face.size, self.bold and "b" or "n", tostring(self.fgcolor), digits0(self.text))
    if self._cut then trunc[digits0(self.text)] = math.max(trunc[digits0(self.text)] or 0, self._cut) end
end
preload("ui/widget/textwidget", TextWidget)

local TextBoxWidget = Widget:extend{}
function TextBoxWidget:init()
    local per_line = math.max(1, math.floor(self.width / (self.face.size * GLYPH_W)))
    local lines = math.max(1, math.ceil(utf8len(self.text) / per_line))
    local h = lines * math.floor(self.face.size * LINE_H)
    if self.height and h > self.height then self._cut = h / self.height; h = self.height end
    self._h = h
end
function TextBoxWidget:getSize() return Geom:new{ w = self.width, h = self._h } end
function TextBoxWidget:paintTo(_, x, y)
    paint_check("textbox", x, y, self.width, self._h, "B")
    tr("X", x, y, self.width, self._h, self.face.size, self.bold and "b" or "n", tostring(self.fgcolor), tostring(self.alignment), digits0(self.text))
    if self._cut then trunc[digits0(self.text)] = math.max(trunc[digits0(self.text)] or 0, self._cut) end
end
preload("ui/widget/textboxwidget", TextBoxWidget)

local GestureRange = {}
function GestureRange:new(o) return o end
preload("ui/gesturerange", GestureRange)

local scheduled = {}
local UIManager = {
    shown = {}, dirty = 0, last_refresh = nil,
    show = function(self, w) self.shown[#self.shown + 1] = w end,
    close = function(self, w)
        for i, x in ipairs(self.shown) do if x == w then table.remove(self.shown, i) end end
        if w.onCloseWidget then w:onCloseWidget() end
    end,
    setDirty = function(self, w, f)
        self.dirty = self.dirty + 1
        if type(f) == "function" then self.last_refresh = f() end
    end,
    scheduleIn = function(_, s, fn) scheduled[#scheduled + 1] = { s = s, fn = fn } end,
    unschedule = function(_, fn) for i = #scheduled, 1, -1 do if scheduled[i].fn == fn then table.remove(scheduled, i) end end end,
    nextTick = function(_, fn) scheduled[#scheduled + 1] = { s = 0, fn = fn } end,
    broadcasts = {},
    broadcastEvent = function(self, ev) self.broadcasts[#self.broadcasts + 1] = ev end,
    forceRePaint = function() end,
}
preload("ui/uimanager", UIManager)
local function run_scheduled(max_s)
    local list = scheduled
    scheduled = {}
    for _, it in ipairs(list) do
        if it.s <= (max_s or 1e9) then it.fn() else scheduled[#scheduled + 1] = it end
    end
end

local Screen = {
    getWidth = function() return SCREEN.w end,
    getHeight = function() return SCREEN.h end,
    getRotationMode = function() return SCREEN.rot end,
    setRotationMode = function(_, m)
        SCREEN.rot = m
        if m % 2 == 1 then SCREEN.w, SCREEN.h = BASE_H, BASE_W else SCREEN.w, SCREEN.h = BASE_W, BASE_H end
    end,
    DEVICE_ROTATED_UPRIGHT = 0, DEVICE_ROTATED_CLOCKWISE = 1,
}
local battery = { pct = 82, charging = false }
preload("device", {
    screen = Screen,
    hasKeys = function() return false end,
    getPowerDevice = function()
        return { getCapacity = function() return battery.pct end, isCharging = function() return battery.charging end }
    end,
})

local wifi = { on = true, connected = true }
preload("ui/network/manager", {
    isWifiOn = function() return wifi.on end,
    isConnected = function() return wifi.connected end,
    isOnline = function() return wifi.on and wifi.connected end,
    toggleWifiOn = function(_, cb) wifi.on, wifi.connected = true, true; if cb then cb() end end,
    toggleWifiOff = function(_, cb) wifi.on, wifi.connected = false, false; if cb then cb() end end,
    getNetworkInterfaceName = function() return "wlan0" end,
})
preload("logger", { info = function() end, warn = function(...) end, err = function(...) print("logger.err", ...) end, dbg = function() end })
preload("ui/event", { new = function(_, name, ...) return { handler = "on" .. name, args = { ... } } end })
local InputDialog = Widget:extend{}
function InputDialog:getInputText() return self._typed or self.input end
function InputDialog:onShowKeyboard() end
preload("ui/widget/inputdialog", InputDialog)
preload("ui/widget/infomessage", Widget:extend{})
preload("gettext", function(s) return s end)
-- a fresh data dir per run: Bateria's CSV log would otherwise grow across runs and change what it draws
local DATA_DIR = os.tmpname(); os.remove(DATA_DIR); os.execute('mkdir -p "' .. DATA_DIR .. '"')
preload("datastorage", { getDataDir = function() return DATA_DIR end,
                         getSettingsDir = function() return "/tmp/tinta-smoke-no-settings" end })
preload("dispatcher", { registerAction = function() end })
local SKIP_APPS = {}
do
    local fh = io.open("tests/fixtures/smoke-skip-apps.txt")
    if fh then
        for l in fh:lines() do
            local id = l:match("^%s*([a-z0-9_]+)%s*$")
            if id then SKIP_APPS[id] = true end
        end
        fh:close()
    end
end
preload("libs/libkoreader-lfs", {
    dir = function(d)
        local p = io.popen('ls -1 "' .. d .. '"')
        local names = {}
        for n in p:lines() do
            -- apps in tests/fixtures/smoke-skip-apps.txt (the reference app of docs/sdk.md and every app made by
            -- scripts/nova-app.sh) load only for SMOKE_APP=<id>: as one more app they would shift the launcher pages
            -- and every hash of the KT3 baseline, which are pinned to the repo's own apps
            if not SKIP_APPS[n] or os.getenv("SMOKE_APP") == n then names[#names + 1] = n end
        end
        p:close()
        local i = 0
        return function() i = i + 1; return names[i] end
    end,
    attributes = function(path, what)
        local f = io.open(path, "r")
        if f then f:close(); return "file" end
        return nil
    end,
})
_G.G_reader_settings = { readSetting = function() return nil end }

-- device/sleep.lua over fakes (no lipc, no Kindle): powerd state is a plain variable the test moves
local fake_powerd = { state = "active", props = { preventScreenSaver = "1" }, calls = {} }
local fake_handle = {
    get_string_property = function(_, _, prop) return fake_powerd.props[prop] or (prop == "state" and fake_powerd.state) or nil end,
    set_string_property = function(_, _, prop, v) fake_powerd.props[prop] = tostring(v); return true end,
    set_int_property = function(_, _, prop, v)
        fake_powerd.calls[#fake_powerd.calls + 1] = prop .. "=" .. tostring(v)
        if prop == "powerButton" then fake_powerd.state = "screenSaver" end
        return true
    end,
    close = function() end,
}
fake_powerd.props.state = nil
local fake_device = require("device")
require("device/sleep")._set_deps({
    ui = UIManager, clock = os.time, lipc_lib = { init = function() return fake_handle end }, device = fake_device,
    network = require("ui/network/manager"), logger = { info = function() end },
    read_file = function() return nil end, exec = function() return "" end,
})
_G.unpack = _G.unpack or table.unpack

---------------------------------------------------------------- drive the Tinta

local Host = require("ui/host")
local ok_open, err_open = xpcall(function()
    Host.DEFAULTS.dev_apps = true   -- the smoke drives the _test_* apps
    Host:open{ plugin_dir = "tinta.koplugin", db_path = "/tmp/none.sqlite3" }
end, debug.traceback)
check("tinta opens", ok_open, err_open)
local win = Host.window
check("window shown", win ~= nil and UIManager.shown[1] == win)
-- UIManager keeps windows whose .toast / .modal are truthy above everything shown later: the Tinta must have
-- neither, or InputDialog and the keyboard open under it, invisible (the bell-tap crash)
check("window is not a toast or modal for UIManager", win ~= nil and not win.toast and not win.modal)
if not win then
    print(("tinta ui smoke: %d passed, %d failed"):format(passed, failed))
    os.exit(1)
end

-- SMOKE_TEXT=large: the whole smoke with "Tamanho do texto: grande" (the KT3 baseline is not compared then)
local TEXT_LARGE = os.getenv("SMOKE_TEXT") == "large"
if TEXT_LARGE then Host:set("text_size", "large"); win:render("full") end

local T = require("ui/theme")
local function paint()
    trace_reset()
    win:paintTo({ paintRect = function(_, x, y, w, h, c) paint_check("rect", x, y, w, h, c); tr("R", x, y, w, h, tostring(c)) end,
        paintRoundedRect = function(_, x, y, w, h, c, r) paint_check("rrect", x, y, w, h, c); tr("Q", x, y, w, h, tostring(c), tostring(r)) end,
        paintBorder = function(_, x, y, w, h, b, c, r) paint_check("border", x, y, w, h, "B"); tr("B", x, y, w, h, b, tostring(c), tostring(r)) end }, 0, 0)
end


local function step(name, fn)
    oob = {}
    local ok, err = xpcall(fn, debug.traceback)
    check(name, ok, err)
    if ok then
        local pok, perr = xpcall(paint, debug.traceback)
        check(name .. ": paints", pok, perr)
        check(name .. ": inside the screen", #oob == 0, oob[1] and (#oob .. " e.g. " .. oob[1]))
        hashes[#hashes + 1] = ("%03d %s %s"):format(#hashes + 1, name, fnv(table.concat(trace, "\n")))
        check(name .. ": nothing but white outside the content box", #outside == 0, outside[1] and (#outside .. " e.g. " .. outside[1]))
        -- smallest tappable box of the screen and the texts the fake font had to cut: the scales test compares them
        -- between the KT3 and the other sizes (touch targets and text fit, spec 6.1)
        local min_h = math.huge
        for _, b in ipairs(win.hot) do
            if b.painted and b.on_tap and b.layer == 0 and b.w * b.h < 0.3 * T.BW * T.BH then min_h = math.min(min_h, b.dimen.h) end
        end
        trace_write(#hashes, name, min_h)
    end
end

-- tap the first painted hot box whose text matches (search the tree for a TextWidget with that text)
local function contains_text(w, text, depth)
    depth = depth or 0
    if depth > 40 or type(w) ~= "table" then return false end
    if w.text and tostring(w.text):find(text, 1, true) then return true end
    if w.child and contains_text(w.child, text, depth + 1) then return true end
    for _, c in ipairs(w) do
        if type(c) == "table" and (contains_text(c, text, depth + 1) or (c.widget and contains_text(c.widget, text, depth + 1))) then return true end
    end
    return false
end
-- the innermost tappable box of the highest layer that shows `text`, tapped at its center
-- `widest`: among the matches take the biggest box (the organizer tab "Repouso" vs the chip of the app Repouso)
local function tap_text(text, widest)
    paint()
    local best
    for _, b in ipairs(win.hot) do
        if b.painted and b.on_tap and contains_text(b, text) then
            local smaller = b.w * b.h < (best and best.w * best.h or 0)
            if widest then smaller = not smaller end
            if not best or b.layer > best.layer or (b.layer == best.layer and smaller) then best = b end
        end
    end
    if not best then return false end
    win:onTintaTap(nil, { pos = { x = best.dimen.x + math.floor(best.w / 2), y = best.dimen.y + math.floor(best.h / 2) } })
    return true
end
-- design coordinates (the 600x800 portrait / 800x600 landscape of spec 6.1) to this screen's pixels
local function at(x, y) return T.ox + math.floor(x * T.s + 0.5), T.oy + math.floor(y * T.s + 0.5) end
local function tap_xy(x, y) paint(); x, y = at(x, y); win:onTintaTap(nil, { pos = { x = x, y = y } }) end
local function swipe(x0, y0, x1, y1)
    x0, y0 = at(x0, y0); x1, y1 = at(x1, y1)
    win:onTintaSwipe(nil, { pos = { x = x0, y = y0 }, end_pos = { x = x1, y = y1 } })
end
local function top() return win:current() end
-- choice popup (6.10): taps the row `row` (opens the popup), checks the popup is up, then taps the option `option`
local function pick(row, option, title)
    check("popup opens from " .. row, tap_text(row) and win.picker ~= nil and (not title or contains_text(win[1], title)), row)
    check("popup shows " .. option, contains_text(win[1], option), option)
    check("popup option " .. option .. " taps", tap_text(option), option)
    check("popup closed after " .. option, win.picker == nil)
end

-- SMOKE_APP=<id> (the template `_modelo`, or an app made by scripts/nova-app.sh): a short flow for that one app instead
-- of the main flow, which is pinned to the repo's own apps (a new app moves the launcher pages and the KT3 hashes)
local only = os.getenv("SMOKE_APP")
if only then
    local app = Host:app(only)
    check("SMOKE_APP: " .. only .. " is registered (dev_apps on)", app ~= nil)
    if app then
        run_scheduled(0)
        for _, size in ipairs(app.sizes) do
            Host:saveLayout("home", { { app = only, size = size } })
            step("SMOKE_APP: home with the " .. size .. " widget", function() win:goHome(); win:render("full") end)
            check("SMOKE_APP: " .. size .. " widget shows the app name", contains_text(win[1], Host:appName(only)))
            check("SMOKE_APP: " .. size .. " widget has no error fallback", not contains_text(win[1], Host:appName(only) .. " · erro na app"))
        end
        step("SMOKE_APP: main screen", function() win:goHome(); win:openApp(only) end)
        check("SMOKE_APP: on the app screen", top().kind == "app" and top().app == only, top().kind)
        check("SMOKE_APP: screen is not the error screen", not contains_text(win[1], Host:appName(only) .. " · erro"))
        step("SMOKE_APP: refresh", function() Host:refresh({ only }, "manual"); run_scheduled(0); win:render("partial") end)
        check("SMOKE_APP: refresh did not fail", Host:status(only).kind ~= "error", Host:status(only).kind)
    end
    os.execute('rm -rf "' .. DATA_DIR .. '"')
    print(("tinta ui smoke (SMOKE_APP=%s): %d passed, %d failed"):format(only, passed, failed))
    os.exit(failed > 0 and 1 or 0)
end

-- a scenario file (tests/tinta_ui_firstrun.lua sets _G.SMOKE_SCENARIO) takes over with the stubs and helpers above
if _G.SMOKE_SCENARIO then
    _G.SMOKE_SCENARIO({
        Host = Host, UIManager = UIManager, SCREEN = SCREEN, check = check, step = step, paint = paint,
        tap_text = tap_text, contains_text = contains_text, run_scheduled = run_scheduled, at = at, wifi = wifi,
        trace = function() return trace end, battery = battery,
        window = function() return Host.window end,
        open = function(opts)
            opts = opts or {}
            opts.plugin_dir, opts.db_path = "tinta.koplugin", "/tmp/none.sqlite3"
            Host:open(opts)
            win = Host.window
            run_scheduled(0)
            return win
        end,
        close = function() Host:close(); run_scheduled(1); win = nil end,
    })
    os.execute('rm -rf "' .. DATA_DIR .. '"')
    print(("tinta ui smoke (scenario): %d passed, %d failed"):format(passed, failed))
    os.exit(failed > 0 and 1 or 0)
end

run_scheduled(0)   -- first refresh
step("home renders", function() win:render("full") end)
check("full refresh on first render", UIManager.last_refresh == "full")
check("home shows the test apps", contains_text(win[1], "Teste OK"))
check("failing widget shows the error widget (R-E2)", contains_text(win[1], "Teste falha · erro na app"))
check("notification widget", contains_text(win[1], "Notificações"))

-- partial refreshes promote to full every 10 (R-R2)
local modes = {}
for i = 1, 10 do win:render("partial"); modes[i] = UIManager.last_refresh end
check("9 partials then a full", modes[9] == "partial" and modes[10] == "full", table.concat(modes, ","))

step("open test app by tapping its widget", function() check("tap widget", tap_text("Teste OK")) end)
check("on app screen", top().kind == "app" and top().app == "_test_ok")
step("notification high", function() check("tap notify", tap_text("Notificação alta")) end)
check("banner shown (R-T5)", win.banner ~= nil and contains_text(win[1], "Teste: prioridade alta"))
step("dedup key twice", function() tap_text("Mesma key"); tap_text("Mesma key") end)
check("dedup (R-T1)", #Host:notifications() == 2, #Host:notifications())
check("unread count in bell", Host:statusInfo().unread == 2)
step("confirm dialog", function() check("tap confirm", tap_text("Confirmar")) end)
check("dialog open", win.dialog ~= nil)
step("dialog ok", function() check("tap ok", tap_text("Executar")) end)
check("dialog closed after ok", win.dialog == nil and win.toast_text == "Ação de teste executada")
step("callback that throws (R-E1)", function() check("tap failing button", tap_text("Botão que falha")) end)
check("tinta still open after callback error", Host.window == win and win.toast_text ~= nil)
step("attention toggle", function() tap_text("Alternar atenção") end)
step("paged list next page", function() check("tap ›", tap_text("›")) end)
check("page 1", top().page == 1, top().page)
step("open detail", function() tap_text("Abrir detalhe") end)
check("detail pushed", top().screen == "detail" and #win.stack == 3)
step("back swipe from left edge", function() swipe(10, 400, 300, 400) end)
check("back pops", #win.stack == 2)
step("menu opens", function() check("tap menu", tap_text("Menu")) end)
check("menu has app items", win.menu_open and contains_text(win[1], "Atualizar Teste OK agora"))
step("interval picked from the popup", function()
    check("tap interval", tap_text("Intervalo desta app"))
    check("interval popup is up, the menu is gone", win.picker ~= nil and not win.menu_open and contains_text(win[1], "a cada 15 min"))
    check("current interval marked", contains_text(win[1], "●"))
    check("tap 5 min", tap_text("a cada 5 min"))
    check("popup closed", win.picker == nil)
    win:openMenu()      -- back to the menu for the next step
end)
check("interval 60 -> 300", Host:interval("_test_ok") == 300, Host:interval("_test_ok"))
step("tap outside menu closes", function() tap_xy(300, 100) end)
check("menu closed", not win.menu_open)
step("refresh button", function() tap_text("Atualizar") end)
run_scheduled(0)
step("home swipe from bottom", function() swipe(300, 790, 300, 600) end)
check("home after swipe up", #win.stack == 1)

-- the content box is centred on screens that are not 3:4 (6.1): the letterbox is not part of the Tinta, but an edge
-- swipe that starts on the physical edge counts at the box edge, and a tap in the letterbox hits nothing
do
    local sw, sh = SCREEN.w, SCREEN.h
    local cx = T.ox + math.floor(T.BW / 2)
    win:goHome(); win:openApp("_test_ok")   -- (no hashed step here: the KT3 baseline is a list of steps)
    win:onTintaSwipe(nil, { pos = { x = 1, y = T.oy + math.floor(T.BH / 2) }, end_pos = { x = 1 + T.px(300), y = T.oy + math.floor(T.BH / 2) } })
    check("letterbox: a back swipe from the physical left edge goes back", #win.stack == 1, #win.stack)
    win:openApp("_test_ok")
    win:onTintaSwipe(nil, { pos = { x = cx, y = sh - 1 }, end_pos = { x = cx, y = sh - 1 - T.px(200) } })
    check("letterbox: a home swipe from the physical bottom edge goes home", #win.stack == 1, #win.stack)
    win:openApp("_test_ok")
    if T.ox > 0 or T.oy > 0 then
        paint()
        check("letterbox: nothing is tappable at the physical corner", win:hitTest(0, 0, "on_tap") == nil)
        win:openMenu()
        local x = T.ox > 0 and 0 or cx
        local y = T.ox > 0 and math.floor(sh / 2) or 0
        win:onTintaTap(nil, { pos = { x = x, y = y } })
        check("letterbox: a tap in it does not close the menu", win.menu_open == true)
        win:closeOverlays()
    end
    win:goHome()
end

step("central by top swipe", function() swipe(300, 20, 300, 300) end)
check("central open", top().app == "notificacoes")
check("central lists notifications", contains_text(win[1], "Teste: prioridade alta"))
step("open notification", function() tap_text("Teste: prioridade alta") end)
check("notification opened route (8.4)", #win.stack == 2 and top().screen == "detail" and top().args and top().args.n == 7)
check("marked read", Host:unreadCount() == 1, Host:unreadCount())
step("bell opens central", function() win:openCentral() end)
step("mark all read", function() tap_text("Marcar todas como lidas") end)
check("all read", Host:unreadCount() == 0)
step("clear asks confirmation", function() tap_text("Limpar") end)
check("clear dialog", win.dialog ~= nil)
step("confirm clear", function() tap_xy(0, 0); tap_text("Limpar") end)
check("cleared (R-T10)", #Host:notifications() == 0, #Host:notifications())
step("wifi quick toggle off", function() tap_text("Wi-Fi") end)
check("wifi off", Host:wifiState() == "off")
step("refresh without wifi", function() Host:refresh({ "_test_ok" }, "manual"); run_scheduled(0) end)
step("wifi quick toggle on", function() tap_text("Wi-Fi") end)

step("failing app screen (R-E2)", function() win:goHome(); win:openApp("_test_fail") end)
check("error screen", contains_text(win[1], "Erro na app"))
step("error screen back", function() tap_text("Voltar") end)
check("back on home", win:isHome())
for _ = 1, 3 do Host:refresh({ "_test_fail" }, "auto") end
check("3 exceptions disable refresh (R-E4)", Host:status("_test_fail").kind == "error", Host:status("_test_fail").kind)
check("header says erro na app", (Host:headerText("_test_fail")) == "erro na app", (Host:headerText("_test_fail")))
step("header shows app error", function() win:openApp("_test_fail") end)
win:goHome()

-- hold a widget -> organizer with it selected
step("hold a widget", function()
    paint()
    local target
    for _, b in ipairs(win.hot) do if b.on_hold and contains_text(b, "Teste OK") then target = b end end
    check("hold target", target ~= nil)
    win:onTintaHold(nil, { pos = { x = target.dimen.x + 5, y = target.dimen.y + 5 } })
    run_scheduled(1)
end)
check("organizer open on hold", top().kind == "organizer" and top().sel == "_test_ok", top().kind)
step("organizer: before", function() tap_text("↑ Antes") end)
step("organizer: size", function() tap_text("Tamanho ▸") end)
step("organizer: hide", function() tap_text("Ocultar") end)
check("hidden saved (R-O6)", (function()
    for _, it in ipairs(Host:layout("home")) do if it.app == "_test_ok" then return it.hidden end end
end)())
step("organizer: hidden popup adds the app", function()
    check("Ocultos button", tap_text("Ocultos ("))
    check("popup lists the hidden app", win.picker ~= nil and contains_text(win[1], "Apps ocultas") and contains_text(win[1], "Teste OK"))
    check("tap hidden app", tap_text("Teste OK"))
    check("popup stays open, shows the toast", win.picker ~= nil and win.toast_text == "Teste OK adicionada", win.toast_text)
    check("Pronto closes the popup", tap_text("Pronto") and win.picker == nil)
end)
check("unhidden at once (R-O6)", (function()
    for _, it in ipairs(Host:layout("home")) do if it.app == "_test_ok" then return not it.hidden end end
end)())
step("organizer: sleep tab", function() tap_text("Repouso", true) end)
check("sleep tab", top().mode == "sleep")
step("organizer: add to sleep", function()
    check("Ocultos button", tap_text("Ocultos ("))
    check("sleep popup title", win.picker ~= nil and contains_text(win[1], "Apps fora do Repouso"))
    check("tap the app", tap_text("Teste OK"))
    tap_text("Pronto")
end)
step("organizer: hide sistema warns", function()
    top().mode = "home"; top().sel = "sistema"; win:render("partial"); tap_text("Ocultar")
end)
check("Sistema continua no Menu (R-O5)", win.toast_text == "Sistema continua no Menu")
step("organizer done", function() tap_text("Pronto") end)

-- Sistema screens
local sys_screens = { "main", "notifs", "updates", "sleep", "conn", "screen", "apps", "data", "log", "restore" }
for _, s in ipairs(sys_screens) do
    step("sistema " .. s, function() win:goHome(); win:openApp("sistema", s) end)
    check("sistema " .. s .. " built", top().app == "sistema" and not contains_text(win[1], "Erro na app"))
end
step("sistema app settings", function() win:openApp("sistema", "app", { id = "_test_ok" }) end)
check("settings fields", contains_text(win[1], "Servidor de teste") and contains_text(win[1], "não definido"))
-- pages forward (tap ›) until `text` is on screen
local function to_text(text)
    for _ = 1, 8 do
        if contains_text(win[1], text) then return true end
        if not tap_text("›") then break end
    end
    return contains_text(win[1], text)
end
step("bool setting toggles", function() tap_text("Opção") end)
step("choice picked from the popup", function() check("Modo row", to_text("Modo")); pick("Modo", "modo B", "modo A") end)
check("choice saved", Host:appSetting("_test_ok", "mode") == "b", Host:appSetting("_test_ok", "mode"))
-- 10.5 turn an app off and on, launcher row, removal guards (nothing is deleted: the dialog is cancelled)
step("app screen: Estado row", function() win:openApp("sistema", "app", { id = "_test_ok" }) end)
check("app screen shows Ativada and Remover app", contains_text(win[1], "Ativada") and to_text("Remover app"))   -- may be on page 2 at some sizes
win:setPage(0)
step("app screen: turn off", function() check("tap Estado", tap_text("Estado")) end)
check("app is off: not registered, parked", Host:app("_test_ok") == nil and Host:inactiveApps()[1] ~= nil)
check("off app: screen says Desativada", contains_text(win[1], "Desativada"))
check("off app: name still resolves", Host:appName("_test_ok") == "Teste OK")
step("sistema apps list shows the off app dashed", function() win:openApp("sistema", "apps") end)
check("apps list has the off app", to_text("desativada"))
step("launcher with an off app", function() win:goHome(); win:openMenu(); tap_text("Apps") end)
check("launcher: off app listed as a turn-on row", to_text("desativada") and contains_text(win[1], "Teste OK") and contains_text(win[1], "Ativar"))
step("launcher: tap turns it on", function() check("tap off row", tap_text("Teste OK")) end)
check("launcher: app is on again", Host:app("_test_ok") ~= nil and win.toast_text == "Teste OK ativada", win.toast_text)
check("launcher: back to a normal row", not contains_text(win[1], "desativada"))
step("sistema is not switchable", function() win:goHome(); win:openApp("sistema", "app", { id = "sistema" }) end)
check("sistema: no remove row, cannot be turned off", not contains_text(win[1], "Remover app") and contains_text(win[1], "não pode ser desativada"))
check("sistema: setAppEnabled refuses", select(2, Host:setAppEnabled("sistema", false)) == "protected" and Host:app("sistema") ~= nil)
check("removeApp refuses system and traversal ids", select(2, Host:removeApp("sistema")) == "system"
    and select(2, Host:removeApp("../x")) == "bad id" and select(2, Host:removeApp("a/b")) == "bad id")
step("remove asks for confirmation", function() win:openApp("sistema", "app", { id = "_test_ok" }); to_text("Remover app"); tap_text("Remover app") end)
check("remove dialog open", win.dialog ~= nil and win.dialog.title == "Remover Teste OK?", win.dialog and win.dialog.title)
step("remove cancelled", function() check("tap cancel", tap_text("Cancelar")) end)
check("cancel keeps the app", win.dialog == nil and Host:app("_test_ok") ~= nil)
-- 5.1 an app that needs a newer Tinta is not loaded and says so (no crash)
do
    local Core = require("ui/core")
    local r, why = Core.register(Host.c, { id = "_futura", name = "Futura", api = 9, min_portal = "9.0" })
    check("needs-newer app is not registered", r == nil and why == "api" and Host:app("_futura") == nil)
    step("needs-newer app: Sistema list", function() win:openApp("sistema", "apps") end)
    check("needs-newer app: listed with the reason", to_text("precisa de uma versão mais nova da Tinta"))
    step("needs-newer app: its screen", function() win:openApp("sistema", "app", { id = "_futura" }) end)
    check("needs-newer app: screen says what it asks", contains_text(win[1], "pede a API 9") and contains_text(win[1], "Remover app")
        and not contains_text(win[1], "Estado"))
    Host.c.registry:forget("_futura")
end
run_scheduled(); win:render("partial")      -- let the toasts of this section expire
step("notif prefs popup", function() win:openApp("sistema", "notifs"); pick("Teste OK", "normal") end)
check("pref cycled", Host:getPref("_test_ok") == "normal", Host:getPref("_test_ok"))
step("navigation gestures only", function()
    win:openApp("sistema", "screen"); pick("Navegação", "só gestos")
end)
check("nav gestures", Host:get("nav") == "gestures")
step("home with handle", function() win:goHome() end)
step("navigation back to bar", function() win:openApp("sistema", "screen"); pick("Navegação", "barra + gestos") end)
step("language en", function() pick("Idioma", "English") end)
check("language is en", Host:get("lang") == "en", Host:get("lang"))
step("language back to pt", function() pick("Language", "Português") end)

-- Dados (10.5): diagnostic export, settings backup and restore, with a token that must never be written
do
    local dir = os.tmpname(); os.remove(dir); os.execute('mkdir -p "' .. dir .. '"')
    local function read(name) local fh = io.open(dir .. "/" .. name); local t = fh and fh:read("*a"); if fh then fh:close() end; return t end
    local function find(prefix)
        local p = io.popen('ls -1 "' .. dir .. '"'); local found
        for n in p:lines() do if n:find("^" .. prefix) then found = n end end
        p:close(); return found
    end
    Host.data_dir = dir
    Host:setAppSetting("_test_ok", "token", "SMOKE-TOKEN-XYZ")
    Host:setAppSetting("_test_ok", "limit", 9)
    step("dados: screen rows", function() win:goHome(); win:openApp("sistema", "data") end)
    check("dados: rows shown", contains_text(win[1], "Exportar diagnóstico") and contains_text(win[1], "Backup das configurações")
        and contains_text(win[1], "Restaurar backup"))
    step("dados: export diagnostic", function() check("tap export", tap_text("Exportar diagnóstico")) end)
    local dname = find("tinta%-diagnostico%-")
    check("dados: diagnostic file written, toast shows its name", dname and win.toast_text == dname, tostring(dname) .. " / " .. tostring(win.toast_text))
    local dtext = read(dname or "")
    check("dados: diagnostic has the token only as redacted", dtext and not dtext:find("SMOKE-TOKEN-XYZ", 1, true) and dtext:find("<redacted>", 1, true))
    check("dados: diagnostic lists apps and versions", dtext and dtext:find("_test_ok v1 enabled", 1, true) and dtext:find("device: ", 1, true)
        and #dtext < 256 * 1024)
    step("dados: backup", function() check("tap backup", tap_text("Backup das configurações")) end)
    local bname = find("tinta%-backup%-")
    check("dados: backup file written, toast shows its name", bname and win.toast_text == bname, tostring(bname) .. " / " .. tostring(win.toast_text))
    local btext = read(bname or "")
    check("dados: backup holds settings but no token", btext and btext:find('"limit":9', 1, true) and not btext:find("SMOKE-TOKEN-XYZ", 1, true))
    Host:setAppSetting("_test_ok", "limit", 4)
    Host:setAppSetting("_test_ok", "token", "NEW-TOKEN-AFTER")
    step("dados: restore list", function() win:openApp("sistema", "restore") end)
    check("dados: restore lists the backup", contains_text(win[1], "tinta-backup-"))
    step("dados: restore asks first", function() check("tap backup file", tap_text("tinta-backup-")) end)
    check("dados: confirm dialog", win.dialog ~= nil)
    step("dados: restore confirmed", function() check("tap restore", tap_text("Restaurar")) end)
    check("dados: restored value", Host:appSetting("_test_ok", "limit") == 9, Host:appSetting("_test_ok", "limit"))
    check("dados: current token kept", Host:appSetting("_test_ok", "token") == "NEW-TOKEN-AFTER")
    check("dados: restore toast", win.toast_text and win.toast_text:find("Restaurado", 1, true) ~= nil, win.toast_text)
    step("dados: tinta reloaded on home", function() win:render("full") end)
    -- a broken file is a message, not a crash
    local fh = io.open(dir .. "/tinta-backup-20000101-0000.json", "w"); fh:write("{oops"); fh:close()
    step("dados: restore bad file", function() win:openApp("sistema", "restore"); tap_text("01/01/2000") end)
    step("dados: bad file confirm", function() tap_text("Restaurar") end)
    check("dados: bad file toast", win.toast_text == "Arquivo de backup inválido", win.toast_text)
    Host.data_dir = nil
    os.execute('rm -rf "' .. dir .. '"')
end

-- every real app: its main screen (and the extra ones), portrait and landscape (drives the layout of each view)
local app_screens = {}
for _, a in ipairs(TA.screens) do app_screens[#app_screens + 1] = a end
for _, a in ipairs({ { "bateria" }, { "relogio" }, { "repouso" },
    { "timer" }, { "nota" }, { "contagem" }, { "contagem", "edit" }, { "notificacoes" } }) do app_screens[#app_screens + 1] = a end
-- Bateria with a log (a day of discharge, a charge, sleep and wake marks), so its chart and stats draw for real
do
    local BA = require("apps/bateria/init")._A
    local now = os.time()
    local st = BA.store
    if not st then require("apps/bateria/init"); st = require("apps/bateria/csvlog").open(BA.data_dir() .. "/tinta-battery.csv"); BA.store = st end
    local pct, t = 100, now - 26 * 3600
    while t < now do
        local charging = t > now - 14 * 3600 and t < now - 12 * 3600
        if charging then pct = math.min(100, pct + 6) elseif math.floor(t / 600) % 3 == 0 then pct = math.max(5, pct - 1) end
        st:sample(t, { pct = pct, charging = charging, wifi = math.floor(t / 3600) % 2 == 0, mv = 3700 + pct, ma = charging and 400 or -40,
            mah = 8 * pct, temp = 24 }, nil)
        t = t + 600
    end
    st:sample(now - 2 * 3600, { pct = pct, charging = false }, 1)
    st:sample(now - 3600, { pct = pct, charging = false }, 3)
    BA.read = function() return { pct = pct, charging = false, mv = 3700, ma = -40, mah = 8 * pct, temp = 24 } end
    Host:refresh({ "bateria" }, "manual"); run_scheduled(0)
end

local function app_screens_flow(label)
    for _, a in ipairs(app_screens) do
        step(label .. " app " .. a[1] .. (a[2] and (" " .. a[2]) or ""), function() win:goHome(); win:openApp(a[1], a[2]) end)
        check(label .. " app " .. a[1] .. " built", not contains_text(win[1], "Erro na app"), a[2])
    end
    win:goHome()
end
app_screens_flow("portrait")

-- launcher (6.5, 7.4): Menu -> Apps lists every app, hidden ones included; opens one and comes back
local Org_hide = function(list, id) return require("ui/orglogic").hide(list, id, "home") end
local function launcher_flow(label)
    local saved = Host:layout("home")
    Host:saveLayout("home", Org_hide(saved, "_test_ok"))
    step(label .. " launcher: home", function() win:goHome() end)
    step(label .. " launcher: menu", function() win:openMenu() end)
    local first_item = (function()
        local _, items = Host:menuItems(win)
        return items[1][1]
    end)()
    check(label .. " launcher: Apps is the first menu item", first_item == "Apps", first_item)
    step(label .. " launcher: tap Apps", function() check("tap Apps", tap_text("Apps")) end)
    check(label .. " launcher: route", top().kind == "launcher" and not win.menu_open and #win.stack == 2)
    check(label .. " launcher: system app listed", contains_text(win[1], "Notificações") or (top().page or 0) == 0)
    local pages = 1
    -- the launcher row of the hidden test app on the page now showing (a toast of an earlier step may say "Teste OK" too)
    local function hidden_row_shown()
        paint()
        for _, b in ipairs(win.hot) do if b.painted and b.on_hold and contains_text(b, "Teste OK") and contains_text(b, "oculta") then return true end end
        return false
    end
    for _ = 1, 6 do
        if hidden_row_shown() then break end
        step(label .. " launcher: next page", function() check("tap ›", tap_text("›")) end)
        pages = pages + 1
    end
    check(label .. " launcher: hidden app listed and marked", contains_text(win[1], "Teste OK") and contains_text(win[1], "oculta"))
    check(label .. " launcher: paged", pages > 1 or contains_text(win[1], "Sistema"))
    step(label .. " launcher: open hidden app", function() check("tap Teste OK", tap_text("Teste OK")) end)
    check(label .. " launcher: app opened", top().kind == "app" and top().app == "_test_ok" and #win.stack == 3)
    step(label .. " launcher: back", function() win:back() end)
    check(label .. " launcher: back on the list", top().kind == "launcher" and #win.stack == 2)
    step(label .. " launcher: menu on the list", function() win:openMenu() end)
    step(label .. " launcher: Apps again only closes the menu", function() tap_text("Apps") end)
    check(label .. " launcher: still one launcher", top().kind == "launcher" and #win.stack == 2 and not win.menu_open)
    step(label .. " launcher: hold adds to Home", function()
        paint()
        local target
        for _, b in ipairs(win.hot) do if b.painted and b.on_hold and contains_text(b, "Teste OK") then target = b end end
        check("hold target", target ~= nil)
        win:onTintaHold(nil, { pos = { x = target.dimen.x + 5, y = target.dimen.y + 5 } })
        run_scheduled(1)
    end)
    check(label .. " launcher: hold unhid it", (function()
        for _, it in ipairs(Host:layout("home")) do if it.app == "_test_ok" then return not it.hidden end end
    end)() and win.toast_text == "Teste OK adicionada ao Início", win.toast_text)
    step(label .. " launcher: marked on Home now", function() win:render("partial") end)
    check(label .. " launcher: mark no Início", contains_text(win[1], "no Início"))
    step(label .. " launcher: home", function() win:goHome() end)
    Host:saveLayout("home", saved)
    win:render("full")
end

launcher_flow("portrait")

-- rotation (6.8)
step("rotate to landscape", function() Host:rotate() end)
check("landscape screen", SCREEN.w == BASE_H)
for _, s in ipairs(sys_screens) do
    step("landscape sistema " .. s, function() win:goHome(); win:openApp("sistema", s) end)
end
step("landscape central", function() win:goHome(); win:openCentral() end)
step("landscape organizer", function() win:goHome(); win:openOrganizer("home", "_test_ok") end)
step("landscape test app", function() win:goHome(); win:openApp("_test_ok") end)
step("landscape home", function() win:goHome() end)
step("landscape menu", function() win:openMenu() end)
check("landscape menu keeps Dormir agora (7 items fit with the bar)", contains_text(win[1], "Dormir agora"))
win:closeOverlays()
launcher_flow("landscape")
app_screens_flow("landscape")
step("landscape app menu keeps Dormir agora", function() win:goHome(); win:openApp("_test_ok"); win:openMenu() end)
check("landscape app menu shows Apps and Dormir agora", contains_text(win[1], "Apps") and contains_text(win[1], "Dormir agora"))
win:closeOverlays()
win:goHome()

-- many apps -> pages on home
step("home pages", function()
    local list = Host:layout("home")
    for _ = 1, 3 do list[#list + 1] = { app = "_test_ok", size = "4x4" } end
    Host:saveLayout("home", list)
    win:render("full")
end)
step("page swipe", function() swipe(400, 300, 150, 310) end)
check("page 2", (win:current().page or 0) == 1, win:current().page)
step("home button back to first page", function() tap_text("Início") end)
check("first page", (win:current().page or 0) == 0)
step("rotate back to portrait", function() Host:rotate() end)
step("portrait pages", function() win:render("full") end)

-- organizer over several Home pages (7.3): pager over all pages, selection kept, moves cross page breaks
do
    local cols, rows = require("ui/geom").grid_dims(SCREEN.w, SCREEN.h)
    local function pages_now() return Host:packedPages("home", cols, rows) end
    local saved_home = Host:layout("home")
    -- distinct apps, so every widget has one place: a + b | bateria + _test_ok | notificacoes
    Host:saveLayout("home", { { app = TA.a, size = "4x4" }, { app = TA.b, size = "4x4" }, { app = "bateria", size = "4x2" },
        { app = "_test_ok", size = "4x4" }, { app = "notificacoes", size = "4x4" } })
    local function page_of(app) return require("ui/orglogic").page_of(pages_now(), app) end
    check("home has several pages", #pages_now() > 1, #pages_now())
    step("organizer pages: open", function() win:goHome(); win:openOrganizer("home", TA.a) end)
    check("organizer opens on the page of the selection", top().kind == "organizer" and top().view == nil and page_of(TA.a) == 1)
    check("organizer meta shows pages", contains_text(win[1], "página 1/"))
    check("organizer info names the page", contains_text(win[1], "pág. 1"))
    step("organizer pages: next page", function() check("tap ›", tap_text("›")) end)
    check("viewing page 2 keeps selection", top().view == 2 and top().sel == TA.a, tostring(top().view))
    check("page 2 in the header", contains_text(win[1], "página 2/"))
    step("organizer pages: pick a widget of page 2", function()
        local target
        for _, it in ipairs(pages_now()[2]) do target = target or it.app end
        check("page 2 widget tapped", tap_text(Host:app(target).short or Host:app(target).name))
    end)
    check("selection moved to page 2", page_of(top().sel) == 2 and top().view == nil, tostring(top().sel))
    -- "↓ Depois" until the widget crosses to the next page, and back with "↑ Antes"
    step("organizer pages: move past a page end", function()
        top().sel = TA.a; top().view = nil; win:render("partial")
        local before = page_of(TA.a)
        local n = 0
        while page_of(TA.a) == before and n < 20 do check("tap ↓ Depois", tap_text("↓ Depois")); n = n + 1 end
        check("moved to another page", page_of(TA.a) ~= before, tostring(page_of(TA.a)))
        check("organizer follows it", top().view == nil and contains_text(win[1], "página " .. page_of(TA.a) .. "/"))
        n = 0
        while page_of(TA.a) == page_of(TA.a) and page_of(TA.a) ~= before and n < 20 do tap_text("↑ Antes"); n = n + 1 end
        check("moved back", page_of(TA.a) == before)
    end)
    step("organizer pages: landscape", function() Host:rotate(); win:render("full") end)
    check("landscape organizer pager", contains_text(win[1], "página") and (tap_text("›") or true))
    step("organizer pages: landscape sleep tab", function() check("tap Repouso", tap_text("Repouso")) end)
    check("landscape sleep tab has the copy button", contains_text(win[1], "Copiar do Início"))
    step("organizer pages: portrait again", function() Host:rotate(); win:render("full") end)
    -- sleep tab: copy Home page 1 (with confirmation)
    step("organizer: sleep tab (copy)", function() tap_text("Repouso") end)
    step("organizer: copy from Home asks", function() check("tap copy", tap_text("Copiar do Início")) end)
    check("copy confirmation open", win.dialog ~= nil and win.dialog.title == "Copiar do Início?")
    step("organizer: copy cancelled changes nothing", function()
        local before = #Host:layout("sleep")
        win.dialog.on_cancel = win.dialog.on_cancel
        win:closeOverlays()
        check("sleep layout untouched", #Host:layout("sleep") == before)
    end)
    step("organizer: copy confirmed", function()
        tap_text("Copiar do Início")
        local ok = win.dialog and win.dialog.on_ok
        check("has on_ok", ok ~= nil)
        win.dialog.on_ok()
        win:closeOverlays()
    end)
    check("sleep layout = Home page 1 without Sistema", (function()
        local want = {}
        for _, it in ipairs(pages_now()[1]) do if it.app ~= "sistema" then want[#want + 1] = it.app .. ":" .. it.size end end
        local got = {}
        for _, it in ipairs(Host:layout("sleep")) do got[#got + 1] = it.app .. ":" .. it.size end
        return table.concat(got, ",") == table.concat(want, ",")
    end)(), nil)
    step("organizer: back home", function() tap_text("Pronto") end)
    Host:saveLayout("home", saved_home)
end

-- tick and clock
step("tick", function() Host:tick(true); run_scheduled(0) end)

-- Sistema → Repouso (10.5): grouped, one wake setting, the schedule text only for "pelo horário"
step("repouso opens", function() win:goHome(); win:openApp("sistema", "sleep") end)
check("repouso: sections", contains_text(win[1], "QUANDO DORMIR") and contains_text(win[1], "ENQUANTO DORME"))
check("repouso: rows", contains_text(win[1], "Dormir sozinho") and contains_text(win[1], "só na bateria") and contains_text(win[1], "Depois de")
    and contains_text(win[1], "5 min") and not contains_text(win[1], "expediente")
    and contains_text(win[1], "Dormir agora") and contains_text(win[1], "Atualizar a tela")
    and (TEXT_LARGE or contains_text(win[1], "O que aparece na tela")))   -- (large text: taller rows push the last one to page 2)
check("repouso: the schedule shows as plain text (default 'pelo horário')", contains_text(win[1], "pelo horário")
    and contains_text(win[1], "dias úteis 07:30–18:30 a cada 30 min") and contains_text(win[1], "23:00–07:30 não atualiza")
    and contains_text(win[1], "horários fixos nesta versão"))
check("repouso: the schedule lines are not tappable", not tap_text("dias úteis 07:30–18:30 a cada 30 min"))
check("repouso: no old rows", not contains_text(win[1], "Agenda por horário") and not contains_text(win[1], "Acordar para atualizar")
    and not contains_text(win[1], "Entrar sozinho"))
step("repouso: wake picked nunca", function() pick("Atualizar a tela", "nunca") end)
check("repouso: nunca", Host:get("wake") == "never" and contains_text(win[1], "nunca") and not contains_text(win[1], "23:00–07:30 não atualiza"))
step("repouso: wake picked 15 min", function() pick("Atualizar a tela", "a cada 15 min") end)
check("repouso: 15 min", Host:get("wake") == 900 and contains_text(win[1], "a cada 15 min") and not contains_text(win[1], "horários fixos"))
for _, want in ipairs({ { 1800, "a cada 30 min" }, { 3600, "a cada 1 h" }, { 7200, "a cada 2 h" }, { "schedule", "pelo horário" } }) do
    local label
    want, label = want[1], want[2]
    step("repouso: wake -> " .. tostring(want), function() pick("Atualizar a tela", label) end)
    check("repouso: wake is " .. tostring(want), Host:get("wake") == want, Host:get("wake"))
end
step("repouso: mode picked nunca", function() pick("Dormir sozinho", "nunca") end)
check("repouso: mode never hides the minutes row", Host:get("idle_mode") == "never" and contains_text(win[1], "não dorme sozinho")
    and not contains_text(win[1], "Depois de"))
step("repouso: mode picked sempre", function() pick("Dormir sozinho", "sempre") end)
check("repouso: mode always shows the minutes row", Host:get("idle_mode") == "always" and contains_text(win[1], "Depois de"))
step("repouso: minutes picked 10", function() pick("Depois de", "10 min") end)
check("repouso: minutes 10", Host:get("idle_sleep") == 10 and contains_text(win[1], "10 min"))
step("repouso: back to 5 min, battery", function() Host:set("idle_sleep", 5); Host:set("idle_mode", "battery"); win:render("full") end)
step("Sistema row shows the summary", function() win:goHome(); win:openApp("sistema", "main") end)
check("Sistema: Repouso summary", contains_text(win[1], "dorme sozinho: 5 min · atualiza: pelo horário"))

-- Bateria's background log (10.3): written every minute whatever the screen, even with Bateria on no Home page
local BG = {}
do
    local BA = require("apps/bateria/init")._A
    BG.A, BG.saved = BA, { data_dir = BA.data_dir, read = BA.read, store = BA.store }
    BG.dir = os.tmpname(); os.remove(BG.dir); os.execute('mkdir -p "' .. BG.dir .. '"')
    BG.file = BG.dir .. "/tinta-battery.csv"
    BG.pct = 77
    BA.data_dir = function() return BG.dir end
    BA.store = nil
    BA.read = function() return { pct = BG.pct, charging = false, mv = 3700, ma = -40, mah = 600, temp = 24 } end
    function BG.lines()
        local out, fh = {}, io.open(BG.file)
        if fh then for l in fh:lines() do out[#out + 1] = l end; fh:close() end
        return out
    end
    BG.home = Host:layout("home")
    local without = {}
    for _, it in ipairs(BG.home) do if it.app ~= "bateria" then without[#without + 1] = it end end
    Host:saveLayout("home", without)
    win:goHome(); win:openApp("_test_ok")
    Host.bg_last = os.time() - 61
    Host:tick(); run_scheduled(0)
    check("background log: a tick on another app's screen writes a sample", #BG.lines() == 2, #BG.lines())
    Host:tick(); run_scheduled(0)
    check("background log: another tick within the minute writes nothing", #BG.lines() == 2, #BG.lines())
    BG.pct = 76
    Host.bg_last = os.time() - 61
    win:goHome(); win:openApp("sistema", "sleep")
    Host:tick(); run_scheduled(0)
    check("background log: a change is logged on the Sistema screen too", #BG.lines() == 3, #BG.lines())
end

-- Dormir agora → sleep page → button → back (device/sleep.lua over fakes)
step("Dormir agora", function() win:goHome(); win:openApp("sistema", "sleep"); tap_text("Dormir agora") end)
check("sleeping: sleep page shown", Host.sleeping == true and contains_text(win[1], "Em repouso. Aperte o botão de energia"))
check("sleeping: status bar text (R-S4)", contains_text(win[1], "Repouso · atualizado"))
check("sleeping: menus closed, window kept", win.menu_open == false and win.dialog == nil and Host.window == win)
step("sleeping: settle then suspend", function() run_scheduled(2) end)
check("sleeping: powerButton sent, preventScreenSaver 0",
    table.concat(fake_powerd.calls, ","):find("powerButton=1", 1, true) ~= nil and fake_powerd.props.preventScreenSaver == "0")
step("sleeping: powerd readyToSuspend -> rtcWakeup", function() fake_powerd.state = "readyToSuspend"; run_scheduled(2) end)
check("sleeping: rtcWakeup requested", table.concat(fake_powerd.calls, ","):find("rtcWakeup=", 1, true) ~= nil)
step("button wake", function() fake_powerd.state = "active"; run_scheduled(2) end)
check("awake again on the previous screen", Host.sleeping == false and not contains_text(win[1], "Em repouso. Aperte")
    and top().app == "sistema" and top().screen == "sleep")
check("preventScreenSaver back to 1 while the Tinta is open", fake_powerd.props.preventScreenSaver == "1")
fake_powerd.state = "active"

do
    local l = BG.lines()
    check("background log: sleep entry and button wake each wrote one marked sample",
        #l == 5 and l[4]:match(",1$") and l[5]:match(",3$"), table.concat(l, " | "))
    BG.A.data_dir, BG.A.read, BG.A.store = BG.saved.data_dir, BG.saved.read, BG.saved.store
    Host:saveLayout("home", BG.home)
    os.execute('rm -rf "' .. BG.dir .. '"')
end

-- idle timer (R-P4): 5 min without touch; mode "só na bateria" (default) does not sleep while plugged in
battery.charging = true
Host.last_touch = os.time() - 301
check("idle: battery mode, plugged -> not due", Host:idleDue() == false)
Host:set("idle_mode", "always")
check("idle: always mode, plugged -> due", Host:idleDue() == true)
Host:set("idle_mode", "never")
battery.charging = false
check("idle: never mode -> not due", Host:idleDue() == false)
Host:set("idle_mode", "battery")
check("idle: battery mode, unplugged -> due", Host:idleDue() == true)
step("idle sleep", function()
    Host.last_touch = os.time() - 301
    Host:tick(true)
end)
check("idle: entered sleep", Host.sleeping == true)
step("idle: wake", function() run_scheduled(2); run_scheduled(2); fake_powerd.state = "active"; run_scheduled(2) end)
check("idle: awake again", Host.sleeping == false)
check("idle: text input open blocks the idle timer", (function()
    Host.last_touch = os.time() - 9999
    Host.input_dialog = {}
    local due = Host:idleDue()
    Host.input_dialog = nil
    return due == false
end)())
Host:touched()

-- sleep page renders (stage 3 drives it)
step("sleep page", function()
    Host.sleeping = true
    Host:set("sleep_shows", "alta")
    Host.sleep_info = { at = "10:00", next = "10:30" }
    Host:emit("sistema", { key = "s1", prio = "alta", title = "Alta no repouso" })
    win:render("full")
end)
check("sleep strip says unread (R-T11)", contains_text(win[1], "1 não lida: Alta no repouso"))
check("sleep: widgets never show the awake interval", not contains_text(win[1], "a cada"))
check("sleep: widget footer is the sleep refresh", contains_text(win[1], "atualizado 10:00"))
check("sleep: taps ignored (R-P8)", (function() local x, y = at(300, 300); win:onTintaTap(nil, { pos = { x = x, y = y } }); return true end)())
Host.sleeping = false

-- wake requests (11.7): ctx.wake_at from the Timer reaches the host, the sleep target and the wake-up batch
do
    local tctx = Host.c.registry:ctx("timer")
    check("timer: ctx has wake_at, input, redraw and back", tctx and type(tctx.wake_at) == "function"
        and type(tctx.input) == "function" and type(tctx.redraw) == "function" and type(tctx.back) == "function")
    local n0 = os.time()
    tctx.wake_at(n0 + 600)
    check("wake request: the host keeps the earliest after now", Host:nextWakeRequest(n0) == n0 + 600)
    check("wake request: none after it", Host:nextWakeRequest(n0 + 600) == nil)
    check("wake request: an awake timer is scheduled", Host.wake_cb ~= nil)
    step("wake request: Dormir agora", function() win:goHome(); Host:sleepNow("now") end)
    check("wake request: sleeping", Host.sleeping == true)
    local Sleep = require("device/sleep")
    local target = Sleep._state() and Sleep._state().target
    check("wake request: the sleep target is the request (it is before the schedule's)", target == n0 + 600, tostring(target))
    local ids = Host:wakePlan(n0 + 500)
    check("wake request: not due yet, not in the batch", (function() for _, id in ipairs(ids) do if id == "timer" then return false end end return true end)())
    ids = Host:wakePlan(n0 + 590)      -- inside the 30 s slack of the RTC wake-up
    check("wake request: due, the timer runs in the wake-up batch", (function() for _, id in ipairs(ids) do if id == "timer" then return true end end return false end)())
    check("wake request: consumed by the batch", Host:nextWakeRequest(0) == nil)
    step("wake request: settle, suspend, button wake", function()
        run_scheduled(2); fake_powerd.state = "readyToSuspend"; run_scheduled(2); fake_powerd.state = "active"; run_scheduled(2)
    end)
    check("wake request: awake again", Host.sleeping == false)
    tctx.wake_at(os.time() + 900)
    tctx.wake_at(nil)
    check("wake request: cancelled", Host:nextWakeRequest(0) == nil and Host.wake_cb == nil)
    fake_powerd.state = "active"
end

-- the Tinta log holds only the errors made on purpose (R-E3: app, function, first line)
do
    local unexpected, failing = {}, 0
    for _, l in ipairs(Host:logTail(500)) do
        if l.level == "error" then
            if tostring(l.msg):find("sqlite binding unavailable", 1, true) then   -- no SQLite binding on a dev machine: memory store
            elseif l.app == "_test_fail" or tostring(l.msg):find("de propósito", 1, true) then failing = failing + 1
            else unexpected[#unexpected + 1] = tostring(l.app) .. ": " .. tostring(l.msg) end
        end
    end
    check("errors of the failing app are logged", failing >= 4, failing)
    check("no unexpected errors in the Tinta log", #unexpected == 0, unexpected[1])
end

-- Choice popup (6.10) from the Sistema rows and the organizer, portrait and landscape: opens with the current option marked,
-- a pick saves and closes, a tap outside / Voltar / the back gesture cancel, long lists page
do
    local function popup_has(text)
        paint()
        for _, b in ipairs(win.hot) do
            if b.painted and b.layer > 0 and b.on_tap and contains_text(b, text) then return true end
        end
        return false
    end
    -- opens the popup from `row`, turns its pages until `option` is shown, taps it
    local function pick_paged(row, option)
        check("popup opens from " .. row, tap_text(row) and win.picker ~= nil)
        for _ = 1, 4 do
            if popup_has(option) then break end
            tap_text("›")
        end
        check("popup shows " .. option, popup_has(option), option)
        tap_text(option)
        check("popup closed after " .. option, win.picker == nil)
    end
    Host:set("wake", "schedule"); Host:set("idle_mode", "battery"); Host:set("idle_sleep", 5); Host:set("lang", "pt")
    for _, land in ipairs({ false, true }) do
        local tag = land and "landscape" or "portrait"
        if land then step("popup: rotate to landscape", function() Host:rotate() end) end
        step("popup " .. tag .. ": Atualizar a tela opens", function()
            win:goHome(); win:openApp("sistema", "sleep"); check("tap row", tap_text("Atualizar a tela"))
        end)
        check(tag .. ": popup up with the title, the current option marked", win.picker ~= nil and contains_text(win[1], "pelo horário")
            and win.picker.current == "schedule" and popup_has("●"))
        step("popup " .. tag .. ": tap outside cancels", function() tap_xy(land and 10 or 10, 300) end)
        check(tag .. ": cancelled, nothing changed", win.picker == nil and Host:get("wake") == "schedule" and top().screen == "sleep")
        step("popup " .. tag .. ": Voltar cancels", function() tap_text("Atualizar a tela"); tap_text("Voltar") end)
        check(tag .. ": Voltar closed only the popup", win.picker == nil and Host:get("wake") == "schedule" and top().screen == "sleep" and #win.stack == 2)
        step("popup " .. tag .. ": back gesture cancels", function() tap_text("Atualizar a tela"); swipe(10, 400, 300, 400) end)
        check(tag .. ": back gesture closed only the popup", win.picker == nil and top().screen == "sleep" and #win.stack == 2)
        step("popup " .. tag .. ": pick nunca (paged when it does not fit)", function() pick_paged("Atualizar a tela", "nunca") end)
        check(tag .. ": wake saved", Host:get("wake") == "never", Host:get("wake"))
        step("popup " .. tag .. ": Dormir sozinho", function() pick_paged("Dormir sozinho", "sempre") end)
        check(tag .. ": mode saved, minutes row shown", Host:get("idle_mode") == "always" and contains_text(win[1], "Depois de"))
        step("popup " .. tag .. ": Depois de", function() pick_paged("Depois de", "15 min") end)
        check(tag .. ": minutes saved", Host:get("idle_sleep") == 15, Host:get("idle_sleep"))
        step("popup " .. tag .. ": language opens", function() win:openApp("sistema", "screen"); check("tap row", tap_text("Idioma")) end)
        check(tag .. ": language popup", win.picker ~= nil and popup_has("English") and popup_has("Português"))
        step("popup " .. tag .. ": language picked", function() tap_text("English") end)
        check(tag .. ": language en", Host:get("lang") == "en" and win.picker == nil)
        step("popup " .. tag .. ": language back", function() pick_paged("Language", "Português") end)
        check(tag .. ": language pt", Host:get("lang") == "pt")
        Host:set("wake", "schedule"); Host:set("idle_mode", "battery"); Host:set("idle_sleep", 5)

        -- organizer: the hidden-apps popup adds apps back and stays open (the popup pages: many apps are not on the Home list)
        local saved_home = Host:layout("home")
        local function extras_n()
            for n = 0, 40 do
                if contains_text(win[1], "Ocultos (" .. n .. ")") then return n end
            end
        end
        local function popup_tap(text)       -- turns the popup pages (forward, then back) until `text` is on one, taps it
            for _, arrow in ipairs({ "›", "‹" }) do
                for _ = 1, 8 do
                    if popup_has(text) then tap_text(text); return true end
                    if not tap_text(arrow) then break end
                end
            end
            return false
        end
        local hidden, n0 = {}, 0
        step("popup " .. tag .. ": organizer with two hidden apps", function()
            win:goHome()
            local l = Host:layout("home")
            for _, it in ipairs(l) do
                if #hidden < 2 and it.app ~= "sistema" and Host:app(it.app) and not it.hidden then it.hidden = true; hidden[#hidden + 1] = it.app end
            end
            Host:saveLayout("home", l)
            win:openOrganizer("home")
            n0 = extras_n() - 2
        end)
        check(tag .. ": organizer button counts the two", #hidden == 2 and n0 >= 0 and extras_n() == n0 + 2, tostring(n0))
        step("popup " .. tag .. ": Ocultos opens the list", function() check("tap Ocultos", tap_text("Ocultos (" .. (n0 + 2) .. ")")) end)
        check(tag .. ": titled, Pronto there", win.picker ~= nil and contains_text(win[1], "Apps ocultas") and popup_has("Pronto"))
        step("popup " .. tag .. ": first app added", function() check("tap " .. hidden[1], popup_tap(Host:appName(hidden[1]))) end)
        check(tag .. ": popup stays open, one fewer, toast", win.picker ~= nil and extras_n() == n0 + 1
            and win.toast_text == Host:appName(hidden[1]) .. " adicionada" and top().sel == hidden[1], tostring(win.toast_text))
        step("popup " .. tag .. ": second app added", function() check("tap " .. hidden[2], popup_tap(Host:appName(hidden[2]))) end)
        check(tag .. ": both added, popup still open", win.picker ~= nil and extras_n() == n0)
        step("popup " .. tag .. ": add the rest, list gets empty", function()
            for _ = 1, 40 do
                if extras_n() == 0 then break end
                local first
                paint()
                for _, b in ipairs(win.hot) do
                    if b.painted and b.layer > 0 and b.on_tap and b.h == T.ROW_H and (not first or b.dimen.y < first.dimen.y) then first = b end
                end
                if not first then break end
                win:onTintaTap(nil, { pos = { x = first.dimen.x + math.floor(first.w / 2), y = first.dimen.y + math.floor(first.h / 2) } })
            end
        end)
        check(tag .. ": empty text and Pronto", win.picker ~= nil and extras_n() == 0 and contains_text(win[1], "Nenhuma app oculta.") and popup_has("Pronto"))
        step("popup " .. tag .. ": Pronto closes it", function() tap_text("Pronto") end)
        check(tag .. ": closed, button disabled", win.picker == nil and extras_n() == 0 and not tap_text("Ocultos (0)"))
        Host:saveLayout("home", saved_home)
        run_scheduled(); win:render("partial")      -- let the toast expire
    end
    step("popup: rotate back to portrait", function() Host:rotate(); win:goHome() end)
end

step("close", function() Host:close() end)
check("closed", Host.window == nil)
check("a short input shield stays above FileManager (swallows taps aimed at the Tinta)",
    #UIManager.shown == 1 and UIManager.shown[1].name == "tinta_shield" and UIManager.shown[1]:onGesture() == true)
check("rotation restored before the window closed", SCREEN.rot == 0, SCREEN.rot)
check("shield goes away", (function() run_scheduled(1); return #UIManager.shown == 0 end)())
check("rotation never broadcast SetRotationMode to FileManager / the reader", (function()
    for _, ev in ipairs(UIManager.broadcasts) do if ev.handler == "onSetRotationMode" then return false end end
    return true
end)())
check("preventScreenSaver back to what KOReader had", fake_powerd.props.preventScreenSaver == "1", fake_powerd.props.preventScreenSaver)

-- pixel identity on the KT3 (spec 6.1): every step's draws hash to the baseline recorded before the scaling work
do
    local out = os.getenv("SMOKE_TRACE_OUT")
    if out then
        local fh = assert(io.open(out, "w"))
        fh:write(table.concat(hashes, "\n"), "\n"); fh:close()
    end
    if BASE_W == 600 and BASE_H == 800 and not out and not LINEAR and not TEXT_LARGE then
        local fh = io.open(TA.baseline)
        check("KT3 baseline file present", fh ~= nil)
        if fh then
            local want = {}
            for l in fh:lines() do want[#want + 1] = l end
            fh:close()
            check("KT3 baseline: same number of steps", #want == #hashes, #want .. " vs " .. #hashes)
            for i, l in ipairs(hashes) do
                check("KT3 pixel identity: " .. l:match("^%d+ (.*) %x+$"), want[i] == l, want[i])
            end
        end
    end
end

os.execute('rm -rf "' .. DATA_DIR .. '"')
print(("tinta ui smoke: %d passed, %d failed"):format(passed, failed))
if failed > 0 then os.exit(1) end
