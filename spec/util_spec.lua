local util = require('oil.util')
describe('util', function()
  it('url_escape', function()
    local cases = {
      { 'foobar', 'foobar' },
      { 'foo bar', 'foo%20bar' },
      { '/foo/bar', '%2Ffoo%2Fbar' },
    }
    for _, case in ipairs(cases) do
      local input, expected = unpack(case)
      local output = util.url_escape(input)
      assert.equals(expected, output)
    end
  end)

  it('url_unescape', function()
    local cases = {
      { 'foobar', 'foobar' },
      { 'foo%20bar', 'foo bar' },
      { '%2Ffoo%2Fbar', '/foo/bar' },
      { 'foo%%bar', 'foo%%bar' },
    }
    for _, case in ipairs(cases) do
      local input, expected = unpack(case)
      local output = util.url_unescape(input)
      assert.equals(expected, output)
    end
  end)

  it('does not delete a renamed buffer when the old name resolves to the same buffer', function()
    local bufnr = vim.api.nvim_create_buf(false, false)
    vim.api.nvim_buf_set_name(bufnr, 'oil-test:///foo')

    local replaced = util.rename_buffer(bufnr, 'oil-test:///foo/')

    assert.is_false(replaced)
    assert.is_true(vim.api.nvim_buf_is_valid(bufnr))
    assert.equals('oil-test:///foo/', vim.api.nvim_buf_get_name(bufnr))
  end)
end)
