local M = {}

---@type table<integer, string>
local uid_to_name
---@type table<integer, string>
local gid_to_name

local function parse_passwd()
  uid_to_name = {}
  local ok, lines = pcall(vim.fn.readfile, '/etc/passwd')
  if not ok then
    return
  end
  for _, line in ipairs(lines) do
    local name, uid = line:match('^([^:]+):[^:]*:(%d+)')
    if name and uid then
      uid_to_name[tonumber(uid)] = name
    end
  end
end

local function parse_group()
  gid_to_name = {}
  local ok, lines = pcall(vim.fn.readfile, '/etc/group')
  if not ok then
    return
  end
  for _, line in ipairs(lines) do
    local name, gid = line:match('^([^:]+):[^:]*:(%d+)')
    if name and gid then
      gid_to_name[tonumber(gid)] = name
    end
  end
end

---@param uid integer
---@return string
M.get_user = function(uid)
  if not uid_to_name then
    parse_passwd()
  end
  return uid_to_name[uid] or tostring(uid)
end

---@param gid integer
---@return string
M.get_group = function(gid)
  if not gid_to_name then
    parse_group()
  end
  return gid_to_name[gid] or tostring(gid)
end

return M
