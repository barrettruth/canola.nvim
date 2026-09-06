local constants = require('canola.constants')
local parser = require('canola.mutator.parser')
local test_adapter = require('canola.adapters.test')
local test_util = require('spec.test_util')
local util = require('canola.util')
local view = require('canola.view')

local FIELD_ID = constants.FIELD_ID
local FIELD_META = constants.FIELD_META

local function set_lines(bufnr, lines)
  vim.bo[bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, true, lines)
end

describe('parser', function()
  after_each(function()
    test_util.reset_editor()
  end)

  it('detects new files', function()
    vim.cmd.edit({ args = { 'canola-test:///foo/' } })
    local bufnr = vim.api.nvim_get_current_buf()
    set_lines(bufnr, {
      'a.txt',
    })
    local diffs = parser.parse(bufnr)
    assert.are.same({ { entry_type = 'file', name = 'a.txt', type = 'new' } }, diffs)
  end)

  it('detects new directories', function()
    vim.cmd.edit({ args = { 'canola-test:///foo/' } })
    local bufnr = vim.api.nvim_get_current_buf()
    set_lines(bufnr, {
      'foo/',
    })
    local diffs = parser.parse(bufnr)
    assert.are.same({ { entry_type = 'directory', name = 'foo', type = 'new' } }, diffs)
  end)

  it('parses permissions from new entries when the column is configured', function()
    local files = require('canola.adapters.files')
    if not files.get_column('permissions') then
      pending('permissions column not available on this platform')
      return
    end
    vim.g.canola = vim.tbl_deep_extend('force', vim.g.canola, {
      columns = { 'permissions' },
    })
    require('canola').init()

    local entry, err = parser.parse_new_entry(files, 'rwsr-sr-t private/')
    assert.is_nil(err)
    assert.are.same({
      name = 'private',
      entry_type = 'directory',
      changes = {
        { column = 'permissions', value = tonumber('7755', 8) },
      },
    }, entry)
  end)

  it('requires whitespace after new-entry permissions', function()
    local files = require('canola.adapters.files')
    if not files.get_column('permissions') then
      pending('permissions column not available on this platform')
      return
    end
    vim.g.canola = vim.tbl_deep_extend('force', vim.g.canola, {
      columns = { 'permissions' },
    })
    require('canola').init()

    local entry = parser.parse_new_entry(files, 'rwxrwxrwxscript.sh')
    assert.are.same({
      name = 'rwxrwxrwxscript.sh',
      entry_type = 'file',
    }, entry)
  end)

  it('keeps permission-like prefixes when the column is hidden', function()
    local files = require('canola.adapters.files')
    local entry = parser.parse_new_entry(files, 'rwxrwxrwx script.sh')
    assert.are.same({
      name = 'rwxrwxrwx script.sh',
      entry_type = 'file',
    }, entry)
  end)

  it('rejects metadata on new symbolic links', function()
    local files = require('canola.adapters.files')
    if not files.get_column('permissions') then
      pending('permissions column not available on this platform')
      return
    end
    vim.g.canola = vim.tbl_deep_extend('force', vim.g.canola, {
      columns = { 'permissions' },
    })
    require('canola').init()

    local entry, err = parser.parse_new_entry(files, 'rwx------ script -> target')
    assert.is_nil(entry)
    assert.equals('Metadata cannot be set when creating a symbolic link', err)
  end)

  it('detects new links', function()
    vim.cmd.edit({ args = { 'canola-test:///foo/' } })
    local bufnr = vim.api.nvim_get_current_buf()
    set_lines(bufnr, {
      'a.txt -> b.txt',
    })
    local diffs = parser.parse(bufnr)
    assert.are.same(
      { { entry_type = 'link', name = 'a.txt', type = 'new', link = 'b.txt' } },
      diffs
    )
  end)

  it('detects deleted files', function()
    local file = test_adapter.test_set('/foo/a.txt', 'file')
    vim.cmd.edit({ args = { 'canola-test:///foo/' } })
    local bufnr = vim.api.nvim_get_current_buf()
    set_lines(bufnr, {})
    local diffs = parser.parse(bufnr)
    assert.are.same({
      { name = 'a.txt', type = 'delete', id = file[FIELD_ID] },
    }, diffs)
  end)

  it('detects deleted directories', function()
    local dir = test_adapter.test_set('/foo/bar', 'directory')
    vim.cmd.edit({ args = { 'canola-test:///foo/' } })
    local bufnr = vim.api.nvim_get_current_buf()
    set_lines(bufnr, {})
    local diffs = parser.parse(bufnr)
    assert.are.same({
      { name = 'bar', type = 'delete', id = dir[FIELD_ID] },
    }, diffs)
  end)

  it('detects deleted links', function()
    local file = test_adapter.test_set('/foo/a.txt', 'link')
    file[FIELD_META] = { link = 'b.txt' }
    vim.cmd.edit({ args = { 'canola-test:///foo/' } })
    local bufnr = vim.api.nvim_get_current_buf()
    set_lines(bufnr, {})
    local diffs = parser.parse(bufnr)
    assert.are.same({
      { name = 'a.txt', type = 'delete', id = file[FIELD_ID] },
    }, diffs)
  end)

  it('ignores empty lines', function()
    local file = test_adapter.test_set('/foo/a.txt', 'file')
    vim.cmd.edit({ args = { 'canola-test:///foo/' } })
    local bufnr = vim.api.nvim_get_current_buf()
    local cols = view.format_entry_line(file, test_adapter, false)
    local lines = util.render_table({ cols }, {})
    table.insert(lines, '')
    table.insert(lines, '     ')
    set_lines(bufnr, lines)
    local diffs = parser.parse(bufnr)
    assert.are.same({}, diffs)
  end)

  it('errors on missing filename', function()
    vim.cmd.edit({ args = { 'canola-test:///foo/' } })
    local bufnr = vim.api.nvim_get_current_buf()
    set_lines(bufnr, {
      '/008',
    })
    local _, errors = parser.parse(bufnr)
    assert.are_same({
      {
        message = 'Malformed ID at start of line',
        lnum = 0,
        end_lnum = 1,
        col = 0,
      },
    }, errors)
  end)

  it('errors on empty dirname', function()
    vim.cmd.edit({ args = { 'canola-test:///foo/' } })
    local bufnr = vim.api.nvim_get_current_buf()
    set_lines(bufnr, {
      '/008 /',
    })
    local _, errors = parser.parse(bufnr)
    assert.are.same({
      {
        message = 'No filename found',
        lnum = 0,
        end_lnum = 1,
        col = 0,
      },
    }, errors)
  end)

  it('errors on duplicate names', function()
    vim.cmd.edit({ args = { 'canola-test:///foo/' } })
    local bufnr = vim.api.nvim_get_current_buf()
    set_lines(bufnr, {
      'foo',
      'foo/',
    })
    local _, errors = parser.parse(bufnr)
    assert.are.same({
      {
        message = 'Duplicate filename: foo',
        lnum = 1,
        end_lnum = 2,
        col = 0,
      },
    }, errors)
  end)

  it('errors on duplicate names for existing files', function()
    local file = test_adapter.test_set('/foo/a.txt', 'file')
    vim.cmd.edit({ args = { 'canola-test:///foo/' } })
    local bufnr = vim.api.nvim_get_current_buf()
    set_lines(bufnr, {
      'a.txt',
      string.format('/%d a.txt', file[FIELD_ID]),
    })
    local _, errors = parser.parse(bufnr)
    assert.are.same({
      {
        message = 'Duplicate filename: a.txt',
        lnum = 1,
        end_lnum = 2,
        col = 0,
      },
    }, errors)
  end)

  it('ignores new dirs with empty name', function()
    vim.cmd.edit({ args = { 'canola-test:///foo/' } })
    local bufnr = vim.api.nvim_get_current_buf()
    set_lines(bufnr, {
      '/',
    })
    local diffs = parser.parse(bufnr)
    assert.are.same({}, diffs)
  end)

  it('parses a rename as a delete + new', function()
    local file = test_adapter.test_set('/foo/a.txt', 'file')
    vim.cmd.edit({ args = { 'canola-test:///foo/' } })
    local bufnr = vim.api.nvim_get_current_buf()
    set_lines(bufnr, {
      string.format('/%d b.txt', file[FIELD_ID]),
    })
    local diffs = parser.parse(bufnr)
    assert.are.same({
      { type = 'new', id = file[FIELD_ID], name = 'b.txt', entry_type = 'file' },
      { type = 'delete', id = file[FIELD_ID], name = 'a.txt' },
    }, diffs)
  end)

  it('detects a new trailing slash as a delete + create', function()
    local file = test_adapter.test_set('/foo', 'file')
    vim.cmd.edit({ args = { 'canola-test:///' } })
    local bufnr = vim.api.nvim_get_current_buf()
    set_lines(bufnr, {
      string.format('/%d foo/', file[FIELD_ID]),
    })
    local diffs = parser.parse(bufnr)
    assert.are.same({
      { type = 'new', name = 'foo', entry_type = 'directory' },
      { type = 'delete', id = file[FIELD_ID], name = 'foo' },
    }, diffs)
  end)

  it('detects renamed files that conflict', function()
    local afile = test_adapter.test_set('/foo/a.txt', 'file')
    local bfile = test_adapter.test_set('/foo/b.txt', 'file')
    vim.cmd.edit({ args = { 'canola-test:///foo/' } })
    local bufnr = vim.api.nvim_get_current_buf()
    set_lines(bufnr, {
      string.format('/%d a.txt', bfile[FIELD_ID]),
      string.format('/%d b.txt', afile[FIELD_ID]),
    })
    local diffs = parser.parse(bufnr)
    local first_two = { diffs[1], diffs[2] }
    local last_two = { diffs[3], diffs[4] }
    table.sort(first_two, function(a, b)
      return a.id < b.id
    end)
    table.sort(last_two, function(a, b)
      return a.id < b.id
    end)
    assert.are.same({
      { name = 'b.txt', type = 'new', id = afile[FIELD_ID], entry_type = 'file' },
      { name = 'a.txt', type = 'new', id = bfile[FIELD_ID], entry_type = 'file' },
    }, first_two)
    assert.are.same({
      { name = 'a.txt', type = 'delete', id = afile[FIELD_ID] },
      { name = 'b.txt', type = 'delete', id = bfile[FIELD_ID] },
    }, last_two)
  end)

  it('views link targets with trailing slashes as the same', function()
    local file = test_adapter.test_set('/foo/mydir', 'link')
    file[FIELD_META] = { link = 'dir/' }
    vim.cmd.edit({ args = { 'canola-test:///foo/' } })
    local bufnr = vim.api.nvim_get_current_buf()
    set_lines(bufnr, {
      string.format('/%d mydir/ -> dir/', file[FIELD_ID]),
    })
    local diffs = parser.parse(bufnr)
    assert.are.same({}, diffs)
  end)
end)
