local TmpDir = require('spec.tmpdir')
local test_util = require('spec.test_util')

describe('freedesktop', function()
  local tmpdir
  local tmphome
  local home = vim.env.XDG_DATA_HOME
  before_each(function()
    require('oil.config').delete_to_trash = true
    tmpdir = TmpDir.new()
    tmphome = TmpDir.new()
    package.loaded['oil.adapters.trash'] = require('oil.adapters.trash.freedesktop')
    vim.env.XDG_DATA_HOME = tmphome.path
  end)
  after_each(function()
    vim.env.XDG_DATA_HOME = home
    if tmpdir then
      tmpdir:dispose()
    end
    if tmphome then
      tmphome:dispose()
    end
    test_util.reset_editor()
    package.loaded['oil.adapters.trash'] = nil
  end)

  it('files can be moved to the trash', function()
    tmpdir:create({ 'a.txt', 'foo/b.txt' })
    test_util.actions.open({ tmpdir.path })
    test_util.actions.focus('a.txt')
    vim.api.nvim_feedkeys('dd', 'x', true)
    test_util.actions.open({ '--trash', tmpdir.path })
    vim.api.nvim_feedkeys('p', 'x', true)
    test_util.actions.save()
    tmpdir:assert_not_exists('a.txt')
    tmpdir:assert_exists('foo/b.txt')
    test_util.actions.reload()
    assert.are.same({ 'a.txt' }, test_util.parse_entries(0))
  end)

  it('deleting a file moves it to trash', function()
    tmpdir:create({ 'a.txt', 'foo/b.txt' })
    test_util.actions.open({ tmpdir.path })
    test_util.actions.focus('a.txt')
    vim.api.nvim_feedkeys('dd', 'x', true)
    test_util.actions.save()
    tmpdir:assert_not_exists('a.txt')
    tmpdir:assert_exists('foo/b.txt')
    test_util.actions.open({ '--trash', tmpdir.path })
    assert.are.same({ 'a.txt' }, test_util.parse_entries(0))
  end)

  it('deleting a directory moves it to trash', function()
    tmpdir:create({ 'a.txt', 'foo/b.txt' })
    test_util.actions.open({ tmpdir.path })
    test_util.actions.focus('foo/')
    vim.api.nvim_feedkeys('dd', 'x', true)
    test_util.actions.save()
    tmpdir:assert_not_exists('foo')
    tmpdir:assert_exists('a.txt')
    test_util.actions.open({ '--trash', tmpdir.path })
    assert.are.same({ 'foo/' }, test_util.parse_entries(0))
  end)

  it('deleting a file from trash deletes it permanently', function()
    tmpdir:create({ 'a.txt' })
    test_util.actions.open({ tmpdir.path })
    test_util.actions.focus('a.txt')
    vim.api.nvim_feedkeys('dd', 'x', true)
    test_util.actions.save()
    test_util.actions.open({ '--trash', tmpdir.path })
    test_util.actions.focus('a.txt')
    vim.api.nvim_feedkeys('dd', 'x', true)
    test_util.actions.save()
    test_util.actions.reload()
    tmpdir:assert_not_exists('a.txt')
    assert.are.same({}, test_util.parse_entries(0))
  end)

  it('cannot create files in the trash', function()
    tmpdir:create({ 'a.txt' })
    test_util.actions.open({ tmpdir.path })
    test_util.actions.focus('a.txt')
    vim.api.nvim_feedkeys('dd', 'x', true)
    test_util.actions.save()
    test_util.actions.open({ '--trash', tmpdir.path })
    vim.api.nvim_feedkeys('onew_file.txt', 'x', true)
    test_util.actions.save()
    test_util.actions.reload()
    assert.are.same({ 'a.txt' }, test_util.parse_entries(0))
  end)

  it('cannot rename files in the trash', function()
    tmpdir:create({ 'a.txt' })
    test_util.actions.open({ tmpdir.path })
    test_util.actions.focus('a.txt')
    vim.api.nvim_feedkeys('dd', 'x', true)
    test_util.actions.save()
    test_util.actions.open({ '--trash', tmpdir.path })
    vim.api.nvim_feedkeys('0facwnew_name', 'x', true)
    test_util.actions.save()
    test_util.actions.reload()
    assert.are.same({ 'a.txt' }, test_util.parse_entries(0))
  end)

  it('cannot copy files in the trash', function()
    tmpdir:create({ 'a.txt' })
    test_util.actions.open({ tmpdir.path })
    test_util.actions.focus('a.txt')
    vim.api.nvim_feedkeys('dd', 'x', true)
    test_util.actions.save()
    test_util.actions.open({ '--trash', tmpdir.path })
    vim.api.nvim_feedkeys('yypp', 'x', true)
    test_util.actions.save()
    test_util.actions.reload()
    assert.are.same({ 'a.txt' }, test_util.parse_entries(0))
  end)

  it('can restore files from trash', function()
    tmpdir:create({ 'a.txt' })
    test_util.actions.open({ tmpdir.path })
    test_util.actions.focus('a.txt')
    vim.api.nvim_feedkeys('dd', 'x', true)
    test_util.actions.save()
    test_util.actions.open({ '--trash', tmpdir.path })
    vim.api.nvim_feedkeys('dd', 'x', true)
    test_util.actions.open({ tmpdir.path })
    vim.api.nvim_feedkeys('p', 'x', true)
    test_util.actions.save()
    test_util.actions.reload()
    assert.are.same({ 'a.txt' }, test_util.parse_entries(0))
    tmpdir:assert_fs({
      ['a.txt'] = 'a.txt',
    })
  end)

  it('can have multiple files with the same name in trash', function()
    tmpdir:create({ 'a.txt' })
    test_util.actions.open({ tmpdir.path })
    vim.api.nvim_feedkeys('dd', 'x', true)
    test_util.actions.save()
    tmpdir:create({ 'a.txt' })
    test_util.actions.reload()
    vim.api.nvim_feedkeys('dd', 'x', true)
    test_util.actions.save()
    test_util.actions.open({ '--trash', tmpdir.path })
    assert.are.same({ 'a.txt', 'a.txt' }, test_util.parse_entries(0))
  end)
end)

local function temporary_directory()
  local root = vim.fn.tempname()
  vim.fn.mkdir(root, 'p')
  return root
end

describe('trash adapters', function()
  local root
  local data_home
  local homedir

  before_each(function()
    root = temporary_directory()
    data_home = vim.env.XDG_DATA_HOME
    vim.env.XDG_DATA_HOME = root
    homedir = stub(vim.uv, 'os_homedir', function()
      return root
    end)
  end)

  after_each(function()
    homedir:revert()
    vim.env.XDG_DATA_HOME = data_home
    vim.fn.delete(root, 'rf')
  end)

  it('writes freedesktop trash metadata before moving a file', function()
    local source = root .. '/source.txt'
    vim.fn.writefile({ 'contents' }, source)
    local err =
      test_util.await(require('oil.adapters.trash.freedesktop').delete_to_trash, 2, source)
    assert.is_nil(err)
    assert.equal(0, vim.fn.filereadable(source))
    local info_files = vim.fn.glob(root .. '/Trash/info/*.trashinfo', false, true)
    assert.equal(1, #info_files)
    local contents = vim.fn.readfile(info_files[1])
    assert.equal('[Trash Info]', contents[1])
    assert.equal('Path=' .. source, contents[2])
    assert.matches('^DeletionDate=', contents[3])
  end)

  it('returns an error for invalid mac trash paths', function()
    local mac = require('oil.adapters.trash.mac')
    for _, action_type in ipairs({ 'move', 'copy' }) do
      for _, urls in ipairs({
        { 'invalid', 'oil-trash:///file' },
        { 'oil:///file', 'invalid' },
      }) do
        local err = test_util.await(mac.perform_action, 2, {
          type = action_type,
          entry_type = 'file',
          src_url = urls[1],
          dest_url = urls[2],
        })
        assert.equal('Invalid source or destination URL', err)
      end
    end
  end)
end)
