local config = require('canola.config')

describe('config', function()
  after_each(function()
    vim.g.canola = nil
  end)

  it('falls back to vim.g.canola when setup() is called with no args', function()
    vim.g.canola = { delete_to_trash = true, cleanup_delay_ms = 5000 }
    config.setup()
    assert.is_true(config.delete_to_trash)
    assert.equals(5000, config.cleanup_delay_ms)
  end)

  it('uses defaults when neither opts nor vim.g.canola is set', function()
    vim.g.canola = nil
    config.setup()
    assert.is_false(config.delete_to_trash)
    assert.equals(2000, config.cleanup_delay_ms)
  end)

  it('prefers explicit opts over vim.g.canola', function()
    vim.g.canola = { delete_to_trash = true }
    config.setup({ delete_to_trash = false })
    assert.is_false(config.delete_to_trash)
  end)
end)
