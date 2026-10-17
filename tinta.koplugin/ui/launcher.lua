-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (C) 2026 Tinta contributors
-- Tinta: launcher (6.5, 7.4). Every registered app in alphabetical order, the ones hidden from Home included;
-- tap opens the app, hold adds it to Home. An app the user turned off is a greyed row (dashed, 10.5): a tap
-- turns it on again, it cannot be opened or added to Home. Paged rows, two columns in landscape (Kit.rows). Reads the Home layout
-- once per render; the subtitle comes from the manifest (no store query per row).
local Kit = require("ui/kit")
local L = require("ui/launchlogic")
local S = require("ui/strings")

local M = {}

local MARK_KEY = { home = "launcher_mark_home", hidden = "launcher_mark_hidden" }

function M.build(win, regions, _route)
    local host = win.host
    local home = host:layout("home")
    local entries = L.entries(host:apps(), function(id) return host:appName(id) end, function(m)
        local d = m.description
        if type(d) == "table" then d = d[S.get_lang()] end
        return type(d) == "string" and d or nil
    end, home, host:inactiveApps())
    local rows = {}
    for i, e in ipairs(entries) do
        local id = e.id
        if e.disabled then
            rows[i] = {
                title = e.name, sub = S.t("launcher_off"), right = S.t("launcher_turn_on"), dim = true,
                on_tap = function()
                    local ok = host:setAppEnabled(id, true)
                    win:showToast(S.t(ok and "launcher_on" or "launcher_on_failed", host:appName(id)))
                    host:redraw()
                end,
            }
        else
            rows[i] = {
                title = e.name, sub = e.sub, right = e.mark and S.t(MARK_KEY[e.mark]) or nil,
                on_tap = function() win:openApp(id) end,
                on_hold = function()
                    local m = host:app(id) or {}
                    local list, changed = L.add_home(host:layout("home"), id, m.sizes)
                    if changed then host:saveLayout("home", list) end
                    win:showToast(S.t(changed and "launcher_added" or "launcher_already", host:appName(id)))
                end,
            }
        end
    end
    local box = win:bodyBox(regions)
    return win:frameScreen(regions, S.t("launcher_title"), S.t("launcher_meta", #entries), nil, Kit.rows(box, rows))
end

return M
