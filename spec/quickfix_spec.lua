local TmpDir = require('spec.tmpdir')
local actions = require('canola.actions')
local test_util = require('spec.test_util')

describe('quickfix', function()
  local tmpdir

  before_each(function()
    tmpdir = TmpDir.new()
    vim.fn.setqflist({})
  end)

  after_each(function()
    if tmpdir then
      tmpdir:dispose()
      tmpdir = nil
    end
    test_util.reset_editor()
  end)

  it('prints the added cursor entry name', function()
    tmpdir:create({ 'a.txt', 'b.txt' })
    test_util.actions.open({ tmpdir.path })
    test_util.actions.focus('a.txt')

    local notify = stub(vim, 'notify')
    local ok, err = pcall(actions.add_to_qflist.callback)
    local qflist = vim.fn.getqflist()
    notify:revert()

    assert(ok, err)
    assert.equals('a.txt', qflist[1].text)
    assert.stub(notify).was_called_with('[canola] Added a.txt to quickfix')
  end)

  it('prints all added visual selection names', function()
    tmpdir:create({ 'a.txt', 'b.txt' })
    test_util.actions.open({ tmpdir.path })
    test_util.actions.focus('a.txt')
    vim.api.nvim_feedkeys('Vj', 'x', true)

    local notify = stub(vim, 'notify')
    local ok, err = pcall(actions.add_to_qflist.callback)
    local qflist = vim.fn.getqflist()
    notify:revert()

    assert(ok, err)
    assert.equals('a.txt', qflist[1].text)
    assert.equals('b.txt', qflist[2].text)
    assert.stub(notify).was_called_with('[canola] Added a.txt, b.txt to quickfix')
  end)
end)
