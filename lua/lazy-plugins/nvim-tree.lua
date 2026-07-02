return {
  -- https://github.com/nvim-tree/nvim-tree.lua
  "nvim-tree/nvim-tree.lua",

  lazy = false,

  -- For file icons.
  dependencies = {
    "nvim-tree/nvim-web-devicons",
  },

  opts = {
    view = {
      width = 30,
    },
    filters = {
      custom = { "^.git$" },
    },
    on_attach = function(bufnr)
      local api = require("nvim-tree.api")

      local function opts(desc)
        return { desc = "nvim-tree: " .. desc, buffer = bufnr, noremap = true, silent = true, nowait = true }
      end

      -- default mappings
      api.config.mappings.default_on_attach(bufnr)

      -- custom mappings
      vim.keymap.set("n", "?", api.tree.toggle_help, opts("Help"))
    end,
  },

  config = function(_, opts)
    -- disable netrw at the very start of your init.lua
    vim.g.loaded_netrw = 1
    vim.g.loaded_netrwPlugin = 1

    require("nvim-tree").setup(opts)

    -- keymap to focus or toggle nvim-tree
    local nvimTreeFocusOrToggle = function()
      local nvimTree = require("nvim-tree.api")
      local currentBuf = vim.api.nvim_get_current_buf()
      local currentBufFt = vim.api.nvim_get_option_value("filetype", { buf = currentBuf })
      if currentBufFt == "NvimTree" then
        nvimTree.tree.toggle()
      else
        nvimTree.tree.focus()
      end
    end
    vim.keymap.set("n", "<C-Left>", nvimTreeFocusOrToggle, { desc = "focus nvim-tree" })

    -- close vim if nvim-tree is the last window
    vim.api.nvim_create_autocmd({ "BufEnter", "QuitPre" }, {
      nested = false,
      callback = function(e)
        local tree = require("nvim-tree.api").tree

        -- Nothing to do if tree is not opened
        if not tree.is_visible() then
          return
        end

        -- How many "real" windows do we have? (excluding e.g. incline status
        -- window and the activity bar)
        local winCount = 0
        for _, winId in ipairs(vim.api.nvim_list_wins()) do
          local ft = vim.bo[vim.api.nvim_win_get_buf(winId)].filetype
          if vim.api.nvim_win_get_config(winId).focusable and ft ~= "activitybar" then
            winCount = winCount + 1
          end
        end

        -- We want to quit and only one window besides tree is left
        if e.event == "QuitPre" and winCount == 2 then
          vim.api.nvim_cmd({ cmd = "qall" }, {})
        end

        -- The tree is the only real window left (e.g. after <C-w>c on the
        -- last file window): reopen the alternate buffer in a main window.
        if e.event == "BufEnter" and winCount == 1 then
          vim.defer_fn(function()
            vim.cmd("botright vsplit")
            local alt = vim.fn.bufnr("#")
            if alt > 0 and vim.fn.buflisted(alt) == 1 then
              vim.api.nvim_set_current_buf(alt)
            else
              vim.cmd("enew")
            end
          end, 10)
        end
      end,
    })
  end,
}
