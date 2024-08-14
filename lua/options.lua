require "nvchad.options"

-- options
local o = vim.o
-- list and map style options helper
local opt = vim.opt

o.list = true
opt.listchars:append {
  tab = "»-",
  lead = "·",
  trail = "·",
  extends = "»",
  precedes = "«",
}

-- install xclip
o.clipboard = "unnamedplus"

o.tabstop = 4
o.shiftwidth = 4

o.keymodel = "startsel,stopsel"

o.autochdir = true

vim.filetype.add {
  extension = {
    mdx = "mdx",
  },
}
