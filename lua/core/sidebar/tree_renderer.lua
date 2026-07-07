-- Shared sidebar tree renderer.
--
-- This module copies and adapts the renderer line-building flow from
-- nvim-tree.lua's GPL-3.0-or-later renderer:
--   https://github.com/nvim-tree/nvim-tree.lua
--   lua/nvim-tree/renderer/builder.lua
--   lua/nvim-tree/renderer/components/padding.lua
--
-- Original copyright: Copyright © 2019 Yazdani Kiyan
-- License: GNU GPL v3 or later. See the upstream nvim-tree.lua LICENSE.
--
-- The copied shape is intentionally kept generic so File Explorer, Search, and
-- Source Control sidebars can share one renderer:
--   indent markers -> folder arrow -> node icon -> decorators-before -> name -> decorators-after

local M = {}

local function renderer_config()
  local ok, config = pcall(require, "nvim-tree.config")
  local renderer = ok and ((config.g and config.g.renderer) or (config.d and config.d.renderer)) or nil
  return renderer or {}
end

local function icon_config()
  local renderer = renderer_config()
  local icons = renderer.icons or {}
  local glyphs = icons.glyphs or {}
  local folder = glyphs.folder or {}
  local padding = icons.padding or {}

  return {
    arrow_closed = folder.arrow_closed or "",
    arrow_open = folder.arrow_open or "",
    file_default = glyphs.default or "",
    folder_default = folder.default or "",
    folder_open = folder.open or "",
    folder_arrow_padding = padding.folder_arrow or " ",
    icon_padding = padding.icon or " ",
  }
end

function M.icon_padding()
  return icon_config().icon_padding
end

local function indent_width()
  return renderer_config().indent_width or 2
end

function M.folder_arrow(expanded)
  local icons = icon_config()
  return {
    str = (expanded and icons.arrow_open or icons.arrow_closed) .. icons.folder_arrow_padding,
    hl = { expanded and "NvimTreeFolderArrowOpen" or "NvimTreeFolderArrowClosed" },
  }
end

function M.folder_icon(expanded)
  local icons = icon_config()
  return {
    str = expanded and icons.folder_open or icons.folder_default,
    hl = { expanded and "NvimTreeOpenedFolderIcon" or "NvimTreeFolderIcon" },
  }
end

function M.file_icon(path)
  local ok, icon, hl = pcall(function()
    local devicons = require("nvim-web-devicons")
    return devicons.get_icon(vim.fn.fnamemodify(path, ":t"), vim.fn.fnamemodify(path, ":e"), { default = true })
  end)
  if ok and icon then
    return { str = icon, hl = { hl or "NvimTreeFileIcon" } }
  end
  return { str = icon_config().file_default, hl = { "NvimTreeFileIcon" } }
end

-- Adapted from nvim-tree.renderer.components.padding.get_indent_markers.
function M.indent_markers(depth)
  return { str = string.rep(" ", depth * indent_width()), hl = { "NvimTreeIndentMarker" } }
end

local function normalise_highlighted_strings(value)
  if not value then
    return nil
  end
  if type(value) == "string" then
    return { { str = value } }
  end
  return value
end

-- Copied/adapted from nvim-tree.renderer.builder:unwrap_highlighted_strings.
local function unwrap_highlighted_strings(highlighted_strings, line_index, marks)
  if not highlighted_strings then
    return ""
  end

  local str = ""
  for _, v in ipairs(highlighted_strings) do
    if #v.str > 0 then
      if v.hl and type(v.hl) == "table" then
        for _, group in ipairs(v.hl) do
          if group then
            marks[#marks + 1] = {
              line = line_index,
              col = #str,
              end_col = #str + #v.str,
              hl = group,
            }
          end
        end
      end
      str = string.format("%s%s", str, v.str)
    end
  end
  return str
end

-- Copied/adapted from nvim-tree.renderer.builder:format_line.
function M.format_line(opts)
  local added_len = 0
  local function add_to_end(parts, next_parts)
    next_parts = normalise_highlighted_strings(next_parts)
    if not next_parts or vim.tbl_isempty(next_parts) then
      return
    end
    for _, v in ipairs(next_parts) do
      if added_len > 0 then
        table.insert(parts, { str = icon_config().icon_padding })
      end
      table.insert(parts, v)
    end

    -- The first add_to_end doesn't need padding; later decorator groups do.
    added_len = 0
    for _, v in ipairs(next_parts) do
      added_len = added_len + #v.str
    end
  end

  local line = { opts.indent_markers, opts.arrows }
  add_to_end(line, { opts.icon })
  add_to_end(line, opts.decorators_before)
  add_to_end(line, { opts.name })
  add_to_end(line, opts.decorators_after)

  return line
end

function M.render_line(opts, line_index)
  local markers = {}
  local highlighted = M.format_line({
    indent_markers = opts.indent_markers or M.indent_markers(opts.depth or 0),
    arrows = opts.arrows,
    icon = opts.icon,
    decorators_before = opts.decorators_before,
    decorators_after = opts.decorators_after,
    name = opts.name,
  })
  return unwrap_highlighted_strings(highlighted, line_index, markers), markers
end

local function item_path(item, opts)
  if opts.item_path then
    return opts.item_path(item)
  end
  return item.path
end

local function build_file_tree(items, opts)
  local root = { name = "", path = "", dirs = {}, files = {} }
  for _, item in ipairs(items) do
    local path = item_path(item, opts)
    local parts = vim.split(path, "/", { plain = true, trimempty = true })
    local node = root
    local prefix = {}
    for i = 1, #parts - 1 do
      prefix[#prefix + 1] = parts[i]
      local key = table.concat(prefix, "/")
      node.dirs[parts[i]] = node.dirs[parts[i]] or { name = parts[i], path = key, dirs = {}, files = {}, items = {} }
      node = node.dirs[parts[i]]
      node.items[#node.items + 1] = item
    end
    if #parts > 0 then
      local file = vim.tbl_extend("force", {}, item, {
        name = parts[#parts],
        path = path,
        source = item,
      })
      node.files[#node.files + 1] = file
    end
  end
  return root
end

local function sorted_dirs(dirs)
  local out = vim.tbl_values(dirs)
  table.sort(out, function(a, b)
    return a.name < b.name
  end)
  return out
end

local function sorted_files(files)
  table.sort(files, function(a, b)
    return a.name < b.name
  end)
  return files
end

local function default_is_expanded(node)
  return node.expanded ~= false
end

local function default_dir_entry(dir)
  return { dir = dir.path }
end

local function default_file_entry(file)
  return file.source or file
end

local function render_tree_node(node, opts, depth, lines, entries, marks)
  for _, dir in ipairs(sorted_dirs(node.dirs)) do
    local expanded = (opts.dir_expanded or default_is_expanded)(dir)
    local line, line_marks = M.render_line({
      depth = depth,
      arrows = M.folder_arrow(expanded),
      icon = M.folder_icon(expanded),
      decorators_before = opts.dir_decorators_before and opts.dir_decorators_before(dir),
      decorators_after = opts.dir_decorators_after and opts.dir_decorators_after(dir),
      name = { str = dir.name, hl = { "NvimTreeFolderName" } },
    }, #lines + 1)
    lines[#lines + 1] = line
    entries[#lines] = (opts.dir_entry or default_dir_entry)(dir)
    for _, mark in ipairs(line_marks) do
      marks[#marks + 1] = mark
    end
    if expanded then
      render_tree_node(dir, opts, depth + 1, lines, entries, marks)
    end
  end

  for _, file in ipairs(sorted_files(node.files)) do
    local line, line_marks = M.render_line({
      depth = depth,
      arrows = { str = " " .. icon_config().folder_arrow_padding },
      icon = opts.file_icon and opts.file_icon(file) or M.file_icon(file.path),
      decorators_before = opts.file_decorators_before and opts.file_decorators_before(file),
      decorators_after = opts.file_decorators_after and opts.file_decorators_after(file),
      name = { str = file.name, hl = { "NvimTreeFileName" } },
    }, #lines + 1)
    lines[#lines + 1] = line
    entries[#lines] = (opts.file_entry or default_file_entry)(file)
    for _, mark in ipairs(line_marks) do
      marks[#marks + 1] = mark
    end
  end
end

function M.render_file_tree(items, opts)
  opts = opts or {}
  local lines, entries, marks = {}, {}, {}
  render_tree_node(build_file_tree(items, opts), opts, opts.depth or 0, lines, entries, marks)
  return lines, entries, marks
end

return M
