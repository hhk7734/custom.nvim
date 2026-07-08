-- Tracks the previous left-click so a double-click on a tab can toggle its pin.
local last_click = { bufnr = nil, time = 0 }

-- bufferline's offset matching only inspects the first and last windows of
-- the top-level layout row, so the sidebar (NvimTree or gitpanel, sitting
-- between the activity bar and the editor) can never match its own offsets
-- entry. The activity bar's entry absorbs the sidebar's width as padding
-- instead, synced by an autocmd below.
local SIDEBAR_TITLES = {
  NvimTree = "File Explorer",
  gitpanel = "Source Control",
  searchpanel = "Search",
  searchpanelinput = "Search",
}

local function sidebar_win()
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    local ft = vim.bo[vim.api.nvim_win_get_buf(win)].filetype
    if SIDEBAR_TITLES[ft] and vim.api.nvim_win_get_config(win).relative == "" then
      return win, ft
    end
  end
  return nil, nil
end

local function sidebar_padding()
  local win = sidebar_win()
  if not win then
    return 0
  end
  return vim.api.nvim_win_get_width(win) + 1 -- +1 for the window separator
end

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
      name_formatter = function(buf)
        local bufnr = buf.id or buf.bufnr
        if bufnr and vim.b[bufnr].sidebar_tab_label then
          return vim.b[bufnr].sidebar_tab_label
        end
        return nil
      end,
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
          local handled = false
          local ok, preview = pcall(require, "core.sidebar.preview")
          if ok then
            handled = preview.show_existing_pair(bufnr)
          end
          if not handled then
            vim.cmd("buffer " .. bufnr)
          end
          if is_double then
            vim.cmd("BufferLineTogglePin")
          end
        end)
      end,
      -- Reserve the left side for the activity bar and its sidebar (nvim-tree
      -- or the git panel) instead of drawing over them. While the bar is open
      -- it is the leftmost window and absorbs the sidebar's width via
      -- sidebar_padding; with the bar closed the sidebar itself is leftmost
      -- and its own fallback entry takes over. Entries never both match
      -- (bufferline only tests the layout row's first/last windows, and the
      -- sidebar is a middle window when the bar is open). The padding
      -- autocmd below writes offsets[1]; keep the activitybar entry first.
      offsets = {
        {
          filetype = "activitybar",
          text = function()
            local _, ft = sidebar_win()
            return SIDEBAR_TITLES[ft] or ""
          end,
          text_align = "center",
          separator = true,
        },
        {
          filetype = "NvimTree",
          text = "File Explorer",
          text_align = "center",
          separator = true,
        },
        {
          filetype = "gitpanel",
          text = "Source Control",
          text_align = "center",
          separator = true,
        },
        {
          filetype = "searchpanelinput",
          text = "Search",
          text_align = "center",
          separator = true,
        },
      },
    },
  },

  config = function(_, opts)
    require("bufferline").setup(opts)

    -- Keep the offset padding in sync with the sidebar window's presence/width.
    local function sync_padding()
      local offsets = require("bufferline.config").options.offsets
      -- left_size excludes the separator glyph, which renders over the
      -- window-separator column; the rendered region ends at editor_col
      -- and the metric reads editor_col - 1. Do not "compensate" for it.
      local pad = sidebar_padding()
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
