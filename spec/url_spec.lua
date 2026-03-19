local canola = require('canola')
local util = require('canola.util')
describe('url', function()
  it('get_url_for_path', function()
    local cases = {
      { '', 'canola://' .. util.addslash(vim.fn.getcwd()) },
      {
        'term://~/oil.nvim//52953:/bin/sh',
        'canola://' .. vim.loop.os_homedir() .. '/oil.nvim/',
      },
      { '/foo/bar.txt', 'canola:///foo/', 'bar.txt' },
      { 'canola:///foo/bar.txt', 'canola:///foo/', 'bar.txt' },
      { 'canola:///', 'canola:///' },
      {
        'canola-ssh://user@hostname:8888//bar.txt',
        'canola-ssh://user@hostname:8888//',
        'bar.txt',
      },
      { 'canola-ssh://user@hostname:8888//', 'canola-ssh://user@hostname:8888//' },
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
