-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (C) 2026 Tinta contributors
-- widgets in every size and the screen in portrait and landscape, built with the real ui/kit over stubbed widgets
local T = ...
local H = require("uistub").install()
local M = require("apps/timer/init")
local L = require("apps/timer/logic")
local A = M._A

local ctx = T.ctx()
ctx.ui = H.kit
M.init(ctx)
local states = {
    idle = function() A.st = L.idle(L.selection("pomo", {})) end,
    running = function() A.st = L.start(L.selection("pomo", {}), ctx.t) end,
    paused = function() A.st = L.pause(L.start(L.selection("m15", {}), ctx.t), ctx.t + 100) end,
}
for _, sname in ipairs({ "idle", "running", "paused" }) do
    states[sname]()
    for _, orient in ipairs({ "portrait", "landscape" }) do
        for _, size in ipairs(M.sizes) do
            for _, inv in ipairs({ false, true }) do
                local box = H.cell(size, orient, inv)
                local name = ("widget %s %s %s%s"):format(sname, size, orient, inv and " inverted" or "")
                H.widget(T, name, function() return M.widget(ctx, size, box) end, box)
                if size == "1x1" then
                    T.check(name .. ": 1x1 shows remaining or ▶", sname == "idle" and H.has("▶") or H.has("25") or H.has("14"))
                elseif sname ~= "idle" then
                    T.check(name .. ": remaining", H.has("min"))
                end
            end
        end
    end
    for _, b in ipairs({ { w = 584, h = 608, landscape = false }, { w = 784, h = 408, landscape = true } }) do
        local name = ("screen %s %s"):format(sname, b.landscape and "landscape" or "portrait")
        H.screen(T, name, function() return M.screens.main(ctx, nil, b) end, b)
        T.check(name .. ": status", H.has(sname == "paused" and "pausado" or (sname == "idle" and "pronto" or "foco")))
        T.check(name .. ": buttons", sname == "idle" and (H.has("Iniciar") and H.has("Outro")) or (H.has("Zerar")))
    end
end
