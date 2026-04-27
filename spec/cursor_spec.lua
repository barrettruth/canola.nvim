local cursor = require('canola.cursor')
local test_util = require('spec.test_util')
local util = require('canola.util')

local function demo_lines()
  local lines = {}
  for i = 1, 40 do
    lines[i] = string.format('/%d file_%02d', i, i)
  end
  return lines
end

describe('cursor constraints', function()
  after_each(function()
    test_util.reset_editor()
  end)

  it('does not error when a stale cursor row is beyond the loading buffer', function()
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(bufnr)
    vim.bo[bufnr].buftype = 'nofile'
    vim.bo[bufnr].bufhidden = 'wipe'
    vim.bo[bufnr].swapfile = false
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, demo_lines())
    local stale = { 40, 0 }
    util.render_text(bufnr, { 'Loading', '[===]' }, { h_align = 'left', v_align = 'top' })
    assert.is_nil(cursor.calc_constrained_cursor_pos(bufnr, nil, 'editable', stale, 0))
  end)
end)
