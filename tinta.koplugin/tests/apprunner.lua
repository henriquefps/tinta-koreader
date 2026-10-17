-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (C) 2026 Tinta contributors
-- Shared runner of the small local apps' tests (timer, nota, contagem): apps/<id>/tests/run.lua calls
-- require("apprunner").run(id, here, suites). Suites are apps/<id>/tests/test_<name>.lua and get T, with
-- T.check / T.eq / T.plugin / T.here / T.L (the app's pt strings, like ctx.i18n.t) / T.ctx (a fake ctx).
local M = {}

function M.run(id, here, suites)
    local plugin = here .. "/../../.."
    package.path = plugin .. "/?.lua;" .. plugin .. "/tests/?.lua;" .. here .. "/?.lua;" .. package.path
    local quiet = os.getenv("QUIET") == "1"
    local T = { passed = 0, failed = 0, here = here, plugin = plugin }
    function T.check(name, cond, extra)
        if cond then
            T.passed = T.passed + 1
            if not quiet then print("ok   - " .. name) end
        else
            T.failed = T.failed + 1
            print("FAIL - " .. name .. (extra ~= nil and (" :: " .. tostring(extra)) or ""))
        end
    end
    function T.eq(name, got, want) T.check(name, got == want, "got " .. tostring(got) .. ", want " .. tostring(want)) end
    -- UTC os.date, so times in the tests do not depend on the machine's time zone
    function T.utc(fmt, t) if fmt:sub(1, 1) == "!" then return os.date(fmt, t) end; return os.date("!" .. fmt, t) end
    local Strings = require("apps/" .. id .. "/strings")
    function T.L(key, ...)
        local s = Strings.pt[key] or key
        if select("#", ...) > 0 then return string.format(s, ...) end
        return (s:gsub("%%%%", "%%"))
    end
    -- fake ctx over in-memory data/settings, recording notifications, wake requests, redraws and toasts
    function T.ctx(opts)
        opts = opts or {}
        local I18n = require("core/i18n")
        local c = { data_store = {}, settings_store = opts.settings or {}, notes = {}, wakes = {}, redraws = 0, toasts = {},
            data_reads = 0, t = opts.now or 1792000000 }
        c.now = function() return c.t end
        c.i18n = I18n.new(Strings)
        c.data = {
            get = function(_, k) c.data_reads = c.data_reads + 1; return c.data_store[k] end,
            set = function(_, k, v) c.data_store[k] = v; return true end,
        }
        c.settings = {
            get = function(_, k) return c.settings_store[k] end,
            set = function(_, k, v) c.settings_store[k] = v; return true, v end,
        }
        c.notify = function(n) c.notes[#c.notes + 1] = n; return #c.notes end
        c.wake_at = function(ts) c.wakes[#c.wakes + 1] = ts or false end
        c.redraw = function() c.redraws = c.redraws + 1 end
        c.toast = function(text) c.toasts[#c.toasts + 1] = text end
        c.log = function() end
        c.back = function() c.backs = (c.backs or 0) + 1 end
        c.open = function(screen, args) c.opened = { screen, args } end
        c.confirm = function(title, text, ok_label, fn) c.confirmed = { title = title, text = text, ok = fn } end
        c.choose = function(title, options, current, on_pick) c.chosen = { title = title, options = options, current = current, pick = on_pick } end
        c.input = function(title, value, hint, on_save, o) c.inputs = c.inputs or {}; c.inputs[#c.inputs + 1] =
            { title = title, value = value, hint = hint, on_save = on_save, opts = o } end
        return c
    end
    for _, name in ipairs(suites) do
        if not quiet then print("\n# " .. name) end
        local fn = assert(loadfile(here .. "/test_" .. name .. ".lua"))
        local ok, err = xpcall(function() fn(T) end, debug.traceback)
        if not ok then T.check(name .. ": suite crashed", false, err) end
    end
    print(string.format("\n%s: %d passed, %d failed", id, T.passed, T.failed))
    os.exit(T.failed == 0 and 0 or 1)
end

return M
