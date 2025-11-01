-- options
-- local o = vim.o
-- list and map style options helper
local opt = vim.opt

opt.list = true
opt.listchars:append {
  tab = "»-",
  lead = "·",
  trail = "·",
  extends = "»",
  precedes = "«",
}

-- install xclip
opt.clipboard = "unnamedplus"

opt.tabstop = 4
opt.shiftwidth = 4

opt.keymodel = { "startsel", "stopsel" }

opt.autochdir = true
