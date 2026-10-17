-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (C) 2026 Tinta contributors
-- Tinta device side: HTTP with timeouts and a byte limit, JSON decoding, Wi-Fi state (spec 4.1, 5.2).
-- ctx.net is this module (or nil when it fails to load). Calls are synchronous, like the old plugins; apps
-- call done(ok, err) from refresh. Apps never turn the Wi-Fi on or off (R-P1): only wifi_on/connected here.
--
--   Net.get_json(url, opts)        -> table | nil, kind, detail
--   Net.post_json(url, body, opts) -> table | nil, kind, detail
--   opts = { token = <string|nil, sent as Authorization: Bearer>, timeout = <s, default 8>,
--            max_bytes = <default 256 KiB>, headers = <table|nil> }
--   kind: "unreachable" | "unauthorized" | "forbidden" | "not_found" | "http" | "too_large" | "bad_json"
--         | "server_failed"
--   detail: "http" -> the status code ("500"); "server_failed" -> the server's short detail (one line,
--           at most 120 characters); "unreachable" -> the transport error. The token is removed from every
--           detail. Nothing here logs URLs, headers or bodies (R-A4).
--   Net.wifi_on() -> bool ; Net.connected() -> bool
--
-- KOReader modules (socket.http, ltn12, socketutil, json, NetworkMgr) are required lazily and can be replaced
-- with Net._set_deps{ http, ltn12, socketutil, json, network } (tests; Net._set_deps(nil) restores them).
local M = {}

M.TIMEOUT = 8                 -- seconds, socket block timeout
M.TOTAL_EXTRA = 7             -- total timeout = timeout + 7 (8 -> 15 s, as the old plugins)
M.MAX_BYTES = 256 * 1024

local deps = nil

function M._set_deps(d) deps = d end

local MODULES = {
    http = "socket.http", ltn12 = "ltn12", socketutil = "socketutil", json = "json",
    network = "ui/network/manager",
}

-- with injected deps, only those are used (a missing one is absent)
local function dep(name)
    if deps then return deps[name] or nil end
    local ok, mod = pcall(require, MODULES[name])
    if ok then return mod end
    return nil
end

---------------------------------------------------------------- helpers

local function plain(p) return (p:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0")) end

-- removes the token (and its URL-encoded form) from a text
local function redact(s, token)
    s = tostring(s or "")
    if type(token) ~= "string" or token == "" then return s end
    s = s:gsub(plain(token), "***")
    local enc = token:gsub("[^%w%-%._~]", function(c) return string.format("%%%02X", c:byte()) end)
    if enc ~= token then s = s:gsub(plain(enc), "***") end
    return s
end
M._redact = redact

-- one line, at most n characters (UTF-8 aware), "…" when cut
local function short(s, n)
    s = tostring(s or ""):gsub("[%c]", " "):gsub("%s+", " "):gsub("^ ", ""):gsub(" $", "")
    local chars = {}
    for ch in s:gmatch("[%z\1-\127\194-\244][\128-\191]*") do chars[#chars + 1] = ch end
    if #chars <= n then return s end
    local out = {}
    for i = 1, n - 1 do out[i] = chars[i] end
    return table.concat(out) .. "…"
end

local function decode(raw)
    local json = dep("json")
    if not json or type(raw) ~= "string" then return nil end
    local ok, t = pcall(json.decode, raw)
    if ok and type(t) == "table" then return t end
    return nil
end

local function encode(v)
    if type(v) == "string" then return v end
    if v == nil then return "{}" end
    local json = dep("json")
    if not json or not json.encode then return nil end
    local ok, s = pcall(json.encode, v)
    if ok and type(s) == "string" then return s end
    return nil
end

---------------------------------------------------------------- request

-- One request. Returns code, raw body | nil, kind, detail ("unreachable" | "too_large").
function M.request(method, url, body, opts)
    opts = opts or {}
    local token = opts.token
    local http = dep("http")
    if not http or type(url) ~= "string" then return nil, "unreachable", "no http" end
    local timeout = tonumber(opts.timeout) or M.TIMEOUT
    local max = tonumber(opts.max_bytes) or M.MAX_BYTES

    local chunks, size, too_large = {}, 0, false
    local function sink(chunk)
        if chunk then
            size = size + #chunk
            if size > max then too_large = true; return nil, "response too large" end
            chunks[#chunks + 1] = chunk
        end
        return 1
    end

    local headers = { ["Accept"] = "application/json" }
    for k, v in pairs(opts.headers or {}) do headers[k] = v end
    if type(token) == "string" and token ~= "" then headers["Authorization"] = "Bearer " .. token end
    local req = { url = url, method = method, headers = headers, sink = sink }
    if body then
        local ltn12 = dep("ltn12")
        if not ltn12 then return nil, "unreachable", "no ltn12" end
        headers["Content-Type"] = "application/json"
        headers["Content-Length"] = tostring(#body)
        req.source = ltn12.source.string(body)
    end

    local socketutil = dep("socketutil")
    if socketutil then pcall(socketutil.set_timeout, socketutil, timeout, timeout + M.TOTAL_EXTRA) end
    -- with a sink, socket.http returns 1, code, headers, status (or nil, err)
    local ok, r1, r2 = pcall(http.request, req)
    if socketutil then pcall(socketutil.reset_timeout, socketutil) end

    if too_large then return nil, "too_large" end
    if not ok then return nil, "unreachable", "request error" end
    if r1 == nil then return nil, "unreachable", short(redact(tostring(r2), token), 80) end
    if type(r2) ~= "number" then return nil, "unreachable", "no status" end
    return r2, table.concat(chunks)
end

-- status code + body -> table | nil, kind, detail
local function result(code, raw, token)
    if code >= 200 and code < 300 then
        local t = decode(raw)
        if not t then return nil, "bad_json" end
        return t
    end
    if code == 401 then return nil, "unauthorized" end
    if code == 403 then return nil, "forbidden" end
    if code == 404 then return nil, "not_found" end
    if code == 502 then
        -- a server that reports a failing upstream: 502 {"error":"<any short code>","detail":"<short text>"}
        local t = decode(raw)
        if type(t) == "table" and type(t.error) == "string" and t.error ~= "" then
            local d = type(t.detail) == "string" and t.detail ~= "" and short(redact(t.detail, token), 120) or nil
            return nil, "server_failed", d
        end
    end
    return nil, "http", tostring(code)
end

function M.get_json(url, opts)
    opts = opts or {}
    local code, raw, detail = M.request("GET", url, nil, opts)
    if not code then return nil, raw, detail end
    return result(code, raw, opts.token)
end

-- body: a JSON string (sent as is) or a Lua table (encoded); nil sends "{}"
function M.post_json(url, body, opts)
    opts = opts or {}
    local text = encode(body)
    if not text then return nil, "bad_json", "encode" end
    local code, raw, detail = M.request("POST", url, text, opts)
    if not code then return nil, raw, detail end
    return result(code, raw, opts.token)
end

---------------------------------------------------------------- Wi-Fi state (read only, R-P1)

function M.wifi_on()
    local nm = dep("network")
    if not nm then return false end
    local ok, v = pcall(function() return nm:isWifiOn() end)
    return ok and v == true
end

function M.connected()
    local nm = dep("network")
    if not nm then return false end
    local ok, v = pcall(function() return nm:isWifiOn() == true and nm:isConnected() == true end)
    return ok and v == true
end

return M
