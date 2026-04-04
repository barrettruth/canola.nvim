local columns = require('canola.columns')
local config = require('canola.config')
local constants = require('canola.constants')
local fs = require('canola.fs')
local permissions = require('canola.adapters.files.permissions')
local util = require('canola.util')

local M = {}

local FIELD_NAME = constants.FIELD_NAME
local FIELD_TYPE = constants.FIELD_TYPE
local FIELD_META = constants.FIELD_META

local file_columns = {}

---@type canola.ColumnDefinition
file_columns.size = {
  require_stat = true,
  default_align = 'right',

  render = function(entry, conf)
    local meta = entry[FIELD_META]
    local stat = meta and meta.stat
    if not stat then
      return columns.EMPTY
    end
    if entry[FIELD_TYPE] == 'directory' then
      return columns.EMPTY
    end
    local text, hl
    if stat.size >= 1e9 then
      text = string.format('%.1fG', stat.size / 1e9)
      hl = 'CanolaSizeGiga'
    elseif stat.size >= 1e6 then
      text = string.format('%.1fM', stat.size / 1e6)
      hl = 'CanolaSizeMega'
    elseif stat.size >= 1e3 then
      text = string.format('%.1fk', stat.size / 1e3)
      hl = 'CanolaSizeKilo'
    else
      text = string.format('%d', stat.size)
      hl = 'CanolaSizeBytes'
    end
    if config.highlights.columns then
      return { text, { { hl, 0, #text } } }
    end
    return text
  end,

  get_sort_value = function(entry)
    local meta = entry[FIELD_META]
    local stat = meta and meta.stat
    if stat then
      return stat.size
    else
      return 0
    end
  end,

  parse = function(line, conf)
    return line:match('^(%d+%S*)%s+(.*)$')
  end,
}

-- TODO support file permissions on windows
if not fs.is_windows then
  local ids = require('canola.adapters.files.ids')
  local current_uid = vim.uv.getuid()
  local current_gid = vim.uv.getgid()

  ---@type canola.ColumnDefinition
  file_columns.owner = {
    require_stat = true,

    render = function(entry, conf)
      local meta = entry[FIELD_META]
      local stat = meta and (meta.lstat or meta.stat)
      if not stat then
        return columns.EMPTY
      end
      local name = ids.get_user(stat.uid)
      if config.highlights.columns then
        local hl = stat.uid == current_uid and 'CanolaOwnerSelf' or 'CanolaOwnerOther'
        return { name, { { hl, 0, #name } } }
      end
      return name
    end,

    parse = function(line, conf)
      return line:match('^(%S+)%s+(.*)$')
    end,
  }

  ---@type canola.ColumnDefinition
  file_columns.group = {
    require_stat = true,

    render = function(entry, conf)
      local meta = entry[FIELD_META]
      local stat = meta and (meta.lstat or meta.stat)
      if not stat then
        return columns.EMPTY
      end
      local name = ids.get_group(stat.gid)
      if config.highlights.columns then
        local hl = stat.gid == current_gid and 'CanolaGroupSelf' or 'CanolaGroupOther'
        return { name, { { hl, 0, #name } } }
      end
      return name
    end,

    parse = function(line, conf)
      return line:match('^(%S+)%s+(.*)$')
    end,
  }

  ---@type canola.ColumnDefinition
  file_columns.permissions = {
    require_stat = true,

    render = function(entry, conf)
      local meta = entry[FIELD_META]
      local stat = meta and meta.stat
      if not stat then
        return columns.EMPTY
      end
      local entry_type = entry[FIELD_TYPE]
      if config.highlights.columns then
        return permissions.mode_to_highlighted(stat.mode, entry_type)
      end
      return permissions.mode_to_str(stat.mode, entry_type)
    end,

    parse = function(line, conf)
      return permissions.parse(line)
    end,

    compare = function(entry, parsed_value)
      local meta = entry[FIELD_META]
      if parsed_value and meta and meta.stat and meta.stat.mode then
        local mask = bit.lshift(1, 12) - 1
        local old_mode = bit.band(meta.stat.mode, mask)
        if parsed_value ~= old_mode then
          return true
        end
      end
      return false
    end,

    render_action = function(action)
      local _, path = util.parse_url(action.url)
      assert(path)
      return string.format(
        'CHMOD %s %s',
        permissions.mode_to_octal_str(action.value),
        require('canola.adapters.files').to_short_os_path(path, action.entry_type)
      )
    end,

    perform_action = function(action, callback)
      local _, path = util.parse_url(action.url)
      assert(path)
      path = fs.posix_to_os_path(path)
      vim.uv.fs_stat(path, function(err, stat)
        if err then
          return callback(err)
        end
        assert(stat)
        -- We are only changing the lower 12 bits of the mode
        local mask = bit.bnot(bit.lshift(1, 12) - 1)
        local old_mode = bit.band(stat.mode, mask)
        vim.uv.fs_chmod(path, bit.bor(old_mode, action.value), callback)
      end)
    end,
  }
end

---@type string
local current_year
-- Make sure we run this import-time effect in the main loop (mostly for tests)
vim.schedule(function()
  current_year = vim.fn.strftime('%Y')
end)

for _, time_key in ipairs({ 'ctime', 'mtime', 'atime', 'birthtime' }) do
  ---@type canola.ColumnDefinition
  file_columns[time_key] = {
    require_stat = true,

    render = function(entry, conf)
      local meta = entry[FIELD_META]
      local stat = meta and meta.stat
      if not stat then
        return columns.EMPTY
      end
      local fmt = conf and conf.format
      local ret
      if fmt then
        ret = vim.fn.strftime(fmt, stat[time_key].sec)
      else
        local year = vim.fn.strftime('%Y', stat[time_key].sec)
        if year ~= current_year then
          ret = vim.fn.strftime('%e %b  %Y', stat[time_key].sec)
        else
          ret = vim.fn.strftime('%e %b %H:%M', stat[time_key].sec)
        end
      end
      return { ret, 'CanolaDate' }
    end,

    parse = function(line, conf)
      local fmt = conf and conf.format
      local pattern
      if fmt then
        -- Replace placeholders with a pattern that matches non-space characters (e.g. %H -> %S+)
        -- and whitespace with a pattern that matches any amount of whitespace
        -- e.g. "%b %d %Y" -> "%S+%s+%S+%s+%S+"
        pattern = fmt
          :gsub('%%.', '%%S+')
          :gsub('%s+', '%%s+')
          -- escape `()[]` because those are special characters in Lua patterns
          :gsub(
            '%(',
            '%%('
          )
          :gsub('%)', '%%)')
          :gsub('%[', '%%[')
          :gsub('%]', '%%]')
      else
        pattern = '%S+%s+%d+%s+%d%d:?%d%d'
      end
      return line:match('^(' .. pattern .. ')%s+(.+)$')
    end,

    get_sort_value = function(entry)
      local meta = entry[FIELD_META]
      local stat = meta and meta.stat
      if stat then
        return stat[time_key].sec
      else
        return 0
      end
    end,
  }
end

---@param column_defs table[]
---@return boolean
M.columns_require_stat = function(column_defs)
  for _, def in ipairs(column_defs) do
    local name = util.split_config(def)
    local column = M.get_column(name)
    ---@diagnostic disable-next-line: undefined-field We only put this on the files adapter columns
    if column and column.require_stat then
      return true
    end
  end
  return false
end

---@param name string
---@return nil|canola.ColumnDefinition
M.get_column = function(name)
  return file_columns[name]
end

return M
