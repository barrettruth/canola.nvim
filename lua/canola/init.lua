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

M.open_float = function(...)
  require('canola.window').open_float(...)
end
M.toggle_float = function(...)
  require('canola.window').toggle_float(...)
end
M.open_split = function(...)
  require('canola.window').open_split(...)
end
M.toggle_split = function(...)
  require('canola.window').toggle_split(...)
end
M.open = function(...)
  require('canola.window').open(...)
end
M.close = function(...)
  require('canola.window').close(...)
end
M.toggle = function(...)
  require('canola.window').toggle(...)
end

M.open_preview = function(...)
  require('canola.preview').open_preview(...)
end

M.select = function(...)
  require('canola.select').select(...)
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
  return require('canola.highlights')._get_highlights()
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
  require('canola.highlights').set_colors()
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
    callback = require('canola.highlights').set_colors,
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
  vim.api.nvim_create_autocmd('VimLeavePre', {
    desc = 'Clear buftype on canola buffers so mksession saves their URLs',
    group = aug,
    pattern = '*',
    callback = function()
      local util = require('canola.util')
      for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_valid(bufnr) and util.is_canola_bufnr(bufnr) then
          vim.bo[bufnr].buftype = ''
        end
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
