local M = {}

M.run = function(cmd, opts, callback)
  if not callback then
    callback = opts
    opts = {}
  end
  vim.system(
    cmd,
    vim.tbl_deep_extend('keep', opts, {
      text = true,
    }),
    vim.schedule_wrap(function(result)
      if result.code == 0 then
        callback(nil, vim.split(result.stdout or '', '\n'))
      else
        local err = result.stderr or 'Unknown error'
        if err == '' then
          err = 'Unknown error'
        end
        local cmd_str = type(cmd) == 'string' and cmd or table.concat(cmd, ' ')
        callback(string.format("Error running command '%s'\n%s", cmd_str, err))
      end
    end)
  )
end

return M
