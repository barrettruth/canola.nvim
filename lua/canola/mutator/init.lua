local Progress = require('canola.mutator.progress')
local action_creation = require('canola.mutator.action_creation')
local action_ordering = require('canola.mutator.action_ordering')
local cache = require('canola.cache')
local canola = require('canola')
local columns = require('canola.columns')
local config = require('canola.config')
local confirmation = require('canola.mutator.confirmation')
local fs = require('canola.fs')
local lsp_helpers = require('canola.lsp.helpers')
local parser = require('canola.mutator.parser')
local util = require('canola.util')
local view = require('canola.view')
local M = {}

M.create_actions_from_diffs = function(all_diffs)
  return action_creation.create_actions_from_diffs(all_diffs)
end

M.enforce_action_order = function(actions)
  return action_ordering.enforce_action_order(actions)
end

local progress

---@param actions canola.Action[]
---@param cb fun(err: nil|string)
M.process_actions = function(actions, cb)
  vim.api.nvim_exec_autocmds(
    'User',
    { pattern = 'CanolaActionsPre', modeline = false, data = { actions = actions } }
  )

  local did_complete = nil
  if config.lsp.enabled then
    did_complete = lsp_helpers.will_perform_file_operations(actions)
  end

  -- Convert some cross-adapter moves to a copy + delete
  for _, action in ipairs(actions) do
    if action.type == 'move' then
      local _, cross_action = util.get_adapter_for_action(action)
      -- Only do the conversion if the cross-adapter support is "copy"
      if cross_action == 'copy' then
        ---@diagnostic disable-next-line: assign-type-mismatch
        action.type = 'copy'
        table.insert(actions, {
          type = 'delete',
          url = action.src_url,
          entry_type = action.entry_type,
        })
      end
    end
  end

  local finished = false
  progress = Progress.new()
  local function finish(err)
    if not finished then
      finished = true
      progress:close()
      progress = nil
      if config.delete.wipe and not err then
        for _, action in ipairs(actions) do
          if action.type == 'delete' then
            local scheme, path = util.parse_url(action.url)
            if config.adapters[scheme] == 'files' then
              assert(path)
              local os_path = fs.posix_to_os_path(path)
              local bufnr = vim.fn.bufnr(os_path)
              if bufnr ~= -1 then
                local did_delete = false
                for _, winid in ipairs(vim.fn.win_findbuf(bufnr)) do
                  if vim.api.nvim_win_is_valid(winid) then
                    vim.api.nvim_win_call(winid, function()
                      vim.api.nvim_buf_delete(bufnr, { force = true })
                    end)
                    did_delete = true
                    break
                  end
                end
                if not did_delete then
                  vim.api.nvim_buf_delete(bufnr, { force = true })
                end
              end
            end
          end
        end
      end
      vim.api.nvim_exec_autocmds(
        'User',
        { pattern = 'CanolaActionsPost', modeline = false, data = { err = err, actions = actions } }
      )
      cb(err)
    end
  end

  -- Defer showing the progress to avoid flicker for fast operations
  vim.defer_fn(function()
    if not finished then
      progress:show({
        -- TODO some actions are actually cancelable.
        -- We should stop them instead of stopping after the current action
        cancel = function()
          finish('Canceled')
        end,
      })
    end
  end, 100)

  local idx = 1
  local next_action
  next_action = function()
    if finished then
      return
    end
    if idx > #actions then
      if did_complete then
        did_complete()
      end
      finish()
      return
    end
    local action = actions[idx]
    progress:set_action(action, idx, #actions)
    idx = idx + 1
    local ok, adapter = pcall(util.get_adapter_for_action, action)
    if not ok then
      return finish(adapter)
    end
    local callback = vim.schedule_wrap(function(err)
      if finished then
        -- This can happen if the user canceled out of the progress window
        return
      elseif err then
        finish(err)
      else
        cache.perform_action(action)
        next_action()
      end
    end)
    if action.type == 'change' then
      ---@cast action canola.ChangeAction
      columns.perform_change_action(adapter, action, callback)
    else
      adapter.perform_action(action, callback)
    end
  end
  next_action()
end

M.show_progress = function()
  if progress then
    progress:restore()
  end
end

---@type boolean
local mutation_in_progress = false

---@return boolean
M.is_mutating = function()
  return mutation_in_progress
end

M.reset = function()
  mutation_in_progress = false
end

---@param confirm nil|boolean
---@param cb? fun(err: nil|string)
M.try_write_changes = function(confirm, cb)
  if not cb then
    cb = function(_err) end
  end
  if mutation_in_progress then
    cb('Cannot perform mutation when already in progress')
    return
  end
  local current_buf = vim.api.nvim_get_current_buf()
  local was_modified = vim.bo.modified
  local buffers = view.get_all_buffers()
  local all_diffs = {}
  ---@type table<integer, canola.ParseError[]>
  local all_errors = {}

  mutation_in_progress = true
  -- Lock the buffer to prevent race conditions from the user modifying them during parsing
  view.lock_buffers()
  for _, bufnr in ipairs(buffers) do
    if vim.bo[bufnr].modified then
      local diffs, errors = parser.parse(bufnr)
      all_diffs[bufnr] = diffs
      local adapter = assert(util.get_adapter(bufnr, true))
      if adapter.filter_error then
        errors = vim.tbl_filter(adapter.filter_error, errors)
      end
      if next(errors) ~= nil then
        all_errors[bufnr] = errors
      end
    end
  end
  local function unlock()
    view.unlock_buffers()
    -- The ":write" will set nomodified even if we cancel here, so we need to restore it
    if was_modified then
      vim.bo[current_buf].modified = true
    end
    mutation_in_progress = false
  end

  local ns = vim.api.nvim_create_namespace('Canola')
  vim.diagnostic.reset(ns)
  if next(all_errors) ~= nil then
    for bufnr, errors in pairs(all_errors) do
      vim.diagnostic.set(ns, bufnr, errors)
    end

    -- Jump to an error
    local curbuf = vim.api.nvim_get_current_buf()
    local first_msg
    if all_errors[curbuf] then
      first_msg = all_errors[curbuf][1].message
      pcall(
        vim.api.nvim_win_set_cursor,
        0,
        { all_errors[curbuf][1].lnum + 1, all_errors[curbuf][1].col }
      )
    else
      local err_bufnr, errs = next(all_errors)
      assert(err_bufnr)
      assert(errs)
      first_msg = errs[1].message
      -- HACK: This is a workaround for the fact that we can't switch buffers in the middle of a
      -- BufWriteCmd.
      vim.schedule(function()
        vim.api.nvim_win_set_buf(0, err_bufnr)
        pcall(vim.api.nvim_win_set_cursor, 0, { errs[1].lnum + 1, errs[1].col })
      end)
    end
    unlock()
    cb(string.format('Error parsing oil buffers: %s', first_msg))
    return
  end

  local actions = M.create_actions_from_diffs(all_diffs)
  confirmation.show(actions, confirm, function(proceed)
    if not proceed then
      unlock()
      cb('Canceled')
      return
    end

    M.process_actions(
      actions,
      vim.schedule_wrap(function(err)
        view.unlock_buffers()
        if err then
          err = string.format('[canola] Error applying actions: %s', err)
          view.rerender_all_oil_buffers({ force = true }, function()
            cb(err)
          end)
        else
          local current_entry = canola.get_cursor_entry()
          if current_entry then
            view.set_last_cursor(
              vim.api.nvim_buf_get_name(0),
              vim.split(current_entry.parsed_name or current_entry.name, '/')[1]
            )
          end
          view.rerender_all_oil_buffers({ force = true }, function(render_err)
            vim.api.nvim_exec_autocmds(
              'User',
              { pattern = 'CanolaMutationComplete', modeline = false, data = { actions = actions } }
            )
            cb(render_err)
          end)
        end
        mutation_in_progress = false
      end)
    )
  end)
end

return M
