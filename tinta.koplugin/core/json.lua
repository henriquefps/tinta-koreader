-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (C) 2026 Tinta contributors
-- Minimal JSON encode/decode for the store (spec 12: settings, app data, cache and routes are kept as JSON).
-- Pure Lua (R-A1): the core cannot require KOReader's rapidjson. Values are plain Lua data: tables, strings,
-- numbers, booleans. A table whose keys are exactly 1..n is an array; any other table is an object (keys are
-- converted with tostring). Functions, userdata and cycles are rejected. JSON null decodes to nil.
local M = {}

local escapes = { ['"'] = '\\"', ["\\"] = "\\\\", ["\b"] = "\\b", ["\f"] = "\\f", ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t" }

local function enc_string(s)
    return '"' .. s:gsub('[%c"\\]', function(c) return escapes[c] or string.format("\\u%04x", c:byte()) end) .. '"'
end

local function is_array(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    for i = 1, n do if t[i] == nil then return false end end
    return true, n
end

local function enc(v, seen, out)
    local tv = type(v)
    if v == nil then out[#out + 1] = "null"
    elseif tv == "boolean" then out[#out + 1] = v and "true" or "false"
    elseif tv == "number" then
        if v ~= v or v == math.huge or v == -math.huge then error("json: cannot encode " .. tostring(v)) end
        if v == math.floor(v) and math.abs(v) < 2^53 then out[#out + 1] = string.format("%d", v)
        else out[#out + 1] = string.format("%.14g", v) end
    elseif tv == "string" then out[#out + 1] = enc_string(v)
    elseif tv == "table" then
        if seen[v] then error("json: cycle") end
        seen[v] = true
        local arr, n = is_array(v)
        if arr then
            out[#out + 1] = "["
            for i = 1, n do
                if i > 1 then out[#out + 1] = "," end
                enc(v[i], seen, out)
            end
            out[#out + 1] = "]"
        else
            local keys = {}
            for k in pairs(v) do keys[#keys + 1] = tostring(k) end
            table.sort(keys)   -- stable output (tests, diffs)
            local lookup = {}
            for k, val in pairs(v) do lookup[tostring(k)] = val end
            out[#out + 1] = "{"
            for i, k in ipairs(keys) do
                if i > 1 then out[#out + 1] = "," end
                out[#out + 1] = enc_string(k)
                out[#out + 1] = ":"
                enc(lookup[k], seen, out)
            end
            out[#out + 1] = "}"
        end
        seen[v] = nil
    else
        error("json: cannot encode " .. tv)
    end
end

function M.encode(v)
    local out = {}
    enc(v, {}, out)
    return table.concat(out)
end

---------------------------------------------------------------- decode

local function utf8_char(cp)
    if cp < 0x80 then return string.char(cp)
    elseif cp < 0x800 then return string.char(0xC0 + math.floor(cp / 0x40), 0x80 + cp % 0x40)
    elseif cp < 0x10000 then
        return string.char(0xE0 + math.floor(cp / 0x1000), 0x80 + math.floor(cp / 0x40) % 0x40, 0x80 + cp % 0x40)
    else
        return string.char(0xF0 + math.floor(cp / 0x40000), 0x80 + math.floor(cp / 0x1000) % 0x40,
            0x80 + math.floor(cp / 0x40) % 0x40, 0x80 + cp % 0x40)
    end
end

local decode_value

local function skip(s, i)
    return s:find("[^ \t\r\n]", i) or #s + 1
end

local function decode_string(s, i)
    local buf, j = {}, i + 1
    while true do
        local c = s:sub(j, j)
        if c == "" then error("json: unterminated string") end
        if c == '"' then return table.concat(buf), j + 1 end
        if c == "\\" then
            local e = s:sub(j + 1, j + 1)
            local map = { b = "\b", f = "\f", n = "\n", r = "\r", t = "\t", ['"'] = '"', ["\\"] = "\\", ["/"] = "/" }
            if map[e] then buf[#buf + 1] = map[e]; j = j + 2
            elseif e == "u" then
                local cp = tonumber(s:sub(j + 2, j + 5), 16)
                if not cp then error("json: bad \\u escape") end
                j = j + 6
                if cp >= 0xD800 and cp <= 0xDBFF and s:sub(j, j + 1) == "\\u" then
                    local lo = tonumber(s:sub(j + 2, j + 5), 16)
                    if lo and lo >= 0xDC00 and lo <= 0xDFFF then
                        cp = 0x10000 + (cp - 0xD800) * 0x400 + (lo - 0xDC00)
                        j = j + 6
                    end
                end
                buf[#buf + 1] = utf8_char(cp)
            else error("json: bad escape") end
        else
            local k = s:find('["\\]', j) or #s + 1
            buf[#buf + 1] = s:sub(j, k - 1)
            j = k
        end
    end
end

decode_value = function(s, i)
    i = skip(s, i)
    local c = s:sub(i, i)
    if c == "{" then
        local t = {}
        i = skip(s, i + 1)
        if s:sub(i, i) == "}" then return t, i + 1 end
        while true do
            i = skip(s, i)
            if s:sub(i, i) ~= '"' then error("json: expected key") end
            local k
            k, i = decode_string(s, i)
            i = skip(s, i)
            if s:sub(i, i) ~= ":" then error("json: expected ':'") end
            local v
            v, i = decode_value(s, i + 1)
            t[k] = v
            i = skip(s, i)
            local d = s:sub(i, i)
            if d == "}" then return t, i + 1 end
            if d ~= "," then error("json: expected ',' or '}'") end
            i = i + 1
        end
    elseif c == "[" then
        local t, n = {}, 0
        i = skip(s, i + 1)
        if s:sub(i, i) == "]" then return t, i + 1 end
        while true do
            local v
            v, i = decode_value(s, i)
            n = n + 1
            t[n] = v
            i = skip(s, i)
            local d = s:sub(i, i)
            if d == "]" then return t, i + 1 end
            if d ~= "," then error("json: expected ',' or ']'") end
            i = i + 1
        end
    elseif c == '"' then return decode_string(s, i)
    elseif s:sub(i, i + 3) == "true" then return true, i + 4
    elseif s:sub(i, i + 4) == "false" then return false, i + 5
    elseif s:sub(i, i + 3) == "null" then return nil, i + 4
    else
        local num = s:match("^-?%d+%.?%d*[eE]?[-+]?%d*", i)
        if not num or num == "" or not tonumber(num) then error("json: unexpected '" .. c .. "' at " .. i) end
        return tonumber(num), i + #num
    end
end

-- Returns the value, or nil and an error message (never throws).
function M.decode(s)
    if type(s) ~= "string" then return nil, "json: not a string" end
    local ok, v, i = pcall(decode_value, s, 1)
    if not ok then return nil, v end
    if skip(s, i) <= #s then return nil, "json: trailing data" end
    return v
end

return M
