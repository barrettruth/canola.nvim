local M = {}

---@param winid nil|integer
---@return boolean
M.is_floating_win = function(winid)
  return vim.api.nvim_win_get_config(winid or 0).relative ~= ''
end

---Recalculate the window title for the current buffer
---@param winid nil|integer
---@return string
M.get_title = function(winid)
  local config = require('canola.config')
  local util = require('canola.util')
  winid = winid or 0
  local src_buf = vim.api.nvim_win_get_buf(winid)
  local title = vim.api.nvim_buf_get_name(src_buf)
  local scheme, path = util.parse_url(title)

  if config.adapters[scheme] == 'files' then
    assert(path)
    local fs = require('canola.fs')
    title = vim.fn.fnamemodify(fs.posix_to_os_path(path), ':~')
  end
  local ev_data = { winid = winid, bufnr = src_buf, title = title }
  vim.api.nvim_exec_autocmds(
    'User',
    { pattern = 'CanolaWinTitle', modeline = false, data = ev_data }
  )
  return ev_data.title
end

---@type table<integer, integer>
local winid_map = {}
M.add_title_to_win = function(winid, opts)
  opts = opts or {}
  opts.align = opts.align or 'left'
  if not vim.api.nvim_win_is_valid(winid) then
    return
  end
  -- HACK to force the parent window to position itself
  -- See https://github.com/neovim/neovim/issues/13403
  vim.cmd.redraw()
  local title = M.get_title(winid)
  local width = math.min(vim.api.nvim_win_get_width(winid) - 4, 2 + vim.api.nvim_strwidth(title))
  local title_winid = winid_map[winid]
  local bufnr
  if title_winid and vim.api.nvim_win_is_valid(title_winid) then
    vim.api.nvim_win_set_width(title_winid, width)
    bufnr = vim.api.nvim_win_get_buf(title_winid)
  else
    bufnr = vim.api.nvim_create_buf(false, true)
    local col = 1
    if opts.align == 'center' then
      col = math.floor((vim.api.nvim_win_get_width(winid) - width) / 2)
    elseif opts.align == 'right' then
      col = vim.api.nvim_win_get_width(winid) - 1 - width
    elseif opts.align ~= 'left' then
      vim.notify(
        string.format("Unknown oil window title alignment: '%s'", opts.align),
        vim.log.levels.ERROR
      )
    end
    title_winid = vim.api.nvim_open_win(bufnr, false, {
      relative = 'win',
      win = winid,
      width = width,
      height = 1,
      row = -1,
      col = col,
      focusable = false,
      zindex = 151,
      style = 'minimal',
      noautocmd = true,
    })
    winid_map[winid] = title_winid
    vim.api.nvim_set_option_value(
      'winblend',
      vim.wo[winid].winblend,
      { scope = 'local', win = title_winid }
    )
    vim.bo[bufnr].bufhidden = 'wipe'

    local update_autocmd = vim.api.nvim_create_autocmd('BufWinEnter', {
      desc = 'Update oil floating window title when buffer changes',
      pattern = '*',
      callback = function(params)
        local winbuf = params.buf
        if vim.api.nvim_win_get_buf(winid) ~= winbuf then
          return
        end
        local new_title = M.get_title(winid)
        local new_width =
          math.min(vim.api.nvim_win_get_width(winid) - 4, 2 + vim.api.nvim_strwidth(new_title))
        vim.api.nvim_buf_set_lines(bufnr, 0, -1, true, { ' ' .. new_title .. ' ' })
        vim.bo[bufnr].modified = false
        vim.api.nvim_win_set_width(title_winid, new_width)
        local new_col = 1
        if opts.align == 'center' then
          new_col = math.floor((vim.api.nvim_win_get_width(winid) - new_width) / 2)
        elseif opts.align == 'right' then
          new_col = vim.api.nvim_win_get_width(winid) - 1 - new_width
        end
        vim.api.nvim_win_set_config(title_winid, {
          relative = 'win',
          win = winid,
          row = -1,
          col = new_col,
          width = new_width,
          height = 1,
        })
      end,
    })
    vim.api.nvim_create_autocmd('WinClosed', {
      desc = 'Close oil floating window title when floating window closes',
      pattern = tostring(winid),
      callback = function()
        if title_winid and vim.api.nvim_win_is_valid(title_winid) then
          vim.api.nvim_win_close(title_winid, true)
        end
        winid_map[winid] = nil
        vim.api.nvim_del_autocmd(update_autocmd)
      end,
      once = true,
      nested = true,
    })
  end
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, true, { ' ' .. title .. ' ' })
  vim.bo[bufnr].modified = false
  vim.api.nvim_set_option_value(
    'winhighlight',
    'Normal:FloatTitle,NormalFloat:FloatTitle',
    { scope = 'local', win = title_winid }
  )
end

---Run a function in the context of a full-editor window
---@param bufnr nil|integer
---@param callback fun()
M.run_in_fullscreen_win = function(bufnr, callback)
  if not bufnr then
    bufnr = vim.api.nvim_create_buf(false, true)
    vim.bo[bufnr].bufhidden = 'wipe'
  end
  local winid = vim.api.nvim_open_win(bufnr, false, {
    relative = 'editor',
    width = vim.o.columns,
    height = vim.o.lines,
    row = 0,
    col = 0,
    noautocmd = true,
  })
  local winnr = vim.api.nvim_win_get_number(winid)
  vim.cmd.wincmd({ count = winnr, args = { 'w' }, mods = { noautocmd = true } })
  callback()
  vim.cmd.close({ count = winnr, mods = { noautocmd = true, emsg_silent = true } })
end

---@param bufnr integer
---@param preferred_win nil|integer
---@return nil|integer
M.buf_get_win = function(bufnr, preferred_win)
  if
    preferred_win
    and vim.api.nvim_win_is_valid(preferred_win)
    and vim.api.nvim_win_get_buf(preferred_win) == bufnr
  then
    return preferred_win
  end
  for _, winid in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.api.nvim_win_is_valid(winid) and vim.api.nvim_win_get_buf(winid) == bufnr then
      return winid
    end
  end
  for _, winid in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_is_valid(winid) and vim.api.nvim_win_get_buf(winid) == bufnr then
      return winid
    end
  end
  return nil
end

---@param opts? {include_not_owned?: boolean}
---@return nil|integer
M.get_preview_win = function(opts)
  opts = opts or {}

  for _, winid in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if
      vim.api.nvim_win_is_valid(winid)
      and vim.wo[winid].previewwindow
      and (opts.include_not_owned or vim.w[winid]['oil_preview'])
    then
      return winid
    end
  end
end

---@return fun() restore Function that restores the cursor
M.hide_cursor = function()
  vim.api.nvim_set_hl(0, 'CanolaPreviewCursor', { nocombine = true, blend = 100 })
  local original_guicursor = vim.go.guicursor
  vim.go.guicursor = 'a:CanolaPreviewCursor/CanolaPreviewCursor'

  return function()
    -- HACK: see https://github.com/neovim/neovim/issues/21018
    vim.go.guicursor = 'a:'
    vim.cmd.redrawstatus()
    vim.go.guicursor = original_guicursor
  end
end

return M
