local Trie = require('canola.mutator.trie')

local M = {}

---@param actions canola.Action[]
---@return canola.Action[]
M.enforce_action_order = function(actions)
  local src_trie = Trie.new()
  local dest_trie = Trie.new()
  for _, action in ipairs(actions) do
    if action.type == 'delete' or action.type == 'change' then
      src_trie:insert_action(action.url, action)
    elseif action.type == 'create' then
      dest_trie:insert_action(action.url, action)
    else
      dest_trie:insert_action(action.dest_url, action)
      src_trie:insert_action(action.src_url, action)
    end
  end

  -- 1. create a graph, each node points to all of its dependencies
  -- 2. for each action, if not added, find it in the graph
  -- 3. traverse through the graph until you reach a node that has no dependencies (leaf)
  -- 4. append that action to the return value, and remove it from the graph
  --   a. TODO optimization: check immediate parents to see if they have no dependencies now
  -- 5. repeat

  ---Gets the dependencies of a particular action. Effectively dynamically calculates the dependency
  ---"edges" of the graph.
  ---@param action canola.Action
  local function get_deps(action)
    local ret = {}
    if action.type == 'delete' then
      src_trie:accum_children_of(action.url, ret)
    elseif action.type == 'create' then
      -- Finish operating on parents first
      -- e.g. NEW /a BEFORE NEW /a/b
      dest_trie:accum_first_parents_of(action.url, ret)
      -- Process remove path before creating new path
      -- e.g. DELETE /a BEFORE NEW /a
      src_trie:accum_actions_at(action.url, ret, function(a)
        return a.type == 'move' or a.type == 'delete'
      end)
    elseif action.type == 'change' then
      -- Finish operating on parents first
      -- e.g. NEW /a BEFORE CHANGE /a/b
      dest_trie:accum_first_parents_of(action.url, ret)
      -- Finish operations on this path first
      -- e.g. NEW /a BEFORE CHANGE /a
      dest_trie:accum_actions_at(action.url, ret)
      -- Finish copy from operations first
      -- e.g. COPY /a -> /b BEFORE CHANGE /a
      src_trie:accum_actions_at(action.url, ret, function(entry)
        return entry.type == 'copy'
      end)
    elseif action.type == 'move' then
      -- Finish operating on parents first
      -- e.g. NEW /a BEFORE MOVE /z -> /a/b
      dest_trie:accum_first_parents_of(action.dest_url, ret)
      -- Process children before moving
      -- e.g. NEW /a/b BEFORE MOVE /a -> /b
      dest_trie:accum_children_of(action.src_url, ret)
      -- Process children before moving parent dir
      -- e.g. COPY /a/b -> /b BEFORE MOVE /a -> /d
      -- e.g. CHANGE /a/b BEFORE MOVE /a -> /d
      src_trie:accum_children_of(action.src_url, ret)
      -- Process remove path before moving to new path
      -- e.g. MOVE /a -> /b BEFORE MOVE /c -> /a
      src_trie:accum_actions_at(action.dest_url, ret, function(a)
        return a.type == 'move' or a.type == 'delete'
      end)
    elseif action.type == 'copy' then
      -- Finish operating on parents first
      -- e.g. NEW /a BEFORE COPY /z -> /a/b
      dest_trie:accum_first_parents_of(action.dest_url, ret)
      -- Process children before copying
      -- e.g. NEW /a/b BEFORE COPY /a -> /b
      dest_trie:accum_children_of(action.src_url, ret)
      -- Process remove path before copying to new path
      -- e.g. MOVE /a -> /b BEFORE COPY /c -> /a
      src_trie:accum_actions_at(action.dest_url, ret, function(a)
        return a.type == 'move' or a.type == 'delete'
      end)
    end
    return ret
  end

  ---@return nil|canola.Action The leaf action
  ---@return nil|canola.Action When no leaves found, this is the last action in the loop
  local function find_leaf(action, seen)
    if not seen then
      seen = {}
    elseif seen[action] then
      return nil, action
    end
    seen[action] = true
    local deps = get_deps(action)
    if next(deps) == nil then
      return action
    end
    local action_in_loop
    for _, dep in ipairs(deps) do
      local leaf, loop_action = find_leaf(dep, seen)
      if leaf then
        return leaf
      elseif not action_in_loop and loop_action then
        action_in_loop = loop_action
      end
    end
    return nil, action_in_loop
  end

  local ret = {}
  local after = {}
  while next(actions) ~= nil do
    local action = actions[1]
    local selected, loop_action = find_leaf(action)
    local to_remove
    if selected then
      to_remove = selected
    else
      if loop_action and loop_action.type == 'move' then
        -- If this is moving a parent into itself, that's an error
        if vim.startswith(loop_action.dest_url, loop_action.src_url) then
          error('Detected cycle in desired paths')
        end

        -- We've detected a move cycle (e.g. MOVE /a -> /b + MOVE /b -> /a)
        -- Split one of the moves and retry
        local intermediate_url =
          string.format('%s__oil_tmp_%05d', loop_action.src_url, math.random(999999))
        local move_1 = {
          type = 'move',
          entry_type = loop_action.entry_type,
          src_url = loop_action.src_url,
          dest_url = intermediate_url,
        }
        local move_2 = {
          type = 'move',
          entry_type = loop_action.entry_type,
          src_url = intermediate_url,
          dest_url = loop_action.dest_url,
        }
        to_remove = loop_action
        table.insert(actions, move_1)
        table.insert(after, move_2)
        dest_trie:insert_action(move_1.dest_url, move_1)
        src_trie:insert_action(move_1.src_url, move_1)
      else
        error('Detected cycle in desired paths')
      end
    end

    if selected then
      if selected.type == 'move' or selected.type == 'copy' then
        if vim.startswith(selected.dest_url, selected.src_url .. '/') then
          error(
            string.format(
              'Cannot move or copy parent into itself: %s -> %s',
              selected.src_url,
              selected.dest_url
            )
          )
        end
      end
      table.insert(ret, selected)
    end

    if to_remove then
      if to_remove.type == 'delete' or to_remove.type == 'change' then
        src_trie:remove_action(to_remove.url, to_remove)
      elseif to_remove.type == 'create' then
        dest_trie:remove_action(to_remove.url, to_remove)
      else
        dest_trie:remove_action(to_remove.dest_url, to_remove)
        src_trie:remove_action(to_remove.src_url, to_remove)
      end
      for i, a in ipairs(actions) do
        if a == to_remove then
          table.remove(actions, i)
          break
        end
      end
    end
  end

  vim.list_extend(ret, after)
  return ret
end

return M
