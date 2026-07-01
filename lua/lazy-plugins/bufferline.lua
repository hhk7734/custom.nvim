-- Tracks the previous left-click so a double-click on a tab can toggle its pin.
local last_click = { bufnr = nil, time = 0 }

return {
  -- https://github.com/akinsho/bufferline.nvim
  "akinsho/bufferline.nvim",

  lazy = false,

  -- For file icons.
  dependencies = {
    "nvim-tree/nvim-web-devicons",
  },

  opts = {
    options = {
      -- Show open buffers as tabs (VS Code / Sublime style).
      mode = "buffers",
      diagnostics = "nvim_lsp",
      show_buffer_close_icons = true,
      show_close_icon = false,
      -- Single left click selects the buffer; double click toggles its pin.
      -- bufferline calls this on every left click (it does not expose the
      -- click count), so we detect a double click by timing.
      left_mouse_command = function(bufnr)
        local now = (vim.uv or vim.loop).now()
        local is_double = last_click.bufnr == bufnr and (now - last_click.time) < 300
        last_click.bufnr = bufnr
        -- Reset the timer after a double so a 3rd quick click starts fresh.
        last_click.time = is_double and 0 or now
        vim.schedule(function()
          vim.cmd("buffer " .. bufnr)
          if is_double then
            vim.cmd("BufferLineTogglePin")
          end
        end)
      end,
      -- Reserve the left side for nvim-tree instead of drawing over it.
      offsets = {
        {
          filetype = "NvimTree",
          text = "File Explorer",
          text_align = "center",
          separator = true,
        },
      },
    },
  },

  keys = {
    { "]b", "<cmd>BufferLineCycleNext<CR>", desc = "next buffer" },
    { "[b", "<cmd>BufferLineCyclePrev<CR>", desc = "prev buffer" },
    { "]B", "<cmd>BufferLineMoveNext<CR>", desc = "move buffer right" },
    { "[B", "<cmd>BufferLineMovePrev<CR>", desc = "move buffer left" },
    { "<leader>bb", "<cmd>BufferLinePick<CR>", desc = "pick buffer" },
    { "<leader>bp", "<cmd>BufferLineTogglePin<CR>", desc = "toggle pin buffer" },
    { "<leader>bd", "<cmd>bdelete<CR>", desc = "delete buffer" },
    { "<leader>bo", "<cmd>BufferLineCloseOthers<CR>", desc = "close other buffers" },
  },
}
