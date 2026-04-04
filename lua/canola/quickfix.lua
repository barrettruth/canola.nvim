local M = {}

---Send files from the current oil directory to quickfix
---based on the provided options.
---@param opts {target?: "qflist"|"loclist", action?: "r"|"a", only_matching_search?: boolean}
M.send_to_quickfix = function(opts)
  if type(opts) ~= 'table' then
    opts = {}
  end
  local canola = require('canola')
  local util = require('canola.util')
  local dir = canola.get_current_dir()
  if type(dir) ~= 'string' then
    return
  end
  local range = util.get_visual_range()
  if not range then
    range = { start_lnum = 1, end_lnum = vim.fn.line('$') }
  end
  local match_all = not opts.only_matching_search
  local qf_entries = {}
  for i = range.start_lnum, range.end_lnum do
    local entry = canola.get_entry_on_line(0, i)
    if entry and entry.type == 'file' and (match_all or util.is_matching(entry)) then
      local qf_entry = {
        filename = dir .. entry.name,
        lnum = 1,
        col = 1,
        text = entry.name,
      }
      table.insert(qf_entries, qf_entry)
    end
  end
  if #qf_entries == 0 then
    vim.notify('[canola] No entries found to send to quickfix', vim.log.levels.WARN)
    return
  end
  vim.api.nvim_exec_autocmds('QuickFixCmdPre', {})
  local qf_title = 'canola files'
  local action = opts.action == 'a' and 'a' or 'r'
  if opts.target == 'loclist' then
    vim.fn.setloclist(0, {}, action, { title = qf_title, items = qf_entries })
    vim.cmd.lopen()
  else
    vim.fn.setqflist({}, action, { title = qf_title, items = qf_entries })
    vim.cmd.copen()
  end
  vim.api.nvim_exec_autocmds('QuickFixCmdPost', {})
end

M.add_to_quickfix = function(opts)
  if type(opts) ~= 'table' then
    opts = {}
  end
  local canola = require('canola')
  local util = require('canola.util')
  local dir = canola.get_current_dir()
  if type(dir) ~= 'string' then
    return
  end
  local range = util.get_visual_range()
  local qf_entries = {}
  if range then
    for i = range.start_lnum, range.end_lnum do
      local entry = canola.get_entry_on_line(0, i)
      if entry and entry.type == 'file' then
        table.insert(qf_entries, {
          filename = dir .. entry.name,
          lnum = 1,
          col = 1,
        })
      end
    end
  else
    local entry = canola.get_cursor_entry()
    if entry and entry.type == 'file' then
      table.insert(qf_entries, {
        filename = dir .. entry.name,
        lnum = 1,
        col = 1,
      })
    end
  end
  if #qf_entries == 0 then
    vim.notify('[canola] No file entries to add to quickfix', vim.log.levels.WARN)
    return
  end
  vim.api.nvim_exec_autocmds('QuickFixCmdPre', {})
  if opts.target == 'loclist' then
    vim.fn.setloclist(0, {}, 'a', { title = 'canola files', items = qf_entries })
  else
    vim.fn.setqflist({}, 'a', { title = 'canola files', items = qf_entries })
  end
  vim.api.nvim_exec_autocmds('QuickFixCmdPost', {})
  local count = #qf_entries
  local names = vim.tbl_map(function(e)
    return e.text
  end, qf_entries)
  vim.notify(('[canola] Added %s to quickfix'):format(table.concat(names, ', ')))
end

return M
