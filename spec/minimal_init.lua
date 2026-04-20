vim.cmd([[set runtimepath=$VIMRUNTIME]])
vim.opt.runtimepath:append('.')
vim.opt.packpath = {}
vim.o.swapfile = false
vim.cmd('filetype on')
vim.fn.mkdir(vim.fn.stdpath('cache'), 'p')
vim.fn.mkdir(vim.fn.stdpath('data'), 'p')
vim.fn.mkdir(vim.fn.stdpath('state'), 'p')
local test_util = require('spec.test_util')
test_util.reset_editor()
