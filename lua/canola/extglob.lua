local M = {}

---@param s string
---@param start integer
---@return integer?
---@return integer?
local function find_brace_group(s, start)
  local depth = 0
  local open_pos = nil
  for i = start, #s do
    local c = s:sub(i, i)
    if c == '{' then
      if depth == 0 then
        open_pos = i
      end
      depth = depth + 1
    elseif c == '}' then
      depth = depth - 1
      if depth == 0 and open_pos then
        return open_pos, i
      end
    end
  end
  return nil, nil
end

---@param s string
---@return string[]
local function split_at_depth_zero(s)
  local parts = {}
  local depth = 0
  local current = ''
  for i = 1, #s do
    local c = s:sub(i, i)
    if c == '{' then
      depth = depth + 1
      current = current .. c
    elseif c == '}' then
      depth = depth - 1
      current = current .. c
    elseif c == ',' and depth == 0 then
      table.insert(parts, current)
      current = ''
    else
      current = current .. c
    end
  end
  table.insert(parts, current)
  return parts
end

---@param content string
---@return string[]?
local function parse_range(content)
  local a, b, step = content:match('^(-?%d+)%.%.(-?%d+)%.%.(-?%d+)$')
  if not a then
    a, b = content:match('^(-?%d+)%.%.(-?%d+)$')
  end
  if not a then
    return nil
  end
  a = tonumber(a)
  b = tonumber(b)
  step = step and tonumber(step) or nil
  if step and step == 0 then
    return nil
  end
  local results = {}
  if a <= b then
    step = step or 1
    if step < 0 then
      step = -step
    end
    for i = a, b, step do
      table.insert(results, tostring(i))
    end
  else
    step = step or 1
    if step < 0 then
      step = -step
    end
    for i = a, b, -step do
      table.insert(results, tostring(i))
    end
  end
  return results
end

---@param s string
---@return string[]
M.expand = function(s)
  local open_pos, close_pos = find_brace_group(s, 1)
  if not open_pos then
    return { s }
  end

  local prefix = s:sub(1, open_pos - 1)
  local content = s:sub(open_pos + 1, close_pos - 1)
  local suffix = s:sub(close_pos + 1)

  local range = parse_range(content)
  if range then
    local results = {}
    for _, val in ipairs(range) do
      local expanded = M.expand(prefix .. val .. suffix)
      vim.list_extend(results, expanded)
    end
    return results
  end

  local parts = split_at_depth_zero(content)
  if #parts <= 1 then
    return { s }
  end

  local results = {}
  for _, part in ipairs(parts) do
    local expanded = M.expand(prefix .. part .. suffix)
    vim.list_extend(results, expanded)
  end
  return results
end

return M
