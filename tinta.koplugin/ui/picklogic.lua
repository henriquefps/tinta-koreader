-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (C) 2026 Tinta contributors
-- Tinta: choice popup logic (6.10), pure: options, the current mark, paging. ui/picker.lua draws it.
local Paging = require("ui/paging")

local M = {}

-- Options as the popup shows them. `options` is a list of values (label = tostring) or of
-- { value, label?, sub? } tables (`value` may also sit at [1]); anything else is left out.
function M.normalize(options)
    local out = {}
    for _, o in ipairs(options or {}) do
        if type(o) == "table" then
            local value = o.value
            if value == nil then value = o[1] end
            if value ~= nil then
                out[#out + 1] = { value = value, label = tostring(o.label or o[2] or value), sub = o.sub }
            end
        elseif o ~= nil then
            out[#out + 1] = { value = o, label = tostring(o) }
        end
    end
    return out
end

function M.is_current(opt, current) return current ~= nil and opt.value == current end

-- 1-based position of the current value, nil when it is not among the options
function M.index_of(options, current)
    for i, o in ipairs(options) do if M.is_current(o, current) then return i end end
    return nil
end

-- Rows per page. avail = height for the rows and the pager, row_h/gap as in the lists, pager_h the height the page
-- control takes (with its gap). Everything on one page when it fits; otherwise the pager's height comes off first.
-- At least one row.
function M.per_page(n, avail, row_h, gap, pager_h)
    local per = Paging.fit(avail, row_h, gap)
    if n > per then per = Paging.fit(avail - pager_h, row_h, gap) end
    return per
end

-- 0-based page that holds the current value (the popup opens there)
function M.start_page(options, current, per)
    local i = M.index_of(options, current)
    if not i then return 0 end
    return math.floor((i - 1) / math.max(1, per))
end

-- the options of `page` (0-based, clamped), the clamped page and the page count
function M.page(options, page, per) return Paging.slice(options, page, per) end

return M
