-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (C) 2026 Tinta contributors
-- Tinta: the main window. Screen stack (R-N5), status bar, navigation bar or handle (R-N2), gestures (R-N3),
-- overlays (banner, menu sheet, dialog, toast) and e-ink refresh (R-R1, R-R2).
--
-- One full-screen InputContainer takes every gesture and hit-tests the tap targets registered by the build
-- (ui/draw Box with on_tap / on_hold); the last registered (overlays) wins. Every callback runs protected:
-- a failing app callback is logged and shown as a toast, the Tinta stays open (R-E1).
--
-- Routes: { kind = "home", page }, { kind = "app", app, screen, args, page }, { kind = "organizer", mode, sel },
--         { kind = "launcher", page }, { kind = "wizard", step, sel }, { kind = "error", title, text }.
local Device = require("device")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local InputContainer = require("ui/widget/container/inputcontainer")
local UIManager = require("ui/uimanager")
local Screen = Device.screen

local AppHeader = require("ui/appheader")
local Banner = require("ui/banner")
local Dialog = require("ui/dialog")
local Draw = require("ui/draw")
local G = require("ui/geom")
local Gestures = require("ui/gestures")
local NavBar = require("ui/navbar")
local Picker = require("ui/picker")
local PickLogic = require("ui/picklogic")
local S = require("ui/strings")
local Sheet = require("ui/sheet")
local StatusBar = require("ui/statusbar")
local T = require("ui/theme")
local Toast = require("ui/toast")

local Window = InputContainer:extend{
    host = nil,          -- ui/host (services and actions)
    covers_fullscreen = true,
}

function Window:init()
    self:updateDimen()
    self.stack = { { kind = "home", page = 0 } }
    self.menu_open = false
    self.dialog = nil      -- { title, text, ok_label, on_ok }
    self.picker = nil      -- choice popup: see Window:pick
    self.renders = 0
    self.toast_text = nil
    self.banner = nil      -- { head, title, on_tap }
    self.hot = {}
    self.partials = 0
    local range = function() return self.dimen end
    self.ges_events = {
        TintaTap = { GestureRange:new{ ges = "tap", range = range } },
        TintaHold = { GestureRange:new{ ges = "hold", range = range } },
        TintaHoldPan = { GestureRange:new{ ges = "hold_pan", range = range } },
        TintaHoldRelease = { GestureRange:new{ ges = "hold_release", range = range } },
        TintaSwipe = { GestureRange:new{ ges = "swipe", range = range } },
    }
    if Device:hasKeys() then
        self.key_events = { TintaBack = { { Device.input.group.Back } } }
    end
end

function Window:updateDimen()
    self.dimen = Geom:new{ x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight() }
end

function Window:current() return self.stack[#self.stack] end
function Window:isHome() return self:current().kind == "home" end

-- app id that owns the current screen (nil on home)
function Window:currentApp()
    local r = self:current()
    if r.kind == "app" or r.kind == "error" then return r.app end
    if r.kind == "organizer" then return "sistema" end
    return nil
end

function Window:regions()
    local host = self.host
    return G.regions(self.dimen.w, self.dimen.h, host:get("nav"), host:isSleeping())
end

---------------------------------------------------------------- protected callbacks (R-E1)

function Window:protect(fn, owner)
    if not fn then return nil end
    return function(...)
        local who = owner or self:currentApp()
        local ok = self.host:callAppFn(who, fn, "callback", ...)
        if not ok and not self.closed then
            self:showToast(S.t("toast_app_error", (who and self.host:appName(who)) or "Tinta"))
        end
    end
end

---------------------------------------------------------------- build and refresh

-- Builds the whole screen into self[1]. mode: "full" (screen change, R-R1) or "partial" (same screen, R-R2:
-- a full one every FULL_EVERY partials).
function Window:render(mode)
    if self.closed then return end
    self.renders = self.renders + 1
    -- 7.5: however the wizard was left (its buttons, the navigation bar, the back gesture) it is done for good
    if self.host.first_run and not self:inWizard() then self.host:finishFirstRun() end
    self:updateDimen()
    local regions = self:regions()
    local W, H = regions.W, regions.H
    self.ox, self.oy, self.box_w, self.box_h = regions.ox, regions.oy, W, H   -- the content box inside the screen (6.1)
    local hot = Draw.begin_hot()
    local layers = Draw.Layers:new{ w = W, h = H }
    layers[#layers + 1] = { widget = Draw.Fill:new{ w = W, h = H, color = Draw.WHITE }, x = 0, y = 0 }

    local ok_build, err = xpcall(function()
        layers[#layers + 1] = { widget = StatusBar.new(W, self.host:statusInfo(), self:statusCallbacks()), x = 0, y = 0 }
        local content = self:buildContent(regions)
        layers[#layers + 1] = { widget = content, x = regions.content.x, y = regions.content.y }
        if regions.nav then
            layers[#layers + 1] = { widget = NavBar.new(W, self:navState(), self:navCallbacks()), x = 0, y = regions.nav.y }
        elseif regions.handle then
            layers[#layers + 1] = { widget = NavBar.handle(), x = regions.handle.x, y = regions.handle.y }
        end
        self:addOverlays(layers, regions)
    end, debug.traceback)
    if not ok_build then
        -- a core or UI bug while building: show it instead of crashing KOReader
        self.host:logError(nil, "render", err)
        for i = #layers, 2, -1 do layers[i] = nil end
        layers[2] = { widget = Draw.box{ w = W - 2 * T.MARGIN, h = H - 2 * T.MARGIN, pad_x = T.px(8), pad_y = T.px(8),
            child = Draw.textbox("Tinta: " .. tostring(err):match("[^\n]*"), T.FONT_BODY, W - T.px(40)) }, x = T.MARGIN, y = T.MARGIN }
        layers[3] = { widget = Draw.box{ w = W, h = H, on_tap = function() self.host:close() end }, x = 0, y = 0 }
    end
    Draw.end_hot()

    local old = self[1]
    self[1] = layers
    self.hot = hot
    if old and old.free then old:free() end

    local refresh = "full"
    if mode == "partial" then
        self.partials = self.partials + 1
        if self.partials % self.host:fullEvery() ~= 0 then refresh = "partial" end
    else
        self.partials = 0
    end
    UIManager:setDirty(self, function() return refresh, self.dimen end)
end

-- The Tinta is laid out in the content box (3:4, spec 6.1) at the scale of ui/theme: paints it at (ox, oy) and the
-- white letterbox around it (nothing extra when the box is the whole screen, the KT3).
function Window:paintTo(bb, x, y)
    self.dimen.x, self.dimen.y = x, y
    if not self[1] then return end
    local ox, oy, bw, bh = self.ox or 0, self.oy or 0, self.box_w or self.dimen.w, self.box_h or self.dimen.h
    local sw, sh = self.dimen.w, self.dimen.h
    if ox > 0 then bb:paintRect(x, y, ox, sh, Draw.WHITE) end
    if sw - ox - bw > 0 then bb:paintRect(x + ox + bw, y, sw - ox - bw, sh, Draw.WHITE) end
    if oy > 0 then bb:paintRect(x + ox, y, bw, oy, Draw.WHITE) end
    if sh - oy - bh > 0 then bb:paintRect(x + ox, y + oy + bh, bw, sh - oy - bh, Draw.WHITE) end
    self[1]:paintTo(bb, x + ox, y + oy)
end

function Window:buildContent(regions)
    local r = self:current()
    if self.host:isSleeping() then
        return require("ui/sleepscreen").build(self, regions)
    end
    if r.kind == "home" then
        return require("ui/home").build(self, regions)
    elseif r.kind == "organizer" then
        return require("ui/organizer").build(self, regions, r)
    elseif r.kind == "launcher" then
        return require("ui/launcher").build(self, regions, r)
    elseif r.kind == "wizard" then
        return require("ui/wizard").build(self, regions, r)
    elseif r.kind == "app" then
        return self:buildAppScreen(regions, r)
    end
    return self:buildError(regions, r.title or S.t("screen_error_title"), r.text or "")
end

-- header + body inside the content margins
function Window:frameScreen(regions, title, meta, emphasis, body)
    local inner = regions.inner
    local header = AppHeader.new(inner.w, title, meta, emphasis)
    return Draw.box{ w = regions.content.w, h = regions.content.h, pad_x = T.MARGIN, pad_y = T.MARGIN,
        child = Draw.vstack({ header, body }, T.GAP) }
end

-- box under the app header for screen bodies
function Window:bodyBox(regions)
    local inner = regions.inner
    return { w = inner.w, h = inner.h - T.HEADER_H - T.GAP, landscape = regions.W > regions.H }
end

function Window:buildAppScreen(regions, r)
    local host = self.host
    local box = self:bodyBox(regions)
    self.building_route = r
    local ok, res = host:callScreen(r.app, r.screen, r.args, box)
    self.building_route = nil
    if not ok then
        return self:buildError(regions, S.t("screen_error_title"),
            S.t("screen_error_text", r.screen or "main", host:appName(r.app) or r.app))
    end
    local body, title, meta, emphasis = res, nil, nil, nil
    if type(res) == "table" and not res.paintTo then
        body, title, meta, emphasis = res.body, res.title, res.meta, res.emphasis
        if res.no_header then
            return Draw.box{ w = regions.content.w, h = regions.content.h, pad_x = T.MARGIN, pad_y = T.MARGIN, child = body }
        end
    end
    if not title then title = host:appName(r.app) end
    if meta == nil then meta, emphasis = host:headerText(r.app) end
    if type(body) ~= "table" or not body.paintTo then body = Draw.space(box.w, box.h) end
    return self:frameScreen(regions, title, meta, emphasis, Draw.box{ w = box.w, h = box.h, child = body })
end

function Window:buildError(regions, title, text)
    local box = self:bodyBox(regions)
    local Button = require("ui/button")
    local body = Draw.vstack({
        Draw.textbox(text, T.FONT_BODY, box.w, box.h - T.BTN_H - T.GAP),
        Button.new{ label = S.t("btn_back"), w = Button.width_for(S.t("btn_back")), on_tap = function() self:back() end },
    }, T.GAP)
    return self:frameScreen(regions, title, "", nil, body)
end

---------------------------------------------------------------- status bar, navigation bar

function Window:statusCallbacks()
    local host = self.host
    if host:isSleeping() then return {} end
    return {
        clock = function() self:closeOverlays(); host:refreshCurrent() end,
        bell = function() self:openCentral() end,
        wifi = function() self:openCentral() end,
        battery = function() self:openApp("bateria") end,
    }
end

function Window:navState()
    return {
        home_enabled = not self:isHome() or (self:current().page or 0) > 0 or self.menu_open,
        back_enabled = #self.stack > 1 or self.menu_open or self.dialog ~= nil or self.picker ~= nil,
    }
end

function Window:navCallbacks()
    return {
        home = function() self:goHome() end,
        back = function() self:back() end,
        refresh = function() self:closeOverlays(); self.host:refreshCurrent() end,
        menu = function() if self.menu_open then self:closeOverlays() else self:openMenu() end end,
    }
end

---------------------------------------------------------------- overlays

function Window:addOverlays(layers, regions)
    local level = 0
    local function add(list) for _, l in ipairs(list) do layers[#layers + 1] = l end end
    local function next_layer() level = level + 1; Draw.set_layer(level) end
    if self.banner and not self.menu_open and not self.dialog and not self.picker then
        next_layer()
        add(Banner.layers(regions, self.banner, self:protect(self.banner.on_tap)))
    end
    if self.menu_open then
        local title, items = self.host:menuItems(self)
        next_layer()
        add(Sheet.layers(regions, title, items, function() self:closeOverlays() end))
    end
    if self.dialog then
        local d = self.dialog
        next_layer()
        add(Dialog.layers(regions, {
            title = d.title, text = d.text, ok_label = d.ok_label,
            on_cancel = function() self.dialog = nil; self:render("partial") end,
            on_ok = function()
                self.dialog = nil
                self:render("partial")
                if d.on_ok then self:protect(d.on_ok, d.owner)() end
            end,
        }))
    end
    if self.picker then
        local p = self.picker
        next_layer()
        local options = PickLogic.normalize(type(p.options) == "function" and p.options() or p.options)
        local layers_, page = Picker.layers(regions, {
            title = p.title, options = options, current = p.current, page = p.page,
            footer = p.done_label, empty = p.empty,
        }, {
            on_pick = function(opt) self:pickChosen(opt) end,
            on_cancel = function() self:closePicker() end,
            on_page = function(d) p.page = (p.page or 0) + d; self:render("partial") end,
            on_footer = function() self:closePicker() end,
        })
        p.page = page
        add(layers_)
    end
    if self.toast_text then add(Toast.layers(regions, self.toast_text)) end
    Draw.set_layer(0)
end

function Window:openMenu()
    self.menu_open = true
    self.dialog, self.picker = nil, nil
    self:render("partial")
end

-- closes the menu, the dialog and the popup; returns true when there was something to close
function Window:closeOverlays(no_render)
    local had = self.menu_open or self.dialog ~= nil or self.picker ~= nil
    self.menu_open, self.dialog, self.picker = false, nil, nil
    if had and not no_render then self:render("partial") end
    return had
end

-- d = { title, text, ok_label, on_ok, owner }
function Window:confirm(d)
    self.menu_open = false
    self.picker = nil
    self.dialog = d
    self:render("partial")
end

-- Choice popup (6.10). d = { title, options, current, on_pick(value), owner?, keep_open?, done_label?, empty? }
-- options: values or { value, label?, sub? } (see ui/picklogic), or a function returning them (read at every build,
-- for popups that stay open and change under the user's finger). A tap on an option runs on_pick(value) and closes
-- the popup, unless keep_open (then `done_label` closes it); tapping outside, Voltar and the back gesture cancel.
function Window:pick(d)
    if not d or type(d.on_pick) ~= "function" then return end
    if type(d.options) ~= "function" and #PickLogic.normalize(d.options) == 0 then return end
    self.menu_open, self.dialog = false, nil
    self.picker = { title = d.title, options = d.options, current = d.current, on_pick = d.on_pick, owner = d.owner,
        keep_open = d.keep_open, done_label = d.done_label, empty = d.empty }
    self:render("partial")
end

function Window:closePicker()
    if not self.picker then return end
    self.picker = nil
    self:render("partial")
end

-- an option was tapped: save through the caller's callback (protected), then close or refresh the popup
function Window:pickChosen(opt)
    local p = self.picker
    if not p then return end
    if not p.keep_open then self.picker = nil end
    local before = self.renders
    self:protect(p.on_pick, p.owner)(opt.value)
    if self.renders == before and not self.closed then self:render("partial") end
end

-- Named showToast, never "toast": UIManager treats any window with a truthy .toast field as a toast and keeps it
-- above every widget shown later, so InputDialog, the keyboard and other KOReader dialogs ended up under the
-- Tinta, unpainted, and taps on their invisible buttons crashed KOReader (docs/investigacao-crash-sino.md).
function Window:showToast(text)
    self.toast_text = text
    if self.toast_cb then UIManager:unschedule(self.toast_cb) end
    self.toast_cb = function()
        self.toast_cb = nil
        self.toast_text = nil
        self:render("partial")
    end
    UIManager:scheduleIn(T.TOAST_MS / 1000, self.toast_cb)
    self:render("partial")
end

-- b = { head, title, on_tap }
function Window:showBanner(b)
    self.banner = b
    if self.banner_cb then UIManager:unschedule(self.banner_cb) end
    self.banner_cb = function()
        self.banner_cb = nil
        self.banner = nil
        self:render("partial")
    end
    UIManager:scheduleIn(T.BANNER_MS / 1000, self.banner_cb)
    self:render("partial")
end

function Window:clearBanner()
    if self.banner_cb then UIManager:unschedule(self.banner_cb); self.banner_cb = nil end
    self.banner = nil
end

---------------------------------------------------------------- navigation (R-N1, R-N5)

function Window:push(route)
    self:closeOverlays(true)
    route.page = route.page or 0
    self.stack[#self.stack + 1] = route
    self:render("full")
end

-- replaces the stack by home -> routes... (opening a notification, R-N5)
function Window:resetTo(routes)
    self:closeOverlays(true)
    self:clearBanner()
    self.stack = { self.stack[1] }
    for _, r in ipairs(routes or {}) do
        r.page = r.page or 0
        self.stack[#self.stack + 1] = r
    end
    self:render("full")
end

-- Back: closes the menu or dialog first, then pops (R-N3)
function Window:back()
    if self:closeOverlays() then return end
    if #self.stack > 1 then
        self.stack[#self.stack] = nil
        self:render("full")
    end
end

-- Home: clears the stack; on home, goes back to the first page (R-N1)
function Window:goHome()
    local had = self:closeOverlays(true)
    if #self.stack > 1 then
        self.stack = { self.stack[1] }
        self:render("full")
    elseif (self.stack[1].page or 0) > 0 then
        self.stack[1].page = 0
        self:render("full")
    elseif had then
        self:render("partial")
    end
end

function Window:openApp(id, screen, args)
    if not self.host:app(id) then return self:showToast(S.t("app_missing", id)) end
    local r = self:current()
    if r.kind == "app" and r.app == id and (r.screen or "main") == (screen or "main") and not args then
        return self:closeOverlays()
    end
    self:push{ kind = "app", app = id, screen = screen or "main", args = args }
end

-- 7.5: first-run wizard over Home (the host asks once, right after opening on a fresh install)
function Window:startWizard() self.stack[#self.stack + 1] = require("ui/wizard").start(self) end
function Window:inWizard()
    for _, r in ipairs(self.stack) do if r.kind == "wizard" then return true end end
    return false
end

function Window:openCentral() self:openApp("notificacoes") end

-- Menu → Apps (6.5): the list of every app; already there, it only closes the menu
function Window:openLauncher()
    if self:current().kind == "launcher" then return self:closeOverlays() end
    self:push{ kind = "launcher" }
end

function Window:openOrganizer(mode, sel)
    local r = self:current()
    if r.kind == "organizer" then
        r.mode, r.sel = mode or r.mode, sel or r.sel
        self:closeOverlays(true)
        return self:render("partial")
    end
    self:push{ kind = "organizer", mode = mode or "home", sel = sel }
end

-- page change of the current route (lists, home): full refresh (R-R1)
function Window:setPage(page)
    local r = self:current()
    r.page = page
    self:render("full")
end

---------------------------------------------------------------- gestures

-- Topmost painted box under (x, y): highest overlay layer, then the smallest box (the innermost). With
-- `field`, only boxes that have that callback count, and nothing is returned when a higher layer (a modal
-- backdrop) covers the point.
function Window:hitTest(x, y, field)
    local best
    for _, b in ipairs(self.hot) do
        if b.painted and G.inside(b.dimen, x, y) then
            if not best or b.layer > best.layer
                or (b.layer == best.layer and b.w * b.h < best.w * best.h) then
                best = b
            end
        end
    end
    if best and field and not best[field] then
        -- an inner box without the callback: look for the smallest box of the same layer that has it
        local alt
        for _, b in ipairs(self.hot) do
            if b.painted and b.layer == best.layer and b[field] and G.inside(b.dimen, x, y)
                and (not alt or b.w * b.h < alt.w * alt.h) then
                alt = b
            end
        end
        return alt
    end
    return best
end

function Window:onTintaTap(_, ges)
    if self.host:isSleeping() then return true end   -- R-P8
    self.host:touched()
    local pos = ges and ges.pos
    if not pos then return true end
    local b = self:hitTest(pos.x, pos.y, "on_tap")
    if b then self:protect(b.on_tap)() end
    return true
end

local function hold_interval_ms()
    local ok, v = pcall(function() return G_reader_settings:readSetting("ges_hold_interval_ms") end)
    return ok and tonumber(v) or 500
end

function Window:onTintaHold(_, ges)
    if self.host:isSleeping() or self.dialog or self.menu_open or self.picker then return true end
    self.host:touched()
    local pos = ges and ges.pos
    if not pos then return true end
    local b = self:hitTest(pos.x, pos.y, "on_hold")
    if not b then return true end
    self:cancelHold()
    self.hold = { x = pos.x, y = pos.y, box = b }
    self.hold_cb = function()
        self.hold_cb = nil
        local h = self.hold
        self.hold = nil
        if h then self:protect(h.box.on_hold)() end
    end
    UIManager:scheduleIn(Gestures.hold_delay_ms(hold_interval_ms()) / 1000, self.hold_cb)
    return true
end

function Window:cancelHold()
    if self.hold_cb then UIManager:unschedule(self.hold_cb); self.hold_cb = nil end
    self.hold = nil
end

function Window:onTintaHoldPan(_, ges)
    local h, pos = self.hold, ges and ges.pos
    if h and pos and Gestures.hold_moved(h.x, h.y, pos.x, pos.y) then self:cancelHold() end
    return true
end

function Window:onTintaHoldRelease()
    if self.hold then self:cancelHold() end
    return true
end

function Window:onTintaSwipe(_, ges)
    if self.host:isSleeping() then return true end
    self.host:touched()
    if not ges or not ges.pos then return true end
    -- the gesture zones are those of the content box; a swipe that starts in the letterbox starts at the box edge
    local ox, oy, bw, bh = self.ox or 0, self.oy or 0, self.box_w or self.dimen.w, self.box_h or self.dimen.h
    local ev = { x0 = math.max(0, math.min(bw - 1, ges.pos.x - ox)), y0 = math.max(0, math.min(bh - 1, ges.pos.y - oy)),
        direction = ges.direction, distance = ges.distance }
    if ges.end_pos then ev.x1, ev.y1 = ges.end_pos.x - ox, ges.end_pos.y - oy end
    local action = Gestures.classify(ev, { W = bw, H = bh,
        home = self:isHome() and not self.menu_open and not self.dialog and not self.picker })
    if action == "home" then self:goHome()
    elseif action == "back" then self:back()
    elseif action == "central" then self:closeOverlays(true); self:openCentral()
    elseif action == "page_next" or action == "page_prev" then
        require("ui/home").turn(self, action == "page_next" and 1 or -1)
    end
    return true
end

function Window:onTintaBack()
    if #self.stack > 1 or self.menu_open or self.dialog or self.picker then self:back() else self.host:close() end
    return true
end

---------------------------------------------------------------- lifecycle

function Window:onCloseWidget()
    self.closed = true
    self:cancelHold()
    if self.toast_cb then UIManager:unschedule(self.toast_cb); self.toast_cb = nil end
    self:clearBanner()
    if self[1] and self[1].free then self[1]:free() end
    self[1] = nil
    if self.host then self.host:onWindowClosed(self) end
end

return Window
