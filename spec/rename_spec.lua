local constants = require('canola.constants')
local parser = require('canola.mutator.parser')
local rename = require('canola.rename')
local test_adapter = require('canola.adapters.test')
local test_util = require('spec.test_util')
local util = require('canola.util')

local FIELD_ID = constants.FIELD_ID
local FIELD_META = constants.FIELD_META

local function open_foo()
  test_util.actions.open({ 'canola-test:///foo/' })
end

local function lines()
  return vim.api.nvim_buf_get_lines(0, 0, -1, true)
end

local function line_text()
  return table.concat(lines(), '\n')
end

local function assert_contains(text, needle)
  assert.truthy(text:find(needle, 1, true))
end

local function assert_not_contains(text, needle)
  assert.falsy(text:find(needle, 1, true))
end

local function find_line(needle)
  for i, line in ipairs(lines()) do
    if line:find(needle, 1, true) then
      return i, line
    end
  end
end

describe('rename transform', function()
  after_each(function()
    test_util.reset_editor()
  end)

  it('renames files and links by default', function()
    local file = test_adapter.test_set('/foo/alpha file.txt', 'file')
    test_adapter.test_set('/foo/delta directory', 'directory')
    local link = test_adapter.test_set('/foo/link item', 'link')
    link[FIELD_META] = { link = 'target file.txt' }
    open_foo()
    local seen = {}

    local ok, err = rename.transform(function(name, entry)
      seen[entry.id] = name
      return name:gsub(' ', '-')
    end)

    assert.is_true(ok)
    assert.is_nil(err)
    assert.equals('alpha file.txt', seen[file[FIELD_ID]])
    assert.equals('link item', seen[link[FIELD_ID]])
    local text = line_text()
    assert_contains(text, 'alpha-file.txt')
    assert_contains(text, 'delta directory/')
    assert_contains(text, 'link-item -> target file.txt')
    assert_not_contains(text, 'target-file.txt')
  end)

  it('renames directories when opted in', function()
    test_adapter.test_set('/foo/delta directory', 'directory')
    open_foo()

    local ok, err = rename.transform(function(name)
      return name:gsub(' ', '-')
    end, { types = { 'directory' } })

    assert.is_true(ok)
    assert.is_nil(err)
    assert_contains(line_text(), 'delta-directory/')
  end)

  it('leaves the buffer unchanged on duplicate names', function()
    test_adapter.test_set('/foo/alpha file.txt', 'file')
    test_adapter.test_set('/foo/bravo file.txt', 'file')
    open_foo()
    local before = lines()

    local ok, err = rename.transform(function()
      return 'same.txt'
    end)

    assert.is_false(ok)
    assert.matches('Duplicate filename: same%.txt', err)
    assert.are.same(before, lines())
  end)

  it('uses the current parsed buffer name', function()
    test_adapter.test_set('/foo/alpha file.txt', 'file')
    open_foo()
    local bufnr = vim.api.nvim_get_current_buf()
    local adapter = assert(util.get_adapter(bufnr, true))
    local lnum, line = find_line('alpha file.txt')
    assert.truthy(lnum)
    local result = assert(parser.parse_line(adapter, line, nil))
    local range = result.ranges.name
    local edited = line:sub(1, range[1]) .. 'alpha edited.txt' .. line:sub(range[2] + 2)
    vim.api.nvim_buf_set_lines(bufnr, lnum - 1, lnum, true, { edited })
    local observed

    local ok, err = rename.transform(function(name)
      observed = name
      return name:gsub(' ', '-')
    end)

    assert.is_true(ok)
    assert.is_nil(err)
    assert.equals('alpha edited.txt', observed)
    assert_contains(line_text(), 'alpha-edited.txt')
  end)
end)
