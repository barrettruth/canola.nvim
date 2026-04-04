local config = require('canola.config')
local util = require('canola.util')

local M = {}

---@type table<integer, { lnum: integer, min_col: integer }>
local insert_boundary = {}

---@param bufnr integer
M.clear_boundary = function(bufnr)
  insert_boundary[bufnr] = nil
end

---@param bufnr integer
local function show_insert_guide(bufnr)
  if not config._constrain_cursor then
    return
  end
  if bufnr ~= vim.api.nvim_get_current_buf() then
    return
  end
  local adapter = util.get_adapter(bufnr, true)
  if not adapter then
    return
  end

  local cur = vim.api.nvim_win_get_cursor(0)
  local current_line = vim.api.nvim_buf_get_lines(bufnr, cur[1] - 1, cur[1], true)[1]
  if current_line ~= '' then
    return
  end

  local all_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, true)
  local ref_line
  if cur[1] > 1 and all_lines[cur[1] - 1] ~= '' then
    ref_line = all_lines[cur[1] - 1]
  elseif cur[1] < #all_lines and all_lines[cur[1] + 1] ~= '' then
    ref_line = all_lines[cur[1] + 1]
  else
    for i, line in ipairs(all_lines) do
      if line ~= '' and i ~= cur[1] then
        ref_line = line
        break
      end
    end
  end
  if not ref_line then
    return
  end

  local id_prefix = ref_line:match('^/%d+ ')
  if not id_prefix then
    return
  end

  local id_width
  local cole = vim.wo.conceallevel
  if cole >= 2 then
    id_width = 0
  elseif cole == 1 then
    id_width = 1
  else
    id_width = vim.api.nvim_strwidth(ref_line:sub(1, #id_prefix - 1))
  end

  local virtual_col = id_width + require('canola.view').get_col_pad(bufnr)
  if virtual_col <= 0 then
    return
  end

  vim.w.canola_saved_ve = vim.wo.virtualedit
  vim.wo.virtualedit = 'all'
  vim.api.nvim_win_set_cursor(0, { cur[1], virtual_col })

  vim.api.nvim_create_autocmd('TextChangedI', {
    group = 'Canola',
    buffer = bufnr,
    once = true,
    callback = function()
      if vim.w.canola_saved_ve ~= nil then
        vim.wo.virtualedit = vim.w.canola_saved_ve
        vim.w.canola_saved_ve = nil
      end
    end,
  })
end

---@param bufnr integer
---@return integer
local function update_insert_boundary(bufnr)
  local cur = vim.api.nvim_win_get_cursor(0)
  local cached = insert_boundary[bufnr]
  if cached and cached.lnum == cur[1] then
    return cached.min_col
  end

  local adapter = util.get_adapter(bufnr, true)
  if not adapter then
    return 0
  end

  local line = vim.api.nvim_buf_get_lines(bufnr, cur[1] - 1, cur[1], true)[1]
  local id_prefix = line:match('^/%d+ ')
  local min_col = (id_prefix and #id_prefix or 0) + require('canola.view').get_col_pad(bufnr)
  insert_boundary[bufnr] = { lnum = cur[1], min_col = min_col }
  return min_col
end

---@param bufnr integer
M.setup_insert_constraints = function(bufnr)
  if not config._constrain_cursor then
    return
  end

  local function make_bs_rhs(bufnr_inner)
    return function()
      local min_col = update_insert_boundary(bufnr_inner)
      local col = vim.fn.col('.')
      if col <= min_col + 1 then
        return ''
      end
      return '<BS>'
    end
  end

  local function make_cu_rhs(bufnr_inner)
    return function()
      local min_col = update_insert_boundary(bufnr_inner)
      local col = vim.fn.col('.')
      if col <= min_col + 1 then
        return ''
      end
      local count = col - min_col - 1
      return string.rep('<BS>', count)
    end
  end

  local function make_cw_rhs(bufnr_inner)
    return function()
      local min_col = update_insert_boundary(bufnr_inner)
      local col = vim.fn.col('.')
      if col <= min_col + 1 then
        return ''
      end
      return '<C-w>'
    end
  end

  local opts = { buffer = bufnr, expr = true, nowait = true, silent = true }
  vim.keymap.set('i', '<BS>', make_bs_rhs(bufnr), opts)
  vim.keymap.set('i', '<C-h>', make_bs_rhs(bufnr), opts)
  vim.keymap.set('i', '<C-u>', make_cu_rhs(bufnr), opts)
  vim.keymap.set('i', '<C-w>', make_cw_rhs(bufnr), opts)
end

M.show_insert_guide = show_insert_guide

return M
