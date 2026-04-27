local config = require('oil.config')
local migrate = require('oil.migrate')
local test_util = require('spec.test_util')

local function current_buffer_text()
  return table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, true), '\n')
end

local function joined(lines)
  return table.concat(lines, '\n')
end

describe('migrate', function()
  before_each(function()
    test_util.reset_editor()
    config.setup()
  end)

  after_each(function()
    test_util.reset_editor()
  end)

  local function generate(opts)
    config.setup(opts)
    return migrate.generate()
  end

  it('moves delete_to_trash to canola-collection config', function()
    local out, _, _, adapters = generate({ delete_to_trash = true })
    assert.is_nil(out.delete)
    assert.is_true(
      vim.tbl_contains(
        adapters,
        'delete_to_trash -> vim.g.canola_trash = {} (requires canola-collection)'
      )
    )
  end)

  it('migrates sort flags even when the sort preset itself stays the same', function()
    local out = generate({
      view_options = {
        natural_order = true,
        case_insensitive = true,
      },
    })
    assert.same({
      by = {
        { 'type', 'asc' },
        { 'name', 'asc' },
      },
      natural = true,
      ignore_case = true,
    }, out.sort)
  end)

  it('migrates float.title when disabled', function()
    local out = generate({
      float = { title = false },
    })
    assert.same({ title = false }, out.float)
  end)

  it('disables canola default keymaps when oil defaults are disabled', function()
    local out, _, removed = generate({
      use_default_keymaps = false,
      keymaps = {
        ['<CR>'] = 'actions.select',
        q = 'actions.close',
      },
    })
    assert.same('actions.select', out.keymaps['<CR>'])
    assert.same('actions.close', out.keymaps.q)
    assert.is_false(out.keymaps['g?'])
    assert.is_false(out.keymaps['<C-p>'])
    assert.is_false(out.keymaps.gy)
    assert.is_false(vim.tbl_contains(removed, 'use_default_keymaps'))
  end)

  it('reports lossy and removed settings instead of dropping them silently', function()
    local out, _, _, _, manual = generate({
      view_options = { show_hidden_when_empty = true },
      constrain_cursor = 'name',
      preview_win = { preview_method = 'scratch' },
      ssh = { border = 'double' },
      keymaps_help = { border = 'double' },
    })
    local text = joined(manual)
    assert.is_true(out.cursor)
    assert.matches('show_hidden_when_empty', text)
    assert.matches('constrain_cursor = "name"', text)
    assert.matches('preview_win%.preview_method = "scratch"', text)
    assert.matches('ssh%.border', text)
    assert.matches('keymaps_help%.border', text)
  end)

  it('does not widen oil confirmation behavior when there is no exact canola equivalent', function()
    local out, _, _, _, manual = generate({
      skip_confirm_for_simple_edits = true,
      skip_confirm_for_delete = true,
    })
    local text = joined(manual)
    assert.is_nil(out.confirm)
    assert.matches('skip_confirm_for_simple_edits', text)
    assert.matches('skip_confirm_for_delete', text)
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

  it('prints manual review items for lossy migrations', function()
    config.setup({
      skip_confirm_for_simple_edits = true,
      constrain_cursor = 'name',
      preview_win = { preview_method = 'scratch' },
    })
    migrate.print()
    local text = current_buffer_text()
    assert.matches('## Manual Review', text)
    assert.matches('skip_confirm_for_simple_edits', text)
    assert.matches('constrain_cursor = "name"', text)
    assert.matches('preview_win%.preview_method = "scratch"', text)
  end)
end)
