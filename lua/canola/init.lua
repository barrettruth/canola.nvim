local M = {}

---@class (exact) canola.Entry
---@field name string
---@field type canola.EntryType
---@field id nil|integer Will be nil if it hasn't been persisted to disk yet
---@field parsed_name nil|string
---@field meta nil|table

---@alias canola.EntryType uv.aliases.fs_types
---@alias canola.HlRange { [1]: string, [2]: integer, [3]: integer } A tuple of highlight group name, col_start, col_end
---@alias canola.HlTuple { [1]: string, [2]: string } A tuple of text, highlight group
---@alias canola.HlRangeTuple { [1]: string, [2]: canola.HlRange[] } A tuple of text, internal highlights
---@alias canola.TextChunk string|canola.HlTuple|canola.HlRangeTuple
---@alias canola.CrossAdapterAction "copy"|"move"

---@class (exact) canola.Adapter
---@field name string The unique name of the adapter (this will be set automatically)
---@field list fun(path: string, column_defs: string[], cb: fun(err?: string, entries?: canola.InternalEntry[], fetch_more?: fun())) Async function to list a directory.
---@field is_modifiable fun(bufnr: integer): boolean Return true if this directory is modifiable (allows for directories with read-only permissions).
---@field get_column fun(name: string): nil|canola.ColumnDefinition If the adapter has any adapter-specific columns, return them when fetched by name.
---@field get_parent? fun(bufname: string): string Get the parent url of the given buffer
---@field normalize_url fun(url: string, callback: fun(url: string)) Before oil opens a url it will be normalized. This allows for link following, path normalizing, and converting an oil file url to the actual path of a file.
---@field get_entry_path? fun(url: string, entry: canola.Entry, callback: fun(path: string)) Similar to normalize_url, but used when selecting an entry
---@field render_action? fun(action: canola.Action): string Render a mutation action for display in the preview window. Only needed if adapter is modifiable.
---@field perform_action? fun(action: canola.Action, cb: fun(err: nil|string)) Perform a mutation action. Only needed if adapter is modifiable.
---@field read_file? fun(bufnr: integer) Used for adapters that deal with remote/virtual files. Read the contents of the file into a buffer.
---@field write_file? fun(bufnr: integer) Used for adapters that deal with remote/virtual files. Write the contents of a buffer to the destination.
---@field supported_cross_adapter_actions? table<string, canola.CrossAdapterAction> Mapping of adapter name to enum for all other adapters that can be used as a src or dest for move/copy actions.
---@field filter_action? fun(action: canola.Action): boolean When present, filter out actions as they are created
---@field filter_error? fun(action: canola.ParseError): boolean When present, filter out errors from parsing a buffer
---@field open_terminal? fun() Open a terminal session in the current directory. Used by the `open_terminal` action.

---Get the entry on a specific line (1-indexed)
---@param bufnr integer
---@param lnum integer
---@return nil|canola.Entry
M.get_entry_on_line = function(bufnr, lnum)
  local columns = require('canola.columns')
  local parser = require('canola.mutator.parser')
  local util = require('canola.util')
  if vim.bo[bufnr].filetype ~= 'canola' then
    return nil
  end
  local adapter = util.get_adapter(bufnr)
  if not adapter then
    return nil
  end

  local line = vim.api.nvim_buf_get_lines(bufnr, lnum - 1, lnum, true)[1]
  if not line then
    return nil
  end
  local column_defs = columns.get_supported_columns(adapter)
  local result = parser.parse_line(adapter, line, column_defs)
  if result then
    if result.entry then
      local entry = util.export_entry(result.entry)
      entry.parsed_name = result.data.name
      return entry
    else
      return {
        id = result.data.id,
        name = result.data.name,
        type = result.data._type,
        parsed_name = result.data.name,
      }
    end
  end
  -- This is a NEW entry that hasn't been saved yet
  local name = vim.trim(line)
  local entry_type
  if vim.endswith(name, '/') then
    name = name:sub(1, name:len() - 1)
    entry_type = 'directory'
  else
    entry_type = 'file'
  end
  if name == '' then
    return nil
  else
    return {
      name = name,
      type = entry_type,
      parsed_name = name,
    }
  end
end

---Get the entry currently under the cursor
---@return nil|canola.Entry
M.get_cursor_entry = function()
  local lnum = vim.api.nvim_win_get_cursor(0)[1]
  return M.get_entry_on_line(0, lnum)
end

---Discard all changes made to oil buffers
M.discard_all_changes = function()
  local view = require('canola.view')
  for _, bufnr in ipairs(view.get_all_buffers()) do
    if vim.bo[bufnr].modified then
      view.render_buffer_async(bufnr, {}, function(err)
        if err then
          vim.notify(
            string.format(
              'Error rendering oil buffer %s: %s',
              vim.api.nvim_buf_get_name(bufnr),
              err
            ),
            vim.log.levels.ERROR
          )
        end
      end)
    end
  end
end

---Change the display columns for oil
---@param cols canola.ColumnSpec[]
M.set_columns = function(cols)
  require('canola.view').set_columns(cols)
end

---Change the sort order for oil
---@param sort canola.SortSpec[] List of columns plus direction. See :help oil-columns to see which ones are sortable.
---@example
--- require("canola").set_sort({ { "type", "asc" }, { "size", "desc" } })
M.set_sort = function(sort)
  require('canola.view').set_sort(sort)
end

---Change how oil determines if the file is hidden
---@param is_hidden_file fun(filename: string, bufnr: integer, entry: canola.Entry): boolean Return true if the file/dir should be hidden
M.set_is_hidden_file = function(is_hidden_file)
  require('canola.view').set_is_hidden_file(is_hidden_file)
end

---Toggle hidden files and directories
M.toggle_hidden = function()
  require('canola.view').toggle_hidden()
end

---Register an external adapter for a URL scheme
---@param scheme string URL scheme including "://" (e.g. "canola-ssh://")
---@param name string Adapter module name (resolved via require("canola.adapters." .. name))
M.register_adapter = function(scheme, name)
  local config = require('canola.config')
  if not config.adapters then
    config.init()
  end
  if config.adapters[scheme] then
    return
  end
  config.adapters[scheme] = name
  config.adapter_to_scheme[name] = scheme
  config._adapter_by_scheme[scheme] = nil

  vim.filetype.add({
    pattern = { [scheme .. '.*'] = { 'canola', { priority = 10 } } },
  })
  local aug = vim.api.nvim_create_augroup('Canola', { clear = false })
  local pattern = scheme .. '*'
  vim.api.nvim_create_autocmd('BufReadCmd', {
    group = aug,
    pattern = pattern,
    nested = true,
    callback = function(params)
      M.load_oil_buffer(params.buf)
    end,
  })
  vim.api.nvim_create_autocmd('BufWriteCmd', {
    group = aug,
    pattern = pattern,
    nested = true,
    callback = M._buf_write_cmd,
  })
end

---Register a custom column
---@param name string Unique column name used in the `columns` config
---@param column canola.ColumnDefinition
M.register_column = function(name, column)
  local columns = require('canola.columns')
  columns.register(name, column)
end

---Get the current directory
---@param bufnr? integer
---@return nil|string
M.get_current_dir = function(bufnr)
  local config = require('canola.config')
  local fs = require('canola.fs')
  local util = require('canola.util')
  local buf_name = vim.api.nvim_buf_get_name(bufnr or 0)
  local scheme, path = util.parse_url(buf_name)
  if config.adapters[scheme] == 'files' then
    assert(path)
    return fs.posix_to_os_path(path)
  end
end

---Get the current buffer's oil URL (e.g. "canola:///path/" or "canola-ssh://host/path/")
---@param bufnr? integer
---@return nil|string
M.get_current_url = function(bufnr)
  local config = require('canola.config')
  local util = require('canola.util')
  local buf_name = vim.api.nvim_buf_get_name(bufnr or 0)
  local scheme = util.parse_url(buf_name)
  if scheme and config.adapters[scheme] then
    return buf_name
  end
end

---Get the oil url for a given directory
---@private
---@param dir nil|string When nil, use the cwd
---@param use_oil_parent nil|boolean If in an oil buffer, return the parent (default true)
---@return string The parent url
---@return nil|string The basename (if present) of the file/dir we were just in
M.get_url_for_path = function(dir, use_oil_parent)
  if use_oil_parent == nil then
    use_oil_parent = true
  end
  local config = require('canola.config')
  local fs = require('canola.fs')
  local util = require('canola.util')
  if vim.bo.filetype == 'netrw' and not dir then
    dir = vim.b.netrw_curdir
  end
  if dir then
    local scheme = util.parse_url(dir)
    if scheme then
      return dir
    end
    local abspath = vim.fn.fnamemodify(dir, ':p')
    local path = fs.os_to_posix_path(abspath)
    return config.adapter_to_scheme.files .. path
  else
    local bufname = vim.api.nvim_buf_get_name(0)
    return M.get_buffer_parent_url(bufname, use_oil_parent)
  end
end

---@private
---@param bufname string
---@param use_oil_parent boolean If in an oil buffer, return the parent
---@return string
---@return nil|string
M.get_buffer_parent_url = function(bufname, use_oil_parent)
  local config = require('canola.config')
  local fs = require('canola.fs')
  local pathutil = require('canola.pathutil')
  local util = require('canola.util')
  local scheme, path = util.parse_url(bufname)
  if not scheme then
    local parent, basename
    scheme = config.adapter_to_scheme.files
    if bufname == '' then
      parent = fs.os_to_posix_path(vim.fn.getcwd())
    else
      parent = fs.os_to_posix_path(vim.fn.fnamemodify(bufname, ':p:h'))
      basename = vim.fn.fnamemodify(bufname, ':t')
    end
    local parent_url = util.addslash(scheme .. parent)
    return parent_url, basename
  else
    assert(path)
    if scheme == 'term://' then
      ---@type string
      path = vim.fn.expand(path:match('^(.*)//')) ---@diagnostic disable-line: assign-type-mismatch
      return config.adapter_to_scheme.files .. util.addslash(path)
    end

    -- This is some unknown buffer scheme
    if not config.adapters[scheme] then
      return vim.fn.getcwd()
    end

    if not use_oil_parent then
      return bufname
    end
    local adapter = assert(config.get_adapter_by_scheme(scheme))
    local parent_url
    if adapter and adapter.get_parent then
      local adapter_scheme = config.adapter_to_scheme[adapter.name]
      parent_url = adapter.get_parent(adapter_scheme .. path)
    else
      local parent = pathutil.parent(path)
      parent_url = scheme .. util.addslash(parent)
    end
    if parent_url == bufname then
      return parent_url
    else
      return util.addslash(parent_url), pathutil.basename(path)
    end
  end
end

---@class (exact) canola.OpenOpts
---@field preview? canola.OpenPreviewOpts When present, open the preview window after opening oil

---Open oil browser in a floating window
---@param dir? string When nil, open the parent of the current buffer, or the cwd if current buffer is not a file
---@param opts? canola.OpenOpts
---@param cb? fun() Called after the oil buffer is ready
M.open_float = function(dir, opts, cb)
  opts = opts or {}
  local config = require('canola.config')
  local layout = require('canola.layout')
  local util = require('canola.util')
  local view = require('canola.view')

  local parent_url, basename = M.get_url_for_path(dir)
  if basename then
    view.set_last_cursor(parent_url, basename)
  end

  if vim.w.is_canola_win then
    vim.cmd.edit({ args = { util.escape_filename(parent_url) }, mods = { keepalt = true } })
    if config.buf.buflisted ~= nil then
      vim.api.nvim_set_option_value('buflisted', config.buf.buflisted, { buf = 0 })
    end
    util.run_after_load(0, function()
      if opts.preview then
        M.open_preview(opts.preview, cb)
      elseif cb then
        cb()
      end
    end)
    return
  end

  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.bo[bufnr].bufhidden = 'wipe'
  local win_opts = layout.get_fullscreen_win_opts()

  local original_winid = vim.api.nvim_get_current_win()
  local ev_data = { buf = bufnr, conf = win_opts }
  vim.api.nvim_exec_autocmds(
    'User',
    { pattern = 'CanolaFloatConfig', modeline = false, data = ev_data }
  )
  local winid = vim.api.nvim_open_win(bufnr, true, ev_data.conf)
  vim.w[winid].is_canola_win = true
  vim.w[winid].canola_original_win = original_winid
  for k, v in pairs(config.float.win) do
    vim.api.nvim_set_option_value(k, v, { scope = 'local', win = winid })
  end
  local autocmds = {}
  table.insert(
    autocmds,
    vim.api.nvim_create_autocmd('WinLeave', {
      desc = 'Close floating oil window',
      group = 'Canola',
      callback = vim.schedule_wrap(function()
        if util.is_floating_win() or vim.fn.win_gettype() == 'command' then
          return
        end
        if not vim.api.nvim_win_is_valid(winid) then
          for _, id in ipairs(autocmds) do
            vim.api.nvim_del_autocmd(id)
          end
          autocmds = {}
          return
        end
        if vim.w[winid].canola_keep_open then
          return
        end
        vim.api.nvim_win_close(winid, true)
        for _, id in ipairs(autocmds) do
          vim.api.nvim_del_autocmd(id)
        end
        autocmds = {}
      end),
      nested = true,
    })
  )

  table.insert(
    autocmds,
    vim.api.nvim_create_autocmd('BufWinEnter', {
      desc = 'Reset local oil window options when buffer changes',
      pattern = '*',
      callback = function(params)
        local winbuf = params.buf
        if not vim.api.nvim_win_is_valid(winid) or vim.api.nvim_win_get_buf(winid) ~= winbuf then
          return
        end
        for k, v in pairs(config.float.win) do
          vim.api.nvim_set_option_value(k, v, { scope = 'local', win = winid })
        end

        if config.float.title then
          if config.float.border ~= nil and config.float.border ~= 'none' then
            local cur_win_opts = vim.api.nvim_win_get_config(winid)
            vim.api.nvim_win_set_config(winid, {
              relative = 'editor',
              row = cur_win_opts.row,
              col = cur_win_opts.col,
              width = cur_win_opts.width,
              height = cur_win_opts.height,
              title = util.get_title(winid),
            })
          else
            util.add_title_to_win(winid)
          end
        end
      end,
    })
  )

  vim.cmd.edit({ args = { util.escape_filename(parent_url) }, mods = { keepalt = true } })
  -- :edit will set buflisted = true, but we may not want that
  if config.buf.buflisted ~= nil then
    vim.api.nvim_set_option_value('buflisted', config.buf.buflisted, { buf = 0 })
  end

  util.run_after_load(0, function()
    if opts.preview then
      M.open_preview(opts.preview, cb)
    elseif cb then
      cb()
    end
  end)

  if config.float.title and (config.float.border == nil or config.float.border == 'none') then
    util.add_title_to_win(winid)
  end
end

---Open oil browser in a floating window, or close it if open
---@param dir nil|string When nil, open the parent of the current buffer, or the cwd if current buffer is not a file
---@param opts? canola.OpenOpts
---@param cb? fun() Called after the oil buffer is ready
M.toggle_float = function(dir, opts, cb)
  if vim.w.is_canola_win then
    M.close()
    if cb then
      cb()
    end
  else
    M.open_float(dir, opts, cb)
  end
end

---@class (exact) canola.OpenSplitOpts : canola.OpenOpts
---@field vertical? boolean Open the buffer in a vertical split
---@field horizontal? boolean Open the buffer in a horizontal split
---@field split? "aboveleft"|"belowright"|"topleft"|"botright" Split modifier

---Open oil browser in a split window
---@param dir? string When nil, open the parent of the current buffer, or the cwd if current buffer is not a file
---@param opts? canola.OpenSplitOpts
---@param cb? fun() Called after the oil buffer is ready
M.open_split = function(dir, opts, cb)
  opts = opts or {}
  local config = require('canola.config')
  local util = require('canola.util')
  local view = require('canola.view')

  local parent_url, basename = M.get_url_for_path(dir)
  if basename then
    view.set_last_cursor(parent_url, basename)
  end

  if not opts.vertical and opts.horizontal == nil then
    opts.horizontal = true
  end
  if not opts.split then
    if opts.horizontal then
      opts.split = vim.o.splitbelow and 'belowright' or 'aboveleft'
    else
      opts.split = vim.o.splitright and 'belowright' or 'aboveleft'
    end
  end

  local mods = {
    vertical = opts.vertical,
    horizontal = opts.horizontal,
    split = opts.split,
  }

  local original_winid = vim.api.nvim_get_current_win()
  vim.cmd.split({ mods = mods })
  local winid = vim.api.nvim_get_current_win()

  vim.w[winid].is_canola_win = true
  vim.w[winid].canola_original_win = original_winid

  vim.cmd.edit({ args = { util.escape_filename(parent_url) }, mods = { keepalt = true } })
  if config.buf.buflisted ~= nil then
    vim.api.nvim_set_option_value('buflisted', config.buf.buflisted, { buf = 0 })
  end

  util.run_after_load(0, function()
    if opts.preview then
      M.open_preview(opts.preview, cb)
    elseif cb then
      cb()
    end
  end)
end

---Open oil browser in a split window, or close it if open
---@param dir nil|string When nil, open the parent of the current buffer, or the cwd if current buffer is not a file
---@param opts? canola.OpenSplitOpts
---@param cb? fun() Called after the oil buffer is ready
M.toggle_split = function(dir, opts, cb)
  if vim.w.is_canola_win then
    M.close()
    if cb then
      cb()
    end
  else
    M.open_split(dir, opts, cb)
  end
end

---@param oil_bufnr? integer
local function update_preview_window(oil_bufnr)
  oil_bufnr = oil_bufnr or 0
  local util = require('canola.util')
  util.run_after_load(oil_bufnr, function()
    local cursor_entry = M.get_cursor_entry()
    local preview_win_id = util.get_preview_win()
    if
      cursor_entry
      and preview_win_id
      and cursor_entry.id ~= vim.w[preview_win_id].canola_entry_id
    then
      M.open_preview()
    end
  end)
end

---Open oil browser for a directory
---@param dir? string When nil, open the parent of the current buffer, or the cwd if current buffer is not a file
---@param opts? canola.OpenOpts
---@param cb? fun() Called after the oil buffer is ready
M.open = function(dir, opts, cb)
  opts = opts or {}
  local config = require('canola.config')
  if config.float.default then
    return M.open_float(dir, opts, cb)
  end
  local util = require('canola.util')
  local view = require('canola.view')
  local parent_url, basename = M.get_url_for_path(dir)
  if parent_url == vim.api.nvim_buf_get_name(0) then
    return
  end
  if basename then
    view.set_last_cursor(parent_url, basename)
  end
  vim.cmd.edit({ args = { util.escape_filename(parent_url) }, mods = { keepalt = true } })
  -- :edit will set buflisted = true, but we may not want that
  if config.buf.buflisted ~= nil then
    vim.api.nvim_set_option_value('buflisted', config.buf.buflisted, { buf = 0 })
  end

  util.run_after_load(0, function()
    if opts.preview then
      M.open_preview(opts.preview, cb)
    elseif cb then
      cb()
    end
  end)

  -- If preview window exists, update its content
  update_preview_window()
end

---@class canola.CloseOpts
---@field exit_if_last_buf? boolean Exit vim if this oil buffer is the last open buffer

---Restore the buffer that was present when oil was opened
---@param opts? canola.CloseOpts
M.close = function(opts)
  opts = opts or {}
  local mode = vim.api.nvim_get_mode().mode
  if mode:match('^[vVsS\22\19]') or mode:match('^no') then
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, true, true), 'n', false)
    return
  end
  -- If we're in a floating oil window, close it and try to restore focus to the original window
  if vim.w.is_canola_win then
    local original_winid = vim.w.canola_original_win
    local ok, _ = pcall(vim.api.nvim_win_close, 0, true)
    if not ok then
      vim.cmd.enew()
    end
    if original_winid and vim.api.nvim_win_is_valid(original_winid) then
      vim.api.nvim_set_current_win(original_winid)
    end
    return
  end
  local ok, bufnr = pcall(vim.api.nvim_win_get_var, 0, 'canola_original_buffer')
  if ok and vim.api.nvim_buf_is_valid(bufnr) then
    vim.api.nvim_win_set_buf(0, bufnr)
    if vim.w.canola_original_view then
      vim.fn.winrestview(vim.w.canola_original_view)
    end
    return
  end

  -- Deleting the buffer closes all windows with that buffer open, so navigate to a different
  -- buffer first
  local oilbuf = vim.api.nvim_get_current_buf()
  ok = pcall(vim.cmd.bprev)
  -- If `bprev` failed, there are no buffers open
  if not ok then
    -- either exit or create a new blank buffer
    if opts.exit_if_last_buf then
      vim.cmd.quit()
    else
      vim.cmd.enew()
    end
  end
  vim.api.nvim_buf_delete(oilbuf, { force = true })
end

---@param dir? string
---@param opts? canola.OpenOpts
---@param cb? fun()
M.toggle = function(dir, opts, cb)
  if vim.w.is_canola_win or vim.bo.filetype == 'canola' then
    M.close()
    if cb then
      cb()
    end
  else
    M.open(dir, opts, cb)
  end
end

---@class canola.OpenPreviewOpts
---@field vertical? boolean Open the buffer in a vertical split
---@field horizontal? boolean Open the buffer in a horizontal split
---@field split? "aboveleft"|"belowright"|"topleft"|"botright" Split modifier

---Preview the entry under the cursor in a split
---@param opts? canola.OpenPreviewOpts
---@param callback? fun(err: nil|string) Called once the preview window has been opened
M.open_preview = function(opts, callback)
  opts = opts or {}
  local config = require('canola.config')
  local layout = require('canola.layout')
  local util = require('canola.util')

  local function finish(err)
    if err then
      vim.notify(err, vim.log.levels.ERROR)
    end
    if callback then
      callback(err)
    end
  end

  if not opts.horizontal and opts.vertical == nil then
    opts.vertical = true
  end
  if not opts.split then
    if opts.horizontal then
      opts.split = vim.o.splitbelow and 'belowright' or 'aboveleft'
    else
      opts.split = vim.o.splitright and 'belowright' or 'aboveleft'
    end
  end

  local preview_win = util.get_preview_win({ include_not_owned = true })
  local prev_win = vim.api.nvim_get_current_win()
  local bufnr = vim.api.nvim_get_current_buf()

  local entry = M.get_cursor_entry()
  if not entry then
    return finish('Could not find entry under cursor')
  end
  local entry_title = entry.name
  if entry.type == 'directory' then
    entry_title = entry_title .. '/'
  end

  if util.is_floating_win() then
    if preview_win == nil then
      local root_win_opts, preview_win_opts =
        layout.split_window(0, config.float.preview_split, config.float.padding)

      local win_opts_oil = {
        relative = 'editor',
        width = root_win_opts.width,
        height = root_win_opts.height,
        row = root_win_opts.row,
        col = root_win_opts.col,
        border = config.float.border,
        zindex = 45,
      }
      vim.api.nvim_win_set_config(0, win_opts_oil)
      local win_opts = {
        relative = 'editor',
        width = preview_win_opts.width,
        height = preview_win_opts.height,
        row = preview_win_opts.row,
        col = preview_win_opts.col,
        border = config.float.border,
        zindex = 45,
        focusable = false,
        noautocmd = true,
        style = 'minimal',
      }

      win_opts.title = entry_title

      local preview_ev_data = { buf = bufnr, conf = win_opts }
      vim.api.nvim_exec_autocmds(
        'User',
        { pattern = 'CanolaFloatConfig', modeline = false, data = preview_ev_data }
      )
      preview_win = vim.api.nvim_open_win(bufnr, true, preview_ev_data.conf)
      vim.api.nvim_set_option_value('previewwindow', true, { scope = 'local', win = preview_win })
      vim.api.nvim_win_set_var(preview_win, 'oil_preview', true)
      vim.api.nvim_set_current_win(prev_win)
    else
      vim.api.nvim_win_set_config(preview_win, { title = entry_title })
    end
  end

  local cmd = preview_win and 'buffer' or 'sbuffer'
  local mods = {
    vertical = opts.vertical,
    horizontal = opts.horizontal,
    split = opts.split,
  }

  -- HACK Switching windows takes us out of visual mode.
  -- Switching with nvim_set_current_win causes the previous visual selection (as used by `gv`) to
  -- not get set properly. So we have to switch windows this way instead.
  local hack_set_win = function(winid)
    local winnr = vim.api.nvim_win_get_number(winid)
    vim.cmd.wincmd({ args = { 'w' }, count = winnr })
  end

  util.get_edit_path(bufnr, entry, function(normalized_url)
    local mc = package.loaded['multicursor-nvim']
    local has_multicursors = mc and mc.hasCursors()
    local is_visual_mode = util.is_visual_mode()
    if preview_win then
      if is_visual_mode then
        hack_set_win(preview_win)
      else
        vim.api.nvim_set_current_win(preview_win)
      end
    end

    local entry_is_file = not vim.endswith(normalized_url, '/')
    local filebufnr
    if entry_is_file then
      local max_mb = config.preview.max_file_size_mb
      local _size = entry.meta and entry.meta.stat and entry.meta.stat.size
      if not _size then
        local _st = vim.uv.fs_stat(normalized_url)
        _size = _st and _st.size
      end
      if max_mb and _size and _size > max_mb * 1024 * 1024 then
        if preview_win then
          filebufnr = vim.api.nvim_create_buf(false, true)
          vim.bo[filebufnr].bufhidden = 'wipe'
          vim.bo[filebufnr].buftype = 'nofile'
          util.render_text(filebufnr, 'File too large to preview', { winid = preview_win })
        else
          vim.notify('File too large to preview', vim.log.levels.WARN)
          return finish()
        end
      else
        local disable_ev = { filename = normalized_url, result = false }
        vim.api.nvim_exec_autocmds(
          'User',
          { pattern = 'CanolaPreviewDisable', modeline = false, data = disable_ev }
        )
        if disable_ev.result then
          filebufnr = vim.api.nvim_create_buf(false, true)
          vim.bo[filebufnr].bufhidden = 'wipe'
          vim.bo[filebufnr].buftype = 'nofile'
          util.render_text(filebufnr, 'Preview disabled', { winid = preview_win })
        elseif
          config._preview_method ~= 'load'
          and not util.file_matches_bufreadcmd(normalized_url)
        then
          filebufnr = util.read_file_to_scratch_buffer(normalized_url, config._preview_method)
        end
      end
    end

    if not filebufnr then
      filebufnr = vim.fn.bufadd(normalized_url)
      if entry_is_file and vim.fn.bufloaded(filebufnr) == 0 then
        vim.bo[filebufnr].bufhidden = 'wipe'
        vim.b[filebufnr].canola_preview_buffer = true
      end
    end

    ---@diagnostic disable-next-line: param-type-mismatch
    local ok, err = pcall(vim.cmd, {
      cmd = cmd,
      args = { filebufnr },
      mods = mods,
    })
    -- Ignore swapfile errors
    if not ok and err and not err:match('^Vim:E325:') then
      vim.api.nvim_echo({ { err, 'Error' } }, true, {})
    end

    -- If we called open_preview during an autocmd, then the edit command may not trigger the
    -- BufReadCmd to load the buffer. So we need to do it manually.
    if util.is_canola_bufnr(filebufnr) and not vim.b[filebufnr].canola_ready then
      M.load_oil_buffer(filebufnr)
    end

    vim.api.nvim_set_option_value('previewwindow', true, { scope = 'local', win = 0 })
    vim.api.nvim_win_set_var(0, 'oil_preview', true)
    for k, v in pairs(config.preview.win) do
      vim.api.nvim_set_option_value(k, v, { scope = 'local', win = preview_win })
    end
    vim.w.canola_entry_id = entry.id
    vim.w.canola_source_win = prev_win
    if has_multicursors then
      hack_set_win(prev_win)
      mc.restoreCursors()
    elseif is_visual_mode then
      hack_set_win(prev_win)
      -- Restore the visual selection
      vim.cmd.normal({ args = { 'gv' }, bang = true })
    else
      vim.api.nvim_set_current_win(prev_win)
    end
    finish()
  end)
end

---@class (exact) canola.SelectOpts
---@field vertical? boolean Open the buffer in a vertical split
---@field horizontal? boolean Open the buffer in a horizontal split
---@field split? "aboveleft"|"belowright"|"topleft"|"botright" Split modifier
---@field tab? boolean Open the buffer in a new tab
---@field confirm? boolean If true, always show confirmation; if false, never show; if nil, respect config
---@field close? boolean Close the original oil buffer once selection is made
---@field handle_buffer_callback? fun(buf_id: integer) If defined, all other buffer related options here would be ignored. This callback allows you to take over the process of opening the buffer yourself.

---Select the entry under the cursor
---@param opts nil|canola.SelectOpts
---@param callback nil|fun(err: nil|string) Called once all entries have been opened
M.select = function(opts, callback)
  local cache = require('canola.cache')
  local config = require('canola.config')
  local constants = require('canola.constants')
  local util = require('canola.util')
  local FIELD_META = constants.FIELD_META
  opts = vim.tbl_extend('keep', opts or {}, {})

  local function finish(err)
    if err then
      vim.notify(err, vim.log.levels.ERROR)
    end
    if callback then
      callback(err)
    end
  end
  if not opts.split and (opts.horizontal or opts.vertical) then
    if opts.horizontal then
      opts.split = vim.o.splitbelow and 'belowright' or 'aboveleft'
    else
      opts.split = vim.o.splitright and 'belowright' or 'aboveleft'
    end
  end
  if opts.tab and opts.split then
    return finish('Cannot use split=true when tab = true')
  end
  local adapter = util.get_adapter(0)
  if not adapter then
    return finish('Not an oil buffer')
  end

  local visual_range = util.get_visual_range()

  ---@type canola.Entry[]
  local entries = {}
  if visual_range then
    for i = visual_range.start_lnum, visual_range.end_lnum do
      local entry = M.get_entry_on_line(0, i)
      if entry then
        table.insert(entries, entry)
      end
    end
  else
    local entry = M.get_cursor_entry()
    if entry then
      table.insert(entries, entry)
    end
  end
  if next(entries) == nil then
    return finish('Could not find entry under cursor')
  end

  -- Check if any of these entries are moved from their original location
  local bufname = vim.api.nvim_buf_get_name(0)
  local any_moved = false
  for _, entry in ipairs(entries) do
    -- Ignore entries with ID 0 (typically the "../" entry)
    if entry.id ~= 0 then
      local is_new_entry = entry.id == nil
      local is_moved_from_dir = entry.id and cache.get_parent_url(entry.id) ~= bufname
      local is_renamed = entry.parsed_name ~= entry.name
      local internal_entry = entry.id and cache.get_entry_by_id(entry.id)
      if internal_entry then
        local meta = internal_entry[FIELD_META]
        if meta and meta.display_name then
          is_renamed = entry.parsed_name ~= meta.display_name
        end
      end
      if is_new_entry or is_moved_from_dir or is_renamed then
        any_moved = true
        break
      end
    end
  end
  if any_moved and config.save ~= false then
    if config.save == 'auto' or opts.confirm == false then
      M.save({ confirm = opts.confirm })
      return finish()
    end
    local ok, choice = pcall(vim.fn.confirm, 'Save changes?', 'Yes\nNo', 1)
    if not ok then
      return finish()
    elseif choice == 0 then
      return
    elseif choice == 1 then
      M.save({ confirm = opts.confirm })
      return finish()
    end
  end

  local prev_win = vim.api.nvim_get_current_win()
  local oil_bufnr = vim.api.nvim_get_current_buf()
  local keep_float_open = util.is_floating_win() and opts.close == false
  local float_win = keep_float_open and prev_win or nil

  -- Async iter over entries so we can normalize the url before opening
  local i = 1
  local function open_next_entry(cb)
    local entry = entries[i]
    i = i + 1
    if not entry then
      return cb()
    end
    if util.is_directory(entry) then
      -- If this is a new directory BUT we think we already have an entry with this name, disallow
      -- entry. This prevents the case of MOVE /foo -> /bar + CREATE /foo.
      -- If you enter the new /foo, it will show the contents of the old /foo.
      if not entry.id and cache.list_url(bufname)[entry.name] then
        return cb('Please save changes before entering new directory')
      end
    else
      local is_float = util.is_floating_win()
      if is_float and opts.close == false then
        vim.w.canola_keep_open = true
      elseif vim.w.is_canola_win then
        M.close()
      end
    end

    -- Normalize the url before opening to prevent needing to rename them inside the BufReadCmd
    -- Renaming buffers during opening can lead to missed autocmds
    util.get_edit_path(oil_bufnr, entry, function(normalized_url)
      local mods = {
        vertical = opts.vertical,
        horizontal = opts.horizontal,
        split = opts.split,
        keepalt = false,
      }
      local filebufnr = vim.fn.bufadd(normalized_url)
      local entry_is_file = not vim.endswith(normalized_url, '/')

      -- The :buffer command doesn't set buflisted=true
      -- So do that for normal files or for oil dirs if config set buflisted=true
      if entry_is_file or config.buf.buflisted then
        vim.bo[filebufnr].buflisted = true
      end

      if keep_float_open and not opts.tab then
        local original_win = vim.w[float_win].canola_original_win
        if original_win and vim.api.nvim_win_is_valid(original_win) then
          vim.api.nvim_set_current_win(original_win)
        else
          for _, winid in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
            if winid ~= float_win and not util.is_floating_win(winid) then
              vim.api.nvim_set_current_win(winid)
              break
            end
          end
        end
      end

      local cmd = 'buffer'
      if opts.tab then
        vim.cmd.tabnew({ mods = mods })
        vim.bo.bufhidden = 'wipe'
      elseif opts.split then
        cmd = 'sbuffer'
      end
      if opts.handle_buffer_callback ~= nil then
        opts.handle_buffer_callback(filebufnr)
      else
        ---@diagnostic disable-next-line: param-type-mismatch
        local ok, err = pcall(vim.cmd, {
          cmd = cmd,
          args = { filebufnr },
          mods = mods,
        })
        -- Ignore swapfile errors
        if not ok and err and not err:match('^Vim:E325:') then
          vim.api.nvim_echo({ { err, 'Error' } }, true, {})
        end
      end

      vim.cmd.redraw()
      open_next_entry(cb)
    end)
  end

  open_next_entry(function(err)
    if err then
      return finish(err)
    end
    if
      opts.close
      and vim.api.nvim_win_is_valid(prev_win)
      and prev_win ~= vim.api.nvim_get_current_win()
    then
      vim.api.nvim_win_call(prev_win, function()
        M.close()
      end)
    end

    if float_win and vim.api.nvim_win_is_valid(float_win) then
      if opts.tab then
        vim.api.nvim_set_current_tabpage(vim.api.nvim_win_get_tabpage(float_win))
      end
      vim.api.nvim_set_current_win(float_win)
    end

    update_preview_window()

    finish()
  end)
end

---@param bufnr integer
---@return boolean
local function maybe_hijack_directory_buffer(bufnr)
  local config = require('canola.config')
  local fs = require('canola.fs')
  local util = require('canola.util')
  local bufname = vim.api.nvim_buf_get_name(bufnr)
  if bufname == '' then
    return false
  end
  if util.parse_url(bufname) or vim.fn.isdirectory(bufname) == 0 then
    return false
  end
  local new_name = util.addslash(
    config.adapter_to_scheme.files .. fs.os_to_posix_path(vim.fn.fnamemodify(bufname, ':p'))
  )
  local replaced = util.rename_buffer(bufnr, new_name)
  return not replaced
end

---@private
M._get_highlights = function()
  return {
    {
      name = 'CanolaEmpty',
      link = 'Comment',
      desc = 'Empty column values',
    },
    {
      name = 'CanolaHidden',
      link = 'Comment',
      desc = 'Hidden entry in an oil buffer',
    },
    {
      name = 'CanolaDir',
      terminal_color = 4,
      bold = true,
      desc = 'Directory names in an oil buffer',
    },
    {
      name = 'CanolaDirHidden',
      link = 'CanolaHidden',
      desc = 'Hidden directory names in an oil buffer',
    },
    {
      name = 'CanolaDirIcon',
      link = 'CanolaDir',
      desc = 'Icon for directories',
    },
    {
      name = 'CanolaFileIcon',
      link = nil,
      desc = 'Icon for files',
    },
    {
      name = 'CanolaSocket',
      terminal_color = 5,
      bold = true,
      desc = 'Socket files in an oil buffer',
    },
    {
      name = 'CanolaSocketHidden',
      link = 'CanolaHidden',
      desc = 'Hidden socket files in an oil buffer',
    },
    {
      name = 'CanolaLink',
      terminal_color = 6,
      bold = true,
      desc = 'Soft links in an oil buffer',
    },
    {
      name = 'CanolaOrphanLink',
      link = 'DiagnosticError',
      bold = true,
      desc = 'Arrow separator for orphaned soft links',
    },
    {
      name = 'CanolaLinkHidden',
      link = 'CanolaHidden',
      desc = 'Hidden soft links in an oil buffer',
    },
    {
      name = 'CanolaOrphanLinkHidden',
      link = 'CanolaLinkHidden',
      desc = 'Hidden orphaned soft links in an oil buffer',
    },
    {
      name = 'CanolaLinkTarget',
      link = 'Comment',
      desc = 'The target of a soft link',
    },
    {
      name = 'CanolaOrphanLinkTarget',
      link = 'DiagnosticError',
      bold = true,
      underline = true,
      desc = 'The target of an orphaned soft link',
    },
    {
      name = 'CanolaLinkTargetHidden',
      link = 'CanolaHidden',
      desc = 'The target of a hidden soft link',
    },
    {
      name = 'CanolaOrphanLinkTargetHidden',
      link = 'CanolaOrphanLinkTarget',
      desc = 'The target of an hidden orphaned soft link',
    },
    {
      name = 'CanolaLinkArrow',
      terminal_color = 8,
      bold = true,
      desc = 'The arrow separator (-> ) between a soft link and its target',
    },
    {
      name = 'CanolaLinkArrowHidden',
      link = 'CanolaHidden',
      desc = 'Hidden arrow separator for soft links',
    },
    {
      name = 'CanolaLinkPath',
      terminal_color = 6,
      bold = true,
      desc = 'The directory prefix of a soft link target path',
    },
    {
      name = 'CanolaLinkPathHidden',
      link = 'CanolaHidden',
      desc = 'Hidden directory prefix of a soft link target path',
    },
    {
      name = 'CanolaFile',
      link = nil,
      desc = 'Normal files in an oil buffer',
    },
    {
      name = 'CanolaFileHidden',
      link = 'CanolaHidden',
      desc = 'Hidden normal files in an oil buffer',
    },
    {
      name = 'CanolaExecutable',
      terminal_color = 2,
      bold = true,
      desc = 'Executable files in an oil buffer',
    },
    {
      name = 'CanolaExecutableHidden',
      link = 'CanolaHidden',
      desc = 'Hidden executable files in an oil buffer',
    },
    {
      name = 'CanolaCreate',
      link = 'DiagnosticInfo',
      desc = 'Create action in the oil preview window',
    },
    {
      name = 'CanolaDelete',
      link = 'DiagnosticError',
      desc = 'Delete action in the oil preview window',
    },
    {
      name = 'CanolaMove',
      link = 'DiagnosticWarn',
      desc = 'Move action in the oil preview window',
    },
    {
      name = 'CanolaCopy',
      link = 'DiagnosticHint',
      desc = 'Copy action in the oil preview window',
    },
    {
      name = 'CanolaChange',
      link = 'Special',
      desc = 'Change action in the oil preview window',
    },
    {
      name = 'CanolaPermUserRead',
      terminal_color = 3,
      bold = true,
      desc = 'User read permission',
    },
    {
      name = 'CanolaPermUserWrite',
      terminal_color = 1,
      bold = true,
      desc = 'User write permission',
    },
    {
      name = 'CanolaPermUserExec',
      terminal_color = 2,
      bold = true,
      desc = 'User execute permission',
    },
    {
      name = 'CanolaPermGroupRead',
      terminal_color = 3,
      desc = 'Group read permission',
    },
    {
      name = 'CanolaPermGroupWrite',
      terminal_color = 1,
      desc = 'Group write permission',
    },
    {
      name = 'CanolaPermGroupExec',
      terminal_color = 2,
      desc = 'Group execute permission',
    },
    {
      name = 'CanolaPermOtherRead',
      terminal_color = 3,
      desc = 'Other read permission',
    },
    {
      name = 'CanolaPermOtherWrite',
      terminal_color = 1,
      desc = 'Other write permission',
    },
    {
      name = 'CanolaPermOtherExec',
      terminal_color = 2,
      desc = 'Other execute permission',
    },
    {
      name = 'CanolaPermNone',
      link = 'Comment',
      desc = 'No permission (dash)',
    },
    {
      name = 'CanolaPermSpecial',
      link = 'Special',
      desc = 'Special permission bit (setuid/setgid/sticky)',
    },
    {
      name = 'CanolaSizeBytes',
      link = 'DiagnosticOk',
      desc = 'File size in bytes',
    },
    {
      name = 'CanolaSizeKilo',
      link = 'DiagnosticOk',
      bold = true,
      desc = 'File size in kilobytes',
    },
    {
      name = 'CanolaSizeMega',
      link = 'DiagnosticWarn',
      desc = 'File size in megabytes',
    },
    {
      name = 'CanolaSizeGiga',
      link = 'DiagnosticError',
      desc = 'File size in gigabytes',
    },
    {
      name = 'CanolaOwnerSelf',
      link = 'DiagnosticWarn',
      bold = true,
      desc = 'File owner matching current user',
    },
    {
      name = 'CanolaOwnerOther',
      link = 'DiagnosticError',
      desc = 'File owner not matching current user',
    },
    {
      name = 'CanolaGroupSelf',
      link = 'DiagnosticWarn',
      bold = true,
      desc = 'File group matching current user group',
    },
    {
      name = 'CanolaGroupOther',
      link = 'DiagnosticError',
      desc = 'File group not matching current user group',
    },
    {
      name = 'CanolaDate',
      link = 'Directory',
      desc = 'File modification date',
    },
  }
end

local function set_colors()
  for _, conf in ipairs(M._get_highlights()) do
    if conf.terminal_color then
      local fg = vim.g['terminal_color_' .. conf.terminal_color]
      if fg then
        vim.api.nvim_set_hl(0, conf.name, {
          default = true,
          fg = fg,
          ctermfg = conf.terminal_color,
          bold = conf.bold or nil,
          underline = conf.underline or nil,
        })
      end
    elseif conf.link then
      if conf.bold or conf.underline then
        local base = vim.api.nvim_get_hl(0, { name = conf.link, link = false })
        vim.api.nvim_set_hl(0, conf.name, {
          default = true,
          fg = base.fg,
          ctermfg = base.ctermfg,
          bold = conf.bold or nil,
          underline = conf.underline or nil,
        })
      else
        vim.api.nvim_set_hl(0, conf.name, { default = true, link = conf.link })
      end
    end
  end
end

---Save all changes
---@param opts nil|table
---    confirm nil|boolean Show confirmation when true, never when false, respect skip_confirm_for_simple_edits if nil
---@param cb? fun(err: nil|string) Called when mutations complete.
---@note
--- If you provide your own callback function, there will be no notification for errors.
M.save = function(opts, cb)
  opts = opts or {}
  if not cb then
    cb = function(err)
      if err and err ~= 'Canceled' then
        vim.notify(err, vim.log.levels.ERROR)
      end
    end
  end
  local mutator = require('canola.mutator')
  mutator.try_write_changes(opts.confirm, cb)
end

local function restore_alt_buf()
  if vim.bo.filetype == 'canola' then
    require('canola.view').set_win_options()
    vim.api.nvim_win_set_var(0, 'canola_did_enter', true)
  elseif vim.w.canola_did_enter then
    vim.api.nvim_win_del_var(0, 'canola_did_enter')
    -- We are entering a non-oil buffer *after* having been in an oil buffer
    local has_orig, orig_buffer = pcall(vim.api.nvim_win_get_var, 0, 'canola_original_buffer')
    if has_orig and vim.api.nvim_buf_is_valid(orig_buffer) then
      if vim.api.nvim_get_current_buf() ~= orig_buffer then
        -- If we are editing a new file after navigating around oil, set the alternate buffer
        -- to be the last buffer we were in before opening oil
        vim.fn.setreg('#', orig_buffer)
      else
        -- If we are editing the same buffer that we started oil from, set the alternate to be
        -- what it was before we opened oil
        local has_orig_alt, alt_buffer =
          pcall(vim.api.nvim_win_get_var, 0, 'canola_original_alternate')
        if has_orig_alt and vim.api.nvim_buf_is_valid(alt_buffer) then
          vim.fn.setreg('#', alt_buffer)
        end
      end
    end
  end
end

---@private
---@param bufnr integer
M.load_oil_buffer = function(bufnr)
  local config = require('canola.config')
  local keymap_util = require('canola.keymap_util')
  local loading = require('canola.loading')
  local util = require('canola.util')
  local view = require('canola.view')
  local bufname = vim.api.nvim_buf_get_name(bufnr)
  local scheme, path = util.parse_url(bufname)
  if config.adapter_aliases[scheme] then
    scheme = config.adapter_aliases[scheme]
    bufname = scheme .. path
    util.rename_buffer(bufnr, bufname)
  end

  -- Early return if we're already loading or have already loaded this buffer
  if loading.is_loading(bufnr) or vim.b[bufnr].filetype ~= nil then
    return
  end

  local adapter = assert(config.get_adapter_by_scheme(scheme))

  if vim.endswith(bufname, '/') then
    -- This is a small quality-of-life thing. If the buffer name ends with a `/`, we know it's a
    -- directory, and can set the filetype early. This is helpful for adapters with a lot of latency
    -- (e.g. ssh) because it will set up the filetype keybinds at the *beginning* of the loading
    -- process.
    vim.bo[bufnr].filetype = 'canola'
    vim.bo[bufnr].buftype = 'acwrite'
    keymap_util.set_keymaps(config.keymaps, bufnr)
  end
  loading.set_loading(bufnr, true)
  local winid = vim.api.nvim_get_current_win()
  local function finish(new_url)
    -- If the buffer was deleted while we were normalizing the name, early return
    if not vim.api.nvim_buf_is_valid(bufnr) then
      return
    end
    -- Since this was async, we may have left the window with this buffer. People often write
    -- BufReadPre/Post autocmds with the expectation that the current window is the one that
    -- contains the buffer. Let's then do our best to make sure that that assumption isn't violated.
    winid = util.buf_get_win(bufnr, winid) or vim.api.nvim_get_current_win()
    vim.api.nvim_win_call(winid, function()
      if new_url ~= bufname then
        if util.rename_buffer(bufnr, new_url) then
          -- If the buffer was replaced then don't initialize it. It's dead. The replacement will
          -- have BufReadCmd called for it
          return
        end

        -- If the renamed buffer doesn't have a scheme anymore, this is a normal file.
        -- Finish setting it up as a normal buffer.
        local new_scheme = util.parse_url(new_url)
        if not new_scheme then
          loading.set_loading(bufnr, false)
          vim.cmd.doautocmd({ args = { 'BufReadPre', new_url }, mods = { emsg_silent = true } })
          vim.cmd.doautocmd({ args = { 'BufReadPost', new_url }, mods = { emsg_silent = true } })
          return
        end

        bufname = new_url
      end
      if vim.endswith(bufname, '/') then
        vim.cmd.doautocmd({ args = { 'BufReadPre', bufname }, mods = { emsg_silent = true } })
        view.initialize(bufnr)
        vim.cmd.doautocmd({ args = { 'BufReadPost', bufname }, mods = { emsg_silent = true } })
      else
        vim.bo[bufnr].buftype = 'acwrite'
        adapter.read_file(bufnr)
      end
      restore_alt_buf()
    end)
  end

  adapter.normalize_url(bufname, finish)
end

local function close_preview_window_if_not_in_oil()
  local util = require('canola.util')
  local preview_win_id = util.get_preview_win()
  if not preview_win_id or not vim.w[preview_win_id].canola_entry_id then
    return
  end

  local canola_source_win = vim.w[preview_win_id].canola_source_win
  if canola_source_win and vim.api.nvim_win_is_valid(canola_source_win) then
    local src_buf = vim.api.nvim_win_get_buf(canola_source_win)
    if util.is_canola_bufnr(src_buf) then
      return
    end
  end

  -- This can fail if it's the last window open
  pcall(vim.api.nvim_win_close, preview_win_id, true)
end

local _on_key_ns = 0
local _keybuf

M._buf_write_cmd = function(params)
  local config = require('canola.config')
  local last_keys = _keybuf and _keybuf:as_str() or ''
  local winid = vim.api.nvim_get_current_win()
  local quit_after_save = vim.endswith(last_keys, ':wq\r')
    or vim.endswith(last_keys, ':x\r')
    or vim.endswith(last_keys, 'ZZ')
  local quit_all = vim.endswith(last_keys, ':wqa\r')
    or vim.endswith(last_keys, ':wqal\r')
    or vim.endswith(last_keys, ':wqall\r')
  local bufname = vim.api.nvim_buf_get_name(params.buf)
  if vim.endswith(bufname, '/') then
    vim.cmd.doautocmd({ args = { 'BufWritePre', params.file }, mods = { silent = true } })
    M.save(nil, function(err)
      if err then
        if err ~= 'Canceled' then
          vim.notify(err, vim.log.levels.ERROR)
        end
      elseif winid == vim.api.nvim_get_current_win() then
        if quit_after_save then
          vim.cmd.quit()
        elseif quit_all then
          vim.cmd.quitall()
        end
      end
    end)
    vim.cmd.doautocmd({ args = { 'BufWritePost', params.file }, mods = { silent = true } })
  else
    local adapter = assert(config.get_adapter_by_scheme(bufname))
    adapter.write_file(params.buf)
  end
end

M.init = function()
  local Ringbuf = require('canola.ringbuf')
  local config = require('canola.config')

  config.init()
  set_colors()
  local callback = function(args)
    local util = require('canola.util')
    if args.smods.tab > 0 then
      vim.cmd.tabnew()
    end
    local float = false
    local preview = false
    local i = 1
    while i <= #args.fargs do
      local v = args.fargs[i]
      if v == '--float' then
        float = true
        table.remove(args.fargs, i)
      elseif v == '--preview' then
        -- In the future we may want to support specifying options for the preview window (e.g.
        -- vertical/horizontal), but if you want that level of control maybe just use the API
        preview = true
        table.remove(args.fargs, i)
      elseif v == '--progress' then
        local mutator = require('canola.mutator')
        if mutator.is_mutating() then
          mutator.show_progress()
        else
          vim.notify('No mutation in progress', vim.log.levels.WARN)
        end
        return
      else
        i = i + 1
      end
    end

    if not float and (args.smods.vertical or args.smods.horizontal or args.smods.split ~= '') then
      local range = args.count > 0 and { args.count } or nil
      local cmdargs = { mods = { split = args.smods.split }, range = range }
      if args.smods.vertical then
        vim.cmd.vsplit(cmdargs)
      else
        vim.cmd.split(cmdargs)
      end
    end

    local method = float and 'open_float' or 'open'
    local path = args.fargs[1]
    local open_opts = {}
    if preview then
      open_opts.preview = {}
    end
    M[method](path, open_opts)
  end
  vim.api.nvim_create_user_command('Canola', callback, {
    desc = 'Open oil file browser on a directory',
    nargs = '*',
    complete = 'dir',
    count = true,
  })
  local aug = vim.api.nvim_create_augroup('Canola', {})

  local view = require('canola.view')
  view.setup_cleanup_autocmd()
  view.setup_decoration_provider()

  vim.g.loaded_netrw = 1
  vim.g.loaded_netrwPlugin = 1
  if vim.fn.exists('#FileExplorer') then
    vim.api.nvim_create_augroup('FileExplorer', { clear = true })
  end

  local patterns = {}
  local filetype_patterns = {}
  for scheme in pairs(config.adapters) do
    table.insert(patterns, scheme .. '*')
    filetype_patterns[scheme .. '.*'] = { 'canola', { priority = 10 } }
  end
  for scheme in pairs(config.adapter_aliases) do
    table.insert(patterns, scheme .. '*')
    filetype_patterns[scheme .. '.*'] = { 'canola', { priority = 10 } }
  end
  local scheme_pattern = table.concat(patterns, ',')
  -- We need to add these patterns to the filetype matcher so the filetype doesn't get overridden
  -- by other patterns. See https://github.com/stevearc/oil.nvim/issues/47
  vim.filetype.add({
    pattern = filetype_patterns,
  })

  _keybuf = Ringbuf.new(7)
  if _on_key_ns == 0 then
    _on_key_ns = vim.on_key(function(char)
      _keybuf:push(char)
    end, _on_key_ns)
  end
  vim.api.nvim_create_autocmd('ColorScheme', {
    desc = 'Set default oil highlights',
    group = aug,
    pattern = '*',
    callback = set_colors,
  })
  vim.api.nvim_create_autocmd('BufReadCmd', {
    group = aug,
    pattern = scheme_pattern,
    nested = true,
    callback = function(params)
      M.load_oil_buffer(params.buf)
    end,
  })
  vim.api.nvim_create_autocmd('BufWriteCmd', {
    group = aug,
    pattern = scheme_pattern,
    nested = true,
    callback = M._buf_write_cmd,
  })
  vim.api.nvim_create_autocmd('BufLeave', {
    desc = 'Save alternate buffer for later',
    group = aug,
    pattern = '*',
    callback = function()
      local util = require('canola.util')
      if not util.is_canola_bufnr(0) then
        vim.w.canola_original_buffer = vim.api.nvim_get_current_buf()
        vim.w.canola_original_view = vim.fn.winsaveview()
        ---@diagnostic disable-next-line: param-type-mismatch
        vim.w.canola_original_alternate = vim.fn.bufnr('#')
      end
    end,
  })
  vim.api.nvim_create_autocmd('BufEnter', {
    desc = 'Set/unset oil window options and restore alternate buffer',
    group = aug,
    pattern = '*',
    callback = function()
      local util = require('canola.util')
      local bufname = vim.api.nvim_buf_get_name(0)
      local scheme = util.parse_url(bufname)
      local is_canola_buf = scheme and config.adapters[scheme]
      -- We want to filter out oil buffers that are not directories (i.e. ssh files)
      local is_oil_dir_or_unknown = (vim.bo.filetype == 'canola' or vim.bo.filetype == '')
      if is_canola_buf and is_oil_dir_or_unknown then
        view.maybe_set_cursor()
        -- While we are in an oil buffer, set the alternate file to the buffer we were in prior to
        -- opening oil
        local has_orig, orig_buffer = pcall(vim.api.nvim_win_get_var, 0, 'canola_original_buffer')
        if has_orig and vim.api.nvim_buf_is_valid(orig_buffer) then
          vim.fn.setreg('#', orig_buffer)
        end
        view.set_win_options()
        if config.buf.buflisted ~= nil then
          vim.api.nvim_set_option_value('buflisted', config.buf.buflisted, { buf = 0 })
        end
        vim.w.canola_did_enter = true
      elseif vim.fn.isdirectory(bufname) == 0 then
        -- Only run this logic if we are *not* in an oil buffer (and it's not a directory, which
        -- will be replaced by a canola:// url)
        -- Oil buffers have to run it in BufReadCmd after confirming they are a directory or a file
        restore_alt_buf()
      end

      close_preview_window_if_not_in_oil()
    end,
  })

  vim.api.nvim_create_autocmd({ 'BufWinEnter', 'WinNew', 'WinEnter' }, {
    desc = 'Reset bufhidden when entering a preview buffer',
    group = aug,
    pattern = '*',
    callback = function()
      -- If we have entered a "preview" buffer in a non-preview window, reset bufhidden
      if vim.b.canola_preview_buffer and not vim.wo.previewwindow then
        vim.bo.bufhidden = vim.api.nvim_get_option_value('bufhidden', { scope = 'global' })
        vim.b.canola_preview_buffer = nil
      end
    end,
  })
  vim.api.nvim_create_autocmd('WinNew', {
    desc = 'Restore window options when splitting an oil window',
    group = aug,
    pattern = '*',
    nested = true,
    callback = function(params)
      if vim.v.vim_did_enter ~= 1 then
        return
      end
      local util = require('canola.util')
      if not util.is_canola_bufnr(params.buf) or vim.w.canola_did_enter then
        return
      end
      -- This new window is a split off of an oil window. We need to transfer the window
      -- variables. First, locate the parent window
      local parent_win
      -- First search windows in this tab, then search all windows
      local winids = vim.list_extend(vim.api.nvim_tabpage_list_wins(0), vim.api.nvim_list_wins())
      for _, winid in ipairs(winids) do
        if vim.api.nvim_win_is_valid(winid) then
          if vim.w[winid].canola_did_enter then
            parent_win = winid
            break
          end
        end
      end
      if not parent_win then
        return
      end

      -- Then transfer over the relevant window vars
      vim.w.canola_did_enter = true
      vim.w.canola_original_buffer = vim.w[parent_win].canola_original_buffer
      vim.w.canola_original_view = vim.w[parent_win].canola_original_view
      vim.w.canola_original_alternate = vim.w[parent_win].canola_original_alternate
    end,
  })
  -- mksession doesn't save oil buffers in a useful way. We have to manually load them after a
  -- session finishes loading. See https://github.com/stevearc/oil.nvim/issues/29
  vim.api.nvim_create_autocmd('SessionLoadPost', {
    desc = 'Load oil buffers after a session is loaded',
    group = aug,
    pattern = '*',
    callback = function(params)
      if vim.g.SessionLoad ~= 1 then
        return
      end
      local util = require('canola.util')
      local scheme = util.parse_url(params.file)
      if config.adapters[scheme] and vim.api.nvim_buf_line_count(params.buf) == 1 then
        M.load_oil_buffer(params.buf)
      end
    end,
  })

  if config.float.default then
    vim.api.nvim_create_autocmd('VimEnter', {
      desc = 'Open oil in a float when starting on a directory',
      group = aug,
      once = true,
      nested = true,
      callback = function()
        local util = require('canola.util')
        if util.is_canola_bufnr(0) then
          local url = vim.api.nvim_buf_get_name(0)
          vim.cmd.enew({ mods = { silent = true, noswapfile = true } })
          M.open_float(url)
        end
      end,
    })
  end

  vim.api.nvim_create_autocmd('BufAdd', {
    desc = 'Detect directory buffer and open oil file browser',
    group = aug,
    pattern = '*',
    nested = true,
    callback = function(params)
      if maybe_hijack_directory_buffer(params.buf) and vim.v.vim_did_enter == 1 then
        M.load_oil_buffer(params.buf)
      end
    end,
  })

  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if maybe_hijack_directory_buffer(bufnr) and vim.v.vim_did_enter == 1 then
      M.load_oil_buffer(bufnr)
    end
  end
end

return M
