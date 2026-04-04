local action_ordering = require('canola.mutator.action_ordering')
local cache = require('canola.cache')
local config = require('canola.config')
local constants = require('canola.constants')
local fs = require('canola.fs')
local util = require('canola.util')

local M = {}

---@alias canola.Action canola.CreateAction|canola.DeleteAction|canola.MoveAction|canola.CopyAction|canola.ChangeAction

---@class (exact) canola.CreateAction
---@field type "create"
---@field url string
---@field entry_type canola.EntryType
---@field link nil|string

---@class (exact) canola.DeleteAction
---@field type "delete"
---@field url string
---@field entry_type canola.EntryType

---@class (exact) canola.MoveAction
---@field type "move"
---@field entry_type canola.EntryType
---@field src_url string
---@field dest_url string

---@class (exact) canola.CopyAction
---@field type "copy"
---@field entry_type canola.EntryType
---@field src_url string
---@field dest_url string

---@class (exact) canola.ChangeAction
---@field type "change"
---@field entry_type canola.EntryType
---@field url string
---@field column string
---@field value any

local FIELD_NAME = constants.FIELD_NAME
local FIELD_TYPE = constants.FIELD_TYPE

local EXTGLOB_HARD_CAP = 10000

---@param name string
---@return string[][]
local function expand_path_segments(name)
  local extglob_setting = config.extglob
  local path_sep = fs.is_windows and '[/\\]' or '/'
  local segments = vim.split(name, path_sep)

  if extglob_setting == false then
    return { segments }
  end

  local extglob = require('canola.extglob')
  local expanded_segments = {}
  for _, seg in ipairs(segments) do
    table.insert(expanded_segments, extglob.expand(seg))
  end

  local results = { {} }
  for _, alternatives in ipairs(expanded_segments) do
    local new_results = {}
    for _, partial in ipairs(results) do
      for _, alt in ipairs(alternatives) do
        local new = vim.list_extend({}, partial)
        table.insert(new, alt)
        table.insert(new_results, new)
      end
    end
    results = new_results
    if #results > EXTGLOB_HARD_CAP then
      vim.notify(
        string.format(
          '[canola] Brace expansion exceeds hard cap of %d entries, aborting',
          EXTGLOB_HARD_CAP
        ),
        vim.log.levels.ERROR
      )
      return { segments }
    end
  end

  if type(extglob_setting) == 'number' and #results > extglob_setting then
    local choice = vim.fn.confirm(
      string.format('Brace expansion will create %d entries. Continue?', #results),
      '&Yes\n&No',
      2
    )
    if choice ~= 1 then
      return { segments }
    end
  end

  return results
end

---@param all_diffs table<integer, canola.Diff[]>
---@return canola.Action[]
M.create_actions_from_diffs = function(all_diffs)
  ---@type canola.Action[]
  local actions = {}

  ---@type table<integer, canola.Diff[]>
  local diff_by_id = setmetatable({}, {
    __index = function(t, key)
      local list = {}
      rawset(t, key, list)
      return list
    end,
  })

  -- To deduplicate create actions
  -- This can happen when creating deep nested files e.g.
  -- > foo/bar/a.txt
  -- > foo/bar/b.txt
  local seen_creates = {}

  ---@param action canola.Action
  local function add_action(action)
    local adapter = assert(config.get_adapter_by_scheme(action.dest_url or action.url))
    if not adapter.filter_action or adapter.filter_action(action) then
      if action.type == 'create' then
        if seen_creates[action.url] then
          return
        else
          seen_creates[action.url] = true
        end
      end

      table.insert(actions, action)
    end
  end
  for bufnr, diffs in pairs(all_diffs) do
    local adapter = util.get_adapter(bufnr, true)
    if not adapter then
      error('Missing adapter')
    end
    local parent_url = vim.api.nvim_buf_get_name(bufnr)
    for _, diff in ipairs(diffs) do
      if diff.type == 'new' then
        if diff.id then
          local expanded_names = expand_path_segments(diff.name)
          for _, segments in ipairs(expanded_names) do
            local expanded_name = table.concat(segments, '/')
            local cloned = vim.deepcopy(diff)
            local by_id = diff_by_id[diff.id]
            ---HACK: set the destination on this diff for use later
            ---@diagnostic disable-next-line: inject-field
            cloned.dest = parent_url .. expanded_name
            ---@diagnostic disable-next-line: inject-field
            cloned._segments = segments
            ---@diagnostic disable-next-line: inject-field
            cloned._parent_url = parent_url
            table.insert(by_id, cloned)
          end
        else
          local expanded_paths = expand_path_segments(diff.name)
          for _, segments in ipairs(expanded_paths) do
            local url = parent_url:gsub('/$', '')
            for i, seg in ipairs(segments) do
              local is_last = i == #segments
              local entry_type = is_last and diff.entry_type or 'directory'
              url = url .. '/' .. seg
              add_action({
                type = 'create',
                url = url,
                entry_type = entry_type,
                link = is_last and diff.link or nil,
              })
            end
          end
        end
      elseif diff.type == 'change' then
        add_action({
          type = 'change',
          url = parent_url .. diff.name,
          entry_type = diff.entry_type,
          column = diff.column,
          value = diff.value,
        })
      else
        local by_id = diff_by_id[diff.id]
        -- HACK: set has_delete field on a list-like table of diffs
        ---@diagnostic disable-next-line: inject-field
        by_id.has_delete = true
        -- Don't insert the delete. We already know that there is a delete because of the presence
        -- in the diff_by_id map. The list will only include the 'new' diffs.
      end
    end
  end

  for id, diffs in pairs(diff_by_id) do
    local entry = cache.get_entry_by_id(id)
    if not entry then
      error(string.format('Could not find entry %d', id))
    end
    ---HACK: access the has_delete field on the list-like table of diffs
    ---@diagnostic disable-next-line: undefined-field
    if diffs.has_delete then
      local has_create = #diffs > 0
      if has_create then
        -- MOVE (+ optional copies) when has both creates and delete
        for i, diff in ipairs(diffs) do
          ---@diagnostic disable-next-line: undefined-field
          if diff._segments and #diff._segments > 1 then
            ---@diagnostic disable-next-line: undefined-field
            local url = diff._parent_url:gsub('/$', '')
            ---@diagnostic disable-next-line: undefined-field
            for j = 1, #diff._segments - 1 do
              ---@diagnostic disable-next-line: undefined-field
              url = url .. '/' .. diff._segments[j]
              add_action({ type = 'create', url = url, entry_type = 'directory' })
            end
          end
          add_action({
            type = i == #diffs and 'move' or 'copy',
            entry_type = entry[FIELD_TYPE],
            ---HACK: access the dest field we set above
            ---@diagnostic disable-next-line: undefined-field
            dest_url = diff.dest,
            src_url = cache.get_parent_url(id) .. entry[FIELD_NAME],
          })
        end
      else
        -- DELETE when no create
        add_action({
          type = 'delete',
          entry_type = entry[FIELD_TYPE],
          url = cache.get_parent_url(id) .. entry[FIELD_NAME],
        })
      end
    else
      -- COPY when create but no delete
      for _, diff in ipairs(diffs) do
        ---@diagnostic disable-next-line: undefined-field
        if diff._segments and #diff._segments > 1 then
          ---@diagnostic disable-next-line: undefined-field
          local url = diff._parent_url:gsub('/$', '')
          ---@diagnostic disable-next-line: undefined-field
          for j = 1, #diff._segments - 1 do
            ---@diagnostic disable-next-line: undefined-field
            url = url .. '/' .. diff._segments[j]
            add_action({ type = 'create', url = url, entry_type = 'directory' })
          end
        end
        add_action({
          type = 'copy',
          entry_type = entry[FIELD_TYPE],
          src_url = cache.get_parent_url(id) .. entry[FIELD_NAME],
          ---HACK: access the dest field we set above
          ---@diagnostic disable-next-line: undefined-field
          dest_url = diff.dest,
        })
      end
    end
  end

  return action_ordering.enforce_action_order(actions)
end

return M
