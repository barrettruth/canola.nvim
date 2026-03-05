local TmpDir = require('spec.tmpdir')
local actions = require('canola.actions')
local canola = require('canola')
local test_util = require('spec.test_util')
local view = require('canola.view')

describe('regression tests', function()
  local tmpdir
  before_each(function()
    tmpdir = TmpDir.new()
  end)
  after_each(function()
    if tmpdir then
      tmpdir:dispose()
      tmpdir = nil
    end
    test_util.reset_editor()
  end)

  it('can edit dirs that will be renamed to an existing buffer', function()
    vim.cmd.edit({ args = { 'README.md' } })
    vim.cmd.vsplit()
    vim.cmd.edit({ args = { '%:p:h' } })
    assert.equals('canola', vim.bo.filetype)
    vim.cmd.wincmd({ args = { 'p' } })
    assert.equals('markdown', vim.bo.filetype)
    vim.cmd.edit({ args = { '%:p:h' } })
    test_util.wait_for_autocmd({ 'User', pattern = 'CanolaEnter' })
    assert.equals('canola', vim.bo.filetype)
  end)

  it('places the cursor on correct entry when opening on file', function()
    vim.cmd.edit({ args = { '.' } })
    test_util.wait_for_autocmd({ 'User', pattern = 'CanolaEnter' })
    local entry = canola.get_cursor_entry()
    assert.not_nil(entry)
    assert.not_equals('README.md', entry and entry.name)
    vim.cmd.edit({ args = { 'README.md' } })
    view.delete_hidden_buffers()
    canola.open()
    test_util.wait_for_autocmd({ 'User', pattern = 'CanolaEnter' })
    entry = canola.get_cursor_entry()
    assert.equals('README.md', entry and entry.name)
  end)

  it("doesn't close floating windows canola didn't open itself", function()
    local winid = vim.api.nvim_open_win(vim.fn.bufadd('README.md'), true, {
      relative = 'editor',
      row = 1,
      col = 1,
      width = 100,
      height = 100,
    })
    canola.open()
    vim.wait(10)
    canola.close()
    vim.wait(10)
    assert.equals(winid, vim.api.nvim_get_current_win())
  end)

  it("doesn't close splits on canola.close", function()
    vim.cmd.edit({ args = { 'README.md' } })
    vim.cmd.vsplit()
    local winid = vim.api.nvim_get_current_win()
    local bufnr = vim.api.nvim_get_current_buf()
    canola.open()
    vim.wait(10)
    canola.close()
    vim.wait(10)
    assert.equals(2, #vim.api.nvim_tabpage_list_wins(0))
    assert.equals(winid, vim.api.nvim_get_current_win())
    assert.equals(bufnr, vim.api.nvim_get_current_buf())
  end)

  it('Returns to empty buffer on close', function()
    canola.open()
    test_util.wait_for_autocmd({ 'User', pattern = 'CanolaEnter' })
    canola.close()
    assert.not_equals('canola', vim.bo.filetype)
    assert.equals('', vim.api.nvim_buf_get_name(0))
  end)

  it('All buffers set nomodified after save', function()
    tmpdir:create({ 'a.txt' })
    vim.cmd.edit({ args = { 'canola://' .. vim.fn.fnamemodify(tmpdir.path, ':p') } })
    local first_dir = vim.api.nvim_get_current_buf()
    test_util.wait_for_autocmd({ 'User', pattern = 'CanolaEnter' })
    test_util.feedkeys({ 'dd', 'itest/<esc>', '<CR>' }, 10)
    vim.wait(1000, function()
      return vim.bo.modifiable
    end, 10)
    test_util.feedkeys({ 'p' }, 10)
    canola.save({ confirm = false })
    vim.wait(1000, function()
      return vim.bo.modifiable
    end, 10)
    tmpdir:assert_fs({
      ['test/a.txt'] = 'a.txt',
    })
    assert.falsy(vim.bo[first_dir].modified)
  end)

  it("refreshing buffer doesn't lose track of it", function()
    vim.cmd.edit({ args = { '.' } })
    test_util.wait_for_autocmd({ 'User', pattern = 'CanolaEnter' })
    local bufnr = vim.api.nvim_get_current_buf()
    vim.cmd.edit({ bang = true })
    test_util.wait_for_autocmd({ 'User', pattern = 'CanolaEnter' })
    assert.are.same({ bufnr }, require('canola.view').get_all_buffers())
  end)

  it('can copy a file multiple times', function()
    test_util.actions.open({ tmpdir.path })
    vim.api.nvim_feedkeys('ifoo.txt', 'x', true)
    test_util.actions.save()
    vim.api.nvim_feedkeys('yyp$ciWbar.txt', 'x', true)
    vim.api.nvim_feedkeys('yyp$ciWbaz.txt', 'x', true)
    test_util.actions.save()
    assert.are.same({ 'bar.txt', 'baz.txt', 'foo.txt' }, test_util.parse_entries(0))
    tmpdir:assert_fs({
      ['foo.txt'] = '',
      ['bar.txt'] = '',
      ['baz.txt'] = '',
    })
  end)

  it('can open files from floating window', function()
    tmpdir:create({ 'a.txt' })
    canola.open_float(tmpdir.path)
    test_util.wait_for_autocmd({ 'User', pattern = 'CanolaEnter' })
    actions.select.callback()
    vim.wait(1000, function()
      return vim.fn.expand('%:t') == 'a.txt'
    end, 10)
    assert.equals('a.txt', vim.fn.expand('%:t'))
  end)
end)
