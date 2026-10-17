-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (C) 2026 Tinta contributors
-- Sistema → Dados: the files of the diagnostic export and the settings backup (reads and writes under koreader/).
-- The content is built by diag.lua and backup.lua (pure); this is the only part that touches the disk and asks
-- KOReader for versions and device facts. Every call is protected: a failing export is a message, never a crash.
local Host = require("ui/host")
local Diag = require("apps/sistema/diag")
local Backup = require("apps/sistema/backup")

local M = {}

-- last `n` lines of a file, nil when it cannot be read; reads at most the last 512 KB of it
local function tail_file(path, n)
    local fh = path and io.open(path, "r")
    if not fh then return nil end
    local size = fh:seek("end") or 0
    fh:seek("set", math.max(0, size - 512 * 1024))
    local lines = {}
    for l in fh:lines() do lines[#lines + 1] = l end
    fh:close()
    return lines
end

local function write_file(path, text)
    local tmp = path .. ".tmp"
    local fh, err = io.open(tmp, "w")
    if not fh then return nil, err end
    local ok, werr = fh:write(text)
    fh:close()
    if not ok then os.remove(tmp); return nil, werr end
    if not os.rename(tmp, path) then os.remove(tmp); return nil, "rename" end
    return true
end

local function read_file(path)
    local fh = io.open(path, "r")
    if not fh then return nil end
    local text = fh:read(Backup.MAX_BYTES + 1)
    fh:close()
    return text
end

-- device and KOReader facts for the report (each one protected: "?" when KOReader does not tell)
local function platform()
    local info = { screen = {} }
    pcall(function() info.koreader_version = require("version"):getCurrentRevision() end)
    pcall(function()
        local Device = require("device")
        info.model = Device.model
        local Screen = Device.screen
        info.screen.w, info.screen.h, info.screen.dpi = Screen:getWidth(), Screen:getHeight(), Screen:getDPI()
        info.screen.scale = ("%.2f"):format(Screen:scaleBySize(1000) / 1000)
    end)
    pcall(function() info.backend = require("device/backends").current().name end)
    return info
end

-- Writes koreader/tinta-diagnostico-<date>.txt. Returns the file name | nil, error text.
function M.exportDiagnostic(tinta_version)
    local dir = Host:dataDir()
    if not dir then return nil, "no data dir" end
    local ok, name_or_err = pcall(function()
        local info = platform()
        info.generated = os.time()
        info.tinta_version = tinta_version
        info.api_version = Host:backupEnv().api_version
        info.apps = {}
        for _, m in ipairs(Host:apps()) do
            local st = Host:state(m.id) or {}
            info.apps[#info.apps + 1] = { id = m.id, name = Host:appName(m.id), version = m.version, enabled = not st.disabled }
        end
        info.settings = Host:redactedSettings()
        info.log = Diag.log_lines(Host:logTail(Diag.LOG_LINES), Diag.LOG_LINES)
        info.power_log = Diag.tail(tail_file(dir .. "/tinta-power.log", Diag.POWER_LINES) or {}, Diag.POWER_LINES)
        info.battery = Diag.tail(tail_file(dir .. "/tinta-battery.csv", Diag.BATTERY_LINES) or {}, Diag.BATTERY_LINES)
        info.crash = Diag.crash_lines(tail_file(dir .. "/crash.log", 5000) or {}, Diag.CRASH_LINES)
        local name = Diag.filename(info.generated)
        local wrote, err = write_file(dir .. "/" .. name, Diag.build(info))
        if not wrote then error(tostring(err), 0) end
        return name
    end)
    if not ok then return nil, tostring(name_or_err) end
    return name_or_err
end

-- Writes koreader/tinta-backup-<date>.json. Returns the file name | nil, error text.
function M.exportBackup(tinta_version)
    local dir = Host:dataDir()
    if not dir then return nil, "no data dir" end
    local ok, name_or_err = pcall(function()
        local env = Host:backupEnv()
        env.tinta_version = tinta_version
        local name = Backup.filename(env.now)
        local wrote, err = write_file(dir .. "/" .. name, Backup.encode(Backup.build(env)))
        if not wrote then error(tostring(err), 0) end
        return name
    end)
    if not ok then return nil, tostring(name_or_err) end
    return name_or_err
end

-- tinta-backup-*.json in koreader/, newest first
function M.backupFiles()
    local dir = Host:dataDir()
    local names = {}
    if not dir then return names end
    pcall(function()
        local lfs = require("libs/libkoreader-lfs")
        for f in lfs.dir(dir) do names[#names + 1] = f end
    end)
    return Backup.list_names(names)
end

-- Validates and applies a backup file. Returns the result counts of backup.apply | nil, "format" | "newer" | "read"
function M.restore(name)
    local dir = Host:dataDir()
    if not dir or (not name:match("^tinta%-backup%-[%w%-]+%.json$") and not name:match("^portal%-backup%-[%w%-]+%.json$")) then return nil, "read" end
    local text = read_file(dir .. "/" .. name)
    if not text then return nil, "read" end
    local t, err = Backup.decode(text)
    if not t then return nil, err end
    local ok, res = pcall(Backup.apply, t, Host:backupEnv())
    if not ok then return nil, "read" end
    Host:reloadAfterRestore()
    return res
end

return M
