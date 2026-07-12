local columns = require('oil.columns')
local constants = require('oil.constants')
local fs = require('oil.fs')
local parser = require('oil.mutator.parser')
local util = require('oil.util')

local M = {}

local FIELD_TYPE = constants.FIELD_TYPE

local default_types = {
  file = true,
  link = true,
}

local path_sep_pattern = fs.is_windows and '[/\\]' or '/'

local function build_type_filter(types)
  if not types then
    return default_types
  end
  local ret = {}
  for _, entry_type in ipairs(types) do
    ret[entry_type] = true
  end
  return ret
end

local function get_display_suffix(text)
  return text:match('([/\\])$') or ''
end

local function check_name(name, seen_names, lnum)
  if name == '' then
    return string.format('Empty filename on line %d', lnum)
  elseif name:match(path_sep_pattern) then
    return string.format('Filename cannot contain path separator: %s', name)
  end

  local key = (fs.is_mac or fs.is_windows) and name:lower() or name
  if seen_names[key] then
    return string.format('Duplicate filename: %s', name)
  end
  seen_names[key] = true
end

---@class oil.RenameTransformOpts
---@field types? oil.EntryType[]
---@field bufnr? integer

---@param callback fun(name: string, entry: oil.Entry): nil|string
---@param opts? oil.RenameTransformOpts
---@return boolean success
---@return nil|string err
M.transform = function(callback, opts)
  opts = opts or {}
  local bufnr = opts.bufnr or vim.api.nvim_get_current_buf()
  local adapter = util.get_adapter(bufnr, true)
  if not adapter then
    return false,
      string.format(
        "Cannot rename entries in buffer '%s': No adapter",
        vim.api.nvim_buf_get_name(bufnr)
      )
  end

  local type_filter = build_type_filter(opts.types)
  local column_defs = columns.get_supported_columns(adapter)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, true)
  local edits = {}
  local seen_names = {}

  for i, line in ipairs(lines) do
    local result, parse_err = parser.parse_line(adapter, line, column_defs)
    if not result and line:match('^/%d+') then
      return false, string.format('Error parsing line %d: %s', i, parse_err)
    end
    if result and result.entry and result.data.id ~= 0 then
      local entry = util.export_entry(result.entry)
      local current_name = result.data.name
      if type_filter[entry.type] and current_name then
        entry.parsed_name = current_name
        local next_name = callback(current_name, entry)
        if next_name == nil then
          next_name = current_name
        end
        if type(next_name) ~= 'string' then
          return false, string.format('Rename callback returned %s for line %d', type(next_name), i)
        end
        local err = check_name(next_name, seen_names, i)
        if err then
          return false, err
        end
        if next_name ~= current_name then
          local range = result.ranges and result.ranges.name
          if not range then
            return false, string.format('Could not find filename range on line %d', i)
          end
          local range_text = line:sub(range[1] + 1, range[2] + 1)
          local suffix = get_display_suffix(range_text)
          local before = line:sub(1, range[1])
          local after = line:sub(range[2] + 2)
          edits[i] = before .. next_name .. suffix .. after
        end
      elseif current_name then
        local err = check_name(current_name, seen_names, i)
        if err then
          return false, err
        end
      end
    end
  end

  if next(edits) == nil then
    return true
  end

  for i, line in pairs(edits) do
    lines[i] = line
  end
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, true, lines)
  return true
end

return M
