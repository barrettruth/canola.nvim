local uv = vim.uv
local cache = require('canola.cache')
local columns = require('canola.columns')
local config = require('canola.config')
local constants = require('canola.constants')
local fs = require('canola.fs')
local keymap_util = require('canola.keymap_util')
local loading = require('canola.loading')
local util = require('canola.util')
local M = {}

local FIELD_ID = constants.FIELD_ID
local FIELD_NAME = constants.FIELD_NAME
local FIELD_TYPE = constants.FIELD_TYPE
local FIELD_META = constants.FIELD_META

-- map of path->last entry under cursor
local last_cursor_entry = {}

local non_canola_enter_count = 0

M.setup_cleanup_autocmd = function()
  vim.api.nvim_create_autocmd('BufEnter', {
    desc = 'Clean up hidden canola buffers after leaving canola',
    group = 'Canola',
    pattern = '*',
    callback = function()
      if vim.bo.filetype == 'canola' then
        non_canola_enter_count = 0
        return
      end
      non_canola_enter_count = non_canola_enter_count + 1
      if non_canola_enter_count >= 2 then
        non_canola_enter_count = 0
        vim.defer_fn(function()
          local mutator = require('canola.mutator')
          if not mutator.is_mutating() then
            M.delete_hidden_buffers()
          end
        end, 100)
      end
    end,
  })
end

---@param bufnr integer
---@param entry canola.InternalEntry
---@return boolean display
---@return boolean is_hidden Whether the file is classified as a hidden file
M.should_display = function(bufnr, entry)
  local name = entry[FIELD_NAME]
  local public_entry = util.export_entry(entry)
  if config._is_always_hidden(name, bufnr, public_entry) then
    return false, true
  else
    local is_hidden = config._is_hidden_file(name, bufnr, public_entry)
    local display = not config.hidden.enabled or not is_hidden
    return display, is_hidden
  end
end

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

local function are_any_modified()
  local buffers = M.get_all_buffers()
  for _, bufnr in ipairs(buffers) do
    if vim.bo[bufnr].modified then
      return true
    end
  end
  return false
end

local function is_unix_executable(entry)
  if entry[FIELD_TYPE] == 'directory' then
    return false
  end
  local meta = entry[FIELD_META]
  if not meta or not meta.stat then
    return false
  end
  if meta.stat.type == 'directory' then
    return false
  end

  local S_IXUSR = 64
  local S_IXGRP = 8
  local S_IXOTH = 1
  return bit.band(meta.stat.mode, bit.bor(S_IXUSR, S_IXGRP, S_IXOTH)) ~= 0
end

M.toggle_hidden = function()
  local any_modified = are_any_modified()
  if any_modified then
    vim.notify('Cannot toggle hidden files when you have unsaved changes', vim.log.levels.WARN)
  else
    config.hidden.enabled = not config.hidden.enabled
    M.rerender_all_oil_buffers({ refetch = false })
  end
end

---@param is_hidden_file fun(filename: string, bufnr: integer, entry: canola.Entry): boolean
M.set_is_hidden_file = function(is_hidden_file)
  local any_modified = are_any_modified()
  if any_modified then
    vim.notify('Cannot change is_hidden_file when you have unsaved changes', vim.log.levels.WARN)
  else
    config._is_hidden_file = is_hidden_file
    M.rerender_all_oil_buffers({ refetch = false })
  end
end

M.set_columns = function(cols)
  local any_modified = are_any_modified()
  if any_modified then
    vim.notify('Cannot change columns when you have unsaved changes', vim.log.levels.WARN)
  else
    config.columns = cols
    -- TODO only refetch if we don't have all the necessary data for the columns
    M.rerender_all_oil_buffers({ refetch = true })
  end
end

M.set_sort = function(new_sort)
  local any_modified = are_any_modified()
  if any_modified then
    vim.notify('Cannot change sorting when you have unsaved changes', vim.log.levels.WARN)
  else
    config._sort_spec = new_sort
    -- TODO only refetch if we don't have all the necessary data for the columns
    M.rerender_all_oil_buffers({ refetch = true })
  end
end

---@class canola.ViewData
---@field fs_event? any uv_fs_event_t
---@field col_width? integer[]
---@field col_align? canola.ColumnAlign[]
---@field hl_cache? table<integer, { line: string, name_highlights: table[], virt_chunks: table[] }>

-- List of bufnrs
---@type table<integer, canola.ViewData>
local session = {}
local _rendering = {}

local decor_ns = vim.api.nvim_create_namespace('CanolaDecor')
local decor_ctx = {}

---@type table<integer, { lnum: integer, min_col: integer }>
local insert_boundary = {}

---@return integer[]
M.get_all_buffers = function()
  return vim.tbl_filter(vim.api.nvim_buf_is_loaded, vim.tbl_keys(session))
end

local buffers_locked = false
---Make all oil buffers nomodifiable
M.lock_buffers = function()
  buffers_locked = true
  for bufnr in pairs(session) do
    if vim.api.nvim_buf_is_loaded(bufnr) then
      vim.bo[bufnr].modifiable = false
    end
  end
end

---Restore normal modifiable settings for oil buffers
M.unlock_buffers = function()
  buffers_locked = false
  for bufnr in pairs(session) do
    if vim.api.nvim_buf_is_loaded(bufnr) then
      local adapter = util.get_adapter(bufnr, true)
      if adapter then
        vim.bo[bufnr].modifiable = adapter.is_modifiable(bufnr)
      end
    end
  end
end

---@param opts? table
---@param callback? fun(err: nil|string)
---@note
--- This DISCARDS ALL MODIFICATIONS a user has made to oil buffers
M.rerender_all_oil_buffers = function(opts, callback)
  opts = opts or {}
  local buffers = M.get_all_buffers()
  local hidden_buffers = {}
  for _, bufnr in ipairs(buffers) do
    hidden_buffers[bufnr] = true
  end
  for _, winid in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_is_valid(winid) then
      hidden_buffers[vim.api.nvim_win_get_buf(winid)] = nil
    end
  end
  local cb = util.cb_collect(#buffers, callback or function() end)
  for _, bufnr in ipairs(buffers) do
    if hidden_buffers[bufnr] then
      vim.b[bufnr].oil_dirty = opts
      -- We also need to mark this as nomodified so it doesn't interfere with quitting vim
      vim.bo[bufnr].modified = false
      vim.schedule(cb)
    else
      M.render_buffer_async(bufnr, opts, cb)
    end
  end
end

M.set_win_options = function()
  local winid = vim.api.nvim_get_current_win()

  -- work around https://github.com/neovim/neovim/pull/27422
  vim.api.nvim_set_option_value('foldmethod', 'manual', { scope = 'local', win = winid })

  for k, v in pairs(config.win) do
    vim.api.nvim_set_option_value(k, v, { scope = 'local', win = winid })
  end
  if vim.wo[winid].previewwindow then
    for k, v in pairs(config.preview.win) do
      vim.api.nvim_set_option_value(k, v, { scope = 'local', win = winid })
    end
  end
end

---Get a list of visible oil buffers and a list of hidden oil buffers
---@note
--- If any buffers are modified, return values are nil
---@return nil|integer[] visible
---@return nil|integer[] hidden
local function get_visible_hidden_buffers()
  local buffers = M.get_all_buffers()
  local hidden_buffers = {}
  for _, bufnr in ipairs(buffers) do
    if vim.bo[bufnr].modified then
      return
    end
    hidden_buffers[bufnr] = true
  end
  for _, winid in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_is_valid(winid) then
      hidden_buffers[vim.api.nvim_win_get_buf(winid)] = nil
    end
  end
  local visible_buffers = vim.tbl_filter(function(bufnr)
    return not hidden_buffers[bufnr]
  end, buffers)
  return visible_buffers, vim.tbl_keys(hidden_buffers)
end

---Delete unmodified, hidden oil buffers and if none remain, clear the cache
M.delete_hidden_buffers = function()
  local visible_buffers, hidden_buffers = get_visible_hidden_buffers()
  if
    not visible_buffers
    or not hidden_buffers
    or next(visible_buffers) ~= nil
    or vim.fn.win_gettype() == 'command'
  then
    return
  end
  if #hidden_buffers == 0 then
    return
  end
  for _, bufnr in ipairs(hidden_buffers) do
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end
  cache.clear_everything()
end

--- @param bufnr integer
--- @param adapter canola.Adapter
--- @param mode false|"name"|"editable"
--- @param cur integer[]
--- @return integer[]|nil
local function calc_constrained_cursor_pos(bufnr, adapter, mode, cur)
  local line = vim.api.nvim_buf_get_lines(bufnr, cur[1] - 1, cur[1], true)[1]
  local id_prefix = line:match('^/%d+ ')
  if id_prefix then
    local min_col = #id_prefix
    if cur[2] < min_col then
      return { cur[1], min_col }
    end
  end
end

---Force cursor to be after hidden/immutable columns
---@param bufnr integer
---@param mode false|"name"|"editable"
local function constrain_cursor(bufnr, mode)
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

  local mc = package.loaded['multicursor-nvim']
  if mc then
    mc.onSafeState(function()
      mc.action(function(ctx)
        ctx:forEachCursor(function(cursor)
          local new_cur =
            calc_constrained_cursor_pos(bufnr, adapter, mode, { cursor:line(), cursor:col() - 1 })
          if new_cur then
            cursor:setPos({ new_cur[1], new_cur[2] + 1 })
          end
        end)
      end)
    end, { once = true })
  else
    local cur = vim.api.nvim_win_get_cursor(0)
    local new_cur = calc_constrained_cursor_pos(bufnr, adapter, mode, cur)
    if new_cur then
      vim.api.nvim_win_set_cursor(0, new_cur)
    end
  end
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

  local sess = session[bufnr]
  local virt_width = 0
  if sess and sess.col_width then
    for _, w in ipairs(sess.col_width) do
      if w > 0 then
        virt_width = virt_width + w + 1
      end
    end
  end
  local virtual_col = id_width + virt_width
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
  local min_col = id_prefix and #id_prefix or 0
  insert_boundary[bufnr] = { lnum = cur[1], min_col = min_col }
  return min_col
end

---@param bufnr integer
local function setup_insert_constraints(bufnr)
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

---@param bufnr integer
M.initialize = function(bufnr)
  if bufnr == 0 then
    bufnr = vim.api.nvim_get_current_buf()
  end
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end
  vim.api.nvim_clear_autocmds({
    buffer = bufnr,
    group = 'Canola',
  })
  vim.bo[bufnr].buftype = 'acwrite'
  vim.bo[bufnr].readonly = false
  vim.bo[bufnr].swapfile = false
  vim.bo[bufnr].syntax = 'canola'
  vim.bo[bufnr].filetype = 'canola'
  vim.bo[bufnr].cindent = false
  vim.bo[bufnr].smartindent = false
  vim.bo[bufnr].indentexpr = ''
  vim.b[bufnr].EditorConfig_disable = 1
  session[bufnr] = session[bufnr] or {}
  for k, v in pairs(config.buf) do
    vim.bo[bufnr][k] = v
  end
  vim.api.nvim_buf_call(bufnr, M.set_win_options)

  vim.api.nvim_create_autocmd('BufUnload', {
    group = 'Canola',
    nested = true,
    once = true,
    buffer = bufnr,
    callback = function()
      local view_data = session[bufnr]
      session[bufnr] = nil
      insert_boundary[bufnr] = nil
      if view_data and view_data.fs_event then
        view_data.fs_event:stop()
      end
    end,
  })
  vim.api.nvim_create_autocmd('BufEnter', {
    group = 'Canola',
    buffer = bufnr,
    callback = function(args)
      local opts = vim.b[args.buf].oil_dirty
      if opts then
        vim.b[args.buf].oil_dirty = nil
        M.render_buffer_async(args.buf, opts)
      end
    end,
  })
  local timer
  vim.api.nvim_create_autocmd('InsertEnter', {
    desc = 'Constrain oil cursor position',
    group = 'Canola',
    buffer = bufnr,
    callback = function()
      -- For some reason the cursor bounces back to its original position,
      -- so we have to defer the call
      vim.schedule(function()
        constrain_cursor(bufnr, config._constrain_cursor)
        show_insert_guide(bufnr)
      end)
    end,
  })
  vim.api.nvim_create_autocmd('InsertLeave', {
    group = 'Canola',
    buffer = bufnr,
    callback = function()
      insert_boundary[bufnr] = nil
      if vim.w.canola_saved_ve ~= nil then
        vim.wo.virtualedit = vim.w.canola_saved_ve
        vim.w.canola_saved_ve = nil
      end
    end,
  })
  vim.api.nvim_create_autocmd({ 'CursorMoved', 'CursorMovedI', 'ModeChanged' }, {
    desc = 'Update oil preview window',
    group = 'Canola',
    buffer = bufnr,
    callback = function()
      local canola = require('canola')
      if vim.wo.previewwindow then
        return
      end

      constrain_cursor(bufnr, config._constrain_cursor)

      if config._preview_update_on_cursor_moved then
        -- Debounce and update the preview window
        if timer then
          timer:again()
          return
        end
        timer = uv.new_timer()
        if not timer then
          return
        end
        timer:start(10, 100, function()
          timer:stop()
          timer:close()
          timer = nil
          vim.schedule(function()
            if vim.api.nvim_get_current_buf() ~= bufnr then
              return
            end
            local entry = canola.get_cursor_entry()
            -- Don't update in visual mode. Visual mode implies editing not browsing,
            -- and updating the preview can cause flicker and stutter.
            if entry and not util.is_visual_mode() then
              local winid = util.get_preview_win()
              if winid then
                if entry.id ~= vim.w[winid].canola_entry_id then
                  canola.open_preview()
                end
              end
            end
          end)
        end)
      end
    end,
  })

  local adapter = util.get_adapter(bufnr, true)

  -- Set up a watcher that will refresh the directory
  if adapter and adapter.name == 'files' and config.watch and not session[bufnr].fs_event then
    local fs_event = assert(uv.new_fs_event())
    local bufname = vim.api.nvim_buf_get_name(bufnr)
    local _, dir = util.parse_url(bufname)
    fs_event:start(
      assert(dir),
      {},
      vim.schedule_wrap(function(err, filename, events)
        if not vim.api.nvim_buf_is_valid(bufnr) then
          local sess = session[bufnr]
          if sess then
            sess.fs_event = nil
          end
          fs_event:stop()
          return
        end
        local mutator = require('canola.mutator')
        if err or vim.bo[bufnr].modified or vim.b[bufnr].oil_dirty or mutator.is_mutating() then
          return
        end

        -- If the buffer is currently visible, rerender
        for _, winid in ipairs(vim.api.nvim_list_wins()) do
          if vim.api.nvim_win_is_valid(winid) and vim.api.nvim_win_get_buf(winid) == bufnr then
            M.render_buffer_async(bufnr)
            return
          end
        end

        -- If it is not currently visible, mark it as dirty
        vim.b[bufnr].oil_dirty = {}
      end)
    )
    session[bufnr].fs_event = fs_event
  end

  M.render_buffer_async(bufnr, {}, function(err)
    if err then
      vim.notify(
        string.format('Error rendering oil buffer %s: %s', vim.api.nvim_buf_get_name(bufnr), err),
        vim.log.levels.ERROR
      )
    else
      vim.b[bufnr].canola_ready = true
      local bufname = vim.api.nvim_buf_get_name(bufnr)
      local scheme, path = util.parse_url(bufname)
      vim.api.nvim_exec_autocmds('User', {
        pattern = 'CanolaEnter',
        modeline = false,
        data = {
          buf = bufnr,
          url = bufname,
          scheme = scheme,
          dir = (config.adapters[scheme] == 'files') and path or nil,
        },
      })
    end
  end)
  keymap_util.set_keymaps(config.keymaps, bufnr)
  setup_insert_constraints(bufnr)
end

---@param adapter canola.Adapter
---@param num_entries integer
---@return fun(a: canola.InternalEntry, b: canola.InternalEntry): boolean
local function get_sort_function(adapter, num_entries)
  local idx_funs = {}
  local sort_config = config._sort_spec

  -- If empty, default to type + name sorting
  if next(sort_config) == nil then
    sort_config = { { 'type', 'asc' }, { 'name', 'asc' } }
  end

  for _, sort_pair in ipairs(sort_config) do
    local col_name, order = unpack(sort_pair)
    if order ~= 'asc' and order ~= 'desc' then
      vim.notify_once(
        string.format(
          "Column '%s' has invalid sort order '%s'. Should be either 'asc' or 'desc'",
          col_name,
          order
        ),
        vim.log.levels.WARN
      )
    end
    local col = columns.get_column(adapter, col_name)
    if col and col.create_sort_value_factory then
      table.insert(idx_funs, { col.create_sort_value_factory(num_entries), order })
    elseif col and col.get_sort_value then
      table.insert(idx_funs, { col.get_sort_value, order })
    else
      vim.notify_once(
        string.format("Column '%s' does not support sorting", col_name),
        vim.log.levels.WARN
      )
    end
  end
  return function(a, b)
    for _, sort_fn in ipairs(idx_funs) do
      local get_sort_value, order = sort_fn[1], sort_fn[2]
      local a_val = get_sort_value(a)
      local b_val = get_sort_value(b)
      if a_val ~= b_val then
        if order == 'desc' then
          return a_val > b_val
        else
          return a_val < b_val
        end
      end
    end
    return a[FIELD_NAME] < b[FIELD_NAME]
  end
end

local function compute_highlights_for_cols(cols, col_width, col_align, line_len)
  local highlights = {}
  local col = 0
  for i, chunk in ipairs(cols) do
    local text, hl
    if type(chunk) == 'table' then
      text = chunk[1]
      hl = chunk[2]
    else
      text = chunk
    end
    local unpadded_len = #text
    local padded_text, padding = util.pad_align(text, col_width[i], (col_align or {})[i] or 'left')
    if hl then
      local hl_end = col + padding + unpadded_len
      if i == #cols and line_len then
        hl_end = line_len
      end
      if type(hl) == 'table' then
        for _, sub_hl in ipairs(hl) do
          table.insert(
            highlights,
            { sub_hl[1], col + padding + sub_hl[2], col + padding + sub_hl[3] }
          )
        end
      else
        table.insert(highlights, { hl, col + padding, hl_end })
      end
    end
    col = col + #padded_text + 1
  end
  return highlights
end

---@param bufnr integer
---@param opts nil|table
---    jump boolean
---    jump_first boolean
---@return boolean
local function render_buffer(bufnr, opts)
  if bufnr == 0 then
    bufnr = vim.api.nvim_get_current_buf()
  end
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return false
  end
  local bufname = vim.api.nvim_buf_get_name(bufnr)
  opts = vim.tbl_extend('keep', opts or {}, {
    jump = false,
    jump_first = false,
  })
  local scheme = util.parse_url(bufname)
  local adapter = util.get_adapter(bufnr, true)
  if not scheme or not adapter then
    return false
  end
  local entries = cache.list_url(bufname)
  local entry_list = vim.tbl_values(entries)

  -- Only sort the entries once we have them all
  if not vim.b[bufnr].oil_rendering then
    table.sort(entry_list, get_sort_function(adapter, #entry_list))
  end

  local jump_idx
  if opts.jump_first then
    jump_idx = 1
  end
  local seek_after_render_found = false
  local seek_after_render = M.get_last_cursor(bufname)
  local column_defs = columns.get_supported_columns(scheme)
  local line_table = {}
  local col_width = {}
  local col_align = {}
  local col_has_data = {}
  for i, col_def in ipairs(column_defs) do
    col_width[i] = 1
    col_has_data[i] = false
    local _, conf = util.split_config(col_def)
    col_align[i] = conf and conf.align or 'left'
  end

  local function collect_entry(entry, is_hidden)
    local cols = M.format_entry_line(entry, adapter, is_hidden, bufnr)
    table.insert(line_table, cols)
    for i, col_def in ipairs(column_defs) do
      local chunk = columns.render_col(adapter, col_def, entry, bufnr)
      if chunk ~= columns.EMPTY then
        col_has_data[i] = true
      end
      local text = type(chunk) == 'table' and chunk[1] or chunk
      ---@cast text string
      col_width[i] = math.max(col_width[i], vim.api.nvim_strwidth(text))
    end
  end

  local parent_entry = { 0, '..', 'directory' }
  if M.should_display(bufnr, parent_entry) then
    collect_entry(parent_entry, true)
  end

  for _, entry in ipairs(entry_list) do
    local should_display, is_hidden = M.should_display(bufnr, entry)
    if should_display then
      collect_entry(entry, is_hidden)

      local name = entry[FIELD_NAME]
      if seek_after_render == name then
        seek_after_render_found = true
        jump_idx = #line_table
      end
    end
  end

  for i = 1, #col_width do
    if not col_has_data[i] then
      col_width[i] = 0
    end
  end

  local lines = util.render_table(line_table, {})

  _rendering[bufnr] = true
  vim.bo[bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, true, lines)
  vim.bo[bufnr].modifiable = false
  vim.bo[bufnr].modified = false
  vim.api.nvim_buf_clear_namespace(bufnr, vim.api.nvim_create_namespace('Canola'), 0, -1)
  vim.api.nvim_buf_set_extmark(bufnr, decor_ns, 0, 0, {
    virt_text = { { '' } },
    virt_text_pos = 'inline',
  })
  _rendering[bufnr] = nil
  session[bufnr].col_width = col_width
  session[bufnr].col_align = col_align
  session[bufnr].hl_cache = nil

  if opts.jump then
    -- TODO why is the schedule necessary?
    vim.schedule(function()
      for _, winid in ipairs(vim.api.nvim_list_wins()) do
        if vim.api.nvim_win_is_valid(winid) and vim.api.nvim_win_get_buf(winid) == bufnr then
          if jump_idx then
            local lnum = jump_idx
            local line = vim.api.nvim_buf_get_lines(bufnr, lnum - 1, lnum, true)[1]
            local id_str = line:match('^/(%d+)')
            local id = tonumber(id_str)
            if id then
              local entry = cache.get_entry_by_id(id)
              if entry then
                local name = entry[FIELD_NAME]
                local col = line:find(name, 1, true) or (id_str:len() + 1)
                vim.api.nvim_win_set_cursor(winid, { lnum, col - 1 })
                return
              end
            end
          end

          constrain_cursor(bufnr, 'name')
        end
      end
    end)
  end
  return seek_after_render_found
end

---@param name string
---@param meta? table
---@return string filename
---@return string|nil link_target
local function get_link_text(name, meta)
  local link_text
  if meta then
    if meta.link_stat and meta.link_stat.type == 'directory' then
      name = name .. '/'
    end

    if meta.link then
      link_text = '-> ' .. meta.link:gsub('\n', '')
      if meta.link_stat and meta.link_stat.type == 'directory' then
        link_text = util.addslash(link_text)
      end
    end
  end

  return name, link_text
end

---@param entry canola.InternalEntry
---@param adapter canola.Adapter
---@param is_hidden boolean
---@param bufnr integer
---@return canola.TextChunk[]
M.format_entry_line = function(entry, adapter, is_hidden, bufnr)
  local name = entry[FIELD_NAME]
  local meta = entry[FIELD_META]
  local hl_suffix = ''
  if is_hidden then
    hl_suffix = 'Hidden'
  end
  if meta and meta.display_name then
    name = meta.display_name
  end
  -- We can't handle newlines in filenames (and shame on you for doing that)
  name = name:gsub('\n', '')
  -- First put the unique ID
  local cols = {}
  local id_key = cache.format_id(entry[FIELD_ID])
  table.insert(cols, id_key)
  -- Always add the entry name at the end
  local entry_type = entry[FIELD_TYPE]

  local custom_hl
  for _, pair in ipairs(config.highlights.filename) do
    if name:match(pair[1]) then
      custom_hl = pair[2]
      break
    end
  end

  local link_name, link_name_hl, link_target, link_target_hl
  if custom_hl then
    if entry_type == 'link' then
      link_name, link_target = get_link_text(name, meta)
      link_name_hl = custom_hl
      if link_target then
        link_target_hl = custom_hl
      end
    else
      if entry_type == 'directory' then
        name = name .. '/'
      end
      table.insert(cols, { name, custom_hl })
      return cols
    end
  end

  local highlight_as_executable = false
  if entry_type ~= 'directory' then
    local lower = name:lower()
    if
      lower:match('%.exe$')
      or lower:match('%.bat$')
      or lower:match('%.cmd$')
      or lower:match('%.com$')
      or lower:match('%.ps1$')
    then
      highlight_as_executable = true
    -- selene: allow(if_same_then_else)
    elseif is_unix_executable(entry) then
      highlight_as_executable = true
    end
  end

  if entry_type == 'directory' then
    table.insert(cols, { name .. '/', 'CanolaDir' .. hl_suffix })
  elseif entry_type == 'socket' then
    table.insert(cols, { name, 'CanolaSocket' .. hl_suffix })
  elseif entry_type == 'link' then
    if not link_name then
      link_name, link_target = get_link_text(name, meta)
    end
    local is_orphan = not (meta and meta.link_stat)
    if not link_name_hl then
      if highlight_as_executable then
        link_name_hl = 'CanolaExecutable' .. hl_suffix
      else
        link_name_hl = (is_orphan and 'CanolaOrphanLink' or 'CanolaLink') .. hl_suffix
      end
    end
    table.insert(cols, { link_name, link_name_hl })

    if link_target then
      if not link_target_hl then
        link_target_hl = (is_orphan and 'CanolaOrphanLinkTarget' or 'CanolaLinkTarget') .. hl_suffix
      end
      table.insert(cols, { link_target, link_target_hl })
    end
  elseif highlight_as_executable then
    table.insert(cols, { name, 'CanolaExecutable' .. hl_suffix })
  else
    table.insert(cols, { name, 'CanolaFile' .. hl_suffix })
  end

  return cols
end

---Get the column names that are used for view and sort
---@return string[]
local function get_used_columns()
  local cols = {}
  for _, def in ipairs(config.columns) do
    local name = util.split_config(def)
    table.insert(cols, name)
  end
  for _, sort_pair in ipairs(config._sort_spec) do
    local name = sort_pair[1]
    table.insert(cols, name)
  end
  return cols
end

---@type table<integer, fun(message: string)[]>
local pending_renders = {}

---@param bufnr integer
---@param opts nil|table
---    refetch nil|boolean Defaults to true
---@param caller_callback nil|fun(err: nil|string)
M.render_buffer_async = function(bufnr, opts, caller_callback)
  local function callback(err)
    if not err then
      local is_first = not vim.b[bufnr].canola_ready
      local bufname = vim.api.nvim_buf_get_name(bufnr)
      vim.api.nvim_exec_autocmds('User', {
        pattern = 'CanolaReadPost',
        modeline = false,
        data = {
          buf = bufnr,
          url = bufname,
          entry_count = vim.api.nvim_buf_line_count(bufnr),
          first = is_first,
        },
      })
    end
    if caller_callback then
      caller_callback(err)
    end
  end

  opts = vim.tbl_deep_extend('keep', opts or {}, {
    refetch = true,
  })
  ---@cast opts -nil
  if bufnr == 0 then
    bufnr = vim.api.nvim_get_current_buf()
  end

  -- If we're already rendering, queue up another rerender after it's complete
  if vim.b[bufnr].oil_rendering then
    if not pending_renders[bufnr] then
      pending_renders[bufnr] = { callback }
    elseif callback then
      table.insert(pending_renders[bufnr], callback)
    end
    return
  end

  local bufname = vim.api.nvim_buf_get_name(bufnr)
  vim.b[bufnr].oil_rendering = true
  local _, dir = util.parse_url(bufname)
  -- Undo should not return to a blank buffer
  -- Method taken from :h clear-undo
  vim.bo[bufnr].undolevels = -1
  local handle_error = vim.schedule_wrap(function(message)
    vim.b[bufnr].oil_rendering = false
    vim.bo[bufnr].undolevels = vim.api.nvim_get_option_value('undolevels', { scope = 'global' })
    util.render_text(bufnr, { 'Error: ' .. message })
    if pending_renders[bufnr] then
      for _, cb in ipairs(pending_renders[bufnr]) do
        cb(message)
      end
      pending_renders[bufnr] = nil
    end
    if callback then
      callback(message)
    else
      error(message)
    end
  end)
  if not dir then
    handle_error(string.format("Could not parse oil url '%s'", bufname))
    return
  end
  local adapter = util.get_adapter(bufnr, true)
  if not adapter then
    handle_error(string.format("[canola] no adapter for buffer '%s'", bufname))
    return
  end
  local start_ms = uv.hrtime() / 1e6
  local seek_after_render_found = false
  local first = true
  vim.bo[bufnr].modifiable = false
  vim.bo[bufnr].modified = false
  loading.set_loading(bufnr, true)

  local finish = vim.schedule_wrap(function()
    if not vim.api.nvim_buf_is_valid(bufnr) then
      return
    end
    vim.b[bufnr].oil_rendering = false
    loading.set_loading(bufnr, false)
    render_buffer(bufnr, { jump = true })
    M.set_last_cursor(bufname, nil)
    vim.bo[bufnr].undolevels = vim.api.nvim_get_option_value('undolevels', { scope = 'global' })
    vim.bo[bufnr].modifiable = not buffers_locked and adapter.is_modifiable(bufnr)
    if callback then
      callback()
    end

    -- If there were any concurrent calls to render this buffer, process them now
    if pending_renders[bufnr] then
      local all_cbs = pending_renders[bufnr]
      pending_renders[bufnr] = nil
      local new_cb = function(...)
        for _, cb in ipairs(all_cbs) do
          cb(...)
        end
      end
      M.render_buffer_async(bufnr, {}, new_cb)
    end
  end)
  if not opts.refetch then
    finish()
    return
  end

  cache.begin_update_url(bufname)
  local num_iterations = 0
  adapter.list(bufname, get_used_columns(), function(err, entries, fetch_more)
    loading.set_loading(bufnr, false)
    if err then
      cache.end_update_url(bufname)
      handle_error(err)
      return
    end
    if entries then
      for _, entry in ipairs(entries) do
        cache.store_entry(bufname, entry)
      end
    end
    if fetch_more then
      local now = uv.hrtime() / 1e6
      local delta = now - start_ms
      -- If we've been chugging for more than 40ms, go ahead and render what we have
      if (delta > 25 and num_iterations < 1) or delta > 500 then
        num_iterations = num_iterations + 1
        start_ms = now
        vim.schedule(function()
          seek_after_render_found =
            render_buffer(bufnr, { jump = not seek_after_render_found, jump_first = first })
          start_ms = uv.hrtime() / 1e6
        end)
      end
      first = false
      vim.defer_fn(fetch_more, 4)
    else
      cache.end_update_url(bufname)
      -- done iterating
      finish()
    end
  end)
end

M.setup_decoration_provider = function()
  vim.api.nvim_set_decoration_provider(decor_ns, {
    on_start = function()
      decor_ctx = {}
      return true
    end,
    on_win = function(_, winid, bufnr, toprow, botrow)
      local sess = session[bufnr]
      if not sess then
        return false
      end
      if decor_ctx[bufnr] then
        return
      end
      local adapter = util.get_adapter(bufnr, true)
      if not adapter then
        return false
      end
      local bufname = vim.api.nvim_buf_get_name(bufnr)
      local scheme = util.parse_url(bufname)
      if not scheme then
        return false
      end
      decor_ctx[bufnr] = {
        adapter = adapter,
        column_defs = columns.get_supported_columns(scheme),
        col_width = sess.col_width or {},
        col_align = sess.col_align or {},
      }
    end,
    on_line = function(_, winid, bufnr, row)
      local ctx = decor_ctx[bufnr]
      if not ctx then
        return
      end
      local line = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1]
      if not line or line == '' then
        return
      end
      local id = tonumber(line:match('^/(%d+)'))
      if not id then
        return
      end
      local sess = session[bufnr]
      local hl_cache = sess and sess.hl_cache
      local cached = hl_cache and hl_cache[id]
      local name_highlights, virt_chunks
      if cached and cached.line == line then
        name_highlights = cached.name_highlights
        virt_chunks = cached.virt_chunks
      else
        local entry = id == 0 and { 0, '..', 'directory' } or cache.get_entry_by_id(id)
        if not entry then
          return
        end
        local _, is_hidden = M.should_display(bufnr, entry)
        local cols = M.format_entry_line(entry, ctx.adapter, is_hidden, bufnr)
        name_highlights = compute_highlights_for_cols(cols, {}, {}, #line)
        virt_chunks = {}
        for i, col_def in ipairs(ctx.column_defs) do
          if (ctx.col_width[i] or 0) > 0 then
            local chunk = columns.render_col(ctx.adapter, col_def, entry, bufnr)
            local text = type(chunk) == 'table' and chunk[1] or chunk
            ---@cast text string
            local hl = type(chunk) == 'table' and chunk[2] or nil
            local padded = util.pad_align(text, ctx.col_width[i], ctx.col_align[i] or 'left')
            if type(hl) == 'table' then
              for _, range in ipairs(hl) do
                table.insert(virt_chunks, { text:sub(range[2] + 1, range[3]), range[1] })
              end
              table.insert(virt_chunks, { padded:sub(#text + 1) .. ' ' })
            else
              table.insert(virt_chunks, { padded .. ' ', hl })
            end
          end
        end
        if not hl_cache then
          hl_cache = {}
          sess.hl_cache = hl_cache
        end
        hl_cache[id] = { line = line, name_highlights = name_highlights, virt_chunks = virt_chunks }
      end
      local id_prefix = line:match('^/%d+ ')
      if id_prefix and #virt_chunks > 0 then
        vim.api.nvim_buf_set_extmark(bufnr, decor_ns, row, #id_prefix, {
          virt_text = virt_chunks,
          virt_text_pos = 'inline',
          ephemeral = true,
        })
      end
      for _, hl in ipairs(name_highlights) do
        vim.api.nvim_buf_set_extmark(bufnr, decor_ns, row, hl[2], {
          end_col = hl[3],
          hl_group = hl[1],
          ephemeral = true,
        })
      end
    end,
  })
end

return M
