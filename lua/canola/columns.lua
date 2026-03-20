local config = require('canola.config')
local constants = require('canola.constants')
local util = require('canola.util')
local M = {}

local FIELD_NAME = constants.FIELD_NAME
local FIELD_TYPE = constants.FIELD_TYPE
local FIELD_META = constants.FIELD_META

local all_columns = {}

---@alias canola.ColumnSpec string|{[1]: string, [string]: any}

---@class (exact) canola.ColumnDefinition
---@field render fun(entry: canola.InternalEntry, conf: nil|table, bufnr: integer): nil|canola.TextChunk
---@field parse fun(line: string, conf: nil|table): nil|string, nil|string
---@field compare? fun(entry: canola.InternalEntry, parsed_value: any): boolean
---@field render_action? fun(action: canola.ChangeAction): string
---@field perform_action? fun(action: canola.ChangeAction, callback: fun(err: nil|string))
---@field get_sort_value? fun(entry: canola.InternalEntry): number|string
---@field create_sort_value_factory? fun(num_entries: integer): fun(entry: canola.InternalEntry): number|string

---@param name string
---@param column canola.ColumnDefinition
M.register = function(name, column)
  all_columns[name] = column
end

---@param adapter canola.Adapter
---@param defn canola.ColumnSpec
---@return nil|canola.ColumnDefinition
M.get_column = function(adapter, defn)
  local name = util.split_config(defn)
  return all_columns[name] or adapter.get_column(name)
end

---@param adapter_or_scheme string|canola.Adapter
---@return canola.ColumnSpec[]
M.get_supported_columns = function(adapter_or_scheme)
  local adapter
  if type(adapter_or_scheme) == 'string' then
    adapter = config.get_adapter_by_scheme(adapter_or_scheme)
  else
    adapter = adapter_or_scheme
  end
  assert(adapter)
  local ret = {}
  for _, def in ipairs(config.columns) do
    if M.get_column(adapter, def) then
      table.insert(ret, def)
    end
  end
  return ret
end

local EMPTY = { '-', 'CanolaEmpty' }

M.EMPTY = EMPTY

---@param adapter canola.Adapter
---@param col_def canola.ColumnSpec
---@param entry canola.InternalEntry
---@param bufnr integer
---@return canola.TextChunk
M.render_col = function(adapter, col_def, entry, bufnr)
  local name, conf = util.split_config(col_def)
  local column = M.get_column(adapter, name)
  if not column then
    -- This shouldn't be possible because supports_col should return false
    return EMPTY
  end

  local chunk = column.render(entry, conf, bufnr)
  if type(chunk) == 'table' then
    if chunk[1]:match('^%s*$') then
      return EMPTY
    end
  else
    if not chunk or chunk:match('^%s*$') then
      return EMPTY
    end
    if conf and conf.highlight then
      local highlight = conf.highlight
      if type(highlight) == 'function' then
        highlight = conf.highlight(chunk)
      end
      return { chunk, highlight }
    end
  end
  return chunk
end

---@param adapter canola.Adapter
---@param line string
---@param col_def canola.ColumnSpec
---@return nil|string
---@return nil|string
M.parse_col = function(adapter, line, col_def)
  local name, conf = util.split_config(col_def)
  -- If rendering failed, there will just be a "-"
  local empty_col, rem = line:match('^%s*(-%s+)(.*)$')
  if empty_col then
    return nil, rem
  end
  local column = M.get_column(adapter, name)
  if column then
    return column.parse(line:gsub('^%s+', ''), conf)
  end
end

---@param adapter canola.Adapter
---@param col_name string
---@param entry canola.InternalEntry
---@param parsed_value any
---@return boolean
M.compare = function(adapter, col_name, entry, parsed_value)
  local column = M.get_column(adapter, col_name)
  if column and column.compare then
    return column.compare(entry, parsed_value)
  else
    return false
  end
end

---@param adapter canola.Adapter
---@param action canola.ChangeAction
---@return string
M.render_change_action = function(adapter, action)
  local column = M.get_column(adapter, action.column)
  if not column then
    error(string.format('Received change action for nonexistant column %s', action.column))
  end
  if column.render_action then
    return column.render_action(action)
  else
    return string.format('CHANGE %s %s = %s', action.url, action.column, action.value)
  end
end

---@param adapter canola.Adapter
---@param action canola.ChangeAction
---@param callback fun(err: nil|string)
M.perform_change_action = function(adapter, action, callback)
  local column = M.get_column(adapter, action.column)
  if not column then
    return callback(
      string.format('Received change action for nonexistant column %s', action.column)
    )
  end
  column.perform_action(action, callback)
end

local icon_provider = util.get_icon_provider()
if icon_provider then
  M.register('icon', {
    render = function(entry, conf, bufnr)
      local field_type = entry[FIELD_TYPE]
      local name = entry[FIELD_NAME]
      local meta = entry[FIELD_META]
      if field_type == 'link' and meta then
        if meta.link then
          name = meta.link
        end
        if meta.link_stat then
          field_type = meta.link_stat.type
        end
      end
      if meta and meta.display_name then
        name = meta.display_name
      end

      local ft = nil
      if conf and conf.use_slow_filetype_detection and field_type == 'file' then
        local bufname = vim.api.nvim_buf_get_name(bufnr)
        local _, path = util.parse_url(bufname)
        if path then
          local lines = vim.fn.readfile(path .. name, '', 16)
          if lines and #lines > 0 then
            ft = vim.filetype.match({ filename = name, contents = lines })
          end
        end
      end

      local icon, hl = icon_provider(field_type, name, conf, ft)
      if not conf or conf.add_padding ~= false then
        icon = icon .. ' '
      end
      if conf and conf.highlight then
        if type(conf.highlight) == 'function' then
          hl = conf.highlight(icon)
        else
          hl = conf.highlight
        end
      end
      return { icon, hl }
    end,

    parse = function(line, conf)
      return line:match('^(%S+)%s+(.*)$')
    end,
  })
end

local default_type_icons = {
  directory = 'dir',
  socket = 'sock',
}
---@param entry canola.InternalEntry
---@return boolean
local function is_entry_directory(entry)
  local type = entry[FIELD_TYPE]
  if type == 'directory' then
    return true
  elseif type == 'link' then
    local meta = entry[FIELD_META]
    return (meta and meta.link_stat and meta.link_stat.type == 'directory') == true
  else
    return false
  end
end
M.register('type', {
  render = function(entry, conf)
    local entry_type = entry[FIELD_TYPE]
    if conf and conf.icons then
      return conf.icons[entry_type] or entry_type
    else
      return default_type_icons[entry_type] or entry_type
    end
  end,

  parse = function(line, conf)
    return line:match('^(%S+)%s+(.*)$')
  end,

  get_sort_value = function(entry)
    if is_entry_directory(entry) then
      return 1
    else
      return 2
    end
  end,
})

local function adjust_number(int)
  return string.format('%03d%s', #int, int)
end

M.register('name', {
  render = function(entry, conf)
    error('Do not use the name column. It is for sorting only')
  end,

  parse = function(line, conf)
    error('Do not use the name column. It is for sorting only')
  end,

  create_sort_value_factory = function(num_entries)
    if
      config._natural_order == false
      or (config._natural_order == 'fast' and num_entries > 5000)
    then
      if config._case_insensitive then
        return function(entry)
          return entry[FIELD_NAME]:lower()
        end
      else
        return function(entry)
          return entry[FIELD_NAME]
        end
      end
    else
      local memo = {}
      return function(entry)
        if memo[entry] == nil then
          local name = entry[FIELD_NAME]:gsub('0*(%d+)', adjust_number)
          if config._case_insensitive then
            name = name:lower()
          end
          memo[entry] = name
        end
        return memo[entry]
      end
    end
  end,
})

return M
