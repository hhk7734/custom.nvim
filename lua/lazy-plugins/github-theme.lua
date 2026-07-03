return {
  -- https://github.com/projekt0n/github-nvim-theme
  "projekt0n/github-nvim-theme",

  name = "github-theme",

  tag = "v1.1.2",

  lazy = false,

  -- Load before every other plugin so highlight groups resolve against the
  -- final palette.
  priority = 1000,

  config = function()
    require("github-theme").setup({})
    vim.cmd.colorscheme("github_dark_default")
  end,
}
