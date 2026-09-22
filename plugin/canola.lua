if vim.g.loaded_canola then
  return
end
vim.g.loaded_canola = 1

require('canola.migration').warn_if_github_source()
require('canola').init()
