local M = {}

---@class (exact) canola.SelectOpts
---@field vertical? boolean Open the buffer in a vertical split
---@field horizontal? boolean Open the buffer in a horizontal split
---@field split? "aboveleft"|"belowright"|"topleft"|"botright" Split modifier
---@field tab? boolean Open the buffer in a new tab
---@field confirm? boolean If true, always show confirmation; if false, never show; if nil, respect config
---@field close? boolean Close the original oil buffer once selection is made
---@field handle_buffer_callback? fun(buf_id: integer) If defined, all other buffer related options here would be ignored. This callback allows you to take over the process of opening the buffer yourself.

---Select the entry under the cursor
---@param opts nil|canola.SelectOpts
---@param callback nil|fun(err: nil|string) Called once all entries have been opened
M.select = function(opts, callback)
  local cache = require('canola.cache')
  local canola = require('canola')
  local config = require('canola.config')
  local constants = require('canola.constants')
  local util = require('canola.util')
  local window = require('canola.window')
  local FIELD_META = constants.FIELD_META
  opts = vim.tbl_extend('keep', opts or {}, {})

  local function finish(err)
    if err then
      vim.notify(err, vim.log.levels.ERROR)
    end
    if callback then
      callback(err)
    end
  end
  if not opts.split and (opts.horizontal or opts.vertical) then
    if opts.horizontal then
      opts.split = vim.o.splitbelow and 'belowright' or 'aboveleft'
    else
      opts.split = vim.o.splitright and 'belowright' or 'aboveleft'
    end
  end
  if opts.tab and opts.split then
    return finish('Cannot use split=true when tab = true')
  end
  local adapter = util.get_adapter(0)
  if not adapter then
    return finish('Not an oil buffer')
  end

  local visual_range = util.get_visual_range()

  ---@type canola.Entry[]
  local entries = {}
  if visual_range then
    for i = visual_range.start_lnum, visual_range.end_lnum do
      local entry = canola.get_entry_on_line(0, i)
      if entry then
        table.insert(entries, entry)
      end
    end
  else
    local entry = canola.get_cursor_entry()
    if entry then
      table.insert(entries, entry)
    end
  end
  if next(entries) == nil then
    return finish('Could not find entry under cursor')
  end

  -- Check if any of these entries are moved from their original location
  local bufname = vim.api.nvim_buf_get_name(0)
  local any_moved = false
  for _, entry in ipairs(entries) do
    -- Ignore entries with ID 0 (typically the "../" entry)
    if entry.id ~= 0 then
      local is_new_entry = entry.id == nil
      local is_moved_from_dir = entry.id and cache.get_parent_url(entry.id) ~= bufname
      local is_renamed = entry.parsed_name ~= entry.name
      local internal_entry = entry.id and cache.get_entry_by_id(entry.id)
      if internal_entry then
        local meta = internal_entry[FIELD_META]
        if meta and meta.display_name then
          is_renamed = entry.parsed_name ~= meta.display_name
        end
      end
      if is_new_entry or is_moved_from_dir or is_renamed then
        any_moved = true
        break
      end
    end
  end
  if any_moved and config.save ~= false then
    if config.save == 'auto' or opts.confirm == false then
      canola.save({ confirm = opts.confirm })
      return finish()
    end
    local ok, choice = pcall(vim.fn.confirm, 'Save changes?', 'Yes\nNo', 1)
    if not ok then
      return finish()
    elseif choice == 0 then
      return
    elseif choice == 1 then
      canola.save({ confirm = opts.confirm })
      return finish()
    end
  end

  local prev_win = vim.api.nvim_get_current_win()
  local oil_bufnr = vim.api.nvim_get_current_buf()
  local keep_float_open = util.is_floating_win() and opts.close == false
  local float_win = keep_float_open and prev_win or nil

  -- Async iter over entries so we can normalize the url before opening
  local i = 1
  local function open_next_entry(cb)
    local entry = entries[i]
    i = i + 1
    if not entry then
      return cb()
    end
    if util.is_directory(entry) then
      -- If this is a new directory BUT we think we already have an entry with this name, disallow
      -- entry. This prevents the case of MOVE /foo -> /bar + CREATE /foo.
      -- If you enter the new /foo, it will show the contents of the old /foo.
      if not entry.id and cache.list_url(bufname)[entry.name] then
        return cb('Please save changes before entering new directory')
      end
    else
      local is_float = util.is_floating_win()
      if is_float and opts.close == false then
        vim.w.canola_keep_open = true
      elseif vim.w.is_canola_win then
        window.close()
      end
    end

    -- Normalize the url before opening to prevent needing to rename them inside the BufReadCmd
    -- Renaming buffers during opening can lead to missed autocmds
    util.get_edit_path(oil_bufnr, entry, function(normalized_url)
      local mods = {
        vertical = opts.vertical,
        horizontal = opts.horizontal,
        split = opts.split,
        keepalt = false,
      }
      local filebufnr = vim.fn.bufadd(normalized_url)
      local entry_is_file = not vim.endswith(normalized_url, '/')

      -- The :buffer command doesn't set buflisted=true
      -- So do that for normal files or for oil dirs if config set buflisted=true
      if entry_is_file or config.buf.buflisted then
        vim.bo[filebufnr].buflisted = true
      end

      if keep_float_open and not opts.tab then
        local original_win = vim.w[float_win].canola_original_win
        if original_win and vim.api.nvim_win_is_valid(original_win) then
          vim.api.nvim_set_current_win(original_win)
        else
          for _, winid in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
            if winid ~= float_win and not util.is_floating_win(winid) then
              vim.api.nvim_set_current_win(winid)
              break
            end
          end
        end
      end

      local cmd = 'buffer'
      if opts.tab then
        vim.cmd.tabnew({ mods = mods })
        vim.bo.bufhidden = 'wipe'
      elseif opts.split then
        cmd = 'sbuffer'
      end
      if opts.handle_buffer_callback ~= nil then
        opts.handle_buffer_callback(filebufnr)
      else
        ---@diagnostic disable-next-line: param-type-mismatch
        local ok, err = pcall(vim.cmd, {
          cmd = cmd,
          args = { filebufnr },
          mods = mods,
        })
        -- Ignore swapfile errors
        if not ok and err and not err:match('^Vim:E325:') then
          vim.api.nvim_echo({ { err, 'Error' } }, true, {})
        end
      end

      vim.cmd.redraw()
      open_next_entry(cb)
    end)
  end

  open_next_entry(function(err)
    if err then
      return finish(err)
    end
    if
      opts.close
      and vim.api.nvim_win_is_valid(prev_win)
      and prev_win ~= vim.api.nvim_get_current_win()
    then
      vim.api.nvim_win_call(prev_win, function()
        window.close()
      end)
    end

    if float_win and vim.api.nvim_win_is_valid(float_win) then
      if opts.tab then
        vim.api.nvim_set_current_tabpage(vim.api.nvim_win_get_tabpage(float_win))
      end
      vim.api.nvim_set_current_win(float_win)
    end

    window.update_preview_window()

    finish()
  end)
end

return M
