local config = require('canola.config')

describe('config', function()
  it('uses defaults when vim.g.canola is nil', function()
    vim.g.canola = nil
    config.init()
    assert.is_false(config.delete_to_trash)
    assert.is_false(config.show_hidden)
    assert.equals('editable', config._constrain_cursor)
  end)

  it('applies vim.g.canola values', function()
    vim.g.canola = { delete_to_trash = true, show_hidden = true }
    config.init()
    assert.is_true(config.delete_to_trash)
    assert.is_true(config.show_hidden)
  end)

  it('resolves sort presets', function()
    vim.g.canola = { sort = 'modified' }
    config.init()
    assert.same({ { 'mtime', 'desc' }, { 'name', 'asc' } }, config._sort_spec)
  end)

  it('resolves sort config table', function()
    vim.g.canola = {
      sort = { by = { { 'size', 'desc' } }, natural = false, ignore_case = true },
    }
    config.init()
    assert.same({ { 'size', 'desc' } }, config._sort_spec)
    assert.is_false(config._natural_order)
    assert.is_true(config._case_insensitive)
  end)

  it('compiles hidden patterns', function()
    vim.g.canola = { hidden = { patterns = { '^%.', '%.bak$' }, always = {} } }
    config.init()
    assert.is_true(config._is_hidden_file('.gitignore', 0, {}))
    assert.is_true(config._is_hidden_file('test.bak', 0, {}))
    assert.is_false(config._is_hidden_file('readme.md', 0, {}))
  end)

  it('compiles disable preview patterns', function()
    vim.g.canola = { preview = { disable = { '%.iso$' } } }
    config.init()
    assert.is_true(config._disable_preview('big.iso'))
    assert.is_false(config._disable_preview('file.txt'))
  end)

  it('maps cursor true to editable', function()
    vim.g.canola = { cursor = true }
    config.init()
    assert.equals('editable', config._constrain_cursor)
  end)

  it('maps cursor false to false', function()
    vim.g.canola = { cursor = false }
    config.init()
    assert.is_false(config._constrain_cursor)
  end)

  it('maps preview.live to preview method', function()
    vim.g.canola = { preview = { live = true } }
    config.init()
    assert.equals('load', config._preview_method)
  end)

  it('inherits global border', function()
    vim.g.canola = { border = 'rounded' }
    config.init()
    assert.equals('rounded', config.confirmation.border)
    assert.equals('rounded', config.progress.border)
    assert.equals('rounded', config.float.border)
  end)

  it('does not override explicit sub-borders', function()
    vim.g.canola = { border = 'rounded', confirmation = { border = 'single' } }
    config.init()
    assert.equals('single', config.confirmation.border)
    assert.equals('rounded', config.float.border)
  end)

  it('merges user keymaps with defaults', function()
    vim.g.canola = { keymaps = { ['<C-x>'] = 'actions.close' } }
    config.init()
    assert.equals('actions.close', config.keymaps['<C-x>'])
    assert.equals('actions.select', config.keymaps['<CR>'])
  end)

  it('allows clearing all keymaps', function()
    vim.g.canola = { keymaps = { ['<CR>'] = false } }
    config.init()
    assert.is_false(config.keymaps['<CR>'])
  end)
end)
