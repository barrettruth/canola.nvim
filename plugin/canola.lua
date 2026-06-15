if vim.g.loaded_canola then
  return
end
vim.g.loaded_canola = 1

require('canola').init()
