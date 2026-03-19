local fs = require('canola.fs')

local M = {}

---@param path string
---@return string|nil
M.get_root = function(path)
  local git_dir = vim.fs.find('.git', { upward = true, path = path })[1]
  if git_dir then
    return vim.fs.dirname(git_dir)
  else
    return nil
  end
end

---@param path string
---@param cb fun(err: nil|string)
M.add = function(path, cb)
  local root = M.get_root(path)
  if not root then
    return cb()
  end

  vim.system(
    { 'git', 'add', path },
    { cwd = root, text = true },
    vim.schedule_wrap(function(result)
      if result.code ~= 0 then
        cb('Error in git add: ' .. (result.stderr or ''))
      else
        cb()
      end
    end)
  )
end

---@param path string
---@param cb fun(err: nil|string)
M.rm = function(path, cb)
  local root = M.get_root(path)
  if not root then
    return cb()
  end

  vim.system(
    { 'git', 'rm', '-r', path },
    { cwd = root, text = true },
    vim.schedule_wrap(function(result)
      if result.code ~= 0 then
        local stderr = vim.trim(result.stderr or '')
        if stderr:match("^fatal: pathspec '.*' did not match any files$") then
          cb()
        else
          cb('Error in git rm: ' .. stderr)
        end
      else
        cb()
      end
    end)
  )
end

---@param entry_type canola.EntryType
---@param src_path string
---@param dest_path string
---@param cb fun(err: nil|string)
M.mv = function(entry_type, src_path, dest_path, cb)
  local src_git = M.get_root(src_path)
  if not src_git or src_git ~= M.get_root(dest_path) then
    fs.recursive_move(entry_type, src_path, dest_path, cb)
    return
  end

  vim.system(
    { 'git', 'mv', src_path, dest_path },
    { cwd = src_git, text = true },
    vim.schedule_wrap(function(result)
      if result.code ~= 0 then
        local stderr = vim.trim(result.stderr or '')
        if
          stderr:match('^fatal: not under version control')
          or stderr:match('^fatal: source directory is empty')
        then
          fs.recursive_move(entry_type, src_path, dest_path, cb)
        else
          cb('Error in git mv: ' .. stderr)
        end
      else
        cb()
      end
    end)
  )
end

return M
