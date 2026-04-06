local TmpDir = require('spec.tmpdir')
local files = require('canola.adapters.files')
local test_util = require('spec.test_util')

describe('files adapter', function()
  local tmpdir
  before_each(function()
    tmpdir = TmpDir.new()
  end)
  after_each(function()
    if tmpdir then
      tmpdir:dispose()
    end
    test_util.reset_editor()
  end)

  it('tmpdir creates files and asserts they exist', function()
    tmpdir:create({ 'a.txt', 'foo/b.txt', 'foo/c.txt', 'bar/' })
    tmpdir:assert_fs({
      ['a.txt'] = 'a.txt',
      ['foo/b.txt'] = 'foo/b.txt',
      ['foo/c.txt'] = 'foo/c.txt',
      ['bar/'] = true,
    })
  end)

  it('Creates files', function()
    local err = test_util.await(files.perform_action, 2, {
      url = 'canola://' .. vim.fn.fnamemodify(tmpdir.path, ':p') .. 'a.txt',
      entry_type = 'file',
      type = 'create',
    })
    assert.is_nil(err)
    tmpdir:assert_fs({
      ['a.txt'] = '',
    })
  end)

  it('Creates directories', function()
    local err = test_util.await(files.perform_action, 2, {
      url = 'canola://' .. vim.fn.fnamemodify(tmpdir.path, ':p') .. 'a',
      entry_type = 'directory',
      type = 'create',
    })
    assert.is_nil(err)
    tmpdir:assert_fs({
      ['a/'] = true,
    })
  end)

  it('Deletes files', function()
    tmpdir:create({ 'a.txt' })
    local url = 'canola://' .. vim.fn.fnamemodify(tmpdir.path, ':p') .. 'a.txt'
    local err = test_util.await(files.perform_action, 2, {
      url = url,
      entry_type = 'file',
      type = 'delete',
    })
    assert.is_nil(err)
    tmpdir:assert_fs({})
  end)

  it('Deletes directories', function()
    local config = require('canola.config')
    config.delete.recursive = true
    tmpdir:create({ 'a/' })
    local url = 'canola://' .. vim.fn.fnamemodify(tmpdir.path, ':p') .. 'a'
    local err = test_util.await(files.perform_action, 2, {
      url = url,
      entry_type = 'directory',
      type = 'delete',
    })
    assert.is_nil(err)
    tmpdir:assert_fs({})
    config.delete.recursive = false
  end)

  it('Deletes empty directories when recursive is false', function()
    tmpdir:create({ 'a/' })
    local url = 'canola://' .. vim.fn.fnamemodify(tmpdir.path, ':p') .. 'a'
    local err = test_util.await(files.perform_action, 2, {
      url = url,
      entry_type = 'directory',
      type = 'delete',
    })
    assert.is_nil(err)
    tmpdir:assert_fs({})
  end)

  it('Refuses to delete non-empty directories when recursive is false', function()
    tmpdir:create({ 'a/', 'a/b.txt' })
    local url = 'canola://' .. vim.fn.fnamemodify(tmpdir.path, ':p') .. 'a'
    local err = test_util.await(files.perform_action, 2, {
      url = url,
      entry_type = 'directory',
      type = 'delete',
    })
    assert.is_not_nil(err)
    tmpdir:assert_fs({ ['a/'] = true, ['a/b.txt'] = 'a/b.txt' })
  end)

  it('Moves files', function()
    tmpdir:create({ 'a.txt' })
    local src_url = 'canola://' .. vim.fn.fnamemodify(tmpdir.path, ':p') .. 'a.txt'
    local dest_url = 'canola://' .. vim.fn.fnamemodify(tmpdir.path, ':p') .. 'b.txt'
    local err = test_util.await(files.perform_action, 2, {
      src_url = src_url,
      dest_url = dest_url,
      entry_type = 'file',
      type = 'move',
    })
    assert.is_nil(err)
    tmpdir:assert_fs({
      ['b.txt'] = 'a.txt',
    })
  end)

  it('Moves directories', function()
    tmpdir:create({ 'a/a.txt' })
    local src_url = 'canola://' .. vim.fn.fnamemodify(tmpdir.path, ':p') .. 'a'
    local dest_url = 'canola://' .. vim.fn.fnamemodify(tmpdir.path, ':p') .. 'b'
    local err = test_util.await(files.perform_action, 2, {
      src_url = src_url,
      dest_url = dest_url,
      entry_type = 'directory',
      type = 'move',
    })
    assert.is_nil(err)
    tmpdir:assert_fs({
      ['b/a.txt'] = 'a/a.txt',
      ['b/'] = true,
    })
  end)

  it('Copies files', function()
    tmpdir:create({ 'a.txt' })
    local src_url = 'canola://' .. vim.fn.fnamemodify(tmpdir.path, ':p') .. 'a.txt'
    local dest_url = 'canola://' .. vim.fn.fnamemodify(tmpdir.path, ':p') .. 'b.txt'
    local err = test_util.await(files.perform_action, 2, {
      src_url = src_url,
      dest_url = dest_url,
      entry_type = 'file',
      type = 'copy',
    })
    assert.is_nil(err)
    tmpdir:assert_fs({
      ['a.txt'] = 'a.txt',
      ['b.txt'] = 'a.txt',
    })
  end)

  it('Recursively copies directories', function()
    tmpdir:create({ 'a/a.txt' })
    local src_url = 'canola://' .. vim.fn.fnamemodify(tmpdir.path, ':p') .. 'a'
    local dest_url = 'canola://' .. vim.fn.fnamemodify(tmpdir.path, ':p') .. 'b'
    local err = test_util.await(files.perform_action, 2, {
      src_url = src_url,
      dest_url = dest_url,
      entry_type = 'directory',
      type = 'copy',
    })
    assert.is_nil(err)
    tmpdir:assert_fs({
      ['b/a.txt'] = 'a/a.txt',
      ['b/'] = true,
      ['a/a.txt'] = 'a/a.txt',
      ['a/'] = true,
    })
  end)

  it('Editing a new canola://path/ creates an oil buffer', function()
    local tmpdir_url = 'canola://' .. vim.fn.fnamemodify(tmpdir.path, ':p') .. '/'
    vim.cmd.edit({ args = { tmpdir_url } })
    test_util.wait_canola_ready()
    local new_url = 'canola://' .. vim.fn.fnamemodify(tmpdir.path, ':p') .. 'newdir'
    vim.cmd.edit({ args = { new_url } })
    test_util.wait_canola_ready()
    assert.equals('canola', vim.bo.filetype)
    assert.equals(new_url .. '/', vim.api.nvim_buf_get_name(0))
  end)

  it('Editing a new canola://file.rb creates a normal buffer', function()
    local tmpdir_url = 'canola://' .. vim.fn.fnamemodify(tmpdir.path, ':p') .. '/'
    vim.cmd.edit({ args = { tmpdir_url } })
    test_util.wait_for_autocmd('BufReadPost')
    local new_url = 'canola://' .. vim.fn.fnamemodify(tmpdir.path, ':p') .. 'file.rb'
    vim.cmd.edit({ args = { new_url } })
    test_util.wait_for_autocmd('BufReadPost')
    assert.equals('ruby', vim.bo.filetype)
    assert.equals(vim.fn.fnamemodify(tmpdir.path, ':p') .. 'file.rb', vim.api.nvim_buf_get_name(0))
    assert.equals(tmpdir.path .. '/file.rb', vim.fn.bufname())
  end)

  describe('cleanup_buffers_on_delete', function()
    local cache = require('canola.cache')
    local config = require('canola.config')
    local mutator = require('canola.mutator')

    before_each(function()
      config.delete.wipe = true
    end)

    after_each(function()
      config.delete.wipe = false
    end)

    it('wipes the buffer for a deleted file', function()
      tmpdir:create({ 'a.txt' })
      local dirurl = 'canola://' .. vim.fn.fnamemodify(tmpdir.path, ':p')
      local filepath = vim.fn.fnamemodify(tmpdir.path, ':p') .. 'a.txt'
      cache.create_and_store_entry(dirurl, 'a.txt', 'file')
      vim.cmd.edit({ args = { filepath } })
      local bufnr = vim.api.nvim_get_current_buf()
      local url = 'canola://' .. filepath
      test_util.await(mutator.process_actions, 2, {
        { type = 'delete', url = url, entry_type = 'file' },
      })
      assert.is_false(vim.api.nvim_buf_is_valid(bufnr))
    end)

    it('wipes the buffer for a deleted file behind a float', function()
      local canola = require('canola')
      tmpdir:create({ 'c.txt' })
      local dirurl = 'canola://' .. vim.fn.fnamemodify(tmpdir.path, ':p')
      local filepath = vim.fn.fnamemodify(tmpdir.path, ':p') .. 'c.txt'
      cache.create_and_store_entry(dirurl, 'c.txt', 'file')
      vim.cmd.edit({ args = { filepath } })
      local bufnr = vim.api.nvim_get_current_buf()
      test_util.await(canola.open_float, 3, tmpdir.path)
      local original_win = vim.w.canola_original_win
      assert(vim.api.nvim_win_is_valid(original_win))
      assert.equals(bufnr, vim.api.nvim_win_get_buf(original_win))
      local url = 'canola://' .. filepath
      test_util.await(mutator.process_actions, 2, {
        { type = 'delete', url = url, entry_type = 'file' },
      })
      assert.is_false(vim.api.nvim_buf_is_valid(bufnr))
    end)

    it('does not wipe the buffer when disabled', function()
      config.delete.wipe = false
      tmpdir:create({ 'b.txt' })
      local dirurl = 'canola://' .. vim.fn.fnamemodify(tmpdir.path, ':p')
      local filepath = vim.fn.fnamemodify(tmpdir.path, ':p') .. 'b.txt'
      cache.create_and_store_entry(dirurl, 'b.txt', 'file')
      vim.cmd.edit({ args = { filepath } })
      local bufnr = vim.api.nvim_get_current_buf()
      local url = 'canola://' .. filepath
      test_util.await(mutator.process_actions, 2, {
        { type = 'delete', url = url, entry_type = 'file' },
      })
      assert.is_true(vim.api.nvim_buf_is_valid(bufnr))
    end)
  end)
end)
