-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (C) 2026 Tinta contributors
-- Tinta: launcher rules (6.5, 7.4), pure. Which apps are listed, in which order and with which mark.
local Org = require("ui/orglogic")

local M = {}

-- UTF-8 accented letters folded to ASCII for the sort key ("Órbita" sorts with the O's)
local FOLD = {
    ["á"] = "a", ["à"] = "a", ["â"] = "a", ["ã"] = "a", ["ä"] = "a", ["é"] = "e", ["è"] = "e", ["ê"] = "e",
    ["ë"] = "e", ["í"] = "i", ["ì"] = "i", ["î"] = "i", ["ó"] = "o", ["ò"] = "o", ["ô"] = "o", ["õ"] = "o",
    ["ö"] = "o", ["ú"] = "u", ["ù"] = "u", ["û"] = "u", ["ü"] = "u", ["ç"] = "c", ["ñ"] = "n",
}

function M.sort_key(name)
    local s = tostring(name or ""):lower()
    -- string.lower leaves "Á" (C3 81) alone: bring Latin-1 capitals (C3 80..9E) down to their small letters
    s = s:gsub("\195([\128-\158])", function(b) return "\195" .. string.char(b:byte() + 32) end)
    s = s:gsub("\195[\128-\191]", function(c) return FOLD[c] or c end)
    return s
end

-- "no Início" (shown on Home), "oculta" (in the Home layout but hidden), nil (never added)
function M.mark(list, id)
    local _, it = Org.find(list, id)
    if not it then return nil end
    return it.hidden and "hidden" or "home"
end

-- Every registered app, alphabetical by display name (ties by id). apps: manifests ({ id, ... });
-- name_of(id) -> display name; sub_of(manifest) -> subtitle or nil; home: the Home layout list.
-- inactive (optional, 10.5): the apps that are not loaded ({ id, why, manifest }); the ones the user turned off
-- ("disabled") are listed too, greyed, so they can be turned on again; the ones that need a newer Tinta are not.
-- Entries: { id, name, sub, mark = "home" | "hidden" | nil, disabled = true | nil }.
function M.entries(apps, name_of, sub_of, home, inactive)
    local out = {}
    for _, m in ipairs(apps or {}) do
        local name = name_of(m.id) or m.id
        out[#out + 1] = { id = m.id, name = name, sub = sub_of and sub_of(m) or nil, mark = M.mark(home, m.id), key = M.sort_key(name) }
    end
    for _, e in ipairs(inactive or {}) do
        if e.why == "disabled" then
            local name = name_of(e.id) or e.id
            out[#out + 1] = { id = e.id, name = name, sub = sub_of and e.manifest and sub_of(e.manifest) or nil,
                disabled = true, key = M.sort_key(name) }
        end
    end
    table.sort(out, function(a, b)
        if a.key ~= b.key then return a.key < b.key end
        return a.id < b.id
    end)
    return out
end

-- "Adicionar ao Início": result list and whether anything changed (false when already shown on Home)
function M.add_home(home, id, sizes)
    if M.mark(home, id) == "home" then return Org.copy(home), false end
    return Org.unhide(home, id, (sizes or {})[1] or "2x2"), true
end

return M
