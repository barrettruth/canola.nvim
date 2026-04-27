local config = require('canola.config')
local util = require('canola.util')

local M = {}

---@type table<string, string>
local last_cursor_entry = {}

---@param bufname string
---@param name nil|string
M.set_last_cursor = function(bufname, name)
  last_cursor_entry[bufname] = name
end

---Set the cursor to the last_cursor_entry if one exists
M.maybe_set_cursor = function()
  local canola = require('canola')
  local bufname = vim.api.nvim_buf_get_name(0)
  local entry_name = last_cursor_entry[bufname]
  if not entry_name then
    return
  end
  local line_count = vim.api.nvim_buf_line_count(0)
  for lnum = 1, line_count do
    local entry = canola.get_entry_on_line(0, lnum)
    if entry and entry.name == entry_name then
      local line = vim.api.nvim_buf_get_lines(0, lnum - 1, lnum, true)[1]
      local id_str = line:match('^/(%d+)')
      local col = line:find(entry_name, 1, true) or (id_str:len() + 1)
      vim.api.nvim_win_set_cursor(0, { lnum, col - 1 })
      M.set_last_cursor(bufname, nil)
      break
    end
  end
end

---@param bufname string
---@return nil|string
M.get_last_cursor = function(bufname)
  return last_cursor_entry[bufname]
end

--- @param bufnr integer
--- @param adapter canola.Adapter
--- @param mode false|"name"|"editable"
--- @param cur integer[]
--- @param col_pad integer
--- @return integer[]|nil
M.calc_constrained_cursor_pos = function(bufnr, adapter, mode, cur, col_pad)
  local line_count = vim.api.nvim_buf_line_count(bufnr)
  if cur[1] < 1 or cur[1] > line_count then
    return
  end
  local line = vim.api.nvim_buf_get_lines(bufnr, cur[1] - 1, cur[1], true)[1]
  local id_prefix = line:match('^/%d+ ')
  if id_prefix then
    local min_col = #id_prefix + col_pad
    if cur[2] < min_col then
      return { cur[1], min_col }
    end
  end
end

---Force cursor to be after hidden/immutable columns
---@param bufnr integer
---@param mode false|"name"|"editable"
M.constrain_cursor = function(bufnr, mode)
  if not mode then
    return
  end
  if bufnr ~= vim.api.nvim_get_current_buf() then
    return
  end

  local adapter = util.get_adapter(bufnr, true)
  if not adapter then
    return
  end

  local col_pad = require('canola.view').get_col_pad(bufnr)

  local mc = package.loaded['multicursor-nvim']
  if mc then
    mc.onSafeState(function()
      mc.action(function(ctx)
        ctx:forEachCursor(function(cursor)
          local new_cur = M.calc_constrained_cursor_pos(
            bufnr,
            adapter,
            mode,
            { cursor:line(), cursor:col() - 1 },
            col_pad
          )
          if new_cur then
            cursor:setPos({ new_cur[1], new_cur[2] + 1 })
          end
        end)
      end)
    end, { once = true })
  else
    local cur = vim.api.nvim_win_get_cursor(0)
    local new_cur = M.calc_constrained_cursor_pos(bufnr, adapter, mode, cur, col_pad)
    if new_cur then
      vim.api.nvim_win_set_cursor(0, new_cur)
    end
  end
end

return M
