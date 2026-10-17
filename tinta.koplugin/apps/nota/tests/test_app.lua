-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (C) 2026 Tinta contributors
-- init.lua over a fake ctx: reading once, editing through ctx.input, validation, clearing with confirmation,
-- and the text never reaching the log or a notification
local T = ...
local check, eq = T.check, T.eq
local M = require("apps/nota/init")
local Settings = require("core/settings")

for _, f in ipairs(M.settings) do check("manifest: default of " .. f.key .. " validates", Settings.validate(f, f.default) == true) end
check("manifest: max_chars range", Settings.validate(M.settings[1], 10) == nil and Settings.validate(M.settings[1], 2001) == nil)
check("manifest: registry accepts it", require("core/registry").validate(M) == true)
eq("manifest: sizes", table.concat(M.sizes, ","), "2x2,4x2,2x4,4x4")
check("manifest: local, no refresh", M.net == false and M.refresh == nil)

local SECRET = "senha do wifi: 12345"
local ctx = T.ctx()
local logged = {}
ctx.log = function(m) logged[#logged + 1] = m end
-- a ui kit that only records the buttons
local calls = {}
local function w() return { getSize = function() return { w = 10, h = 10 } end } end
ctx.ui = { theme = require("ui/theme"), fg = function() return "B" end,
    text = w, textbox = w, box = function(o) return o end, space = w, vstack = w,
    button_row = function(specs) for _, s in ipairs(specs) do calls[#calls + 1] = s end; return w() end }
local function build() calls = {}; M.screens.main(ctx, nil, { w = 584, h = 608, landscape = false }) end
local function tap(label) for _, s in ipairs(calls) do if s[1] == label then s[2](); return true end end return false end

ctx.data_store.text = "nota antiga"
M.init(ctx)
eq("init reads the store once", ctx.data_reads, 1)
build(); build()
eq("rendering does not read the store again", ctx.data_reads, 1)
check("with a note: Editar and Limpar", (function() build(); return tap("Limpar") end)())

build(); check("Editar", tap("Editar"))
local inp = ctx.inputs[1]
eq("input: previous text offered", inp.value, "nota antiga")
check("input: multiline", inp.opts.multiline == true)
check("input: save", inp.on_save("  " .. SECRET .. "\r\n") == true)
eq("saved normalised", ctx.data_store.text, SECRET)
local ok, msg = inp.on_save(("x"):rep(501))
check("too long refused with the counts", ok == false and msg == "Nota longa demais: 501 de 500 caracteres", msg)
eq("a refused save keeps the old text", ctx.data_store.text, SECRET)
ctx.settings_store.max_chars = 60
build(); tap("Editar")
local ok2, msg2 = ctx.inputs[2].on_save(("x"):rep(61))
check("max_chars setting applies", ok2 == false and msg2:find("61 de 60") ~= nil, msg2)

-- Limpar asks first
build(); check("Limpar", tap("Limpar"))
check("clear: confirmation asked", ctx.confirmed ~= nil and ctx.confirmed.title == "Limpar a nota")
eq("clear: nothing deleted before OK", ctx.data_store.text, SECRET)
ctx.confirmed.ok()
eq("clear: deleted after OK", ctx.data_store.text, nil)
check("clear: toast and redraw", #ctx.toasts == 1 and ctx.redraws == 1)
build()
check("empty: Escrever, no Limpar", tap("Escrever") and not tap("Limpar"))
ctx.inputs[3].on_save("")
eq("saving an empty text keeps it empty", ctx.data_store.text, nil)

-- privacy: no log line, no notification carries the text
local leaked = false
for _, l in ipairs(logged) do if tostring(l):find(SECRET, 1, true) then leaked = true end end
check("the text is never logged", not leaked and #logged == 0)
eq("no notifications", #ctx.notes, 0)
