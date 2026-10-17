-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (C) 2026 Tinta contributors
-- the widget in both sizes and the screen, portrait and landscape, built with the real ui/kit over stubbed widgets:
-- they must build, paint and stay inside their box (R-W1)
local T = ...
EXJSON_H = EXJSON_H or require("uistub").install()   -- install() once per process: ui/kit keeps the first stubs it required
local H = EXJSON_H
local M = require("apps/_exemplo_json/init")
local ctx = T.ctx{ settings = { url = "https://example.com/s.json", threshold = 40 } }
ctx.ui = H.kit
for _, case in ipairs({ { "with a reading", { value = 42, label = "Queue", unit = "items", at = ctx.t }, "42" },
                        { "before the first refresh", nil, T.L("empty") } }) do
    ctx.cache = { get = function() return case[2] end }
    for _, orient in ipairs({ "portrait", "landscape" }) do
        for _, size in ipairs(M.sizes) do
            for _, inv in ipairs({ false, true }) do
                local box = H.cell(size, orient, inv)
                local name = ("widget %s %s %s%s"):format(case[1], size, orient, inv and " inverted" or "")
                H.widget(T, name, function() return M.widget(ctx, size, box) end, box)
                T.check(name .. ": shows the value", H.has(case[3]))
            end
        end
    end
    for _, b in ipairs({ { w = 584, h = 608, landscape = false }, { w = 784, h = 408, landscape = true } }) do
        local name = "screen " .. case[1] .. " " .. (b.landscape and "landscape" or "portrait")
        H.screen(T, name, function() return M.screens.main(ctx, nil, b) end, b)
        T.check(name .. ": button", H.has(T.L("btn_rearm")))
    end
end
