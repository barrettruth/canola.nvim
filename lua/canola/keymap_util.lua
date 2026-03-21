local actions = require('canola.actions')
local config = require('canola.config')
local M = {}

---@param rhs string|table|fun()
---@return string|fun() rhs
---@return table opts
---@return string|nil mode
local function resolve(rhs)
  if type(rhs) == 'string' and vim.startswith(rhs, 'actions.') then
    local action_name = vim.split(rhs, '.', { plain = true })[2]
    local action = actions[action_name]
    if not action then
      vim.notify('[oil.nvim] Unknown action name: ' .. action_name, vim.log.levels.ERROR)
    end
    return resolve(action)
  elseif type(rhs) == 'table' then
    local opts = vim.deepcopy(rhs)
    -- We support passing in a `callback` key, or using the 1 index as the rhs of the keymap
    local callback, parent_opts = resolve(opts.callback or opts[1])

    -- Fall back to the parent desc, adding the opts as a string if it exists
    if parent_opts.desc and not opts.desc then
      if opts.opts then
        opts.desc =
          string.format('%s %s', parent_opts.desc, vim.inspect(opts.opts):gsub('%s+', ' '))
      else
        opts.desc = parent_opts.desc
      end
    end

    local mode = opts.mode
    if type(rhs.callback) == 'string' then
      local action_opts, action_mode
      callback, action_opts, action_mode = resolve(rhs.callback)
      opts = vim.tbl_extend('keep', opts, action_opts)
      mode = mode or action_mode
    end

    -- remove all the keys that we can't pass as options to `vim.keymap.set`
    opts.callback = nil
    opts.mode = nil
    opts[1] = nil
    opts.parameters = nil

    if opts.opts and type(callback) == 'function' then
      local callback_args = opts.opts
      opts.opts = nil
      local orig_callback = callback
      callback = function()
        ---@diagnostic disable-next-line: redundant-parameter
        orig_callback(callback_args)
      end
    end

    return callback, opts, mode
  else
    return rhs, {}
  end
end

---@param keymaps table<string, string|table|fun()>
---@param bufnr integer
M.set_keymaps = function(keymaps, bufnr)
  for k, v in pairs(keymaps) do
    local rhs, opts, mode = resolve(v)
    if rhs then
      vim.keymap.set(mode or '', k, rhs, vim.tbl_extend('keep', { buffer = bufnr }, opts))
    end
  end
end

return M
