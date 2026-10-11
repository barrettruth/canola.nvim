local loading = require('canola.loading')

describe('loading timers', function()
  local bufnr
  local new_timer

  before_each(function()
    bufnr = vim.api.nvim_create_buf(false, true)
  end)

  after_each(function()
    loading.set_loading(bufnr, false)
    if new_timer then
      new_timer:revert()
      new_timer = nil
    end
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end)

  it('does not mark a buffer as loading after allocation failure', function()
    new_timer = stub(vim.uv, 'new_timer', function()
      return nil, 'Cannot allocate a timer'
    end)
    loading.set_loading(bufnr, true)
    assert.is_false(loading.is_loading(bufnr))
  end)

  it('closes a timer after start failure', function()
    local close = spy.new(function() end)
    new_timer = stub(vim.uv, 'new_timer', function()
      return {
        start = function()
          return nil, 'Cannot start a timer'
        end,
        close = close,
      }
    end)
    loading.set_loading(bufnr, true)
    assert.is_false(loading.is_loading(bufnr))
    assert.spy(close).was_called(1)
  end)

  it('closes a successful timer when loading stops', function()
    loading.set_loading(bufnr, true)
    assert.is_true(loading.is_loading(bufnr))
    loading.set_loading(bufnr, false)
    assert.is_false(loading.is_loading(bufnr))
  end)
end)
