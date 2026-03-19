local cache = require('canola.cache')
local canola = require('canola')
local columns = require('canola.columns')
local config = require('canola.config')
local fs = require('canola.fs')
local parser = require('canola.mutator.parser')
local util = require('canola.util')
local view = require('canola.view')

local M = {}

---@return "wayland"|"x11"|nil
local function get_linux_session_type()
  local xdg_session_type = vim.env.XDG_SESSION_TYPE
  if not xdg_session_type then
    return
  end
  xdg_session_type = xdg_session_type:lower()
  if xdg_session_type:find('x11') then
    return 'x11'
  elseif xdg_session_type:find('wayland') then
    return 'wayland'
  else
    return nil
  end
end

---@return boolean
local function is_linux_desktop_gnome()
  local cur_desktop = vim.env.XDG_CURRENT_DESKTOP
  local session_desktop = vim.env.XDG_SESSION_DESKTOP
  local idx = session_desktop and session_desktop:lower():find('gnome')
    or cur_desktop and cur_desktop:lower():find('gnome')
  return idx ~= nil or cur_desktop == 'X-Cinnamon' or cur_desktop == 'XFCE'
end

---@param winid integer
---@param entry canola.InternalEntry
---@param column_defs canola.ColumnSpec[]
---@param adapter canola.Adapter
---@param bufnr integer
local function write_pasted(winid, entry, column_defs, adapter, bufnr)
  local col_width = {}
  for i in ipairs(column_defs) do
    col_width[i + 1] = 1
  end
  local line_table =
    { view.format_entry_cols(entry, column_defs, col_width, adapter, false, bufnr) }
  local lines, _ = util.render_table(line_table, col_width)
  local pos = vim.api.nvim_win_get_cursor(winid)
  vim.api.nvim_buf_set_lines(bufnr, pos[1], pos[1], true, lines)
end

---@param parent_url string
---@param entry canola.InternalEntry
local function remove_entry_from_parent_buffer(parent_url, entry)
  local bufnr = vim.fn.bufadd(parent_url)
  assert(vim.api.nvim_buf_is_loaded(bufnr), 'Expected parent buffer to be loaded during paste')
  local adapter = assert(util.get_adapter(bufnr))
  local column_defs = columns.get_supported_columns(adapter)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  for i, line in ipairs(lines) do
    local result = parser.parse_line(adapter, line, column_defs)
    if result and result.entry == entry then
      vim.api.nvim_buf_set_lines(bufnr, i - 1, i, false, {})
      return
    end
  end
  local exported = util.export_entry(entry)
  vim.notify(
    string.format("Error: could not delete original file '%s'", exported.name),
    vim.log.levels.ERROR
  )
end

---@param paths string[]
---@param delete_original? boolean
local function paste_paths(paths, delete_original)
  local bufnr = vim.api.nvim_get_current_buf()
  local scheme = 'canola://'
  local adapter = assert(config.get_adapter_by_scheme(scheme))
  local column_defs = columns.get_supported_columns(scheme)
  local winid = vim.api.nvim_get_current_win()

  local parent_urls = {}
  local pending_paths = {}

  -- Handle as many paths synchronously as possible
  for _, path in ipairs(paths) do
    -- Trim the trailing slash off directories
    if vim.endswith(path, '/') then
      path = path:sub(1, -2)
    end

    local ori_entry = cache.get_entry_by_url(scheme .. path)
    local parent_url = util.addslash(scheme .. vim.fs.dirname(path))
    if ori_entry then
      write_pasted(winid, ori_entry, column_defs, adapter, bufnr)
      if delete_original then
        remove_entry_from_parent_buffer(parent_url, ori_entry)
      end
    else
      parent_urls[parent_url] = true
      table.insert(pending_paths, path)
    end
  end

  -- If all paths could be handled synchronously, we're done
  if #pending_paths == 0 then
    return
  end

  -- Process the remaining paths by asynchronously loading them
  local cursor = vim.api.nvim_win_get_cursor(winid)
  local complete_loading = util.cb_collect(#vim.tbl_keys(parent_urls), function(err)
    if err then
      vim.notify(string.format('Error loading parent directory: %s', err), vim.log.levels.ERROR)
    else
      -- Something in this process moves the cursor to the top of the window, so have to restore it
      vim.api.nvim_win_set_cursor(winid, cursor)

      for _, path in ipairs(pending_paths) do
        local ori_entry = cache.get_entry_by_url(scheme .. path)
        if ori_entry then
          write_pasted(winid, ori_entry, column_defs, adapter, bufnr)
          if delete_original then
            local parent_url = util.addslash(scheme .. vim.fs.dirname(path))
            remove_entry_from_parent_buffer(parent_url, ori_entry)
          end
        else
          vim.notify(
            string.format("The pasted file '%s' could not be found", path),
            vim.log.levels.ERROR
          )
        end
      end
    end
  end)

  for parent_url, _ in pairs(parent_urls) do
    local new_bufnr = vim.api.nvim_create_buf(false, false)
    vim.api.nvim_buf_set_name(new_bufnr, parent_url)
    canola.load_oil_buffer(new_bufnr)
    util.run_after_load(new_bufnr, complete_loading)
  end
end

---@return integer start
---@return integer end
local function range_from_selection()
  -- [bufnum, lnum, col, off]; both row and column 1-indexed
  local start = vim.fn.getpos('v')
  local end_ = vim.fn.getpos('.')
  local start_row = start[2]
  local end_row = end_[2]

  if start_row > end_row then
    start_row, end_row = end_row, start_row
  end

  return start_row, end_row
end

M.copy_to_system_clipboard = function()
  local dir = canola.get_current_dir()
  if not dir then
    vim.notify('System clipboard only works for local files', vim.log.levels.ERROR)
    return
  end

  local entries = {}
  local mode = vim.api.nvim_get_mode().mode
  if mode == 'v' or mode == 'V' then
    if fs.is_mac then
      vim.notify(
        'Copying multiple paths to clipboard is not supported on mac',
        vim.log.levels.ERROR
      )
      return
    end
    local start_row, end_row = range_from_selection()
    for i = start_row, end_row do
      table.insert(entries, canola.get_entry_on_line(0, i))
    end

    -- leave visual mode
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, false, true), 'n', true)
  else
    table.insert(entries, canola.get_cursor_entry())
  end

  -- This removes holes in the list-like table
  entries = vim.tbl_values(entries)

  if #entries == 0 then
    vim.notify('Could not find local file under cursor', vim.log.levels.WARN)
    return
  end
  local paths = {}
  for _, entry in ipairs(entries) do
    table.insert(paths, dir .. entry.name)
  end
  local cmd = {}
  local stdin
  if fs.is_mac then
    cmd = {
      'osascript',
      '-e',
      'on run args',
      '-e',
      'set the clipboard to POSIX file (first item of args)',
      '-e',
      'end run',
      paths[1],
    }
  elseif fs.is_linux then
    local xdg_session_type = get_linux_session_type()
    if xdg_session_type == 'x11' then
      vim.list_extend(cmd, { 'xclip', '-i', '-selection', 'clipboard' })
    elseif xdg_session_type == 'wayland' then
      table.insert(cmd, 'wl-copy')
    else
      vim.notify('System clipboard not supported, check $XDG_SESSION_TYPE', vim.log.levels.ERROR)
      return
    end
    local urls = {}
    for _, path in ipairs(paths) do
      table.insert(urls, 'file://' .. path)
    end
    if is_linux_desktop_gnome() then
      stdin = string.format('copy\n%s\0', table.concat(urls, '\n'))
      vim.list_extend(cmd, { '-t', 'x-special/gnome-copied-files' })
    else
      stdin = table.concat(urls, '\n') .. '\n'
      vim.list_extend(cmd, { '-t', 'text/uri-list' })
    end
  else
    vim.notify('System clipboard not supported on Windows', vim.log.levels.ERROR)
    return
  end

  if vim.fn.executable(cmd[1]) == 0 then
    vim.notify(string.format("Could not find executable '%s'", cmd[1]), vim.log.levels.ERROR)
    return
  end
  vim.system(
    cmd,
    { stdin = stdin or false, text = true },
    vim.schedule_wrap(function(result)
      if result.code ~= 0 then
        vim.notify(
          string.format(
            "Error copying '%s' to system clipboard\n%s",
            vim.inspect(paths),
            result.stderr or ''
          ),
          vim.log.levels.ERROR
        )
      else
        if #paths == 1 then
          vim.notify(string.format("Copied '%s' to system clipboard", paths[1]))
        else
          vim.notify(string.format('Copied %d files to system clipboard', #paths))
        end
      end
    end)
  )
end

---@param lines string[]
---@return string[]
local function handle_paste_output_mac(lines)
  local ret = {}
  for _, line in ipairs(lines) do
    if not line:match('^%s*$') then
      table.insert(ret, line)
    end
  end
  return ret
end

---@param lines string[]
---@return string[]
local function handle_paste_output_linux(lines)
  local ret = {}
  for _, line in ipairs(lines) do
    local path = line:match('^file://(.+)$')
    if path then
      table.insert(ret, util.url_unescape(path))
    end
  end
  return ret
end

---@param delete_original? boolean Delete the source file after pasting
M.paste_from_system_clipboard = function(delete_original)
  local dir = canola.get_current_dir()
  if not dir then
    return
  end
  local cmd = {}
  local handle_paste_output
  if fs.is_mac then
    cmd = {
      'osascript',
      '-e',
      'on run',
      '-e',
      'POSIX path of (the clipboard as «class furl»)',
      '-e',
      'end run',
    }
    handle_paste_output = handle_paste_output_mac
  elseif fs.is_linux then
    local xdg_session_type = get_linux_session_type()
    if xdg_session_type == 'x11' then
      vim.list_extend(cmd, { 'xclip', '-o', '-selection', 'clipboard' })
    elseif xdg_session_type == 'wayland' then
      table.insert(cmd, 'wl-paste')
    else
      vim.notify('System clipboard not supported, check $XDG_SESSION_TYPE', vim.log.levels.ERROR)
      return
    end
    if is_linux_desktop_gnome() then
      vim.list_extend(cmd, { '-t', 'x-special/gnome-copied-files' })
    else
      vim.list_extend(cmd, { '-t', 'text/uri-list' })
    end
    handle_paste_output = handle_paste_output_linux
  else
    vim.notify('System clipboard not supported on Windows', vim.log.levels.ERROR)
    return
  end
  if vim.fn.executable(cmd[1]) == 0 then
    vim.notify(string.format("Could not find executable '%s'", cmd[1]), vim.log.levels.ERROR)
    return
  end
  vim.system(
    cmd,
    { text = true },
    vim.schedule_wrap(function(result)
      if result.code ~= 0 then
        vim.notify(
          string.format('Error pasting from system clipboard: %s', result.stderr or ''),
          vim.log.levels.ERROR
        )
      else
        local lines = vim.split(result.stdout or '', '\r?\n')
        local paths = handle_paste_output(lines)
        if #paths == 0 then
          vim.notify('No valid files found in system clipboard', vim.log.levels.WARN)
        else
          paste_paths(paths, delete_original)
        end
      end
    end)
  )
end

return M
