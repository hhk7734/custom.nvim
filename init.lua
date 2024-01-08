local opt = vim.opt

-- local autocmd = vim.api.nvim_create_autocmd

-- Auto resize panes when resizing nvim window
-- autocmd("VimResized", {
--   pattern = "*",
--   command = "tabdo wincmd =",
-- })

opt.list = true
opt.listchars:append {
  tab = '»-',
  lead = '·',
  trail = '·',
  extends = '»',
  precedes = '«',
}

opt.clipboard = 'unnamedplus'

opt.tabstop = 4
opt.shiftwidth = 4

vim.filetype.add({
  extension = {
    mdx = 'mdx'
  }
})
