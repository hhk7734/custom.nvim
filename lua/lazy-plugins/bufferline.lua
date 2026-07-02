-- Tracks the previous left-click so a double-click on a tab can toggle its pin.
local last_click = { bufnr = nil, time = 0 }

-- bufferline's offset matching only inspects the first and last windows of
-- the top-level layout row, so the tree (sitting between the activity bar and
-- the editor) can never match its own offsets entry. The activity bar's entry
-- absorbs the tree's width as padding instead, synced by an autocmd below.
local function tree_padding()
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if
      vim.bo[vim.api.nvim_win_get_buf(win)].filetype == "NvimTree"
      and vim.api.nvim_win_get_config(win).relative == ""
    then
      return vim.api.nvim_win_get_width(win) + 1 -- +1 for the window separator
    end
  end
  return 0
end

-- bufferline/offset.lua's get_section_text() appends the "separator = true"
-- glyph below onto the rendered offset text, but its M.get() sizes
-- left_size/total_size from `win_width + padding` alone and never credits
-- that glyph. Without this, the offset's reported size trails the editor's
-- real start column by one. Compensate with one extra column of padding.
local SEPARATOR_CREDIT = 1

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
      -- Reserve the left side for the activity bar and nvim-tree instead of
      -- drawing over them (see tree_padding above for why a single entry).
      offsets = {
        {
          filetype = "activitybar",
          text = function()
            return tree_padding() > 0 and "File Explorer" or ""
          end,
          text_align = "center",
          separator = true,
        },
      },
    },
  },

  config = function(_, opts)
    require("bufferline").setup(opts)

    -- Keep the offset padding in sync with the tree window's presence/width.
    local function sync_padding()
      local offsets = require("bufferline.config").options.offsets
      local pad = tree_padding() + SEPARATOR_CREDIT
      if offsets and offsets[1] and offsets[1].padding ~= pad then
        offsets[1].padding = pad
        vim.cmd.redrawtabline()
      end
    end

    sync_padding()
    vim.api.nvim_create_autocmd({ "WinNew", "WinClosed", "WinResized" }, {
      group = vim.api.nvim_create_augroup("bufferline_activitybar", {}),
      callback = function()
        vim.schedule(sync_padding)
      end,
    })
  end,

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
