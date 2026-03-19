local config = require('canola.config')

describe('config', function()
  it('uses defaults when vim.g.canola is nil', function()
    vim.g.canola = nil
    config.init()
    assert.is_false(config.delete_to_trash)
    assert.equals(2000, config.cleanup_delay_ms)
  end)

  it('applies vim.g.canola values', function()
    vim.g.canola = { delete_to_trash = true, cleanup_delay_ms = 5000 }
    config.init()
    assert.is_true(config.delete_to_trash)
    assert.equals(5000, config.cleanup_delay_ms)
  end)
end)
