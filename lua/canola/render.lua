local M = {}

---@param text string
---@param width integer|nil
---@param align canola.ColumnAlign
---@return string padded_text
---@return integer left_padding
M.pad_align = function(text, width, align)
  if not width then
    return text, 0
  end
  local text_width = vim.api.nvim_strwidth(text)
  local total_pad = width - text_width
  if total_pad <= 0 then
    return text, 0
  end

  if align == 'right' then
    return string.rep(' ', total_pad) .. text, total_pad
  elseif align == 'center' then
    local left_pad = math.floor(total_pad / 2)
    local right_pad = total_pad - left_pad
    return string.rep(' ', left_pad) .. text .. string.rep(' ', right_pad), left_pad
  else
    return text .. string.rep(' ', total_pad), 0
  end
end

---@alias canola.ColumnAlign "left"|"center"|"right"

---@param lines canola.TextChunk[][]
---@param col_width integer[]
---@param col_align? canola.ColumnAlign[]
---@return string[]
M.render_table = function(lines, col_width, col_align)
  col_align = col_align or {}
  local str_lines = {}
  for _, cols in ipairs(lines) do
    local pieces = {}
    for i, chunk in ipairs(cols) do
      local text
      if type(chunk) == 'table' then
        text = chunk[1]
      else
        text = chunk
      end
      text = M.pad_align(text, col_width[i], col_align[i] or 'left')
      table.insert(pieces, text)
    end
    table.insert(str_lines, table.concat(pieces, ' '))
  end
  return str_lines
end

---@param bufnr integer
---@param highlights any[][] List of highlights {group, lnum, col_start, col_end}
M.set_highlights = function(bufnr, highlights)
  local ns = vim.api.nvim_create_namespace('Canola')
  vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
  for _, hl in ipairs(highlights) do
    local group, line, col_start, col_end = unpack(hl)
    vim.api.nvim_buf_set_extmark(bufnr, ns, line, col_start, {
      end_col = col_end,
      hl_group = group,
      strict = false,
    })
  end
end

---@param str string
---@param align "left"|"right"|"center"
---@param width integer
---@return string
---@return integer
M.h_align = function(str, align, width)
  if align == 'center' then
    local padding = math.floor((width - vim.api.nvim_strwidth(str)) / 2)
    return string.rep(' ', padding) .. str, padding
  elseif align == 'right' then
    local padding = width - vim.api.nvim_strwidth(str)
    return string.rep(' ', padding) .. str, padding
  else
    return str, 0
  end
end

---@param bufnr integer
---@param text string|string[]
---@param opts nil|table
---    h_align nil|"left"|"right"|"center"
---    v_align nil|"top"|"bottom"|"center"
---    actions nil|string[]
---    winid nil|integer
M.render_text = function(bufnr, text, opts)
  opts = vim.tbl_deep_extend('keep', opts or {}, {
    h_align = 'center',
    v_align = 'center',
  })
  ---@cast opts -nil
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end
  if type(text) == 'string' then
    text = { text }
  end
  local height = 40
  local width = 30

  -- If no winid passed in, find the first win that displays this buffer
  if not opts.winid then
    for _, winid in ipairs(vim.api.nvim_list_wins()) do
      if vim.api.nvim_win_is_valid(winid) and vim.api.nvim_win_get_buf(winid) == bufnr then
        opts.winid = winid
        break
      end
    end
  end
  if opts.winid then
    height = vim.api.nvim_win_get_height(opts.winid)
    width = vim.api.nvim_win_get_width(opts.winid)
  end
  local lines = {}

  -- Add vertical spacing for vertical alignment
  if opts.v_align == 'center' then
    for _ = 1, (height / 2) - (#text / 2) do
      table.insert(lines, '')
    end
  elseif opts.v_align == 'bottom' then
    local num_lines = height
    if opts.actions then
      num_lines = num_lines - 2
    end
    while #lines + #text < num_lines do
      table.insert(lines, '')
    end
  end

  -- Add the lines of text
  for _, line in ipairs(text) do
    line = M.h_align(line, opts.h_align, width)
    table.insert(lines, line)
  end

  -- Render the actions (if any) at the bottom
  local highlights = {}
  if opts.actions then
    while #lines < height - 1 do
      table.insert(lines, '')
    end
    local last_line, padding = M.h_align(table.concat(opts.actions, '    '), 'center', width)
    local col = padding
    for _, action in ipairs(opts.actions) do
      table.insert(highlights, { 'Special', #lines, col, col + 3 })
      col = padding + action:len() + 4
    end
    table.insert(lines, last_line)
  end

  vim.bo[bufnr].modifiable = true
  pcall(vim.api.nvim_buf_set_lines, bufnr, 0, -1, false, lines)
  vim.bo[bufnr].modifiable = false
  vim.bo[bufnr].modified = false
  M.set_highlights(bufnr, highlights)
end

return M
