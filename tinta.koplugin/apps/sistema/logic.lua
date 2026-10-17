-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (C) 2026 Tinta contributors
-- Sistema app: pure helpers (R-A1: no KOReader require). The server rule of 8.6 lives in core/notify
-- (source_result); validation of settings fields in core/settings.
local M = {}

M.VERSION = require("core/version").TINTA_VERSION   -- shown by Sistema and written in the diagnostic and backups (one source: core/version)

-- Sources of the registered apps: list of { id, name, apps = { app_id, ... } } in registry order.
-- manifests: list of manifests (each may have source = { id, name, url_key? }).
function M.sources(manifests)
    local out, by_id = {}, {}
    for _, m in ipairs(manifests or {}) do
        local s = m.source
        if type(s) == "table" and s.id then
            local e = by_id[s.id]
            if not e then
                e = { id = s.id, name = s.name or s.id, apps = {} }
                by_id[s.id] = e
                out[#out + 1] = e
            end
            e.apps[#e.apps + 1] = m.id
        end
    end
    return out
end

-- the entry with this id in a list of { id, ... } (inactive apps), or nil
function M.find(list, id)
    for _, e in ipairs(list or {}) do if e.id == id then return e end end
    return nil
end

-- host:port of a URL ("http://192.0.2.101:4747/x" -> "192.0.2.101:4747"); nil when not a URL
function M.host_of(url)
    if type(url) ~= "string" then return nil end
    return url:match("^%a[%w+.-]*://([^/%?#]+)")
end

-- next value of a cycle list
function M.cycle(list, v)
    for i, x in ipairs(list) do
        if x == v then return list[i % #list + 1] end
    end
    return list[1]
end

-- bytes -> "212 KB" / "1,4 MB"
function M.size_text(bytes, lang)
    if not bytes then return "?" end
    if bytes < 1024 then return bytes .. " B" end
    if bytes < 1024 * 1024 then return math.floor(bytes / 1024 + 0.5) .. " KB" end
    local s = ("%.1f MB"):format(bytes / (1024 * 1024))
    if lang ~= "en" then s = s:gsub("%.", ",") end
    return s
end

return M
