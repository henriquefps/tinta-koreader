-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (C) 2026 Tinta contributors
-- the CSV log (D2): append on change, reopen, bounded size (ported), and the one-time import of the old log (16.4)
local T = ...
local check, eq = T.check, T.eq
local Log = require("apps/bateria/csvlog")
local B = require("apps/bateria/logic")
local function R(pct, chg, wifi, extra)
    local r = { pct = pct, charging = chg or false, wifi = wifi or false }
    for k, v in pairs(extra or {}) do r[k] = v end
    return r
end

eq("file name (16.4)", Log.FILE, "tinta-battery.csv")
eq("bounds: 2800 -> 2000", Log.TRIM_AT .. "->" .. Log.MAX_LINES, "2800->2000")

-- file: appends only on change, survives a reopen, stays small
local path = T.tmp()
local st = Log.open(path)
check("bat file: written sample returned", st:sample(1000, R(90, false, true)) ~= nil)
eq("bat file: unchanged -> nil", st:sample(1060, R(90, false, true)), nil)
st:sample(1120, R(89, false, true))
local lines = T.lines(path)
eq("bat file: header + 2 lines", #lines, 3)
eq("bat file: header", lines[1], B.HEADER)
eq("bat file: wifi column", lines[2], "1000,90,0,1,,,,")
st:sample(1180, R(88, false, true, { mv = 3900, ma = -45, mah = 800, temp = 27 }))
lines = T.lines(path)
eq("bat file: gauge columns", lines[#lines], "1180,88,0,1,3900,-45,800,27")
eq("bat file: nlines", st.nlines, 3)
st:sample(1240, R(86.6, false, true))
eq("bat file: pct rounded", T.lines(path)[5]:match("^%d+,(%d+)"), "87")
local st3 = Log.open(path)
eq("bat file: reload", #st3.samples, 4)
check("bat file: gauge kept in memory", st3.samples[3].ma == -45 and st3.samples[3].mah == 800)
local st2 = Log.open(path)
for i = 1, 9000 do st2:sample(2000 + i * 60, R(90 - (i % 80), i % 7 == 0, i % 2 == 0, { mv = 3900, ma = -48, mah = 800, temp = 25 })) end
local n, bytes = 0, 0
for _, l in ipairs(T.lines(path)) do n = n + 1; bytes = bytes + #l + 1 end
check("bat file: line count bounded", n <= Log.TRIM_AT + 1, n)
check("bat file: stays under ~100 KB", bytes < 100 * 1024, bytes)
check("bat file: memory bounded", #st2.samples <= B.MAX_SAMPLES)
check("bat file: not broken", not st2.broken)
os.remove(path)

-- a log with an older header (4 columns) is rewritten once and keeps its samples
local oldp = T.tmp()
local fh = io.open(oldp, "w")
fh:write("# unix_time,percent,charging,wifi\n1000,90,0,1\n1100,89,0,1\n")
fh:close()
local so = Log.open(oldp)
eq("bat migrate: samples kept", #so.samples, 2)
eq("bat migrate: new header", T.lines(oldp)[1], B.HEADER)
os.remove(oldp)

-- an oversized file is trimmed on open
local big = T.tmp()
fh = io.open(big, "w")
fh:write(B.HEADER, "\n")
for i = 1, 3000 do fh:write(B.format_line(i * 60, 50, false, false), "\n") end
fh:close()
local sb = Log.open(big)
eq("bat trim on open", sb.nlines, Log.MAX_LINES)
eq("bat trim keeps the newest", T.lines(big)[#T.lines(big)], B.format_line(3000 * 60, 50, false, false))
eq("bat trim memory", #sb.samples, B.MAX_SAMPLES)
os.remove(big)

-- no path / unwritable path: never raises, the estimate still works from memory
local mem = Log.open(nil)
local ok = pcall(function() for i = 0, 9 do mem:sample(i * 360, R(90 - i)) end end)
eq("bat mem: no raise", ok, true)
check("bat mem: estimate from memory", B.estimate(mem.samples, 3600, 80, false) ~= nil)
local bad = Log.open("/nonexistent-dir/xx/battery.csv")
eq("bat bad path: broken", bad.broken, true)
eq("bat bad path: no raise", pcall(function() bad:sample(1, R(50)) end), true)
eq("bat bad path: memory kept", #bad.samples, 1)

---------------------------------------------------------------- import of the old log (16.4)

local dir_old, dir_new = T.tmp(), T.tmp()
eq("import: no legacy", select(2, Log.import(dir_old, dir_new)), "no_legacy")
eq("import: no file created without legacy", io.open(dir_new, "r"), nil)

-- the old log as the plugin wrote it: old 4-column lines, then gauge lines, a damaged line
fh = io.open(dir_old, "w")
fh:write("# unix_time,percent,charging,wifi,mv,ma,mah,temp_c\n",
    "1791983035,99,1,1\n", "1791983066,99,0,1\n", "garbage\n",
    "1792089259,79,0,1,3949,-62,727,23\n", "1792089867,79,0,1,3947,-48,720,22\n")
fh:close()
local before = table.concat(T.lines(dir_old), "\n")
-- the Tinta already logged a bit (it ran next to the old plugin): one line at the same time as an old one
fh = io.open(dir_new, "w")
fh:write(B.HEADER, "\n", "1792089867,79,0,1,3947,-50,720,22\n", "1792090000,78,0,1,3943,-59,718,22\n")
fh:close()
local added = Log.import(dir_old, dir_new)
eq("import: old lines added", added, 3)
local merged = T.lines(dir_new)
eq("import: header", merged[1], B.HEADER)
eq("import: merged count", #merged, 1 + 5)
eq("import: sorted, oldest first", merged[2], "1791983035,99,1,1")
eq("import: same time keeps the Tinta line", merged[5], "1792089867,79,0,1,3947,-50,720,22")
eq("import: newest last", merged[6], "1792090000,78,0,1,3943,-59,718,22")
eq("import: old file untouched", table.concat(T.lines(dir_old), "\n"), before)
local reopened = Log.open(dir_new)
eq("import: reopen reads all", #reopened.samples, 5)
eq("import: second import adds nothing", Log.import(dir_old, dir_new), 0)
eq("import: still 5 samples", #Log.open(dir_new).samples, 5)
os.remove(dir_old); os.remove(dir_new)

-- a big old log is bounded like the new one
local bo, bn = T.tmp(), T.tmp()
fh = io.open(bo, "w")
for i = 1, 2600 do fh:write(B.format_line(i * 60, 50, false, true), "\n") end
fh:close()
eq("import big: all counted", Log.import(bo, bn), 2600)
local bl = T.lines(bn)
eq("import big: bounded to MAX_LINES", #bl, Log.MAX_LINES + 1)
eq("import big: keeps the newest", bl[#bl], B.format_line(2600 * 60, 50, false, true))
os.remove(bo); os.remove(bn)

-- unwritable destination
local wo = T.tmp()
fh = io.open(wo, "w"); fh:write("1000,50,0,0\n"); fh:close()
eq("import: write failure", select(2, Log.import(wo, "/nonexistent-dir/xx/tinta-battery.csv")), "write")
os.remove(wo)
