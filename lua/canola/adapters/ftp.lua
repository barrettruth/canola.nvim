local config = require('canola.config')
local constants = require('canola.constants')
local files = require('canola.adapters.files')
local fs = require('canola.fs')
local loading = require('canola.loading')
local pathutil = require('canola.pathutil')
local permissions = require('canola.adapters.files.permissions')
local shell = require('canola.shell')
local util = require('canola.util')
local M = {}

local FIELD_TYPE = constants.FIELD_TYPE
local FIELD_META = constants.FIELD_META

---@class (exact) oil.ftpUrl
---@field scheme string
---@field host string
---@field user nil|string
---@field password nil|string
---@field port nil|integer
---@field path string

---@param oil_url string
---@return oil.ftpUrl
M.parse_url = function(oil_url)
  local scheme, url = util.parse_url(oil_url)
  assert(scheme and url, string.format("Malformed input url '%s'", oil_url))
  local ret = { scheme = scheme }
  local userinfo, rem = url:match('^([^@%s]+)@(.*)$')
  if userinfo then
    local user, pass = userinfo:match('^([^:]+):(.+)$')
    if user then
      ret.user = user
      ret.password = pass
    else
      ret.user = userinfo
    end
    url = rem
  end
  local host, port, path = url:match('^([^:]+):(%d+)/(.*)$')
  if host then
    ret.host = host
    ret.port = tonumber(port)
    ret.path = path
  else
    host, path = url:match('^([^/]+)/(.*)$')
    ret.host = host
    ret.path = path
  end
  if not ret.host or not ret.path then
    error(string.format('Malformed FTP url: %s', oil_url))
  end
  ---@cast ret oil.ftpUrl
  return ret
end

---@param url oil.ftpUrl
---@return string
local function url_to_str(url)
  local pieces = { url.scheme }
  if url.user then
    table.insert(pieces, url.user)
    if url.password then
      table.insert(pieces, ':')
      table.insert(pieces, url.password)
    end
    table.insert(pieces, '@')
  end
  table.insert(pieces, url.host)
  if url.port then
    table.insert(pieces, string.format(':%d', url.port))
  end
  table.insert(pieces, '/')
  table.insert(pieces, url.path)
  return table.concat(pieces, '')
end

---@param s string
---@return string
local function url_encode_path(s)
  return (
    s:gsub('[^A-Za-z0-9%-._~:/]', function(c)
      return string.format('%%%02X', c:byte())
    end)
  )
end

---@param url oil.ftpUrl
---@return string
local function curl_ftp_url(url)
  local pieces = { 'ftp://' }
  if url.user then
    table.insert(pieces, url.user)
    if url.password then
      table.insert(pieces, ':')
      table.insert(pieces, url.password)
    end
    table.insert(pieces, '@')
  end
  table.insert(pieces, url.host)
  if url.port then
    table.insert(pieces, string.format(':%d', url.port))
  end
  table.insert(pieces, '/')
  table.insert(pieces, url_encode_path(url.path))
  return table.concat(pieces, '')
end

---@param host string
---@return string[]
local function resolved_curl_args(host)
  local extra = vim.deepcopy(config.extra_curl_args)
  local host_cfg = config.ftp_hosts[host]
  if host_cfg and host_cfg.extra_curl_args then
    vim.list_extend(extra, host_cfg.extra_curl_args)
  end
  return extra
end

---@param url oil.ftpUrl
---@param py_lines string[]
---@param cb fun(err: nil|string)
local function ftpcmd(url, py_lines, cb)
  local lines = {}
  local use_tls = url.scheme == 'canola-ftps://'
  if use_tls then
    local curl_args = resolved_curl_args(url.host)
    local insecure = vim.tbl_contains(curl_args, '--insecure') or vim.tbl_contains(curl_args, '-k')
    table.insert(lines, 'import ftplib, ssl')
    table.insert(lines, 'ctx = ssl.create_default_context()')
    if insecure then
      table.insert(lines, 'ctx.check_hostname = False')
      table.insert(lines, 'ctx.verify_mode = ssl.CERT_NONE')
    end
    table.insert(lines, 'ftp = ftplib.FTP_TLS(context=ctx)')
  else
    table.insert(lines, 'import ftplib')
    table.insert(lines, 'ftp = ftplib.FTP()')
  end
  table.insert(lines, string.format('ftp.connect(%q, %d)', url.host, url.port or 21))
  if use_tls then
    table.insert(lines, 'ftp.auth()')
  end
  local user = url.user or 'anonymous'
  local password = url.password or ''
  table.insert(lines, string.format('ftp.login(%q, %q)', user, password))
  if use_tls then
    table.insert(lines, 'ftp.prot_p()')
  end
  for _, line in ipairs(py_lines) do
    table.insert(lines, line)
  end
  table.insert(lines, 'ftp.quit()')
  local script = table.concat(lines, '\n')
  shell.run({ 'python3', '-c', script }, function(err)
    if err then
      cb(err:match('ftplib%.[^:]+: (.+)$') or err:match('[^\n]+$') or err)
    else
      cb(nil)
    end
  end)
end

---@param url oil.ftpUrl
---@return string[]
local function ssl_args(url)
  if url.scheme == 'canola-ftps://' then
    return { '--ssl-reqd' }
  end
  return {}
end

---@param url oil.ftpUrl
---@param extra_args string[]
---@param opts table|fun(err: nil|string, output: nil|string[])
---@param cb? fun(err: nil|string, output: nil|string[])
local function curl(url, extra_args, opts, cb)
  if not cb then
    cb = opts --[[@as fun(err: nil|string, output: nil|string[])]]
    opts = {}
  end
  local cmd = { 'curl', '-sS', '--netrc-optional' }
  vim.list_extend(cmd, ssl_args(url))
  vim.list_extend(cmd, resolved_curl_args(url.host))
  vim.list_extend(cmd, extra_args)
  shell.run(cmd, opts, cb)
end

---@param url oil.ftpUrl
---@return string
local function ftp_abs_path(url)
  return '/' .. url.path
end

---@param url1 oil.ftpUrl
---@param url2 oil.ftpUrl
---@return boolean
local function url_hosts_equal(url1, url2)
  return url1.host == url2.host and url1.port == url2.port and url1.user == url2.user
end

local month_map = {
  Jan = 1,
  Feb = 2,
  Mar = 3,
  Apr = 4,
  May = 5,
  Jun = 6,
  Jul = 7,
  Aug = 8,
  Sep = 9,
  Oct = 10,
  Nov = 11,
  Dec = 12,
}

---@param line string
---@return nil|string, nil|string, nil|table
local function parse_unix_list_line(line)
  local perms, user, group, size, month, day, timeoryear, name =
    line:match('^([dlrwxstST%-]+)%s+%d+%s+(%S+)%s+(%S+)%s+(%d+)%s+(%a+)%s+(%d+)%s+(%S+)%s+(.+)$')
  if not perms then
    return nil
  end
  local entry_type
  local first = perms:sub(1, 1)
  if first == 'd' then
    entry_type = 'directory'
  elseif first == 'l' then
    entry_type = 'link'
  else
    entry_type = 'file'
  end
  local link_target
  if entry_type == 'link' then
    local link_name, target = name:match('^(.+) %-> (.+)$')
    if link_name then
      name = link_name
      link_target = target
    end
  end
  local mtime
  local mon = month_map[month]
  if mon then
    local hour, min = timeoryear:match('^(%d+):(%d+)$')
    if hour then
      local now = os.time()
      local t = os.date('*t', now)
      ---@cast t osdate
      mtime = os.time({
        year = t.year,
        month = mon,
        day = tonumber(day) or 0,
        hour = tonumber(hour) or 0,
        min = tonumber(min) or 0,
        sec = 0,
      })
      if mtime > now + 86400 then
        mtime = os.time({
          year = t.year - 1,
          month = mon,
          day = tonumber(day) or 0,
          hour = tonumber(hour) or 0,
          min = tonumber(min) or 0,
          sec = 0,
        })
      end
    else
      local year = tonumber(timeoryear)
      if year then
        mtime = os.time({
          year = year,
          month = mon,
          day = tonumber(day) or 0,
          hour = 0,
          min = 0,
          sec = 0,
        })
      end
    end
  end
  local mode = permissions.parse(perms:sub(2))
  local meta = { user = user, group = group, size = tonumber(size), mtime = mtime, mode = mode }
  if link_target then
    meta.link = link_target
  end
  return name, entry_type, meta
end

---@param line string
---@return nil|string, nil|string, nil|table
local function parse_iis_list_line(line)
  local size_or_dir, name = line:match('^%d+%-%d+%-%d+%s+%d+:%d+%a+%s+(%S+)%s+(.+)$')
  if not size_or_dir then
    return nil
  end
  local entry_type, size
  if size_or_dir == '<DIR>' then
    entry_type = 'directory'
  else
    entry_type = 'file'
    size = tonumber(size_or_dir)
  end
  local meta = { size = size }
  return name, entry_type, meta
end

local ftp_columns = {}
ftp_columns.size = {
  render = function(entry, conf)
    local meta = entry[FIELD_META]
    if not meta or not meta.size then
      return ''
    end
    if entry[FIELD_TYPE] == 'directory' then
      return ''
    end
    if meta.size >= 1e9 then
      return string.format('%.1fG', meta.size / 1e9)
    elseif meta.size >= 1e6 then
      return string.format('%.1fM', meta.size / 1e6)
    elseif meta.size >= 1e3 then
      return string.format('%.1fk', meta.size / 1e3)
    else
      return string.format('%d', meta.size)
    end
  end,

  parse = function(line, conf)
    return line:match('^(%d+%S*)%s+(.*)$')
  end,

  get_sort_value = function(entry)
    local meta = entry[FIELD_META]
    if meta and meta.size then
      return meta.size
    else
      return 0
    end
  end,
}

ftp_columns.mtime = {
  render = function(entry, conf)
    local meta = entry[FIELD_META]
    if not meta or not meta.mtime then
      return ''
    end
    return os.date('%Y-%m-%d %H:%M', meta.mtime)
  end,

  parse = function(line, conf)
    return line:match('^(%d+%-%d+%-%d+%s%d+:%d+)%s+(.*)$')
  end,

  get_sort_value = function(entry)
    local meta = entry[FIELD_META]
    if meta and meta.mtime then
      return meta.mtime
    else
      return 0
    end
  end,
}

ftp_columns.permissions = {
  render = function(entry, conf)
    local meta = entry[FIELD_META]
    if not meta or not meta.mode then
      return
    end
    return permissions.mode_to_str(meta.mode)
  end,

  parse = function(line, conf)
    return permissions.parse(line)
  end,

  compare = function(entry, parsed_value)
    local meta = entry[FIELD_META]
    if parsed_value and meta and meta.mode then
      local mask = bit.lshift(1, 12) - 1
      local old_mode = bit.band(meta.mode, mask)
      if parsed_value ~= old_mode then
        return true
      end
    end
    return false
  end,

  render_action = function(action)
    return string.format('CHMOD %s %s', permissions.mode_to_octal_str(action.value), action.url)
  end,

  perform_action = function(action, callback)
    local res = M.parse_url(action.url)
    local octal = permissions.mode_to_octal_str(action.value)
    local ftp_path = ftp_abs_path(res)
    ftpcmd(
      res,
      { string.format('ftp.voidcmd(%q)', 'SITE CHMOD ' .. octal .. ' ' .. ftp_path) },
      callback
    )
  end,
}

ftp_columns.owner = {
  render = function(entry, conf)
    local meta = entry[FIELD_META]
    if not meta or not meta.user then
      return ''
    end
    return meta.user
  end,

  parse = function(line, conf)
    return line:match('^(%S+)%s+(.*)$')
  end,
}

ftp_columns.group = {
  render = function(entry, conf)
    local meta = entry[FIELD_META]
    if not meta or not meta.group then
      return ''
    end
    return meta.group
  end,

  parse = function(line, conf)
    return line:match('^(%S+)%s+(.*)$')
  end,
}

---@param name string
---@return nil|canola.ColumnDefinition
M.get_column = function(name)
  return ftp_columns[name]
end

---@param bufname string
---@return string
M.get_parent = function(bufname)
  local res = M.parse_url(bufname)
  res.path = pathutil.parent(res.path)
  return url_to_str(res)
end

---@param url string
---@param callback fun(url: string)
M.normalize_url = function(url, callback)
  local res = M.parse_url(url)
  callback(url_to_str(res))
end

---@param url string
---@param column_defs string[]
---@param callback fun(err?: string, entries?: canola.InternalEntry[], fetch_more?: fun())
M.list = function(url, column_defs, callback)
  if vim.fn.executable('curl') ~= 1 then
    callback('`curl` is not executable. Can you run `curl --version`?')
    return
  end
  local res = M.parse_url(url)
  curl(res, { curl_ftp_url(res) }, function(err, output)
    if err then
      callback(err)
      return
    end
    local entries = {}
    for _, line in ipairs(output or {}) do
      if line ~= '' then
        local name, entry_type, meta = parse_unix_list_line(line)
        if not name then
          name, entry_type, meta = parse_iis_list_line(line)
        end
        if name and entry_type and name ~= '.' and name ~= '..' then
          table.insert(entries, { nil, name, entry_type, meta })
        end
      end
    end
    callback(nil, entries)
  end)
end

---@param bufnr integer
---@return boolean
M.is_modifiable = function(bufnr)
  return true
end

---@param action canola.Action
---@return string
M.render_action = function(action)
  if action.type == 'create' then
    local ret = string.format('CREATE %s', action.url)
    if action.link then
      ret = ret .. ' -> ' .. action.link
    end
    return ret
  elseif action.type == 'delete' then
    return string.format('DELETE %s', action.url)
  elseif action.type == 'move' or action.type == 'copy' then
    local src = action.src_url
    local dest = action.dest_url
    if config.get_adapter_by_scheme(src) ~= M then
      local _, path = util.parse_url(src)
      assert(path)
      src = files.to_short_os_path(path, action.entry_type)
    end
    if config.get_adapter_by_scheme(dest) ~= M then
      local _, path = util.parse_url(dest)
      assert(path)
      dest = files.to_short_os_path(path, action.entry_type)
    end
    return string.format('  %s %s -> %s', action.type:upper(), src, dest)
  else
    error(string.format("Bad action type: '%s'", action.type))
  end
end

---@param src_res oil.ftpUrl
---@param dest_res oil.ftpUrl
---@param cb fun(err: nil|string)
local function ftp_copy_file(src_res, dest_res, cb)
  local cache_dir = vim.fn.stdpath('cache')
  assert(type(cache_dir) == 'string')
  local tmpdir = fs.join(cache_dir, 'canola')
  fs.mkdirp(tmpdir)
  local fd, tmpfile = vim.loop.fs_mkstemp(fs.join(tmpdir, 'ftp_XXXXXX'))
  if fd then
    vim.loop.fs_close(fd)
  end
  curl(src_res, { curl_ftp_url(src_res), '-o', tmpfile }, function(err)
    if err then
      vim.loop.fs_unlink(tmpfile)
      return cb(err)
    end
    curl(dest_res, { '-T', tmpfile, curl_ftp_url(dest_res) }, function(err2)
      vim.loop.fs_unlink(tmpfile)
      cb(err2)
    end)
  end)
end

---@param action canola.Action
---@param cb fun(err: nil|string)
M.perform_action = function(action, cb)
  if action.type == 'create' then
    local res = M.parse_url(action.url)
    local ftp_path = ftp_abs_path(res)
    if action.entry_type == 'directory' then
      ftpcmd(res, { string.format('ftp.voidcmd(%q)', 'MKD ' .. ftp_path) }, cb)
    elseif action.entry_type == 'link' then
      cb('FTP does not support symbolic links')
    else
      curl(res, { '-T', '-', curl_ftp_url(res) }, { stdin = 'null' }, cb)
    end
  elseif action.type == 'delete' then
    local res = M.parse_url(action.url)
    local ftp_path = ftp_abs_path(res)
    if action.entry_type == 'directory' then
      ftpcmd(res, {
        'def rmtree(f, p):',
        '  try:',
        '    entries = list(f.mlsd(p))',
        '  except ftplib.error_perm as e:',
        '    if "500" in str(e) or "502" in str(e): import sys; sys.exit("Server does not support MLSD; cannot recursively delete non-empty directories")',
        '    raise',
        '  for name, facts in entries:',
        '    if name in (".", ".."): continue',
        '    child = p.rstrip("/") + "/" + name',
        '    if facts["type"] == "dir": rmtree(f, child)',
        '    else: f.voidcmd("DELE " + child)',
        '  f.voidcmd("RMD " + p)',
        string.format('rmtree(ftp, %q)', ftp_path),
      }, cb)
    else
      ftpcmd(res, { string.format('ftp.voidcmd(%q)', 'DELE ' .. ftp_path) }, cb)
    end
  elseif action.type == 'move' then
    local src_adapter = assert(config.get_adapter_by_scheme(action.src_url))
    local dest_adapter = assert(config.get_adapter_by_scheme(action.dest_url))
    if src_adapter == M and dest_adapter == M then
      local src_res = M.parse_url(action.src_url)
      local dest_res = M.parse_url(action.dest_url)
      if url_hosts_equal(src_res, dest_res) then
        ftpcmd(src_res, {
          string.format('ftp.rename(%q, %q)', ftp_abs_path(src_res), ftp_abs_path(dest_res)),
        }, cb)
      else
        if action.entry_type == 'directory' then
          cb('Cannot move directories across FTP hosts')
          return
        end
        ftp_copy_file(src_res, dest_res, function(err)
          if err then
            return cb(err)
          end
          ftpcmd(
            src_res,
            { string.format('ftp.voidcmd(%q)', 'DELE ' .. ftp_abs_path(src_res)) },
            cb
          )
        end)
      end
    else
      cb('We should never attempt to move across adapters')
    end
  elseif action.type == 'copy' then
    local src_adapter = assert(config.get_adapter_by_scheme(action.src_url))
    local dest_adapter = assert(config.get_adapter_by_scheme(action.dest_url))
    if src_adapter == M and dest_adapter == M then
      if action.entry_type == 'directory' then
        cb('Cannot copy directories over FTP; copy individual files instead')
        return
      end
      local src_res = M.parse_url(action.src_url)
      local dest_res = M.parse_url(action.dest_url)
      ftp_copy_file(src_res, dest_res, cb)
    elseif src_adapter == M then
      if action.entry_type == 'directory' then
        cb('Cannot copy FTP directories to local filesystem via curl')
        return
      end
      local src_res = M.parse_url(action.src_url)
      local _, dest_path = util.parse_url(action.dest_url)
      assert(dest_path)
      local local_path = fs.posix_to_os_path(dest_path)
      curl(src_res, { curl_ftp_url(src_res), '-o', local_path }, cb)
    else
      if action.entry_type == 'directory' then
        cb('Cannot copy local directories to FTP via curl')
        return
      end
      local _, src_path = util.parse_url(action.src_url)
      assert(src_path)
      local local_path = fs.posix_to_os_path(src_path)
      local dest_res = M.parse_url(action.dest_url)
      curl(dest_res, { '-T', local_path, curl_ftp_url(dest_res) }, cb)
    end
  else
    cb(string.format('Bad action type: %s', action.type))
  end
end

M.supported_cross_adapter_actions = { files = 'copy' }

---@param bufnr integer
M.read_file = function(bufnr)
  loading.set_loading(bufnr, true)
  local bufname = vim.api.nvim_buf_get_name(bufnr)
  local url = M.parse_url(bufname)
  local basename = pathutil.basename(bufname)
  local cache_dir = vim.fn.stdpath('cache')
  assert(type(cache_dir) == 'string')
  local tmpdir = fs.join(cache_dir, 'canola')
  fs.mkdirp(tmpdir)
  local fd, tmpfile = vim.loop.fs_mkstemp(fs.join(tmpdir, 'ftp_XXXXXX'))
  if fd then
    vim.loop.fs_close(fd)
  end
  local tmp_bufnr = vim.fn.bufadd(tmpfile)

  curl(url, { curl_ftp_url(url), '-o', tmpfile }, function(err)
    loading.set_loading(bufnr, false)
    vim.bo[bufnr].modifiable = true
    vim.cmd.doautocmd({ args = { 'BufReadPre', bufname }, mods = { silent = true } })
    if err then
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, true, vim.split(err, '\n'))
    else
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, true, {})
      vim.api.nvim_buf_call(bufnr, function()
        vim.cmd.read({ args = { tmpfile }, mods = { silent = true } })
      end)
      vim.loop.fs_unlink(tmpfile)
      vim.api.nvim_buf_set_lines(bufnr, 0, 1, true, {})
    end
    vim.bo[bufnr].modified = false
    local filetype = vim.filetype.match({ buf = bufnr, filename = basename })
    if filetype then
      vim.bo[bufnr].filetype = filetype
    end
    vim.cmd.doautocmd({ args = { 'BufReadPost', bufname }, mods = { silent = true } })
    vim.api.nvim_buf_delete(tmp_bufnr, { force = true })
  end)
end

---@param bufnr integer
M.write_file = function(bufnr)
  local bufname = vim.api.nvim_buf_get_name(bufnr)
  local url = M.parse_url(bufname)
  local cache_dir = vim.fn.stdpath('cache')
  assert(type(cache_dir) == 'string')
  local tmpdir = fs.join(cache_dir, 'canola')
  local fd, tmpfile = vim.loop.fs_mkstemp(fs.join(tmpdir, 'ftp_XXXXXXXX'))
  if fd then
    vim.loop.fs_close(fd)
  end
  vim.cmd.doautocmd({ args = { 'BufWritePre', bufname }, mods = { silent = true } })
  vim.bo[bufnr].modifiable = false
  vim.cmd.write({ args = { tmpfile }, bang = true, mods = { silent = true, noautocmd = true } })
  local tmp_bufnr = vim.fn.bufadd(tmpfile)

  curl(url, { '-T', tmpfile, curl_ftp_url(url) }, function(err)
    vim.bo[bufnr].modifiable = true
    if err then
      vim.notify(string.format('Error writing file: %s', err), vim.log.levels.ERROR)
    else
      vim.bo[bufnr].modified = false
      vim.cmd.doautocmd({ args = { 'BufWritePost', bufname }, mods = { silent = true } })
    end
    vim.loop.fs_unlink(tmpfile)
    vim.api.nvim_buf_delete(tmp_bufnr, { force = true })
  end)
end

M._parse_unix_list_line = parse_unix_list_line
M._parse_iis_list_line = parse_iis_list_line
M._url_encode_path = url_encode_path
M._curl_ftp_url = curl_ftp_url

return M
