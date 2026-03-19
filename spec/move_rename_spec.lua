local fs = require('canola.fs')
local test_util = require('spec.test_util')
local util = require('canola.util')

describe('update_moved_buffers', function()
  after_each(function()
    test_util.reset_editor()
  end)

  it('Renames moved buffers', function()
    vim.cmd.edit({ args = { 'canola-test:///foo/bar.txt' } })
    util.update_moved_buffers('file', 'canola-test:///foo/bar.txt', 'canola-test:///foo/baz.txt')
    assert.equals('canola-test:///foo/baz.txt', vim.api.nvim_buf_get_name(0))
  end)

  it('Renames moved buffers when they are normal files', function()
    local tmpdir = fs.join(vim.loop.fs_realpath(vim.fn.stdpath('cache')), 'canola', 'test')
    local testfile = fs.join(tmpdir, 'foo.txt')
    vim.cmd.edit({ args = { testfile } })
    util.update_moved_buffers(
      'file',
      'canola://' .. fs.os_to_posix_path(testfile),
      'canola://' .. fs.os_to_posix_path(fs.join(tmpdir, 'bar.txt'))
    )
    assert.equals(fs.join(tmpdir, 'bar.txt'), vim.api.nvim_buf_get_name(0))
  end)

  it('Renames directories', function()
    vim.cmd.edit({ args = { 'canola-test:///foo/' } })
    util.update_moved_buffers('directory', 'canola-test:///foo/', 'canola-test:///bar/')
    assert.equals('canola-test:///bar/', vim.api.nvim_buf_get_name(0))
  end)

  it('Renames subdirectories', function()
    vim.cmd.edit({ args = { 'canola-test:///foo/bar/' } })
    util.update_moved_buffers('directory', 'canola-test:///foo/', 'canola-test:///baz/')
    assert.equals('canola-test:///baz/bar/', vim.api.nvim_buf_get_name(0))
  end)

  it('Renames subfiles', function()
    vim.cmd.edit({ args = { 'canola-test:///foo/bar.txt' } })
    util.update_moved_buffers('directory', 'canola-test:///foo/', 'canola-test:///baz/')
    assert.equals('canola-test:///baz/bar.txt', vim.api.nvim_buf_get_name(0))
  end)

  it('Renames subfiles when they are normal files', function()
    local tmpdir = fs.join(vim.loop.fs_realpath(vim.fn.stdpath('cache')), 'canola', 'test')
    local foo = fs.join(tmpdir, 'foo')
    local bar = fs.join(tmpdir, 'bar')
    local testfile = fs.join(foo, 'foo.txt')
    vim.cmd.edit({ args = { testfile } })
    util.update_moved_buffers(
      'directory',
      'canola://' .. fs.os_to_posix_path(foo),
      'canola://' .. fs.os_to_posix_path(bar)
    )
    assert.equals(fs.join(bar, 'foo.txt'), vim.api.nvim_buf_get_name(0))
  end)
end)
