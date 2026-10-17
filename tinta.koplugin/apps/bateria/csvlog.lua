-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (C) 2026 Tinta contributors
-- Bateria app: the battery log file (D2: CSV in v1, koreader/tinta-battery.csv, 16.4). Pure Lua (plain io, no
-- KOReader modules). Ported from the standalone plugin this app replaces:
-- one line per change plus a heartbeat (logic.should_log), trimmed to MAX_LINES when it reaches TRIM_AT lines
-- (2800 x ~36 B = ~100 KB at most). A failing disk never raises: the log stops and the estimate keeps working
-- from memory. Also the one-time import of the old log of another plugin into this one.
local Logic = require("apps/bateria/logic")

local M = {}

M.MAX_LINES = 2000      -- lines kept after a trim
M.TRIM_AT = 2800        -- lines that trigger a trim
M.FILE = "tinta-battery.csv"

local function read_lines(path)
    local fh = path and io.open(path, "r")
    if not fh then return nil end
    local lines = {}
    for l in fh:lines() do lines[#lines + 1] = l end
    fh:close()
    return lines
end

-- writes `lines` (plus the header) to a temp file and renames it over `path`
local function rewrite(path, lines)
    local tmp = path .. ".tmp"
    local fh = io.open(tmp, "w")
    if not fh then return false end
    local ok = pcall(function()
        fh:write(Logic.HEADER, "\n")
        for _, l in ipairs(lines) do fh:write(l, "\n") end
    end)
    fh:close()
    if not ok then os.remove(tmp); return false end
    local renamed = os.rename(tmp, path)
    if not renamed then os.remove(tmp) end
    return renamed and true or false
end

local Store = {}
Store.__index = Store

-- path: log file (nil = no file, estimate only from memory). Reads the existing log once.
function M.open(path)
    local self = setmetatable({ path = path, samples = {}, nlines = 0, broken = path == nil }, Store)
    if not path then return self end
    local lines = read_lines(path)
    if lines then
        local keep = {}
        for _, l in ipairs(lines) do
            local s = Logic.parse_line(l)
            if s then
                keep[#keep + 1] = l
                self.samples[#self.samples + 1] = s
            end
        end
        self.nlines = #keep
        if lines[1] ~= Logic.HEADER and self.nlines < M.TRIM_AT then   -- other header: rewrite once
            if not rewrite(path, keep) then self.broken = true end
        end
        if #self.samples > Logic.MAX_SAMPLES then
            local tail = {}
            for i = #self.samples - Logic.MAX_SAMPLES + 1, #self.samples do tail[#tail + 1] = self.samples[i] end
            self.samples = tail
        end
        if self.nlines >= M.TRIM_AT then self:trim(keep) end
    else
        local fh = io.open(path, "w")
        if fh then fh:write(Logic.HEADER, "\n"); fh:close() else self.broken = true end
    end
    return self
end

function Store:trim(lines)
    lines = lines or read_lines(self.path) or {}
    local keep = {}
    for _, l in ipairs(lines) do if Logic.parse_line(l) then keep[#keep + 1] = l end end
    local from = math.max(1, #keep - M.MAX_LINES + 1)
    local tail = {}
    for i = from, #keep do tail[#tail + 1] = keep[i] end
    if rewrite(self.path, tail) then self.nlines = #tail else self.broken = true end
end

-- Records the reading when it is due (logic.should_log). Returns the sample written, or nil.
-- r = { pct, charging, wifi, mv, ma, mah, temp }. ev (Logic.EV value) marks a sleep/wake sample: it is written even
-- when nothing changed (the marker is the point), except twice in the same second with the same marker.
function Store:sample(now, r, ev)
    local pct = math.floor(tonumber(r.pct) + 0.5)
    local charging = r.charging == true
    local last = self.samples[#self.samples]
    if ev then
        if last and last.t == math.floor(now) and last.ev == ev then return nil end
    elseif not Logic.should_log(last, now, pct, charging) then
        return nil
    end
    local s = { t = math.floor(now), pct = pct, chg = charging, wifi = r.wifi == true,
        mv = tonumber(r.mv), ma = tonumber(r.ma), mah = tonumber(r.mah), temp = tonumber(r.temp), ev = ev }
    self.samples[#self.samples + 1] = s
    if #self.samples > Logic.MAX_SAMPLES then table.remove(self.samples, 1) end
    if not self.broken then
        local ok = pcall(function()
            local fh = assert(io.open(self.path, "a"))
            fh:write(Logic.format_line(s.t, s.pct, s.chg, s.wifi, s, s.ev), "\n")
            fh:close()
        end)
        if ok then
            self.nlines = self.nlines + 1
            if self.nlines >= M.TRIM_AT then pcall(self.trim, self) end
        else
            self.broken = true
        end
    end
    return s
end

---------------------------------------------------------------- one-time import of the old log (16.4)

-- Merges the old plugin's log into the tinta's: every valid line of both, by time (a time present in both keeps
-- the tinta's line), the newest MAX_LINES kept. The old file is only read, never changed (the old plugin may
-- still be running until stage 4). Returns the number of old lines added, or nil, reason
-- ("no_legacy" when the old file does not exist, "write" when the new file cannot be written).
function M.import(old_path, new_path)
    local old = read_lines(old_path)
    if not old then return nil, "no_legacy" end
    local by_t, order = {}, {}
    local function add(l, from_old)
        local s = Logic.parse_line(l)
        if not s then return false end
        if by_t[s.t] then return false end
        by_t[s.t] = l
        order[#order + 1] = s.t
        return from_old
    end
    for _, l in ipairs(read_lines(new_path) or {}) do add(l, false) end
    local added = 0
    for _, l in ipairs(old) do if add(l, true) then added = added + 1 end end
    table.sort(order)
    local from = math.max(1, #order - M.MAX_LINES + 1)
    local out = {}
    for i = from, #order do out[#out + 1] = by_t[order[i]] end
    if not rewrite(new_path, out) then return nil, "write" end
    return added
end

return M
