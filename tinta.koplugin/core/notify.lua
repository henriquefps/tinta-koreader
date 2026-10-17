-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (C) 2026 Tinta contributors
-- Notifications (spec 8): the ctx.notify API, deduplication by (app, key) (R-T1), per-app preference (R-T2),
-- storage (R-T3) with the 200 limit (R-T4), unread count (R-T6), opening (8.4), the sleep-page summary (R-T11),
-- "the first reading after opening only records state" (8.6) and the Sistema server rules (8.6).
-- Pure Lua (R-A1): store, clock, preferences and callbacks are injected.
local I18n = require("core/i18n")
local Format = require("core/format")
local Layout = require("core/layout")

local M = {}

M.MAX = 200
M.PRIOS = { alta = true, normal = true }
M.SYSTEM_APP = "sistema"

-- Notify.new{
--   store = store,                         -- required (core/store interface)
--   now = fn,                              -- clock (default os.time)
--   pref = fn(app) -> "alta"|"normal"|"desligada"   (default: always "alta"; settings:notify_pref fits)
--   log = fn(level, app, msg),             -- optional
--   on_new = fn(notification),             -- optional: banner (R-T5), redraw of the bell
--   first_read_gate = bool,                -- default true: emissions before arm(app) only record the key
--   armed = { app_id, ... },               -- apps armed from the start (default { "sistema" })
--   max = 200,
-- }
function M.new(opts)
    opts = opts or {}
    local store = assert(opts.store, "notify: store required")
    local now = opts.now or os.time
    local pref = opts.pref or function() return "alta" end
    local log = opts.log or function() end
    local gate = opts.first_read_gate ~= false
    local max = opts.max or M.MAX
    local always = opts.armed or { M.SYSTEM_APP }

    local C = { store = store }
    local armed, suppressed, sources = {}, {}, {}

    local function reset_session()
        armed, suppressed = {}, {}
        for _, a in ipairs(always) do armed[a] = true end
    end
    reset_session()

    -- Opening the Tinta starts a session: every app's first reading only records state again (8.6).
    function C:begin_session() reset_session() end
    -- Called after an app's first successful reading of the session (the registry does it).
    function C:arm(app) armed[app] = true end
    function C:is_armed(app) return not gate or armed[app] == true end

    -- ctx.notify (8.1). n = { key, title, body, prio, route, type }.
    -- Returns the new id, or nil and the reason: "invalid" | "off" | "dup" | "first_read".
    function C:emit(app, n)
        if type(app) ~= "string" or type(n) ~= "table" or type(n.key) ~= "string" or n.key == ""
                or type(n.title) ~= "string" then
            log("warn", app, "notify: invalid notification")
            return nil, "invalid"
        end
        local p = pref(app)
        if p == "desligada" then                                  -- R-T2: dropped, logged
            log("info", app, I18n.t("log_notify_off", app, n.title))
            return nil, "off"
        end
        local sk = app .. "\0" .. n.key
        if suppressed[sk] or store:notif_find(app, n.key) then     -- R-T1: read or not, never twice
            log("debug", app, I18n.t("log_notify_dup", app, n.title))
            return nil, "dup"
        end
        if gate and not armed[app] then                            -- 8.6: first reading only records state
            suppressed[sk] = true
            log("debug", app, I18n.t("log_notify_first", app, n.title))
            return nil, "first_read"
        end
        local prio = M.PRIOS[n.prio] and n.prio or "normal"
        if p == "normal" and prio == "alta" then prio = "normal" end   -- R-T2: lowered
        local row = {
            app = app, key = n.key, type = n.type, title = n.title, body = n.body, prio = prio,
            route = n.route, created_at = now(), read_at = nil,
        }
        local id = store:notif_add(row)
        if not id then return nil, "dup" end
        store:notif_trim(max)                                      -- R-T4
        row.id = id
        log("info", app, I18n.t("log_notify_new", prio, app, n.title))
        if opts.on_new then pcall(opts.on_new, row) end
        return id
    end

    -- Bound emitter for one app (ctx.notify).
    function C:emitter(app)
        return function(n) return C:emit(app, n) end
    end

    function C:unread_count() return store:notif_unread_count() end   -- R-T6
    function C:count() return store:notif_count() end
    function C:get(id) return store:notif_get(id) end
    function C:list(o) return store:notif_list(o) end              -- newest first (R-T9)

    -- One page of the central (R-T9: 4 per page portrait, 2 landscape): items, page, pages.
    function C:page(page, per_page)
        local total = store:notif_count()
        local p, pages, first = Layout.paginate(total, per_page, page)
        local items = store:notif_list({ offset = first - 1, limit = per_page })
        return items, p, pages
    end

    function C:mark_read(id) return store:notif_mark_read(id, now()) end
    function C:mark_all_read() return store:notif_mark_all_read(now()) end   -- R-T10
    function C:clear() return store:notif_clear() end                      -- R-T10 (UI confirms first)

    -- 8.4: marks as read and returns where to go: { id, app, screen, args }. Without route the app's "main".
    -- route = { "screen", args } or "screen". nil for an unknown id.
    function C:open(id)
        local n = store:notif_get(id)
        if not n then return nil end
        store:notif_mark_read(id, now())
        local screen, args = "main", nil
        if type(n.route) == "table" and type(n.route[1]) == "string" then screen, args = n.route[1], n.route[2]
        elseif type(n.route) == "string" then screen = n.route end
        return { id = id, app = n.app, screen = screen, args = args }
    end

    -- R-T11: UNREAD stored notifications for the sleep page (the strip says "não lidas", so it is not mistaken
    -- for the widgets' state). mode = "alta" (default) | "todas" | "nenhuma".
    -- Returns nil when nothing fits, else { count, latest (notification), text = "2 não lidas · <título>" }.
    -- hide_titles (8.5): the text is only the count ("1 não lida"), no title.
    function C:sleep_summary(mode, hide_titles)
        mode = mode or "alta"
        if mode == "nenhuma" then return nil end
        local list = store:notif_list({ unread = true })
        local fit = {}
        for _, n in ipairs(list) do
            if mode == "todas" or n.prio == "alta" then fit[#fit + 1] = n end
        end
        if #fit == 0 then return nil end
        local text
        if hide_titles then
            text = #fit == 1 and I18n.t("sleep_banner_one_hidden") or I18n.t("sleep_banner_many_hidden", #fit)
        else
            text = #fit == 1 and I18n.t("sleep_banner_one", fit[1].title) or I18n.t("sleep_banner_many", #fit, fit[1].title)
        end
        return { count = #fit, latest = fit[1], text = text }
    end

    -- R-T5 banner lines: "App · HH:MM" and the title. app_name is the display name.
    function C.banner_lines(n, app_name, date)
        return (app_name or n.app) .. " · " .. Format.hm(n.created_at, date), n.title
    end

    ---------------------------------------------------------------- Sistema server rules (8.6, R-U6)

    -- Result of one update of an app that talks to `src` = { id, name, host }. Two failures in a row emit
    -- "down" (alta); the first success after a "down" emits "up" (normal). Returns the new notification id or nil.
    function C:source_result(src, ok, latency_ms)
        local t = now()
        local s = sources[src.id] or { fail_streak = 0 }
        sources[src.id] = s
        local id
        if ok then
            if s.down then
                id = C:emit(M.SYSTEM_APP, {
                    key = "up:" .. src.id .. ":" .. t, type = "server_up", prio = "normal",
                    title = I18n.t("source_up_title", src.name or src.id),
                    body = I18n.t("source_up_body", src.host or src.name or src.id),
                    route = { "conn" },
                })
            end
            s.fail_streak, s.down, s.down_since = 0, false, nil
            s.last_ok, s.latency = t, latency_ms
        else
            s.fail_streak = s.fail_streak + 1
            s.last_err = t
            if s.fail_streak == 1 then s.down_since = t end
            if s.fail_streak == 2 then
                s.down = true
                id = C:emit(M.SYSTEM_APP, {
                    key = "down:" .. src.id .. ":" .. t, type = "server_down", prio = "alta",
                    title = I18n.t("source_down_title", src.name or src.id),
                    body = I18n.t("source_down_body", src.host or src.name or src.id),
                    route = { "conn" },
                })
            end
        end
        return id
    end

    -- Conexões screen (10.5): { fail_streak, down, down_since, last_ok, last_err, latency } or nil.
    function C:source_state(id)
        local s = sources[id]
        if not s then return nil end
        local o = {}
        for k, v in pairs(s) do o[k] = v end
        return o
    end

    return C
end

return M
