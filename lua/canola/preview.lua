local M = {}

---@class canola.OpenPreviewOpts
---@field vertical? boolean Open the buffer in a vertical split
---@field horizontal? boolean Open the buffer in a horizontal split
---@field split? "aboveleft"|"belowright"|"topleft"|"botright" Split modifier

---Preview the entry under the cursor in a split
---@param opts? canola.OpenPreviewOpts
---@param callback? fun(err: nil|string) Called once the preview window has been opened
M.open_preview = function(opts, callback)
  opts = opts or {}
  local canola = require('canola')
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

  local entry = canola.get_cursor_entry()
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
      canola.load_oil_buffer(filebufnr)
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

return M
