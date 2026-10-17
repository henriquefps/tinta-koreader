-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (C) 2026 Tinta contributors
local T = ...
local Registry = require("core/registry")
local Store = require("core/store")
local Notify = require("core/notify")
local Settings = require("core/settings")
local eq, same, check = T.eq, T.same, T.check

local NONE = {}   -- removes a field from the manifest
local function app(id, over)
    local m = { id = id, name = id:upper(), sizes = { "2x2", "1x1" }, defaults = { interval = 60 },
        widget = function(ctx, size, box) return { kind = "widget", app = id, size = size, w = box and box.w } end,
        refresh = function(ctx, done) done(true) end }
    for k, v in pairs(over or {}) do if v == NONE then m[k] = nil else m[k] = v end end
    return m
end

-- validation
check("validate: ok", Registry.validate(app("alfa")))
local function bad(name, m, why)
    local ok, err = Registry.validate(m)
    check("validate: " .. name, not ok and err == why, err)
end
bad("not a table", 42, "manifest is not a table")
bad("bad id", app("Alfa!"), "bad id")
bad("no name", app("a", { name = "" }), "bad name")
bad("no sizes", app("a", { sizes = {} }), "no sizes")
bad("bad size", app("a", { sizes = { "3x3" } }), "bad size 3x3")
bad("no widget", app("a", { widget = false }), "no widget()")
bad("refresh not fn", app("a", { refresh = "x" }), "refresh is not a function")
check("validate: refresh optional (no refresh app)", Registry.validate(app("sistema", { refresh = NONE })))

local clock = T.clock(1000)
local log = T.logger()
local reg = Registry.new({ now = clock, log = log.fn })
check("register: ok", reg:register(app("alfa")))
local ok, err = reg:register(app("alfa"))
check("register: duplicate rejected", not ok and err == "duplicate id")
check("register: bad manifest logged, not thrown", not reg:register({ id = "x" }) and log.find("rejected manifest"))
reg:register(app("beta"))
same("ids in registration order", reg:ids(), { "alfa", "beta" })
eq("get", reg:get("beta").name, "BETA")
eq("list", #reg:list(), 2)

-- R-E1 protected calls
local boom = app("boom", {
    init = function() error("init exploded") end,
    widget = function() error("widget exploded") end,
    refresh = function() error("refresh exploded") end,
    attention = function() error("attention exploded") end,
    on_route = function() error("route exploded") end,
    screens = { main = function() error("screen exploded") end, ok = function(ctx, args) return "screen:" .. tostring(args) end },
})
reg:register(boom)
local ok1, e1 = reg:call("boom", "init", {})
check("call: error returns false", ok1 == false and e1:find("init exploded"), e1)
local line = log.find("init exploded")
check("call: error logged with app and function (R-E3)", line and line.app == "boom" and line.msg:find("^init: "), line and line.msg)
check("call: log has first traceback frame (R-E3)", line and line.msg:find("test_registry.lua:%d+"), line and line.msg)
local ok2, v2 = reg:call("alfa", "widget", {}, "2x2", { w = 100 })
check("call: success returns results", ok2 and v2.app == "alfa" and v2.w == 100)
same("call: missing function", { reg:call("alfa", "on_route", {}) }, { false, "missing" })
same("call: unknown app", { reg:call("nope", "init") }, { false, "unknown app" })
same("call: dotted path", { reg:call("boom", "screens.ok", {}, 7) }, { true, "screen:7" })
check("call: on_route error isolated", not reg:call("boom", "on_route", {}, { "x" }))
check("has: yes", reg:has("boom", "screens.main"))
check("has: no", not reg:has("alfa", "screens.main"))
local nlog = #log.lines
reg:call("alfa", "on_route")
eq("call: missing does not log", #log.lines, nlog)

-- callbacks the app hands over
local cb = reg:wrap("boom", function(x) if x then error("cb exploded") end return "fine" end, "confirm")
eq("wrap: passes through", cb(false), "fine")
eq("wrap: error -> nil, no throw", cb(true), nil)
check("wrap: error logged with label", log.find("^confirm: .*cb exploded"))
same("call_fn: not a function", { reg:call_fn("boom", nil) }, { false, "missing" })

-- R-E2 widget and screen fallback
local fb = function(m, size, box, e) return { kind = "fallback", name = m.name, size = size, err = e } end
local w, good = reg:widget("boom", {}, "2x2", { w = 10 }, fb)
check("widget: fallback on error", not good and w.kind == "fallback" and w.size == "2x2" and w.err:find("widget exploded"))
local w2, good2 = reg:widget("alfa", {}, "1x1", { w = 10 }, fb)
check("widget: normal", good2 and w2.kind == "widget" and w2.size == "1x1")
reg:register(app("nilw", { widget = function() return nil end }))
local w3 = reg:widget("nilw", {}, "2x2", {}, fb)
eq("widget: nil result -> fallback", w3.kind, "fallback")
eq("error_text", reg:error_text("boom"), "BOOM · erro na app")
local sfb = function(m, name, e) return { kind = "error_screen", name = name, err = e } end
local s1, sg = reg:screen("boom", "main", {}, nil, sfb)
check("screen: fallback on error", not sg and s1.kind == "error_screen" and s1.err:find("screen exploded"))
local s2 = reg:screen("alfa", "main", {}, nil, sfb)
check("screen: missing -> fallback", s2.kind == "error_screen" and s2.err == "missing")
eq("screen: ok", reg:screen("boom", "ok", {}, "a", sfb), "screen:a")
check("attention: error -> false", reg:attention("boom", {}) == false)
reg:register(app("att", { attention = function() return 1 end }))
check("attention: truthy -> true", reg:attention("att", {}) == true)
check("attention: missing -> false", reg:attention("alfa", {}) == false)

-- refresh lifecycle, state, R-E4, R-U8
clock.set(2000)
local results = {}
local on_done = function(id, ok, e, kind) results[#results + 1] = id .. ":" .. tostring(ok) .. ":" .. kind end
check("refresh: started", reg:refresh("alfa", {}, { on_done = on_done }))
local st = reg:state("alfa")
eq("refresh: last_ok set", st.last_ok, 2000)
eq("refresh: not busy after sync done", st.busy, false)
same("refresh: on_done called", results, { "alfa:true:done" })

-- async refresh with network failure
local pending_done
reg:register(app("net", { net = true, refresh = function(ctx, done) pending_done = done end }))
check("refresh async: started", reg:refresh("net", {}, { on_done = on_done }))
eq("refresh async: busy", reg:state("net").busy, true)
same("refresh async: second request queued (R-U8)", { reg:refresh("net", {}, { manual = true }) }, { false, "busy" })
clock.set(2010)
local first_done = pending_done
first_done(false, "timeout")
eq("network failure: last_err", reg:state("net").last_err, 2010)
eq("network failure: err_text", reg:state("net").err_text, "timeout")
eq("network failure: fail_streak", reg:state("net").fail_streak, 1)
eq("network failure: exc_streak untouched", reg:state("net").exc_streak, 0)
eq("queued refresh ran after done", reg:state("net").busy, true)
first_done(true)
eq("stale done ignored", reg:state("net").last_ok, nil)
pending_done(true)
eq("queued run ok", reg:state("net").last_ok, 2010)
eq("ok resets fail_streak", reg:state("net").fail_streak, 0)
eq("not busy", reg:state("net").busy, false)
pending_done(false, "late twice")
eq("done twice ignored", reg:state("net").fail_streak, 0)

-- busy timeout
check("refresh: start hung run", reg:refresh("net", {}))
clock.add(Registry.BUSY_TIMEOUT - 1)
same("busy within timeout -> queued", { reg:refresh("net", {}) }, { false, "busy" })
reg:state("net").pending = nil
clock.add(2)
check("busy past timeout -> restarts", reg:refresh("net", {}))
eq("timeout counted as failure", reg:state("net").err_text, "timeout")
check("timeout logged", log.find("refresh timed out"))

-- R-E4: three exceptions in a row disable auto refresh until manual
results = {}
for i = 1, 3 do reg:refresh("boom", {}, { on_done = on_done }) end
same("exceptions reported", results, { "boom:false:exception", "boom:false:exception", "boom:false:exception" })
eq("R-E4: disabled after 3", reg:state("boom").disabled, true)
eq("R-E4: err_text", reg:state("boom").err_text, "erro na app")
check("R-E4: logged", log.find("auto refresh off"))
same("R-E4: auto refresh refused", { reg:refresh("boom", {}) }, { false, "disabled" })
check("R-E4: manual runs and clears lock", reg:refresh("boom", {}, { manual = true }))
eq("R-E4: exc_streak restarted by manual", reg:state("boom").exc_streak, 1)
eq("R-E4: enabled again", reg:state("boom").disabled, false)
-- network failures between exceptions break the streak
local mode = "throw"
reg:register(app("mix", { refresh = function(ctx, done) if mode == "throw" then error("x") else done(false, "net") end end }))
reg:refresh("mix", {}); reg:refresh("mix", {})
mode = "net"; reg:refresh("mix", {})
mode = "throw"; reg:refresh("mix", {}); reg:refresh("mix", {})
eq("R-E4: only consecutive exceptions count", reg:state("mix").disabled, false)
reg:refresh("mix", {})
eq("R-E4: third in a row disables", reg:state("mix").disabled, true)
-- no refresh
reg:register(app("sistema", { refresh = NONE, defaults = {} }))
same("refresh: app without refresh", { reg:refresh("sistema", {}) }, { false, "no_refresh" })
same("refresh: unknown", { reg:refresh("zz", {}) }, { false, "unknown" })
-- error in on_done does not break the registry
check("refresh: on_done error isolated", reg:refresh("alfa", {}, { on_done = function() error("ui bug") end }) and log.find("on_done: .*ui bug"))

-- state persisted in the store, reloaded on register
local store = Store.memory()
local reg2 = Registry.new({ now = T.clock(5000), store = store })
reg2:register(app("alfa"))
reg2:refresh("alfa", {})
eq("persist: saved", store:state_get("alfa").last_ok, 5000)
local reg3 = Registry.new({ now = T.clock(6000), store = store })
reg3:register(app("alfa"))
eq("persist: reloaded", reg3:state("alfa").last_ok, 5000)

-- arm the notification center after the first good reading
local center = Notify.new({ store = store, now = T.clock(7000) })
local reg4 = Registry.new({ now = T.clock(7000), notify = center })
local fail_first = true
reg4:register(app("alfa", { refresh = function(ctx, done) done(not fail_first) end }))
reg4:refresh("alfa", {})
check("arm: not armed after a failed reading", not center:is_armed("alfa"))
fail_first = false
reg4:refresh("alfa", {})
check("arm: armed after the first good reading", center:is_armed("alfa"))

-- scheduler entries
local sstore = Store.memory()
local settings = Settings.new({ store = sstore })
local reg5 = Registry.new({ now = T.clock(100) })
local alfa = app("alfa", { net = true, defaults = { interval = 60 } })
local beta = app("beta", { net = true, defaults = { interval = 1800, window = { from = "07:30", to = "18:30", weekdays = true } },
    in_window = function(ctx, t) return ctx.workday end })
local notif = app("notificacoes", { refresh = NONE, defaults = {} })
for _, m in ipairs({ alfa, beta, notif }) do reg5:register(m); settings:register_app(m) end
local es = reg5:sched_entries(nil, settings)
eq("entries: count", #es, 3)
same("entries: alfa", { es[1].id, es[1].interval, es[1].net }, { "alfa", 60, true })
eq("entries: no refresh -> interval nil", es[3].interval, nil)
eq("entries: window from settings", es[2].window.from, "07:30")
reg5:set_ctx("beta", { workday = false })
check("entries: app in_window used (R-U2)", es[2].window.in_window(0) == false)
reg5:set_ctx("beta", { workday = true })
check("entries: app in_window true", es[2].window.in_window(0) == true)
settings:set_interval("alfa", 300)
eq("entries: interval from settings", reg5:sched_entry("alfa", settings).interval, 300)
reg5:register(app("brk", { in_window = function() error("bad window") end }))
check("entries: in_window error = inside", reg5:sched_entry("brk", settings).window.in_window(0) == true)

-- R-D2 versions
local vstore = Store.memory()
local reg6 = Registry.new({ now = T.clock(1), store = vstore })
reg6:register(app("alfa", { version = 1 }))
eq("version: first time", reg6:check_version("alfa", {}), "new")
eq("version: same", reg6:check_version("alfa", {}), "same")
vstore:cache_put("alfa", { a = 1 }, 1, 1)
local reg7 = Registry.new({ store = vstore })
reg7:register(app("alfa", { version = 2 }))
eq("version: no migrate -> cache cleared", reg7:check_version("alfa", {}), "cache_cleared")
eq("version: cache gone", vstore:cache_get("alfa"), nil)
eq("version: stored", vstore:meta_get("app_version:alfa"), "2")
local migrated
local reg8 = Registry.new({ store = vstore })
reg8:register(app("alfa", { version = 3, migrate = function(ctx, from, to) migrated = from .. "->" .. to end }))
vstore:cache_put("alfa", { a = 1 }, 1, 2)
eq("version: migrate called", reg8:check_version("alfa", {}), "migrated")
eq("version: migrate args", migrated, "2->3")
check("version: cache kept after migrate", vstore:cache_get("alfa") ~= nil)
local reg9 = Registry.new({ store = vstore, log = function() end })
reg9:register(app("alfa", { version = 4, migrate = function() error("bad migration") end }))
eq("version: failing migrate -> cache cleared", reg9:check_version("alfa", {}), "cache_cleared")

-- make_ctx (5.2)
local cstore = Store.memory()
local csettings = Settings.new({ store = cstore })
local cclock = T.clock(4242)
local ccenter = Notify.new({ store = cstore, now = cclock, first_read_gate = false })
local creg = Registry.new({ now = cclock, store = cstore })
local cm = app("alfa", { version = 2, strings = { pt = { hi = "oi" }, en = { hi = "hi" } },
    settings = { { key = "server_url", type = "url", default = "http://192.0.2.101:4747" } } })
creg:register(cm); csettings:register_app(cm)
local logs = T.logger()
local ctx = Registry.make_ctx("alfa", { registry = creg, store = cstore, settings = csettings, notify = ccenter, now = cclock, log = logs.fn })
eq("ctx: now", ctx.now(), 4242)
eq("ctx: settings default", ctx.settings:get("server_url"), "http://192.0.2.101:4747")
check("ctx: settings set validates", ctx.settings:set("server_url", "http://192.0.2.2:4747/") and ctx.settings:get("server_url") == "http://192.0.2.2:4747")
check("ctx: settings set rejects", not ctx.settings:set("server_url", "nope"))
ctx.data:set("seen", { 1, 2 })
same("ctx: data", ctx.data:get("seen"), { 1, 2 })
ctx.cache:put({ total = 3 })
local cv, cat, cver = ctx.cache:get()
same("ctx: cache value", cv, { total = 3 })
eq("ctx: cache fetched_at", cat, 4242)
eq("ctx: cache version", cver, 2)
check("ctx: notify bound to app", ctx.notify({ key = "k1", title = "t" }) and ccenter:list()[1].app == "alfa")
eq("ctx: i18n", ctx.i18n.t("hi"), "oi")
ctx.log("hello")
check("ctx: log tagged with app", logs.lines[1].app == "alfa" and logs.lines[1].msg == "hello")
check("ctx: state is the registry state", ctx.state == creg:state("alfa"))
check("ctx: registered in registry", creg:ctx("alfa") == ctx)

-- ctx.cache keeps the decoded value in memory (a SQLite query + JSON decode per read is slow on the Kindle)
do
    local reads = 0
    local orig = cstore.cache_get
    cstore.cache_get = function(s, id) reads = reads + 1; return orig(s, id) end
    ctx.cache.reset()
    for _ = 1, 50 do ctx.cache:get() end
    eq("ctx: cache read from the store once", reads, 1)
    ctx.cache:put({ total = 4 })
    same("ctx: cache put updates the memory copy", (ctx.cache:get()), { total = 4 })
    eq("ctx: cache put needs no store read", reads, 1)
    ctx.cache.reset()
    same("ctx: cache after reset reads the store", (ctx.cache:get()), { total = 4 })
    eq("ctx: cache reset forces one read", reads, 2)
    cstore.cache_get = orig
end
