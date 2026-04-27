local config = require('canola.config')
local fs = require('canola.fs')
local test_util = require('spec.test_util')
local view = require('canola.view')

describe('watcher paths', function()
  local uv = vim.uv
  local old_is_windows
  local old_new_fs_event
  local old_render_buffer_async
  local old_watch
  local started_path
  local start_calls

  before_each(function()
    started_path = nil
    start_calls = 0
    old_is_windows = fs.is_windows
    old_new_fs_event = uv.new_fs_event
    old_render_buffer_async = view.render_buffer_async
    old_watch = config.watch
    fs.is_windows = true
    config.watch = true
    uv.new_fs_event = function()
      return {
        start = function(_, path)
          start_calls = start_calls + 1
          started_path = path
        end,
        stop = function() end,
      }
    end
    view.render_buffer_async = function() end
  end)

  after_each(function()
    fs.is_windows = old_is_windows
    config.watch = old_watch
    uv.new_fs_event = old_new_fs_event
    view.render_buffer_async = old_render_buffer_async
    test_util.reset_editor()
  end)

  it('uses an os path when starting file watchers on windows', function()
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(bufnr)
    vim.api.nvim_buf_set_name(bufnr, 'canola:///C/tmp/canola-test/')
    view.initialize(bufnr)
    assert.equals('C:\\tmp\\canola-test\\', started_path)
    assert.equals(1, start_calls)
  end)

  it('skips starting a watcher for the windows drive list buffer', function()
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(bufnr)
    vim.api.nvim_buf_set_name(bufnr, 'canola:///')
    view.initialize(bufnr)
    assert.is_nil(started_path)
    assert.equals(0, start_calls)
  end)
end)
