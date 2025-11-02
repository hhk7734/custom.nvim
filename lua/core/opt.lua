-- options
-- local o = vim.o
-- list and map style options helper
local opt = vim.opt

opt.list = true
opt.listchars:append({
  tab = "»-",
  lead = "·",
  trail = "·",
  extends = "»",
  precedes = "«",
})

opt.clipboard = "unnamedplus" -- install xclip
opt.cursorline = true
opt.cursorlineopt = "number"

opt.tabstop = 4
opt.shiftwidth = 4

opt.keymodel = { "startsel", "stopsel" }

opt.autochdir = true

-- Numbers
opt.number = true
opt.numberwidth = 2
opt.ruler = false
