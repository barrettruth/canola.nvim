local cache = require('canola.cache')
local config = require('canola.config')
local constants = require('canola.constants')
local util = require('canola.util')

local M = {}

local FIELD_ID = constants.FIELD_ID
local FIELD_NAME = constants.FIELD_NAME
local FIELD_TYPE = constants.FIELD_TYPE
local FIELD_META = constants.FIELD_META

---@param entry canola.InternalEntry
---@return boolean
local function is_unix_executable(entry)
  if entry[FIELD_TYPE] == 'directory' then
    return false
  end
  local meta = entry[FIELD_META]
  if not meta or not meta.stat then
    return false
  end
  if meta.stat.type == 'directory' then
    return false
  end

  local S_IXUSR = 64
  local S_IXGRP = 8
  local S_IXOTH = 1
  return bit.band(meta.stat.mode, bit.bor(S_IXUSR, S_IXGRP, S_IXOTH)) ~= 0
end

local function get_link_text(name, meta)
  local arrow, link_dir, link_base
  if meta then
    if meta.link then
      local link = meta.link:gsub('\n', '')
      arrow = '-> '
      local last_sep = link:match('.*()/')
      if last_sep then
        link_dir = link:sub(1, last_sep)
        link_base = link:sub(last_sep + 1)
      else
        link_base = link
      end
    end
  end

  return name, arrow, link_dir, link_base
end

---@param cols canola.TextChunk[]
---@param col_width integer[]
---@param col_align? canola.ColumnAlign[]
---@param line_len integer
---@return canola.HlRange[]
M.compute_highlights_for_cols = function(cols, col_width, col_align, line_len)
  local highlights = {}
  local col = 0
  for i, chunk in ipairs(cols) do
    local text, hl
    if type(chunk) == 'table' then
      text = chunk[1]
      hl = chunk[2]
    else
      text = chunk
    end
    local unpadded_len = #text
    local padded_text, padding = util.pad_align(text, col_width[i], (col_align or {})[i] or 'left')
    if hl then
      local hl_end = col + padding + unpadded_len
      if i == #cols and line_len then
        hl_end = line_len
      end
      if type(hl) == 'table' then
        for _, sub_hl in ipairs(hl) do
          table.insert(
            highlights,
            { sub_hl[1], col + padding + sub_hl[2], col + padding + sub_hl[3] }
          )
        end
      else
        table.insert(highlights, { hl, col + padding, hl_end })
      end
    end
    col = col + #padded_text + 1
  end
  return highlights
end

---@param entry canola.InternalEntry
---@param adapter canola.Adapter
---@param is_hidden boolean
---@param bufnr integer
---@return canola.TextChunk[]
M.format_entry_line = function(entry, adapter, is_hidden, bufnr)
  local name = entry[FIELD_NAME]
  local meta = entry[FIELD_META]
  local hl_suffix = ''
  if is_hidden then
    hl_suffix = 'Hidden'
  end
  if meta and meta.display_name then
    name = meta.display_name
  end
  -- We can't handle newlines in filenames (and shame on you for doing that)
  name = name:gsub('\n', '')
  -- First put the unique ID
  local cols = {}
  local id_key = cache.format_id(entry[FIELD_ID])
  table.insert(cols, id_key)
  -- Always add the entry name at the end
  local entry_type = entry[FIELD_TYPE]

  local custom_hl
  for _, pair in ipairs(config.highlights.filename) do
    if name:match(pair[1]) then
      custom_hl = pair[2]
      break
    end
  end

  local link_name, link_name_hl, link_arrow, link_dir, link_base, link_target_hl
  if custom_hl then
    if entry_type == 'link' then
      link_name, link_arrow, link_dir, link_base = get_link_text(name, meta)
      link_name_hl = custom_hl
      link_target_hl = custom_hl
    else
      if entry_type == 'directory' then
        name = name .. '/'
      end
      table.insert(cols, { name, custom_hl })
      return cols
    end
  end

  local highlight_as_executable = false
  if entry_type ~= 'directory' then
    local lower = name:lower()
    if
      lower:match('%.exe$')
      or lower:match('%.bat$')
      or lower:match('%.cmd$')
      or lower:match('%.com$')
      or lower:match('%.ps1$')
    then
      highlight_as_executable = true
    -- selene: allow(if_same_then_else)
    elseif is_unix_executable(entry) then
      highlight_as_executable = true
    end
  end

  if entry_type == 'directory' then
    table.insert(cols, { name .. '/', 'CanolaDir' .. hl_suffix })
  elseif entry_type == 'socket' then
    table.insert(cols, { name, 'CanolaSocket' .. hl_suffix })
  elseif entry_type == 'link' then
    if not link_arrow then
      link_name, link_arrow, link_dir, link_base = get_link_text(name, meta)
    end
    local is_orphan = not (meta and meta.link_stat)
    if not link_name_hl then
      if highlight_as_executable then
        link_name_hl = 'CanolaExecutable' .. hl_suffix
      else
        link_name_hl = 'CanolaLink' .. hl_suffix
      end
    end
    table.insert(cols, { link_name, link_name_hl })

    if link_arrow then
      if link_target_hl then
        local target_text = link_arrow .. (link_dir or '') .. (link_base or '')
        table.insert(cols, { target_text, link_target_hl })
      else
        local target_text = link_arrow .. (link_dir or '') .. (link_base or '')
        local sub_hls = {}
        local off = 0
        local orphan_hl = 'CanolaOrphanLinkTarget' .. hl_suffix
        local orphan_arrow_hl = 'CanolaOrphanLink' .. hl_suffix
        sub_hls[#sub_hls + 1] = {
          is_orphan and orphan_arrow_hl or ('CanolaLinkArrow' .. hl_suffix),
          off,
          off + #link_arrow,
        }
        off = off + #link_arrow
        if link_dir then
          sub_hls[#sub_hls + 1] = {
            is_orphan and orphan_hl or ('CanolaLinkPath' .. hl_suffix),
            off,
            off + #link_dir,
          }
          off = off + #link_dir
        end
        if link_base then
          local base_hl
          if is_orphan then
            base_hl = orphan_hl
          elseif highlight_as_executable then
            base_hl = 'CanolaExecutable' .. hl_suffix
          else
            local target_type = meta and meta.link_stat and meta.link_stat.type
            if target_type == 'directory' then
              base_hl = 'CanolaDir' .. hl_suffix
            elseif target_type == 'socket' then
              base_hl = 'CanolaSocket' .. hl_suffix
            else
              base_hl = 'CanolaFile' .. hl_suffix
            end
          end
          sub_hls[#sub_hls + 1] = { base_hl, off, off + #link_base }
        end
        table.insert(cols, { target_text, sub_hls })
      end
    end
  elseif highlight_as_executable then
    table.insert(cols, { name, 'CanolaExecutable' .. hl_suffix })
  else
    table.insert(cols, { name, 'CanolaFile' .. hl_suffix })
  end

  return cols
end

return M
