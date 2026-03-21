local M = {}

local default_buf = { buflisted = false, bufhidden = 'hide' }
local default_win = {
  wrap = false,
  signcolumn = 'no',
  cursorcolumn = false,
  foldcolumn = '0',
  spell = false,
  list = false,
  conceallevel = 3,
  concealcursor = 'nvic',
}

local sort_presets = {
  ['type,asc|name,asc'] = 'default',
  ['name,asc'] = 'name',
  ['mtime,desc|name,asc'] = 'modified',
  ['size,desc|name,asc'] = 'size',
}

local removed = {
  'default_file_explorer',
  'use_default_keymaps',
  'cleanup_delay_ms',
  'extra_scp_args',
  'extra_s3_args',
  'ssh_hosts',
  's3_buckets',
  'delete_to_trash',
}

local function indent(s, level)
  return string.rep('  ', level) .. s
end

local function is_default_table(a, b)
  if type(a) ~= 'table' or type(b) ~= 'table' then
    return a == b
  end
  for k, v in pairs(a) do
    if not is_default_table(v, b[k]) then
      return false
    end
  end
  for k, v in pairs(b) do
    if not is_default_table(a[k], v) then
      return false
    end
  end
  return true
end

local function serialize(val, level)
  level = level or 0
  if val == nil then
    return 'nil'
  elseif type(val) == 'string' then
    return string.format('%q', val)
  elseif type(val) == 'number' or type(val) == 'boolean' then
    return tostring(val)
  elseif type(val) == 'function' then
    return nil
  elseif type(val) == 'table' then
    if vim.islist(val) then
      local items = {}
      for _, v in ipairs(val) do
        local s = serialize(v, level + 1)
        if s then
          table.insert(items, s)
        end
      end
      if #items == 0 then
        return '{}'
      end
      local oneline = '{ ' .. table.concat(items, ', ') .. ' }'
      if #oneline < 60 then
        return oneline
      end
      local lines = { '{' }
      for _, item in ipairs(items) do
        table.insert(lines, indent(item .. ',', level + 1))
      end
      table.insert(lines, indent('}', level))
      return table.concat(lines, '\n')
    else
      local keys = {}
      for k in pairs(val) do
        table.insert(keys, k)
      end
      table.sort(keys, function(a, b)
        return tostring(a) < tostring(b)
      end)
      local items = {}
      for _, k in ipairs(keys) do
        local s = serialize(val[k], level + 1)
        if s then
          local key_str
          if type(k) == 'string' and k:match('^[%a_][%w_]*$') then
            key_str = k
          else
            key_str = '[' .. serialize(k, 0) .. ']'
          end
          table.insert(items, indent(key_str .. ' = ' .. s .. ',', level + 1))
        end
      end
      if #items == 0 then
        return '{}'
      end
      return '{\n' .. table.concat(items, '\n') .. '\n' .. indent('}', level)
    end
  end
  return tostring(val)
end

local function sort_key(sort_spec)
  local parts = {}
  for _, s in ipairs(sort_spec) do
    table.insert(parts, s[1] .. ',' .. s[2])
  end
  return table.concat(parts, '|')
end

local function migrate_keymaps(oil_keymaps)
  local canola = {}
  for key, val in pairs(oil_keymaps) do
    if val == false then
      canola[key] = false
    elseif type(val) == 'string' then
      canola[key] = val
    elseif type(val) == 'table' then
      local action = val[1] or val.callback
      if action then
        local entry = { callback = action }
        if val.opts then
          entry.opts = val.opts
        end
        if val.mode then
          entry.mode = val.mode
        end
        if val.desc then
          entry.desc = val.desc
        end
        canola[key] = entry
      end
    end
  end
  return canola
end

M.generate = function()
  local cfg = require('oil.config')
  local out = {}
  local warnings = {}

  out.columns = cfg.columns

  if cfg.constrain_cursor == 'editable' or cfg.constrain_cursor == 'name' then
    out.cursor = true
  elseif cfg.constrain_cursor == false then
    out.cursor = false
  end

  out.watch = cfg.watch_for_changes or false

  if not is_default_table(cfg.view_options.sort, { { 'type', 'asc' }, { 'name', 'asc' } }) then
    local key = sort_key(cfg.view_options.sort)
    local preset = sort_presets[key]
    if preset then
      out.sort = preset
    else
      out.sort = {
        by = cfg.view_options.sort,
        natural = cfg.view_options.natural_order,
        ignore_case = cfg.view_options.case_insensitive,
      }
    end
  end

  local hidden = {}
  if cfg.view_options.show_hidden then
    hidden.enabled = false
  else
    hidden.enabled = true
  end
  out.hidden = hidden

  if cfg.skip_confirm_for_simple_edits and cfg.skip_confirm_for_delete then
    out.confirm = false
  elseif cfg.skip_confirm_for_simple_edits then
    out.confirm = 'delete'
  end

  if cfg.auto_save_on_select_new_entry then
    out.save = 'auto'
  elseif not cfg.prompt_save_on_select_new_entry then
    out.save = false
  end

  local delete = {}
  if cfg.cleanup_buffers_on_delete then
    delete.wipe = true
  end
  if next(delete) then
    out.delete = delete
  end

  if cfg.new_file_mode ~= 420 or cfg.new_dir_mode ~= 493 then
    out.create = { file_mode = cfg.new_file_mode, dir_mode = cfg.new_dir_mode }
  end

  local lsp = {}
  if not cfg.lsp_file_methods.enabled then
    lsp.enabled = false
  end
  if cfg.lsp_file_methods.timeout_ms ~= 1000 then
    lsp.timeout_ms = cfg.lsp_file_methods.timeout_ms
  end
  if cfg.lsp_file_methods.autosave_changes then
    lsp.autosave = cfg.lsp_file_methods.autosave_changes
  end
  if next(lsp) then
    out.lsp = lsp
  end

  local keymaps = migrate_keymaps(cfg.keymaps)
  local default_keys = {
    ['g?'] = true,
    ['<CR>'] = true,
    ['<C-s>'] = true,
    ['<C-h>'] = true,
    ['<C-t>'] = true,
    ['<C-p>'] = true,
    ['<C-c>'] = true,
    ['<C-l>'] = true,
    ['-'] = true,
    ['_'] = true,
    ['`'] = true,
    ['g~'] = true,
    ['gs'] = true,
    ['gx'] = true,
    ['g.'] = true,
    ['g\\'] = true,
  }
  local custom_keymaps = {}
  for k, v in pairs(keymaps) do
    if not default_keys[k] then
      custom_keymaps[k] = v
    end
  end
  for k, v in pairs(keymaps) do
    if default_keys[k] and v == false then
      custom_keymaps[k] = false
    end
  end
  if next(custom_keymaps) then
    out.keymaps = custom_keymaps
  end

  local float = {}
  if cfg.default_to_float then
    float.default = true
  end
  if cfg.float.padding ~= 2 then
    float.padding = cfg.float.padding
  end
  if cfg.float.max_width ~= 0 then
    float.max_width = cfg.float.max_width
  end
  if cfg.float.max_height ~= 0 then
    float.max_height = cfg.float.max_height
  end
  if cfg.float.border then
    float.border = cfg.float.border
  end
  if cfg.float.preview_split ~= 'auto' then
    float.preview_split = cfg.float.preview_split
  end
  if not is_default_table(cfg.float.win_options, { winblend = 0 }) then
    float.win = cfg.float.win_options
  end
  if next(float) then
    out.float = float
  end

  local preview = {}
  if not cfg.preview_win.update_on_cursor_moved then
    preview.follow = false
  end
  if cfg.preview_win.preview_method == 'load' then
    preview.live = true
  end
  if cfg.preview_win.max_file_size ~= 10 then
    preview.max_file_size_mb = cfg.preview_win.max_file_size
  end
  if not is_default_table(cfg.preview_win.win_options, {}) then
    preview.win = cfg.preview_win.win_options
  end
  if next(preview) then
    out.preview = preview
  end

  if not is_default_table(cfg.buf_options, default_buf) then
    out.buf = cfg.buf_options
  end

  if not is_default_table(cfg.win_options, default_win) then
    out.win = cfg.win_options
  end

  local confirmation = {}
  if cfg.confirmation.max_width ~= 0.9 then
    confirmation.max_width = cfg.confirmation.max_width
  end
  if not is_default_table(cfg.confirmation.min_width, { 40, 0.4 }) then
    confirmation.min_width = cfg.confirmation.min_width
  end
  if cfg.confirmation.width then
    confirmation.width = cfg.confirmation.width
  end
  if cfg.confirmation.max_height ~= 0.9 then
    confirmation.max_height = cfg.confirmation.max_height
  end
  if not is_default_table(cfg.confirmation.min_height, { 5, 0.1 }) then
    confirmation.min_height = cfg.confirmation.min_height
  end
  if cfg.confirmation.height then
    confirmation.height = cfg.confirmation.height
  end
  if cfg.confirmation.border then
    confirmation.border = cfg.confirmation.border
  end
  if not is_default_table(cfg.confirmation.win_options, { winblend = 0 }) then
    confirmation.win = cfg.confirmation.win_options
  end
  if next(confirmation) then
    out.confirmation = confirmation
  end

  local progress = {}
  if cfg.progress.max_width ~= 0.9 then
    progress.max_width = cfg.progress.max_width
  end
  if not is_default_table(cfg.progress.min_width, { 40, 0.4 }) then
    progress.min_width = cfg.progress.min_width
  end
  if cfg.progress.width then
    progress.width = cfg.progress.width
  end
  if not is_default_table(cfg.progress.max_height, { 10, 0.9 }) then
    progress.max_height = cfg.progress.max_height
  end
  if not is_default_table(cfg.progress.min_height, { 5, 0.1 }) then
    progress.min_height = cfg.progress.min_height
  end
  if cfg.progress.height then
    progress.height = cfg.progress.height
  end
  if cfg.progress.border then
    progress.border = cfg.progress.border
  end
  if cfg.progress.minimized_border ~= 'none' then
    progress.minimized_border = cfg.progress.minimized_border
  end
  if not is_default_table(cfg.progress.win_options, { winblend = 0 }) then
    progress.win = cfg.progress.win_options
  end
  if next(progress) then
    out.progress = progress
  end

  if cfg.float.override and type(cfg.float.override) == 'function' then
    table.insert(warnings, 'float.override -> use CanolaFloatConfig autocmd event')
  end
  if cfg.float.get_win_title and type(cfg.float.get_win_title) == 'function' then
    table.insert(warnings, 'float.get_win_title -> use CanolaWinTitle autocmd event')
  end
  if cfg.preview_win.disable_preview and type(cfg.preview_win.disable_preview) == 'function' then
    table.insert(warnings, 'preview_win.disable_preview -> use CanolaPreviewDisable autocmd event')
  end
  if
    cfg.view_options.highlight_filename
    and type(cfg.view_options.highlight_filename) == 'function'
  then
    table.insert(warnings, 'view_options.highlight_filename -> use highlights.filename config')
  end
  if cfg.view_options.is_hidden_file and type(cfg.view_options.is_hidden_file) == 'function' then
    table.insert(
      warnings,
      'view_options.is_hidden_file -> use hidden.patterns or set_is_hidden_file()'
    )
  end
  if
    cfg.view_options.is_always_hidden and type(cfg.view_options.is_always_hidden) == 'function'
  then
    table.insert(warnings, 'view_options.is_always_hidden -> use hidden.always patterns')
  end
  if cfg.git then
    table.insert(warnings, 'git.add/mv/rm hooks -> use canola-collection canola-git')
  end
  if cfg.delete_to_trash then
    table.insert(warnings, 'delete_to_trash -> use canola-collection canola-trash')
  end
  for _, key in ipairs(removed) do
    if cfg[key] ~= nil then
      table.insert(warnings, key .. ' -> removed in canola (see :h canola-migration-removed)')
    end
  end

  return out, warnings
end

M.print = function()
  local out, warnings = M.generate()
  local lines = {}
  table.insert(lines, 'vim.g.canola = ' .. serialize(out, 0))
  if #warnings > 0 then
    table.insert(lines, '')
    table.insert(lines, '-- Manual migration needed:')
    for _, w in ipairs(warnings) do
      table.insert(lines, '--   ' .. w)
    end
  end
  table.insert(lines, '')
  table.insert(lines, '-- See :h canola-migration for the full guide')

  local text = table.concat(lines, '\n')

  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, vim.split(text, '\n'))
  vim.bo[bufnr].filetype = 'lua'
  vim.bo[bufnr].modifiable = false
  vim.cmd.split()
  vim.api.nvim_win_set_buf(0, bufnr)
end

return M
