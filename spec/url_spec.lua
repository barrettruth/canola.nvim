local canola = require('canola')
local util = require('canola.util')
describe('url', function()
  it('get_url_for_path', function()
    local cases = {
      { '', 'canola://' .. util.addslash(vim.fn.getcwd()) },
      {
        'term://~/oil.nvim//52953:/bin/sh',
        'canola://' .. vim.uv.os_homedir() .. '/oil.nvim/',
      },
      { '/foo/bar.txt', 'canola:///foo/', 'bar.txt' },
      { 'canola:///foo/bar.txt', 'canola:///foo/', 'bar.txt' },
      { 'canola:///', 'canola:///' },
    }
    for _, case in ipairs(cases) do
      local input, expected, expected_basename = unpack(case)
      local output, basename = canola.get_buffer_parent_url(input, true)
      assert.equals(expected, output, string.format('Parent url for path "%s" failed', input))
      assert.equals(
        expected_basename,
        basename,
        string.format('Basename for path "%s" failed', input)
      )
    end
  end)
end)
