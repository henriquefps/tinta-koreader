-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (C) 2026 Tinta contributors
-- the widget in both sizes and the screen, portrait and landscape, built with the real ui/kit over stubbed widgets:
-- they must build, paint and stay inside their box (R-W1)
local T = ...
-- install() once per process: ui/kit keeps the first stubs it required, so every suite shares one H
MODELO_H = MODELO_H or require("uistub").install()
local H = MODELO_H
local M = require("apps/_modelo/init")
local ctx = T.ctx()
ctx.ui = H.kit
ctx.cache = { get = function() return { count = 12, at = ctx.t } end }
for _, orient in ipairs({ "portrait", "landscape" }) do
    for _, size in ipairs(M.sizes) do
        for _, inv in ipairs({ false, true }) do
            local box = H.cell(size, orient, inv)
            local name = ("widget %s %s%s"):format(size, orient, inv and " inverted" or "")
            H.widget(T, name, function() return M.widget(ctx, size, box) end, box)
            T.check(name .. ": shows the counter", H.has("12"))
        end
    end
end
for _, b in ipairs({ { w = 584, h = 608, landscape = false }, { w = 784, h = 408, landscape = true } }) do
    local name = "screen " .. (b.landscape and "landscape" or "portrait")
    H.screen(T, name, function() return M.screens.main(ctx, nil, b) end, b)
    T.check(name .. ": button", H.has(T.L("btn_reset")))
end
