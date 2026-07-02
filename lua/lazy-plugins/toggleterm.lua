return {
  -- https://github.com/akinsho/toggleterm.nvim
  "akinsho/toggleterm.nvim",

  cmd = { "ToggleTerm", "TermExec" },

  keys = {
    -- Note: some terminal emulators do not transmit Ctrl+` (it needs the
    -- extended-keys protocol). If nothing happens on keypress, replace
    -- "<C-`>" with "<C-\>" here — everything else stays the same.
    { "<C-`>", "<cmd>ToggleTerm<CR>", mode = { "n", "t" }, desc = "toggle terminal" },
  },

  opts = {
    direction = "horizontal",
    -- Must match edgy.lua's bottom size.height for ft "toggleterm"; edgy
    -- re-applies its own height when it docks the window.
    size = 12,
  },
}
