local M = {}

local default_buf = { buflisted = false, bufhidden = 'hide' }
local default_win = {
  wrap = false,
  signcolumn = 'no',
  cursorcolumn = false,
  foldcolumn = '0',
  spell = false,
  list = false,
  conceallevel = 3,
  concealcursor = 'nvic',
}

local sort_presets = {
  ['type,asc|name,asc'] = 'default',
  ['name,asc'] = 'name',
  ['mtime,desc|name,asc'] = 'modified',
  ['size,desc|name,asc'] = 'size',
}

local removed_defaults = {
  default_file_explorer = true,
  use_default_keymaps = true,
  cleanup_delay_ms = 2000,
  extra_scp_args = {},
  extra_s3_args = {},
  ssh_hosts = {},
  s3_buckets = {},
}

local function indent(s, level)
  return string.rep('  ', level) .. s
end

local function is_default_table(a, b)
  if type(a) ~= 'table' or type(b) ~= 'table' then
    return a == b
  end
  for k, v in pairs(a) do
    if not is_default_table(v, b[k]) then
      return false
    end
  end
  for k, v in pairs(b) do
    if not is_default_table(a[k], v) then
      return false
    end
  end
  return true
end

local function serialize(val, level)
  level = level or 0
  if val == nil then
    return 'nil'
  elseif type(val) == 'string' then
    return string.format('%q', val)
  elseif type(val) == 'number' or type(val) == 'boolean' then
    return tostring(val)
  elseif type(val) == 'function' then
    return nil
  elseif type(val) == 'table' then
    if vim.islist(val) then
      local items = {}
      for _, v in ipairs(val) do
        local s = serialize(v, level + 1)
        if s then
          table.insert(items, s)
        end
      end
      if #items == 0 then
        return '{}'
      end
      local oneline = '{ ' .. table.concat(items, ', ') .. ' }'
      if #oneline < 60 then
        return oneline
      end
      local lines = { '{' }
      for _, item in ipairs(items) do
        table.insert(lines, indent(item .. ',', level + 1))
      end
      table.insert(lines, indent('}', level))
      return table.concat(lines, '\n')
    else
      local keys = {}
      for k in pairs(val) do
        table.insert(keys, k)
      end
      table.sort(keys, function(a, b)
        return tostring(a) < tostring(b)
      end)
      local items = {}
      for _, k in ipairs(keys) do
        local s = serialize(val[k], level + 1)
        if s then
          local key_str
          if type(k) == 'string' and k:match('^[%a_][%w_]*$') then
            key_str = k
          else
            key_str = '[' .. serialize(k, 0) .. ']'
          end
          table.insert(items, indent(key_str .. ' = ' .. s .. ',', level + 1))
        end
      end
      if #items == 0 then
        return '{}'
      end
      return '{\n' .. table.concat(items, '\n') .. '\n' .. indent('}', level)
    end
  end
  return tostring(val)
end

local function sort_key(sort_spec)
  local parts = {}
  for _, s in ipairs(sort_spec) do
    table.insert(parts, s[1] .. ',' .. s[2])
  end
  return table.concat(parts, '|')
end

local function migrate_keymaps(oil_keymaps)
  local canola = {}
  for key, val in pairs(oil_keymaps) do
    if val == false then
      canola[key] = false
    elseif type(val) == 'string' then
      canola[key] = val
    elseif type(val) == 'table' then
      local action = val[1] or val.callback
      if action then
        local entry = { callback = action }
        if val.opts then
          entry.opts = val.opts
        end
        if val.mode then
          entry.mode = val.mode
        end
        if val.desc then
          entry.desc = val.desc
        end
        canola[key] = entry
      end
    end
  end
  return canola
end

local function is_default_override(fn)
  local sentinel = { _test = true }
  local ok, result = pcall(fn, sentinel)
  return ok and result == sentinel
end

local function is_default_predicate(fn, ...)
  local ok, result = pcall(fn, ...)
  return ok and result == false
end

local function is_default_hidden(fn)
  local ok1, r1 = pcall(fn, '.hidden', 0)
  local ok2, r2 = pcall(fn, 'visible', 0)
  return ok1 and r1 == true and ok2 and r2 == false
end

local function is_default_git(git)
  if not git then
    return true
  end
  local a = type(git.add) ~= 'function' or is_default_predicate(git.add, '/tmp/test')
  local m = type(git.mv) ~= 'function' or is_default_predicate(git.mv, '/tmp/a', '/tmp/b')
  local r = type(git.rm) ~= 'function' or is_default_predicate(git.rm, '/tmp/test')
  return a and m and r
end

M.generate = function()
  local cfg = require('oil.config')
  local out = {}
  local hooks = {}
  local removed = {}
  local adapters = {}

  out.columns = cfg.columns

  if cfg.constrain_cursor == 'editable' or cfg.constrain_cursor == 'name' then
    out.cursor = true
  elseif cfg.constrain_cursor == false then
    out.cursor = false
  end

  out.watch = cfg.watch_for_changes or false

  if not is_default_table(cfg.view_options.sort, { { 'type', 'asc' }, { 'name', 'asc' } }) then
    local key = sort_key(cfg.view_options.sort)
    local preset = sort_presets[key]
    if preset then
      out.sort = preset
    else
      out.sort = {
        by = cfg.view_options.sort,
        natural = cfg.view_options.natural_order,
        ignore_case = cfg.view_options.case_insensitive,
      }
    end
  end

  local hidden = {}
  if cfg.view_options.show_hidden then
    hidden.enabled = false
  else
    hidden.enabled = true
  end
  out.hidden = hidden

  if cfg.skip_confirm_for_simple_edits and cfg.skip_confirm_for_delete then
    out.confirm = false
  elseif cfg.skip_confirm_for_simple_edits then
    out.confirm = 'delete'
  end

  if cfg.auto_save_on_select_new_entry then
    out.save = 'auto'
  elseif not cfg.prompt_save_on_select_new_entry then
    out.save = false
  end

  local delete = {}
  if cfg.cleanup_buffers_on_delete then
    delete.wipe = true
  end
  if next(delete) then
    out.delete = delete
  end

  if cfg.new_file_mode ~= 420 or cfg.new_dir_mode ~= 493 then
    out.create = { file_mode = cfg.new_file_mode, dir_mode = cfg.new_dir_mode }
  end

  local lsp = {}
  if not cfg.lsp_file_methods.enabled then
    lsp.enabled = false
  end
  if cfg.lsp_file_methods.timeout_ms ~= 1000 then
    lsp.timeout_ms = cfg.lsp_file_methods.timeout_ms
  end
  if cfg.lsp_file_methods.autosave_changes then
    lsp.autosave = cfg.lsp_file_methods.autosave_changes
  end
  if next(lsp) then
    out.lsp = lsp
  end

  local keymaps = migrate_keymaps(cfg.keymaps)
  local default_keys = {
    ['g?'] = true,
    ['<CR>'] = true,
    ['<C-s>'] = true,
    ['<C-h>'] = true,
    ['<C-t>'] = true,
    ['<C-p>'] = true,
    ['<C-c>'] = true,
    ['<C-l>'] = true,
    ['-'] = true,
    ['_'] = true,
    ['`'] = true,
    ['g~'] = true,
    ['gs'] = true,
    ['gx'] = true,
    ['g.'] = true,
    ['g\\'] = true,
  }
  local custom_keymaps = {}
  for k, v in pairs(keymaps) do
    if not default_keys[k] then
      custom_keymaps[k] = v
    end
  end
  for k, v in pairs(keymaps) do
    if default_keys[k] and v == false then
      custom_keymaps[k] = false
    end
  end
  if next(custom_keymaps) then
    out.keymaps = custom_keymaps
  end

  local float = {}
  if cfg.default_to_float then
    float.default = true
  end
  if cfg.float.padding ~= 2 then
    float.padding = cfg.float.padding
  end
  if cfg.float.max_width ~= 0 then
    float.max_width = cfg.float.max_width
  end
  if cfg.float.max_height ~= 0 then
    float.max_height = cfg.float.max_height
  end
  if cfg.float.border then
    float.border = cfg.float.border
  end
  if cfg.float.preview_split ~= 'auto' then
    float.preview_split = cfg.float.preview_split
  end
  if not is_default_table(cfg.float.win_options, { winblend = 0 }) then
    float.win = cfg.float.win_options
  end
  if next(float) then
    out.float = float
  end

  local preview = {}
  if not cfg.preview_win.update_on_cursor_moved then
    preview.follow = false
  end
  if cfg.preview_win.preview_method == 'load' then
    preview.live = true
  end
  if cfg.preview_win.max_file_size ~= 10 then
    preview.max_file_size_mb = cfg.preview_win.max_file_size
  end
  if not is_default_table(cfg.preview_win.win_options, {}) then
    preview.win = cfg.preview_win.win_options
  end
  if next(preview) then
    out.preview = preview
  end

  if not is_default_table(cfg.buf_options, default_buf) then
    out.buf = cfg.buf_options
  end

  if not is_default_table(cfg.win_options, default_win) then
    out.win = cfg.win_options
  end

  local confirmation = {}
  if cfg.confirmation.max_width ~= 0.9 then
    confirmation.max_width = cfg.confirmation.max_width
  end
  if not is_default_table(cfg.confirmation.min_width, { 40, 0.4 }) then
    confirmation.min_width = cfg.confirmation.min_width
  end
  if cfg.confirmation.width then
    confirmation.width = cfg.confirmation.width
  end
  if cfg.confirmation.max_height ~= 0.9 then
    confirmation.max_height = cfg.confirmation.max_height
  end
  if not is_default_table(cfg.confirmation.min_height, { 5, 0.1 }) then
    confirmation.min_height = cfg.confirmation.min_height
  end
  if cfg.confirmation.height then
    confirmation.height = cfg.confirmation.height
  end
  if cfg.confirmation.border then
    confirmation.border = cfg.confirmation.border
  end
  if not is_default_table(cfg.confirmation.win_options, { winblend = 0 }) then
    confirmation.win = cfg.confirmation.win_options
  end
  if next(confirmation) then
    out.confirmation = confirmation
  end

  local progress = {}
  if cfg.progress.max_width ~= 0.9 then
    progress.max_width = cfg.progress.max_width
  end
  if not is_default_table(cfg.progress.min_width, { 40, 0.4 }) then
    progress.min_width = cfg.progress.min_width
  end
  if cfg.progress.width then
    progress.width = cfg.progress.width
  end
  if not is_default_table(cfg.progress.max_height, { 10, 0.9 }) then
    progress.max_height = cfg.progress.max_height
  end
  if not is_default_table(cfg.progress.min_height, { 5, 0.1 }) then
    progress.min_height = cfg.progress.min_height
  end
  if cfg.progress.height then
    progress.height = cfg.progress.height
  end
  if cfg.progress.border then
    progress.border = cfg.progress.border
  end
  if cfg.progress.minimized_border ~= 'none' then
    progress.minimized_border = cfg.progress.minimized_border
  end
  if not is_default_table(cfg.progress.win_options, { winblend = 0 }) then
    progress.win = cfg.progress.win_options
  end
  if next(progress) then
    out.progress = progress
  end

  if type(cfg.float.override) == 'function' and not is_default_override(cfg.float.override) then
    table.insert(hooks, {
      name = 'float.override',
      before = [[float = {
  override = function(conf)
    -- your customizations
    return conf
  end,
}]],
      after = [[vim.api.nvim_create_autocmd("User", {
  pattern = "CanolaFloatConfig",
  callback = function(args)
    local conf = args.data.conf
    -- mutate conf directly, no return needed
  end,
})]],
    })
  end

  if type(cfg.float.get_win_title) == 'function' then
    table.insert(hooks, {
      name = 'float.get_win_title',
      before = [[float = {
  get_win_title = function(winid)
    return "my title"
  end,
}]],
      after = [[vim.api.nvim_create_autocmd("User", {
  pattern = "CanolaWinTitle",
  callback = function(args)
    args.data.title = "my title"
  end,
})]],
    })
  end

  if
    type(cfg.preview_win.disable_preview) == 'function'
    and not is_default_predicate(cfg.preview_win.disable_preview, '/tmp/test.txt')
  then
    table.insert(hooks, {
      name = 'preview_win.disable_preview',
      before = [[preview_win = {
  disable_preview = function(filename)
    return filename:match("%.pdf$")
  end,
}]],
      after = [[vim.api.nvim_create_autocmd("User", {
  pattern = "CanolaPreviewDisable",
  callback = function(args)
    if args.data.filename:match("%.pdf$") then
      args.data.result = true
    end
  end,
})]],
    })
  end

  if
    type(cfg.view_options.is_hidden_file) == 'function'
    and not is_default_hidden(cfg.view_options.is_hidden_file)
  then
    table.insert(hooks, {
      name = 'view_options.is_hidden_file',
      before = [[view_options = {
  is_hidden_file = function(name, bufnr)
    -- your custom logic
  end,
}]],
      after = [[-- Option A: use Lua patterns in config
vim.g.canola = {
  hidden = { patterns = { "^%." } },
}

-- Option B: use the setter API for complex logic
require("canola").set_is_hidden_file(function(name, bufnr, entry)
  -- your custom logic
end)

-- Option C: use canola-git for git-aware hiding
-- Install canola-collection, it handles this automatically]],
    })
  end

  if
    type(cfg.view_options.is_always_hidden) == 'function'
    and not is_default_predicate(cfg.view_options.is_always_hidden, 'test', 0)
  then
    table.insert(hooks, {
      name = 'view_options.is_always_hidden',
      before = [[view_options = {
  is_always_hidden = function(name, bufnr)
    return name == ".DS_Store"
  end,
}]],
      after = [[vim.g.canola = {
  hidden = { always = { "^%.DS_Store$" } },
}]],
    })
  end

  if type(cfg.view_options.highlight_filename) == 'function' then
    table.insert(hooks, {
      name = 'view_options.highlight_filename',
      before = [[view_options = {
  highlight_filename = function(entry, is_hidden, is_link_target, is_link_orphan)
    if entry.name:match("%.lua$") then return "Special" end
  end,
}]],
      after = [[vim.g.canola = {
  highlights = {
    filename = {
      { "%.lua$", "Special" },
    },
  },
}]],
    })
  end

  if not is_default_git(cfg.git) then
    table.insert(hooks, {
      name = 'git.add/mv/rm',
      before = [[git = {
  add = function(path) return true end,
  mv = function(src, dest) return true end,
  rm = function(path) return true end,
}]],
      after = [[-- Install canola-collection and enable canola-git:
--   vim.g.canola_git = {}
-- Optional:
--   vim.g.canola = { columns = { "git_status" } }]],
    })
  end

  if cfg.delete_to_trash then
    table.insert(
      adapters,
      'delete_to_trash -> vim.g.canola_trash = {} (requires canola-collection)'
    )
  end
  if cfg.extra_scp_args and #cfg.extra_scp_args > 0 then
    table.insert(adapters, 'extra_scp_args -> configure via vim.g.canola_ssh in canola-collection')
  end
  if cfg.ssh_hosts and next(cfg.ssh_hosts) then
    table.insert(adapters, 'ssh_hosts -> configure via vim.g.canola_ssh.hosts in canola-collection')
  end
  if cfg.extra_s3_args and #cfg.extra_s3_args > 0 then
    table.insert(adapters, 'extra_s3_args -> configure via vim.g.canola_s3 in canola-collection')
  end
  if cfg.s3_buckets and next(cfg.s3_buckets) then
    table.insert(
      adapters,
      's3_buckets -> configure via vim.g.canola_s3.buckets in canola-collection'
    )
  end

  for key, default in pairs(removed_defaults) do
    if cfg[key] ~= nil and not is_default_table(cfg[key], default) then
      table.insert(removed, key)
    end
  end

  return out, hooks, removed, adapters
end

local function add(md, s)
  table.insert(md, s)
end

local function block(md, lines)
  add(md, '')
  add(md, '```lua')
  for _, l in ipairs(lines) do
    add(md, l)
  end
  add(md, '```')
end

M.print = function()
  local out, hooks, removed, adapters = M.generate()
  local md = {}
  local hook_map = {}
  for _, h in ipairs(hooks) do
    hook_map[h.name] = h
  end

  add(md, '# canola.nvim Migration')
  add(md, '')
  add(md, 'Generated from your live oil.nvim config.')
  add(md, '')
  add(md, '## Config')
  add(md, '')
  add(md, 'Paste this into your plugin config after switching to `branch = "canola"`:')
  block(md, { 'vim.g.canola = ' .. serialize(out, 0) })

  if next(hook_map) then
    add(md, '')
    add(md, '## Hook Replacements')
    add(md, '')
    add(md, 'canola replaces function-in-config options with User autocmd events.')
    add(md, 'You have the following custom hooks that need manual migration:')

    if hook_map['float.override'] then
      add(md, '')
      add(md, '### `float.override` → `CanolaFloatConfig`')
      block(md, {
        'vim.api.nvim_create_autocmd("User", {',
        '  pattern = "CanolaFloatConfig",',
        '  callback = function(args)',
        '    local conf = args.data.conf',
        '    -- move your override logic here',
        '    -- mutate conf directly, no return needed',
        '  end,',
        '})',
      })
    end

    if hook_map['float.get_win_title'] then
      add(md, '')
      add(md, '### `float.get_win_title` → `CanolaWinTitle`')
      block(md, {
        'vim.api.nvim_create_autocmd("User", {',
        '  pattern = "CanolaWinTitle",',
        '  callback = function(args)',
        '    args.data.title = "your title logic here"',
        '  end,',
        '})',
      })
    end

    if hook_map['preview_win.disable_preview'] then
      add(md, '')
      add(md, '### `preview_win.disable_preview` → `CanolaPreviewDisable`')
      block(md, {
        'vim.api.nvim_create_autocmd("User", {',
        '  pattern = "CanolaPreviewDisable",',
        '  callback = function(args)',
        '    if args.data.filename:match("%.pdf$") then',
        '      args.data.result = true',
        '    end',
        '  end,',
        '})',
      })
    end

    if hook_map['view_options.highlight_filename'] then
      add(md, '')
      add(md, '### `view_options.highlight_filename` → `highlights.filename`')
      block(md, {
        'vim.g.canola = {',
        '  highlights = {',
        '    filename = {',
        '      { "%.lua$", "Special" },',
        '      { "%.md$", "Identifier" },',
        '    },',
        '  },',
        '}',
      })
    end

    if hook_map['view_options.is_hidden_file'] then
      add(md, '')
      add(md, '### `view_options.is_hidden_file`')
      add(md, '')
      add(md, 'Declarative patterns:')
      block(md, {
        'vim.g.canola = {',
        '  hidden = { enabled = true, patterns = { "^%." } },',
        '}',
      })
      add(md, '')
      add(md, 'Function API for complex logic:')
      block(md, {
        'require("canola").set_is_hidden_file(function(name, bufnr, entry)',
        '  -- your custom logic here',
        'end)',
      })
      add(md, '')
      add(md, 'If your `is_hidden_file` was git-based, install `barrettruth/canola-collection`')
      add(md, 'and enable canola-git:')
      block(md, {
        'vim.g.canola_git = {}',
      })
    end

    if hook_map['view_options.is_always_hidden'] then
      add(md, '')
      add(md, '### `view_options.is_always_hidden` → `hidden.always`')
      block(md, {
        'vim.g.canola = {',
        '  hidden = { always = { "^%.DS_Store$", "^%.git$" } },',
        '}',
      })
    end

    if hook_map['git.add/mv/rm'] then
      add(md, '')
      add(md, '### `git.add/mv/rm` → canola-collection')
      add(md, '')
      add(md, 'canola does not support these config hooks directly.')
      add(md, 'If you relied on custom add/mv/rm behavior, migrate it manually.')
      add(md, 'If you only want git-aware hiding and the `git_status` column, install')
      add(md, '`barrettruth/canola-collection` and enable canola-git:')
      block(md, {
        'vim.g.canola_git = {}',
        'vim.g.canola = { columns = { "git_status" } }',
      })
    end
  end

  if #adapters > 0 then
    add(md, '')
    add(md, '## Adapters')
    add(md, '')
    add(md, 'Install `barrettruth/canola-collection` and configure:')
    add(md, '')
    for _, a in ipairs(adapters) do
      add(md, '- `' .. a .. '`')
    end
  end

  if #removed > 0 then
    add(md, '')
    add(md, '## Removed Options')
    add(md, '')
    add(md, 'You changed these from their defaults, but they have no canola equivalent:')
    add(md, '')
    for _, key in ipairs(removed) do
      add(md, '- `' .. key .. '`')
    end
    add(md, '')
    add(md, 'See `:h canola-migration-removed` for details.')
  end

  add(md, '')
  add(md, '## Next Steps')
  add(md, '')
  local step = 1
  add(md, step .. '. Set `branch = "canola"` in your plugin manager')
  step = step + 1
  add(md, step .. '. Replace `require("oil").setup({...})` with the config above')
  if next(hook_map) then
    step = step + 1
    add(md, step .. '. Add the autocmd replacements from Hook Replacements')
  end
  step = step + 1
  add(md, step .. '. See `:h canola-recipes` for new features (git, brace expansion, etc.)')
  add(md, '')
  add(md, 'Full reference: `:h canola-migration`')

  local text = table.concat(md, '\n')

  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, vim.split(text, '\n'))
  vim.bo[bufnr].filetype = 'markdown'
  vim.bo[bufnr].modifiable = false
  vim.cmd.split()
  vim.api.nvim_win_set_buf(0, bufnr)
end

return M
