local config = require('oil.config')
local migrate = require('oil.migrate')
local test_util = require('spec.test_util')

local function current_buffer_text()
  return table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, true), '\n')
end

describe('migrate', function()
  before_each(function()
    test_util.reset_editor()
    config.setup()
  end)

  it('moves delete_to_trash to canola-collection config', function()
    config.setup({ delete_to_trash = true })
    local out, _, _, adapters = migrate.generate()
    assert.is_nil(out.delete)
    assert.is_true(
      vim.tbl_contains(
        adapters,
        'delete_to_trash -> vim.g.canola_trash = {} (requires canola-collection)'
      )
    )
  end)

  it('prints canola-git as an opt-in collection config', function()
    config.setup({
      view_options = {
        is_hidden_file = function()
          return false
        end,
      },
      git = {
        add = function()
          return true
        end,
        mv = function()
          return true
        end,
        rm = function()
          return true
        end,
      },
    })
    migrate.print()
    local text = current_buffer_text()
    assert.matches('vim%.g%.canola_git = %{%}', text)
    assert.is_not_nil(text:match('git_status'))
    assert.is_nil(text:match('No config needed'))
  end)
end)
