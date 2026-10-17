-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (C) 2026 Tinta contributors
-- Tinta: screen-size independence (spec 6.1). Runs the headless smokes (tests/tinta_ui_smoke.lua and the UI smokes of
-- apps that have one, portrait and landscape inside each run) at every screen size the platform supports and compares what they drew:
--   * every size passes the whole smoke (every box inside the screen, the letterbox white, no Lua error);
--   * proportionality: on screens that are exactly 600x800 x k (k = 2, 3), with the linear fake font, every draw of
--     every step is the KT3's times k (same rects, same texts, within 2k px of rounding), so a loose pixel constant
--     is caught (draws of one pixel row, the spans of icons and charts, follow the size and are left out);
--   * text fit: no text is cut by its box more than on the KT3 in the same step (6 % of rounding allowed);
--   * touch targets: the smallest tappable box of each screen is at least the KT3's times the scale.
-- The KT3 itself is pinned by the hash baselines inside the smokes (tests/fixtures/kt3-*trace.txt).
--   luajit tests/tinta_ui_scales.lua       (from the repo root)
local passed, failed = 0, 0
local function check(name, cond, extra)
    if cond then passed = passed + 1
    else failed = failed + 1; print("FAIL - " .. name .. (extra and (" :: " .. tostring(extra)) or "")) end
end

local SIZES = { "600x800", "758x1024", "1072x1448", "1264x1680", "1404x1872", "1860x2480" }
local EXACT = { ["1200x1600"] = 2, ["1800x2400"] = 3 }   -- exact multiples of the design: proportionality is checked here
local SUITES = { { name = "tinta", file = "tests/tinta_ui_smoke.lua" } }
for _, su in ipairs(dofile("tests/testapps.lua").smokes) do SUITES[#SUITES + 1] = su end   -- (UI smokes of apps kept out of the public tree)

local base = os.tmpname(); os.remove(base); os.execute('mkdir -p "' .. base .. '"')

-- runs a smoke at `size`; returns the trace dir and the output
local function run(suite, size, extra_env)
    local dir = base .. "/" .. suite.name .. "-" .. size .. (extra_env and "-lin" or "")
    os.execute('mkdir -p "' .. dir .. '"')
    local cmd = ('SMOKE_SCREEN=%s SMOKE_TRACE_DIR="%s" QUIET=1 %s luajit %s 2>&1'):format(size, dir, extra_env or "", suite.file)
    local p = io.popen(cmd)
    local out = p:read("*a")
    p:close()
    return dir, out
end

-- Spans (icons, chart, rings) paint one rect per pixel row: their count follows the size, so only the 1 px rows are
-- left out of the proportionality comparison (every other rect, border and text is compared)
-- A diagonal stroke drawn as t x t squares one pixel apart (the X of a failed child square, t <= 6 up to x3) has one
-- rect per pixel as well, so small squares are left out too.
local function is_span(l)
    if l:match("^R %-?%d+ %-?%d+ %-?%d+ 1 ") then return true end
    local w, h = l:match("^R %-?%d+ %-?%d+ (%d+) (%d+) ")
    return w ~= nil and w == h and tonumber(w) <= 6
end

local function read_step(dir, i)
    local fh = io.open(("%s/%03d.txt"):format(dir, i))
    if not fh then return nil end
    local s = { name = fh:read("*l"), lines = {}, cut = {}, touch = nil }
    for l in fh:lines() do
        if l:sub(1, 7) == "#touch " then s.touch = tonumber(l:sub(8))
        elseif l:sub(1, 5) == "#cut " then
            local ratio, text = l:sub(6):match("^(%S+) (.*)$")
            s.cut[text] = tonumber(ratio)
        elseif not is_span(l) then s.lines[#s.lines + 1] = l end
    end
    fh:close()
    return s
end

local function words(l)
    local t = {}
    for w in l:gmatch("%S+") do t[#t + 1] = w end
    return t
end

local function count_steps(dir)
    local n = 0
    while read_step(dir, n + 1) do n = n + 1 end
    return n
end

-- numeric fields of a trace line: R x y w h c | Q x y w h c r | B x y w h b c r | T x y w h size b color text | X x y w h size ...
local NUM = { R = 4, Q = 4, B = 5, T = 5, X = 5 }
local TEXT_PAT = "^%a [^ ]+ [^ ]+ [^ ]+ [^ ]+ [^ ]+ [^ ]+ [^ ]+ [^ ]+ (.*)$"

for _, suite in ipairs(SUITES) do
    local ran = {}
    for _, size in ipairs(SIZES) do
        local dir, out = run(suite, size)
        ran[size] = dir
        check(suite.name .. " " .. size .. ": smoke passes", out:find(", 0 failed", 1, true) ~= nil, out:sub(-300))
        if out:find(", 0 failed", 1, true) == nil then print(out:sub(1, 1500)) end
    end
    local ref = ran["600x800"]
    local n_steps = count_steps(ref)
    check(suite.name .. ": the KT3 run recorded steps", n_steps > 40, n_steps)

    for _, size in ipairs(SIZES) do
        if size ~= "600x800" then
            local w, h = size:match("(%d+)x(%d+)")
            local s_scale = math.min(tonumber(w) / 600, tonumber(h) / 800)
            local bad_cut, bad_touch = {}, {}
            for i = 1, n_steps do
                local a, b = read_step(ref, i), read_step(ran[size], i)
                if not b or a.name ~= b.name then
                    check(suite.name .. " " .. size .. ": step " .. i .. " exists with the same name", false, b and b.name)
                    break
                end
                -- text fit: a text may be cut (the real TextWidget ellipsises it) only as much as on the KT3 in the same
                -- step, plus 6 % for the rounding of the font size and of the box
                for t, ratio in pairs(b.cut) do
                    if ratio > math.max(a.cut[t] or 1, 1) + 0.06 then bad_cut[#bad_cut + 1] = ("%s: '%s' x%.2f"):format(b.name, t, ratio) end
                end
                -- touch targets: >= the KT3's smallest, scaled (1 px of rounding)
                if a.touch and b.touch and b.touch < math.floor(a.touch * s_scale) - 1 then
                    bad_touch[#bad_touch + 1] = ("%s: %d < %d x %.2f"):format(b.name, b.touch, a.touch, s_scale)
                end
            end
            check(suite.name .. " " .. size .. ": no text cut that the KT3 does not cut", #bad_cut == 0,
                bad_cut[1] and (#bad_cut .. " e.g. " .. bad_cut[1]))
            check(suite.name .. " " .. size .. ": touch targets keep the KT3 proportion", #bad_touch == 0,
                bad_touch[1] and (#bad_touch .. " e.g. " .. bad_touch[1]))
        end
    end

    -- proportionality on exact multiples of the design, linear fake font (no rounding noise from the text)
    local lin_ref = run(suite, "600x800", "SMOKE_FONT=linear")
    check(suite.name .. ": the linear-font KT3 run has the same steps", count_steps(lin_ref) == n_steps, count_steps(lin_ref))
    for size, k in pairs(EXACT) do
        local dir, out = run(suite, size, "SMOKE_FONT=linear")
        -- (the linear font is 1.5 em tall, the apps assume ~1.4: its own fit checks are not asked to pass here)
        check(suite.name .. " " .. size .. " (linear font): the smoke ran", out:find("passed, ", 1, true) ~= nil, out:sub(-300))
        local bad = {}
        for i = 1, n_steps do
            local a, b = read_step(lin_ref, i), read_step(dir, i)
            if not b or a.name ~= b.name then bad[#bad + 1] = "step " .. i .. " missing"; break end
            if #a.lines ~= #b.lines then
                bad[#bad + 1] = ("%s: %d draws vs %d on the KT3"):format(b.name, #b.lines, #a.lines)
            else
                for j = 1, #a.lines do
                    local wa, wb = words(a.lines[j]), words(b.lines[j])
                    local ok = wa[1] == wb[1]
                    for f = 2, (NUM[wa[1]] or 0) + 1 do
                        local va, vb = tonumber(wa[f]), tonumber(wb[f])
                        if not (va and vb) or math.abs(vb - va * k) > 2 * k then ok = false end
                    end
                    if (wa[1] == "T" or wa[1] == "X") and a.lines[j]:match(TEXT_PAT) ~= b.lines[j]:match(TEXT_PAT) then ok = false end
                    if not ok then
                        bad[#bad + 1] = ("%s: draw %d: %s  vs  %s x%d"):format(b.name, j, b.lines[j], a.lines[j], k)
                        break
                    end
                end
            end
        end
        check(suite.name .. " " .. size .. ": every draw is the KT3's x" .. k, #bad == 0, bad[1] and (#bad .. " steps, e.g. " .. bad[1]))
        for i = 1, math.min(#bad, 12) do print("   " .. bad[i]) end
    end
end

-- first run, privacy and text size (spec 7.5, 11.8, 6.1): the scenario of tests/tinta_ui_firstrun.lua at every size, and
-- the whole Tinta smoke with "Tamanho do texto: grande" (every box inside the screen, no Lua error, flows still work)
do
    local function run_cmd(cmd)
        local p = io.popen(cmd .. " 2>&1")
        local out = p:read("*a")
        p:close()
        return out
    end
    local sizes = {}
    for _, size in ipairs(SIZES) do sizes[#sizes + 1] = size end
    for size in pairs(EXACT) do sizes[#sizes + 1] = size end
    for _, size in ipairs(sizes) do
        local out = run_cmd(('SMOKE_SCREEN=%s QUIET=1 luajit tests/tinta_ui_firstrun.lua'):format(size))
        check("firstrun scenario " .. size .. ": passes", out:find(", 0 failed", 1, true) ~= nil, out:sub(-400))
        out = run_cmd(('SMOKE_SCREEN=%s SMOKE_TEXT=large QUIET=1 luajit tests/tinta_ui_smoke.lua'):format(size))
        check("tinta smoke " .. size .. " with large text: passes", out:find(", 0 failed", 1, true) ~= nil, out:sub(-400))
        if out:find(", 0 failed", 1, true) == nil then print(out:sub(1, 1200)) end
    end
end

os.execute('rm -rf "' .. base .. '"')
print(("tinta ui scales: %d passed, %d failed"):format(passed, failed))
if failed > 0 then os.exit(1) end
