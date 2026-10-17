-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (C) 2026 Tinta contributors
-- Sistema → Dados → "Exportar diagnóstico": builds the text report (pure, R-A1; the files are read and
-- written by ui/host). Secrets never get in: settings arrive already redacted (core/settings) and every text
-- line goes through Settings.redact_text as a second net (spec 14). The report is bounded (MAX_BYTES).
local Settings = require("core/settings")

local M = {}

M.MAX_BYTES = 250 * 1024        -- < 256 KB
M.LINE_MAX = 400                -- one line is cut here
M.LOG_LINES, M.POWER_LINES, M.BATTERY_LINES, M.CRASH_LINES = 500, 100, 200, 200

-- koreader/tinta-diagnostico-YYYYMMDD-HHMM.txt (the name only; `t` is a unix time)
function M.filename(t)
    return os.date("tinta-diagnostico-%Y%m%d-%H%M.txt", t)
end

-- the last n of a list of lines, in the same order
function M.tail(lines, n)
    local out = {}
    for i = math.max(1, #lines - n + 1), #lines do out[#out + 1] = lines[i] end
    return out
end

-- crash.log: the lines that mention Tinta or a traceback (the header and its indented frames), last n
function M.crash_lines(lines, n)
    local out, in_tb = {}, false
    for _, l in ipairs(lines or {}) do
        local low = l:lower()
        if low:find("traceback", 1, true) then in_tb = true; out[#out + 1] = l
        elseif in_tb and l:match("^%s+%S") then out[#out + 1] = l
        else
            in_tb = false
            if l:find("Tinta", 1, true) then out[#out + 1] = l end
        end
    end
    return M.tail(out, n or M.CRASH_LINES)
end

-- one line of the Tinta log (rows are newest first, as the store returns them) -> text
function M.log_lines(rows, n)
    local out = {}
    for i = math.min(#rows, n or M.LOG_LINES), 1, -1 do
        local l = rows[i]
        out[#out + 1] = ("%s %s %s %s"):format(l.at and os.date("%Y-%m-%d %H:%M:%S", l.at) or "-",
            tostring(l.app or "portal"), tostring(l.level or ""), tostring(l.msg or ""))
    end
    return out
end

-- compact, key-sorted text of a settings value
local function dump(v)
    if type(v) ~= "table" then return type(v) == "string" and string.format("%q", v) or tostring(v) end
    local keys = {}
    for k in pairs(v) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    local parts = {}
    for _, k in ipairs(keys) do parts[#parts + 1] = tostring(k) .. "=" .. dump(v[k]) end
    return "{" .. table.concat(parts, ", ") .. "}"
end
M.dump = dump

local function clean(line)
    line = Settings.redact_text(line):gsub("[%c]", " ")
    if #line > M.LINE_MAX then line = line:sub(1, M.LINE_MAX):gsub("[\192-\255][\128-\191]*$", "") .. "…" end
    return line
end

local function sorted_keys(t)
    local keys = {}
    for k in pairs(t or {}) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    return keys
end

-- info = { generated, tinta_version, api_version, koreader_version, model, backend,
--          screen = { w, h, dpi, scale }, apps = { { id, name, version, enabled } },
--          settings = { tinta = {..}, apps = { id = {..} } }  (already redacted),
--          log = lines, power_log = lines, battery = lines, crash = lines (already limited to the last N) }
function M.build(info)
    info = info or {}
    local sc = info.screen or {}
    local head = {
        "Tinta diagnostic",
        "generated: " .. (info.generated and os.date("%Y-%m-%d %H:%M:%S", info.generated) or "?"),
        "tinta version: " .. tostring(info.tinta_version or "?"),
        "api version: " .. tostring(info.api_version or "?"),
        "koreader: " .. tostring(info.koreader_version or "?"),
        "device: " .. tostring(info.model or "?") .. " (backend " .. tostring(info.backend or "?") .. ")",
        ("screen: %sx%s, %s dpi, scale %s"):format(tostring(sc.w or "?"), tostring(sc.h or "?"), tostring(sc.dpi or "?"), tostring(sc.scale or "?")),
        "",
        "== apps",
    }
    for _, a in ipairs(info.apps or {}) do
        head[#head + 1] = ("%s v%s %s"):format(tostring(a.id), tostring(a.version or "?"), a.enabled and "enabled" or "disabled")
    end
    head[#head + 1] = ""
    head[#head + 1] = "== settings"
    local st = info.settings or {}
    head[#head + 1] = "tinta: " .. dump(st.tinta or {})
    for _, id in ipairs(sorted_keys(st.apps)) do head[#head + 1] = id .. ": " .. dump(st.apps[id]) end
    for i, l in ipairs(head) do head[i] = clean(l) end

    local logs = {
        { "Tinta log (last " .. M.LOG_LINES .. ")", info.log },
        { "tinta-power.log (last " .. M.POWER_LINES .. ")", info.power_log },
        { "tinta-battery.csv (last " .. M.BATTERY_LINES .. ")", info.battery },
        { "crash.log (Tinta / traceback, last " .. M.CRASH_LINES .. ")", info.crash },
    }
    local function render(scale)
        local out = {}
        for _, l in ipairs(head) do out[#out + 1] = l end
        for _, sec in ipairs(logs) do
            out[#out + 1] = ""
            out[#out + 1] = "== " .. sec[1]
            local lines = sec[2]
            if not lines or #lines == 0 then out[#out + 1] = "(none)"
            else
                local keep = math.max(1, math.floor(#lines * scale))
                if keep < #lines then out[#out + 1] = ("(%d older lines left out to fit)"):format(#lines - keep) end
                for i = #lines - keep + 1, #lines do out[#out + 1] = clean(lines[i]) end
            end
        end
        return table.concat(out, "\n") .. "\n"
    end
    local text, scale = render(1), 1
    while #text > M.MAX_BYTES and scale > 0.01 do
        scale = scale / 2
        text = render(scale)
    end
    if #text > M.MAX_BYTES then text = text:sub(1, M.MAX_BYTES - 20) .. "\n[truncated]\n" end
    return text
end

return M
