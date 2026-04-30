local M = {}

---@class (exact) canola.OpenOpts
---@field preview? canola.OpenPreviewOpts When present, open the preview window after opening oil

---Open oil browser in a floating window
---@param dir? string When nil, open the parent of the current buffer, or the cwd if current buffer is not a file
---@param opts? canola.OpenOpts
---@param cb? fun() Called after the oil buffer is ready
M.open_float = function(dir, opts, cb)
  opts = opts or {}
  local canola = require('canola')
  local config = require('canola.config')
  local layout = require('canola.layout')
  local util = require('canola.util')
  local view = require('canola.view')

  local parent_url, basename = canola.get_url_for_path(dir)
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
        canola.open_preview(opts.preview, cb)
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
          local cur_win_opts = vim.api.nvim_win_get_config(winid)
          if cur_win_opts.border ~= 'none' then
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
      canola.open_preview(opts.preview, cb)
    elseif cb then
      cb()
    end
  end)

  if config.float.title and vim.api.nvim_win_get_config(winid).border == 'none' then
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
  local canola = require('canola')
  local config = require('canola.config')
  local util = require('canola.util')
  local view = require('canola.view')

  local parent_url, basename = canola.get_url_for_path(dir)
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
      canola.open_preview(opts.preview, cb)
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
M.update_preview_window = function(oil_bufnr)
  oil_bufnr = oil_bufnr or 0
  local canola = require('canola')
  local util = require('canola.util')
  util.run_after_load(oil_bufnr, function()
    local cursor_entry = canola.get_cursor_entry()
    local preview_win_id = util.get_preview_win()
    if
      cursor_entry
      and preview_win_id
      and cursor_entry.id ~= vim.w[preview_win_id].canola_entry_id
    then
      canola.open_preview()
    end
  end)
end

---Open oil browser for a directory
---@param dir? string When nil, open the parent of the current buffer, or the cwd if current buffer is not a file
---@param opts? canola.OpenOpts
---@param cb? fun() Called after the oil buffer is ready
M.open = function(dir, opts, cb)
  opts = opts or {}
  local canola = require('canola')
  local config = require('canola.config')
  if config.float.default then
    return M.open_float(dir, opts, cb)
  end
  local util = require('canola.util')
  local view = require('canola.view')
  local parent_url, basename = canola.get_url_for_path(dir)
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
      canola.open_preview(opts.preview, cb)
    elseif cb then
      cb()
    end
  end)

  -- If preview window exists, update its content
  M.update_preview_window()
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

return M
