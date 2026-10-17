-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (C) 2026 Tinta contributors
local T = ...
local Notify = require("core/notify")
local Store = require("core/store")
local Settings = require("core/settings")
local Registry = require("core/registry")
local eq, same, check = T.eq, T.same, T.check

local function setup(o)
    o = o or {}
    local store = Store.memory()
    local settings = Settings.new({ store = store })
    local clock = T.clock(T.utc(2026, 10, 16, 13, 50))
    local log = T.logger()
    local banners = {}
    local c = Notify.new({ store = store, now = clock, log = log.fn,
        pref = function(app) return settings:notify_pref(app) end,
        on_new = function(n) banners[#banners + 1] = n end,
        first_read_gate = o.gate, max = o.max })
    return c, store, settings, clock, log, banners
end

local N = function(key, over)
    local n = { key = key, title = "projeto precisa de você", body = "claude pediu confirmação", prio = "alta",
        route = { "project", { id = "9f8e" } }, type = "attention" }
    for k, v in pairs(over or {}) do n[k] = v end
    return n
end

-- basic emit (8.1, R-T3)
local c, store, settings, clock, log, banners = setup({ gate = false })
local id = c:emit("alfa", N("attn:9f8e:1"))
check("emit: returns id", type(id) == "number")
local n = c:get(id)
same("emit: stored fields", { n.app, n.key, n.type, n.title, n.body, n.prio, n.created_at, n.read_at },
    { "alfa", "attn:9f8e:1", "attention", "projeto precisa de você", "claude pediu confirmação", "alta", clock(), nil })
same("emit: route stored", n.route, { "project", { id = "9f8e" } })
eq("emit: on_new called (banner R-T5)", #banners, 1)
eq("emit: banner gets id", banners[1].id, id)
check("emit: logged", log.find("notificação alta"))

-- R-T1 dedup by (app, key), read or not
same("dedup: same key", { c:emit("alfa", N("attn:9f8e:1", { title = "other" })) }, { nil, "dup" })
c:mark_read(id)
same("dedup: still dup after read", { c:emit("alfa", N("attn:9f8e:1")) }, { nil, "dup" })
check("dedup: other app same key ok", c:emit("beta", N("attn:9f8e:1")))
check("dedup: new key ok (event 'comes back')", c:emit("alfa", N("attn:9f8e:2")))
eq("dedup: banner not repeated", #banners, 3)

-- invalid
same("invalid: no key", { c:emit("alfa", { title = "x" }) }, { nil, "invalid" })
same("invalid: empty key", { c:emit("alfa", { key = "", title = "x" }) }, { nil, "invalid" })
same("invalid: no title", { c:emit("alfa", { key = "k" }) }, { nil, "invalid" })
same("invalid: not a table", { c:emit("alfa", "x") }, { nil, "invalid" })
local idp = c:emit("alfa", N("p1", { prio = "urgent" }))
eq("prio: unknown -> normal", c:get(idp).prio, "normal")
local idn = c:emit("alfa", N("p2", { prio = "normal" }))
eq("prio: normal kept", c:get(idn).prio, "normal")

-- R-T2 preferences
c, store, settings, clock, log, banners = setup({ gate = false })
settings:set_notify_pref("alfa", "normal")
local i1 = c:emit("alfa", N("a"))
eq("pref normal: alta lowered", c:get(i1).prio, "normal")
settings:set_notify_pref("alfa", "desligada")
same("pref off: dropped", { c:emit("alfa", N("b")) }, { nil, "off" })
check("pref off: logged", log.find("descartada"))
eq("pref off: not stored", store:notif_find("alfa", "b"), nil)
eq("pref off: no banner", #banners, 1)
settings:set_notify_pref("alfa", "alta")
local i3 = c:emit("alfa", N("b"))
eq("pref back on: later emit works (dropped key not recorded)", c:get(i3).prio, "alta")
eq("pref default alta for others", c:get(c:emit("beta", N("x"))).prio, "alta")

-- R-T6 unread, R-T10 mark all, clear
c, store, settings, clock = setup({ gate = false })
for i = 1, 5 do clock.add(60); c:emit("alfa", N("k" .. i, { title = "t" .. i })) end
eq("unread: count", c:unread_count(), 5)
c:mark_read(c:list()[1].id)
eq("unread: after mark", c:unread_count(), 4)
eq("mark_all_read", c:mark_all_read(), 4)
eq("unread: zero", c:unread_count(), 0)
eq("clear", c:clear(), 5)
eq("clear: empty", c:count(), 0)

-- R-T9 pages, newest first
for i = 1, 9 do clock.add(60); c:emit("alfa", N("k" .. i, { title = "t" .. i })) end
local items, page, pages = c:page(1, 4)
same("page: portrait 4/page", { #items, page, pages, items[1].title, items[4].title }, { 4, 1, 3, "t9", "t6" })
items, page, pages = c:page(3, 4)
same("page: last page", { #items, page, items[1].title }, { 1, 3, "t1" })
items, page, pages = c:page(9, 2)
same("page: landscape 2/page clamps", { #items, page, pages }, { 1, 5, 5 })

-- R-T4 limit 200: read ones go first
c, store, settings, clock = setup({ gate = false })
for i = 1, 200 do clock.add(1); c:emit("alfa", N("n" .. i)) end
eq("limit: 200 kept", c:count(), 200)
c:mark_read(store:notif_find("alfa", "n150").id)
clock.add(1); c:emit("alfa", N("n201"))
eq("limit: still 200", c:count(), 200)
eq("limit: oldest read dropped first", store:notif_find("alfa", "n150"), nil)
check("limit: oldest unread kept while a read one existed", store:notif_find("alfa", "n1") ~= nil)
clock.add(1); c:emit("alfa", N("n202"))
eq("limit: then oldest unread", store:notif_find("alfa", "n1"), nil)
check("limit: newest present", store:notif_find("alfa", "n202") ~= nil)
local cs = setup({ gate = false, max = 3 })
for i = 1, 5 do cs:emit("alfa", N("m" .. i)) end
eq("limit: custom max", cs:count(), 3)

-- 8.6 first reading after opening only records state
c, store, settings, clock, log, banners = setup()
check("gate: not armed at start", not c:is_armed("alfa"))
check("gate: sistema armed from start", c:is_armed("sistema"))
same("gate: first reading suppressed", { c:emit("alfa", N("late:2026-10-16:3")) }, { nil, "first_read" })
eq("gate: nothing stored", c:count(), 0)
eq("gate: no banner", #banners, 0)
c:arm("alfa")
same("gate: same event later is a dup (already known)", { c:emit("alfa", N("late:2026-10-16:3")) }, { nil, "dup" })
check("gate: new event after arm notifies", c:emit("alfa", N("done:2026-10-16")))
c:begin_session()
check("gate: new session disarms", not c:is_armed("alfa"))
same("gate: new session first reading suppressed again", { c:emit("alfa", N("new")) }, { nil, "first_read" })
local c0 = setup({ gate = false })
check("gate: can be turned off", c0:is_armed("alfa") and c0:emit("alfa", N("x")))
-- with the registry: the first successful refresh arms the app
do
    local store2 = Store.memory()
    local clock2 = T.clock(1000)
    local center = Notify.new({ store = store2, now = clock2 })
    local reg = Registry.new({ now = clock2, notify = center })
    local pending = { "late:1" }
    local m = { id = "beta", name = "Beta", sizes = { "2x2" }, widget = function() return {} end,
        refresh = function(ctx, done)
            for _, k in ipairs(pending) do ctx.notify({ key = k, title = k, prio = "alta" }) end
            done(true)
        end }
    reg:register(m)
    local ctx = Registry.make_ctx("beta", { registry = reg, store = store2, notify = center, now = clock2 })
    reg:refresh("beta", ctx)
    eq("gate+registry: first refresh does not notify", center:count(), 0)
    pending = { "late:1", "late:2" }
    reg:refresh("beta", ctx)
    eq("gate+registry: second refresh notifies only the new event", center:count(), 1)
    eq("gate+registry: it is late:2", center:list()[1].key, "late:2")
end

-- 8.4 open
c, store, settings, clock = setup({ gate = false })
local oid = c:emit("alfa", N("o1"))
same("open: target from route", c:open(oid), { id = oid, app = "alfa", screen = "project", args = { id = "9f8e" } })
check("open: marks read", c:get(oid).read_at ~= nil)
local oid2 = c:emit("beta", { key = "o2", title = "sem rota", prio = "alta" })
same("open: no route -> main", c:open(oid2), { id = oid2, app = "beta", screen = "main" })
local oid3 = c:emit("beta", N("o3", { route = "history" }))
eq("open: string route", c:open(oid3).screen, "history")
eq("open: unknown id", c:open(9999), nil)

-- R-T11 sleep summary
c, store, settings, clock = setup({ gate = false })
eq("sleep: nothing", c:sleep_summary("alta"), nil)
clock.add(1); c:emit("alfa", N("s1", { title = "alta antiga" }))
clock.add(1); c:emit("beta", N("s2", { title = "normal nova", prio = "normal" }))
local sm = c:sleep_summary("alta")
same("sleep: só alta", { sm.count, sm.latest.title, sm.text }, { 1, "alta antiga", "1 não lida: alta antiga" })
sm = c:sleep_summary("todas")
same("sleep: todas", { sm.count, sm.text }, { 2, "2 não lidas · normal nova" })
eq("sleep: nenhuma", c:sleep_summary("nenhuma"), nil)
eq("sleep: default is alta", c:sleep_summary().count, 1)
c:mark_all_read()
eq("sleep: read ones do not show", c:sleep_summary("todas"), nil)

-- banner lines (R-T5)
local l1, l2 = c.banner_lines({ app = "alfa", created_at = T.utc(2026, 10, 16, 13, 50), title = "T" }, "Alfa Monitor", T.date)
eq("banner: line 1", l1, "Alfa Monitor · 13:50")
eq("banner: line 2", l2, "T")

-- Sistema server rules (8.6)
c, store, settings, clock = setup({ gate = false })
local src = { id = "alfa", name = "alfa-server", host = "192.0.2.101:4747" }
eq("source: 1st failure no notification", c:source_result(src, false), nil)
eq("source: down_since = 1st failure", c:source_state("alfa").down_since, clock())
clock.add(60)
local did = c:source_result(src, false)
check("source: 2nd failure -> down", did ~= nil)
local dn = c:get(did)
same("source: down fields", { dn.app, dn.key, dn.prio, dn.title }, { "sistema", "down:alfa:" .. clock(), "alta", "alfa-server sem resposta" })
eq("source: down body", dn.body, "192.0.2.101:4747 não respondeu às 2 últimas atualizações")
same("source: down route to Conexões", dn.route, { "conn" })
clock.add(60)
eq("source: 3rd failure silent", c:source_result(src, false), nil)
eq("source: streak", c:source_state("alfa").fail_streak, 3)
clock.add(60)
local uid = c:source_result(src, true, 85)
local un = c:get(uid)
same("source: back -> up (normal)", { un.key, un.prio, un.title }, { "up:alfa:" .. clock(), "normal", "alfa-server voltou" })
same("source: state after up", { c:source_state("alfa").down, c:source_state("alfa").fail_streak, c:source_state("alfa").latency }, { false, 0, 85 })
eq("source: ok without previous down is silent", c:source_result(src, true), nil)
c:source_result(src, false)
eq("source: single failure then ok -> no up", c:source_result(src, true), nil)
eq("source: unknown", c:source_state("zz"), nil)
settings:set_notify_pref("sistema", "desligada")
c:source_result(src, false); clock.add(1)
eq("source: respects Sistema preference", c:source_result(src, false), nil)

-- sleep strip without titles (11.8)
do
    local c = setup({ gate = false })
    c:emit("alfa", N("h1", { title = "Titulo reservado" }))
    local sm = c:sleep_summary("alta", true)
    eq("sleep strip hidden titles: one", sm and sm.text, "1 não lida")
    check("sleep strip hidden titles: no title anywhere", sm and not sm.text:find("Titulo", 1, true))
    c:emit("alfa", N("h2", { title = "Outro" }))
    eq("sleep strip hidden titles: many", c:sleep_summary("alta", true).text, "2 não lidas")
    check("sleep strip: titles shown by default", c:sleep_summary("alta").text:find("Titulo", 1, true) ~= nil
        or c:sleep_summary("alta").text:find("Outro", 1, true) ~= nil)
    eq("sleep strip hidden titles: nenhuma is still nothing", c:sleep_summary("nenhuma", true), nil)
end
