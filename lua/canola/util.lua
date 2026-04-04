local config = require('canola.config')
local constants = require('canola.constants')

local M = {}

local FIELD_ID = constants.FIELD_ID
local FIELD_NAME = constants.FIELD_NAME
local FIELD_TYPE = constants.FIELD_TYPE
local FIELD_META = constants.FIELD_META

---@param url string
---@return nil|string
---@return nil|string
M.parse_url = function(url)
  return url:match('^(.*://)(.*)$')
end

---Escapes a filename for use in :edit
---@param filename string
---@return string
M.escape_filename = function(filename)
  local ret = vim.fn.fnameescape(filename)
  return ret
end

---@type table<string, string>
local _url_escape_to_char = {
  ['20'] = ' ',
  ['22'] = '“',
  ['23'] = '#',
  ['24'] = '$',
  ['25'] = '%',
  ['26'] = '&',
  ['27'] = '‘',
  ['2B'] = '+',
  ['2C'] = ',',
  ['2F'] = '/',
  ['3A'] = ':',
  ['3B'] = ';',
  ['3C'] = '<',
  ['3D'] = '=',
  ['3E'] = '>',
  ['3F'] = '?',
  ['40'] = '@',
  ['5B'] = '[',
  ['5C'] = '\\',
  ['5D'] = ']',
  ['5E'] = '^',
  ['60'] = '`',
  ['7B'] = '{',
  ['7C'] = '|',
  ['7D'] = '}',
  ['7E'] = '~',
}
---@type table<string, string>
local _char_to_url_escape = {}
for k, v in pairs(_url_escape_to_char) do
  _char_to_url_escape[v] = '%' .. k
end
-- TODO this uri escape handling is very incomplete

---@param string string
---@return string
M.url_escape = function(string)
  return (string:gsub('.', _char_to_url_escape))
end

---@param string string
---@return string
M.url_unescape = function(string)
  return (
    string:gsub('%%([0-9A-Fa-f][0-9A-Fa-f])', function(seq)
      return _url_escape_to_char[seq:upper()] or ('%' .. seq)
    end)
  )
end

---@param bufnr integer
---@param silent? boolean
---@return nil|canola.Adapter
M.get_adapter = function(bufnr, silent)
  local bufname = vim.api.nvim_buf_get_name(bufnr)
  local adapter = config.get_adapter_by_scheme(bufname)
  if not adapter and not silent then
    vim.notify_once(
      string.format("[canola] could not find adapter for buffer '%s://'", bufname),
      vim.log.levels.ERROR
    )
  end
  return adapter
end

M.pad_align = function(...)
  return require('canola.render').pad_align(...)
end

---@generic T : any
---@param tbl T[]
---@param start_idx? number
---@param end_idx? number
---@return T[]
M.tbl_slice = function(tbl, start_idx, end_idx)
  local ret = {}
  if not start_idx then
    start_idx = 1
  end
  if not end_idx then
    end_idx = #tbl
  end
  for i = start_idx, end_idx do
    table.insert(ret, tbl[i])
  end
  return ret
end

---@param entry canola.InternalEntry
---@return canola.Entry
M.export_entry = function(entry)
  return {
    name = entry[FIELD_NAME],
    type = entry[FIELD_TYPE],
    id = entry[FIELD_ID],
    meta = entry[FIELD_META],
  }
end

---@param src_bufnr integer|string Buffer number or name
---@param dest_buf_name string
---@return boolean True if the buffer was replaced instead of renamed
M.rename_buffer = function(src_bufnr, dest_buf_name)
  if type(src_bufnr) == 'string' then
    src_bufnr = vim.fn.bufadd(src_bufnr --[[@as string]])
    if not vim.api.nvim_buf_is_loaded(src_bufnr) then
      vim.api.nvim_buf_delete(src_bufnr, {})
      return false
    end
  end

  local bufname = vim.api.nvim_buf_get_name(src_bufnr)
  -- If this buffer is not literally a file on disk, then we can use the simple
  -- rename logic. The only reason we can't use nvim_buf_set_name on files is because vim will
  -- think that the new buffer conflicts with the file next time it tries to save.
  if not vim.uv.fs_stat(dest_buf_name) then
    ---@diagnostic disable-next-line: param-type-mismatch
    local altbuf = vim.fn.bufnr('#')
    -- This will fail if the dest buf name already exists
    local ok = pcall(vim.api.nvim_buf_set_name, src_bufnr, dest_buf_name)
    if ok then
      -- Renaming the buffer creates a new buffer with the old name.
      -- Find it and try to delete it, but don't if the buffer is in a context
      -- where Neovim doesn't allow buffer modifications.
      pcall(vim.api.nvim_buf_delete, vim.fn.bufadd(bufname), {})
      if altbuf and vim.api.nvim_buf_is_valid(altbuf) then
        vim.fn.setreg('#', altbuf)
      end

      return false
    end
  end

  local is_modified = vim.bo[src_bufnr].modified
  local dest_bufnr = vim.fn.bufadd(dest_buf_name)
  pcall(vim.fn.bufload, dest_bufnr)
  if vim.bo[src_bufnr].buflisted then
    vim.bo[dest_bufnr].buflisted = true
  end
  -- If the src_bufnr was marked as modified by the previous operation, we should undo that
  vim.bo[src_bufnr].modified = is_modified

  -- If we're renaming a buffer that we're about to enter, this may be called before the buffer is
  -- actually in the window. We need to wait to enter the buffer and _then_ replace it.
  vim.schedule(function()
    -- Find any windows with the old buffer and replace them
    for _, winid in ipairs(vim.api.nvim_list_wins()) do
      if vim.api.nvim_win_is_valid(winid) then
        if vim.api.nvim_win_get_buf(winid) == src_bufnr then
          vim.api.nvim_win_set_buf(winid, dest_bufnr)
        end
      end
    end
    if vim.api.nvim_buf_is_valid(src_bufnr) then
      if vim.bo[src_bufnr].modified then
        local src_lines = vim.api.nvim_buf_get_lines(src_bufnr, 0, -1, true)
        vim.api.nvim_buf_set_lines(dest_bufnr, 0, -1, true, src_lines)
      end
      -- Try to delete, but don't if the buffer has changes
      pcall(vim.api.nvim_buf_delete, src_bufnr, {})
    end
    -- Renaming a buffer won't load the undo file, so we need to do that manually
    if vim.bo[dest_bufnr].undofile then
      vim.api.nvim_buf_call(dest_bufnr, function()
        vim.cmd.rundo({
          args = { vim.fn.undofile(dest_buf_name) },
          magic = { file = false, bar = false },
          mods = {
            emsg_silent = true,
          },
        })
      end)
    end
  end)
  return true
end

---@param count integer
---@param cb fun(err: nil|string)
M.cb_collect = function(count, cb)
  return function(err)
    if err then
      -- selene: allow(mismatched_arg_count)
      cb(err)
      cb = function() end
    else
      count = count - 1
      if count == 0 then
        cb()
      end
    end
  end
end

---@param url string
---@return string[]
local function get_possible_buffer_names_from_url(url)
  local fs = require('canola.fs')
  local scheme, path = M.parse_url(url)
  if config.adapters[scheme] == 'files' then
    assert(path)
    return { fs.posix_to_os_path(path) }
  end
  return { url }
end

---@param entry_type canola.EntryType
---@param src_url string
---@param dest_url string
M.update_moved_buffers = function(entry_type, src_url, dest_url)
  local src_buf_names = get_possible_buffer_names_from_url(src_url)
  local dest_buf_name = get_possible_buffer_names_from_url(dest_url)[1]
  if entry_type ~= 'directory' then
    for _, src_buf_name in ipairs(src_buf_names) do
      M.rename_buffer(src_buf_name, dest_buf_name)
    end
  else
    M.rename_buffer(M.addslash(src_url), M.addslash(dest_url))
    -- If entry type is directory, we need to rename this buffer, and then update buffers that are
    -- inside of this directory

    for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
      local bufname = vim.api.nvim_buf_get_name(bufnr)
      if vim.startswith(bufname, src_url) then
        -- Handle oil directory buffers
        vim.api.nvim_buf_set_name(bufnr, dest_url .. bufname:sub(src_url:len() + 1))
      elseif bufname ~= '' and vim.bo[bufnr].buftype == '' then
        -- Handle regular buffers
        local scheme = M.parse_url(bufname)

        -- If the buffer is a local file, make sure we're using the absolute path
        if not scheme then
          bufname = vim.fn.fnamemodify(bufname, ':p')
        end

        for _, src_buf_name in ipairs(src_buf_names) do
          if vim.startswith(bufname, src_buf_name) then
            M.rename_buffer(bufnr, dest_buf_name .. bufname:sub(src_buf_name:len() + 1))
            break
          end
        end
      end
    end
  end
end

---@param name_or_config string|table
---@return string
---@return table|nil
M.split_config = function(name_or_config)
  if type(name_or_config) == 'string' then
    return name_or_config, nil
  else
    if not name_or_config[1] and name_or_config['1'] then
      name_or_config[1] = name_or_config['1']
      name_or_config['1'] = nil
    end
    local name = name_or_config[1] or name_or_config.name
    return name, name_or_config
  end
end

M.render_table = function(...)
  return require('canola.render').render_table(...)
end

M.set_highlights = function(...)
  return require('canola.render').set_highlights(...)
end

---@param path string
---@param os_slash? boolean use os filesystem slash instead of posix slash
---@return string
M.addslash = function(path, os_slash)
  local slash = '/'
  if os_slash and require('canola.fs').is_windows then
    slash = '\\'
  end

  local endslash = path:match(slash .. '$')
  if not endslash then
    return path .. slash
  else
    return path
  end
end

M.is_floating_win = function(...)
  return require('canola.win_util').is_floating_win(...)
end

M.get_title = function(...)
  return require('canola.win_util').get_title(...)
end

M.add_title_to_win = function(...)
  return require('canola.win_util').add_title_to_win(...)
end

---@param action canola.Action
---@return canola.Adapter
---@return nil|canola.CrossAdapterAction
M.get_adapter_for_action = function(action)
  local adapter = assert(config.get_adapter_by_scheme(action.url or action.src_url))
  if action.dest_url then
    local dest_adapter = assert(config.get_adapter_by_scheme(action.dest_url))
    if adapter ~= dest_adapter then
      if
        adapter.supported_cross_adapter_actions
        and adapter.supported_cross_adapter_actions[dest_adapter.name]
      then
        return adapter, adapter.supported_cross_adapter_actions[dest_adapter.name]
      elseif
        dest_adapter.supported_cross_adapter_actions
        and dest_adapter.supported_cross_adapter_actions[adapter.name]
      then
        return dest_adapter, dest_adapter.supported_cross_adapter_actions[adapter.name]
      else
        error(
          string.format(
            'Cannot copy files from %s -> %s; no cross-adapter transfer method found',
            action.src_url,
            action.dest_url
          )
        )
      end
    end
  end
  return adapter
end

M.h_align = function(...)
  return require('canola.render').h_align(...)
end

M.render_text = function(...)
  return require('canola.render').render_text(...)
end

M.run_in_fullscreen_win = function(...)
  return require('canola.win_util').run_in_fullscreen_win(...)
end

---@param bufnr integer
---@return boolean
M.is_canola_bufnr = function(bufnr)
  local filetype = vim.bo[bufnr].filetype
  if filetype == 'canola' then
    return true
  elseif filetype ~= '' then
    -- If the filetype is set and is NOT "canola", then it's not an oil buffer
    return false
  end
  local scheme = M.parse_url(vim.api.nvim_buf_get_name(bufnr))
  return config.adapters[scheme] or config.adapter_aliases[scheme]
end

---This is a hack so we don't end up in insert mode after starting a task
---@param prev_mode string The vim mode we were in before opening a terminal
M.hack_around_termopen_autocmd = function(prev_mode)
  -- It's common to have autocmds that enter insert mode when opening a terminal
  vim.defer_fn(function()
    local new_mode = vim.api.nvim_get_mode().mode
    if new_mode ~= prev_mode then
      if string.find(new_mode, 'i') == 1 then
        vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<ESC>', true, true, true), 'n', false)
        if string.find(prev_mode, 'v') == 1 or string.find(prev_mode, 'V') == 1 then
          vim.cmd.normal({ bang = true, args = { 'gv' } })
        end
      end
    end
  end, 10)
end

M.get_preview_win = function(...)
  return require('canola.win_util').get_preview_win(...)
end

M.hide_cursor = function()
  return require('canola.win_util').hide_cursor()
end

M.buf_get_win = function(...)
  return require('canola.win_util').buf_get_win(...)
end

---@param adapter canola.Adapter
---@param url string
---@param opts {columns?: string[], no_cache?: boolean}
---@param callback fun(err: nil|string, entries: nil|canola.InternalEntry[])
M.adapter_list_all = function(adapter, url, opts, callback)
  local cache = require('canola.cache')
  if not opts.no_cache then
    local entries = cache.list_url(url)
    if next(entries) ~= nil then
      return callback(nil, vim.tbl_values(entries))
    end
  end
  local ret = {}
  adapter.list(url, opts.columns or {}, function(err, entries, fetch_more)
    if err then
      callback(err)
      return
    end
    if entries then
      vim.list_extend(ret, entries)
    end
    if fetch_more then
      vim.defer_fn(fetch_more, 4)
    else
      callback(nil, ret)
    end
  end)
end

M.send_to_quickfix = function(...)
  return require('canola.quickfix').send_to_quickfix(...)
end

M.add_to_quickfix = function(...)
  return require('canola.quickfix').add_to_quickfix(...)
end

---@return boolean
M.is_visual_mode = function()
  local mode = vim.api.nvim_get_mode().mode
  return mode:match('^[vV]') ~= nil
end

---Get the current visual selection range. If not in visual mode, return nil.
---@return {start_lnum: integer, end_lnum: integer}?
M.get_visual_range = function()
  if not M.is_visual_mode() then
    return
  end
  -- This is the best way to get the visual selection at the moment
  -- https://github.com/neovim/neovim/pull/13896
  local _, start_lnum, _, _ = unpack(vim.fn.getpos('v'))
  local _, end_lnum, _, _, _ = unpack(vim.fn.getcurpos())
  if start_lnum > end_lnum then
    start_lnum, end_lnum = end_lnum, start_lnum
  end
  return { start_lnum = start_lnum, end_lnum = end_lnum }
end

---@param entry canola.Entry
---@return boolean
M.is_matching = function(entry)
  -- if search highlightig is not enabled, all files are considered to match
  local search_highlighting_is_off = (vim.v.hlsearch == 0)
  if search_highlighting_is_off then
    return true
  end
  local pattern = vim.fn.getreg('/')
  local position_of_match = vim.fn.match(entry.name, pattern)
  return position_of_match ~= -1
end

---@param bufnr integer
---@param callback fun()
M.run_after_load = function(bufnr, callback)
  if bufnr == 0 then
    bufnr = vim.api.nvim_get_current_buf()
  end
  if vim.b[bufnr].canola_ready then
    callback()
  else
    vim.api.nvim_create_autocmd('User', {
      pattern = 'CanolaEnter',
      callback = function(args)
        if args.data.buf == bufnr then
          vim.api.nvim_buf_call(bufnr, callback)
          return true
        end
      end,
    })
  end
end

---@param entry canola.Entry
---@return boolean
M.is_directory = function(entry)
  local is_directory = entry.type == 'directory'
    or (
      entry.type == 'link'
      and entry.meta
      and entry.meta.link_stat
      and entry.meta.link_stat.type == 'directory'
    )
  return is_directory == true
end

---Get the :edit path for an entry
---@param bufnr integer The oil buffer that contains the entry
---@param entry canola.Entry
---@param callback fun(normalized_url: string)
M.get_edit_path = function(bufnr, entry, callback)
  local pathutil = require('canola.pathutil')

  local bufname = vim.api.nvim_buf_get_name(bufnr)
  local scheme, dir = M.parse_url(bufname)
  local adapter = M.get_adapter(bufnr, true)
  assert(scheme and dir and adapter)

  local url = scheme .. dir .. entry.name
  if M.is_directory(entry) then
    url = url .. '/'
  end

  if entry.name == '..' then
    callback(scheme .. pathutil.parent(dir))
  elseif adapter.get_entry_path then
    adapter.get_entry_path(url, entry, callback)
  else
    adapter.normalize_url(url, callback)
  end
end

M.get_icon_provider = function()
  return require('canola.icons').get_icon_provider()
end

---Read a buffer into a scratch buffer and apply syntactic highlighting when possible
---@param path string The path to the file to read
---@param preview_method canola.PreviewMethod
---@return nil|integer
M.read_file_to_scratch_buffer = function(path, preview_method)
  local bufnr = vim.api.nvim_create_buf(false, true)
  if bufnr == 0 then
    return
  end

  vim.bo[bufnr].bufhidden = 'wipe'
  vim.bo[bufnr].buftype = 'nofile'

  local has_lines, read_res
  if preview_method == 'fast_scratch' then
    has_lines, read_res = pcall(vim.fn.readfile, path, '', vim.o.lines)
  else
    has_lines, read_res = pcall(vim.fn.readfile, path)
  end
  local lines = has_lines and vim.split(table.concat(read_res, '\n'), '\n') or {}

  local ok = pcall(vim.api.nvim_buf_set_lines, bufnr, 0, -1, false, lines)
  if not ok then
    return
  end
  local ft = vim.filetype.match({ filename = path, buf = bufnr })
  if ft and ft ~= '' and vim.treesitter.language.get_lang then
    local lang = vim.treesitter.language.get_lang(ft)
    -- selene: allow(empty_if)
    if not pcall(vim.treesitter.start, bufnr, lang) then
      vim.bo[bufnr].syntax = ft
    else
    end
  end

  -- Replace the scratch buffer with a real buffer if we enter it
  vim.api.nvim_create_autocmd('BufEnter', {
    desc = 'canola.nvim replace scratch buffer with real buffer',
    buffer = bufnr,
    callback = function()
      local winid = vim.api.nvim_get_current_win()
      -- Have to schedule this so all the FileType, etc autocmds will fire
      vim.schedule(function()
        if vim.api.nvim_get_current_win() == winid then
          vim.cmd.edit({ args = { path } })

          -- If we're still in a preview window, make sure this buffer still gets treated as a
          -- preview
          if vim.wo.previewwindow then
            vim.bo.bufhidden = 'wipe'
            vim.b.canola_preview_buffer = true
          end
        end
      end)
    end,
  })

  return bufnr
end

---@type table<string, string>
local _regcache = {}
---Check if a file matches a BufReadCmd autocmd
---@param filename string
---@return boolean
M.file_matches_bufreadcmd = function(filename)
  local autocmds = vim.api.nvim_get_autocmds({
    event = 'BufReadCmd',
  })
  for _, au in ipairs(autocmds) do
    local pat = _regcache[au.pattern]
    if not pat then
      pat = vim.fn.glob2regpat(au.pattern)
      _regcache[au.pattern] = pat
    end

    if vim.fn.match(filename, pat) >= 0 then
      return true
    end
  end
  return false
end

return M
