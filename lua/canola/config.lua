local sort_presets = {
  default = { { 'type', 'asc' }, { 'name', 'asc' } },
  name = { { 'name', 'asc' } },
  modified = { { 'mtime', 'desc' }, { 'name', 'asc' } },
  size = { { 'size', 'desc' }, { 'name', 'asc' } },
  extension = { { 'name', 'asc' } },
}

local default_keymaps = {
  ['g?'] = { callback = 'actions.show_help', mode = 'n' },
  ['<CR>'] = 'actions.select',
  ['<C-s>'] = { callback = 'actions.select', opts = { vertical = true } },
  ['<C-h>'] = { callback = 'actions.select', opts = { horizontal = true } },
  ['<C-t>'] = { callback = 'actions.select', opts = { tab = true } },
  ['<C-p>'] = 'actions.preview',
  ['<C-c>'] = { callback = 'actions.close', mode = 'n' },
  ['<C-l>'] = 'actions.refresh',
  ['-'] = { callback = 'actions.parent', mode = 'n' },
  ['_'] = { callback = 'actions.open_cwd', mode = 'n' },
  ['`'] = { callback = 'actions.cd', mode = 'n' },
  ['g~'] = { callback = 'actions.cd', opts = { scope = 'tab' }, mode = 'n' },
  ['gs'] = { callback = 'actions.change_sort', mode = 'n' },
  ['gx'] = 'actions.open_external',
  ['g.'] = { callback = 'actions.toggle_hidden', mode = 'n' },
  ['q'] = { callback = 'actions.close', mode = 'n' },
}

local default_config = {
  columns = { 'icon' },
  cursor = true,
  watch = false,
  border = nil,

  show_hidden = false,
  hidden = { patterns = { '^%.' }, always = {} },

  sort = 'default',
  highlights = {},

  confirm = true,
  save = 'prompt',
  delete = { wipe_buffers = false },
  create = { file_mode = 420, dir_mode = 493 },

  keymaps = {},

  lsp = { enabled = true, timeout_ms = 1000, autosave = false },

  float = {
    default = false,
    padding = 2,
    max_width = 0,
    max_height = 0,
    border = nil,
    preview_split = 'auto',
    win_options = { winblend = 0 },
  },

  preview = {
    follow = true,
    live = false,
    max_file_size_mb = 10,
    disable = {},
    win_options = {},
  },

  confirmation = {
    max_width = 0.9,
    min_width = { 40, 0.4 },
    width = nil,
    max_height = 0.9,
    min_height = { 5, 0.1 },
    height = nil,
    border = nil,
    win_options = { winblend = 0 },
  },

  progress = {
    max_width = 0.9,
    min_width = { 40, 0.4 },
    width = nil,
    max_height = { 10, 0.9 },
    min_height = { 5, 0.1 },
    height = nil,
    border = nil,
    minimized_border = 'none',
    win_options = { winblend = 0 },
  },

  buf_options = { buflisted = false, bufhidden = 'hide' },
  win_options = {
    wrap = false,
    signcolumn = 'no',
    cursorcolumn = false,
    foldcolumn = '0',
    spell = false,
    list = false,
    conceallevel = 3,
    concealcursor = 'nvic',
  },
}

---@class canola.Config
---@field adapters table<string, string>
---@field adapter_aliases table<string, string>
---@field columns canola.ColumnSpec[]
---@field cursor boolean
---@field watch boolean
---@field border? string|string[]
---@field show_hidden boolean
---@field hidden canola.HiddenConfig
---@field sort string|canola.SortConfig
---@field highlights canola.HighlightPattern[]
---@field confirm boolean|"delete"
---@field save "prompt"|"auto"|false
---@field delete canola.DeleteConfig
---@field create canola.CreateConfig
---@field keymaps table<string, any>
---@field lsp canola.LspConfig
---@field float canola.FloatConfig
---@field preview canola.PreviewConfig
---@field confirmation canola.ConfirmationWindowConfig
---@field progress canola.ProgressWindowConfig
---@field buf_options table<string, any>
---@field win_options table<string, any>
---@field _constrain_cursor false|"name"|"editable"
---@field _sort_spec canola.SortSpec[]
---@field _natural_order boolean|"fast"
---@field _case_insensitive boolean
---@field _is_hidden_file fun(name: string, bufnr: integer, entry: canola.Entry): boolean
---@field _is_always_hidden fun(name: string, bufnr: integer, entry: canola.Entry): boolean
---@field _disable_preview fun(filename: string): boolean
---@field _preview_method canola.PreviewMethod
---@field _preview_update_on_cursor_moved boolean
local M = {}

---@class (exact) canola.HiddenConfig
---@field patterns string[]
---@field always string[]

---@class (exact) canola.SortConfig
---@field by canola.SortSpec[]
---@field natural? boolean|"fast"
---@field ignore_case? boolean

---@alias canola.HighlightPattern { [1]: string, [2]: string }

---@class (exact) canola.DeleteConfig
---@field wipe_buffers boolean

---@class (exact) canola.CreateConfig
---@field file_mode integer
---@field dir_mode integer

---@class (exact) canola.LspConfig
---@field enabled boolean
---@field timeout_ms integer
---@field autosave boolean|"unmodified"

---@class (exact) canola.FloatConfig
---@field default boolean
---@field padding integer
---@field max_width integer
---@field max_height integer
---@field border? string|string[]
---@field preview_split "auto"|"left"|"right"|"above"|"below"
---@field win_options table<string, any>

---@class (exact) canola.PreviewConfig
---@field follow boolean
---@field live boolean
---@field max_file_size_mb? number
---@field disable string[]
---@field win_options table<string, any>

---@class (exact) canola.SortSpec
---@field [1] string
---@field [2] "asc"|"desc"

---@class (exact) canola.WindowDimensionDualConstraint
---@field [1] number
---@field [2] number

---@alias canola.WindowDimension number|canola.WindowDimensionDualConstraint

---@class (exact) canola.WindowConfig
---@field max_width canola.WindowDimension
---@field min_width canola.WindowDimension
---@field width? number
---@field max_height canola.WindowDimension
---@field min_height canola.WindowDimension
---@field height? number
---@field border? string|string[]
---@field win_options table<string, any>

---@alias canola.PreviewMethod
---| '"load"'
---| '"scratch"'
---| '"fast_scratch"'

---@class (exact) canola.ConfirmationWindowConfig : canola.WindowConfig

---@class (exact) canola.ProgressWindowConfig : canola.WindowConfig
---@field minimized_border string|string[]

---@param patterns string[]
---@return fun(name: string, bufnr: integer, entry: canola.Entry): boolean
local function compile_hidden_patterns(patterns)
  if #patterns == 0 then
    return function()
      return false
    end
  end
  return function(name, bufnr, entry)
    for _, pat in ipairs(patterns) do
      if name:match(pat) then
        return true
      end
    end
    return false
  end
end

---@param disable_list string[]
---@return fun(filename: string): boolean
local function compile_disable_preview(disable_list)
  if #disable_list == 0 then
    return function()
      return false
    end
  end
  return function(filename)
    for _, pat in ipairs(disable_list) do
      if filename:match(pat) then
        return true
      end
    end
    return false
  end
end

---@param sort_input string|canola.SortConfig
---@return canola.SortSpec[], boolean|"fast", boolean
local function resolve_sort(sort_input)
  local natural = 'fast' ---@type boolean|"fast"
  local case_insensitive = false
  local spec

  if type(sort_input) == 'string' then
    spec = sort_presets[sort_input]
    if not spec then
      vim.notify_once(
        string.format("[canola] Unknown sort preset '%s', using 'default'", sort_input),
        vim.log.levels.WARN
      )
      spec = sort_presets.default
    end
  elseif type(sort_input) == 'table' then
    spec = sort_input.by or sort_presets.default
    if sort_input.natural ~= nil then
      natural = sort_input.natural --[[@as boolean|"fast"]]
    end
    if sort_input.ignore_case ~= nil then
      case_insensitive = sort_input.ignore_case --[[@as boolean]]
    end
  else
    spec = sort_presets.default
  end

  return spec, natural, case_insensitive
end

local canola_s3_string = vim.fn.has('nvim-0.12') == 1 and 'canola-s3://' or 'canola-sss://'
local default_adapters = {
  ['canola://'] = 'files',
  ['canola-ssh://'] = 'ssh',
  [canola_s3_string] = 's3',
  ['canola-ftp://'] = 'ftp',
  ['canola-ftps://'] = 'ftps',
}

M.init = function()
  local opts = vim.g.canola or {}

  local new_conf = vim.tbl_deep_extend('keep', opts, default_config)

  local user_keymaps = opts.keymaps or {}
  new_conf.keymaps = vim.tbl_deep_extend('keep', {}, default_keymaps)
  for k, v in pairs(user_keymaps) do
    local normalized = vim.api.nvim_replace_termcodes(k, true, true, true)
    for existing_k, _ in pairs(new_conf.keymaps) do
      if
        existing_k ~= k
        and vim.api.nvim_replace_termcodes(existing_k, true, true, true) == normalized
      then
        new_conf.keymaps[existing_k] = nil
      end
    end
    new_conf.keymaps[k] = v
  end

  new_conf.adapters = vim.tbl_deep_extend('keep', opts.adapters or {}, default_adapters)
  new_conf.adapter_aliases = opts.adapter_aliases or {}

  for k, v in pairs(new_conf) do
    M[k] = v
  end

  M._constrain_cursor = new_conf.cursor and 'editable' or false

  local sort_spec, natural, case_insensitive = resolve_sort(new_conf.sort)
  M._sort_spec = sort_spec
  M._natural_order = natural
  M._case_insensitive = case_insensitive

  M._is_hidden_file = compile_hidden_patterns(new_conf.hidden.patterns)
  M._is_always_hidden = compile_hidden_patterns(new_conf.hidden.always)

  M._disable_preview = compile_disable_preview(new_conf.preview.disable)

  M._preview_method = new_conf.preview.live and 'load' or 'fast_scratch'
  M._preview_update_on_cursor_moved = new_conf.preview.follow

  if new_conf.confirmation.border == nil then
    new_conf.confirmation.border = new_conf.border
    M.confirmation = new_conf.confirmation
  end
  if new_conf.progress.border == nil then
    new_conf.progress.border = new_conf.border
    M.progress = new_conf.progress
  end
  if new_conf.float.border == nil then
    new_conf.float.border = new_conf.border
    M.float = new_conf.float
  end

  M.adapter_to_scheme = {}
  for k, v in pairs(M.adapters) do
    M.adapter_to_scheme[v] = k
  end
  M._adapter_by_scheme = {}
end

---@param scheme nil|string
---@return nil|canola.Adapter
M.get_adapter_by_scheme = function(scheme)
  if not scheme then
    return nil
  end
  if not vim.endswith(scheme, '://') then
    local pieces = vim.split(scheme, '://', { plain = true })
    if #pieces <= 2 then
      scheme = pieces[1] .. '://'
    else
      error(string.format("Malformed url: '%s'", scheme))
    end
  end
  local adapter = M._adapter_by_scheme[scheme]
  if adapter == nil then
    local name = M.adapters[scheme]
    if not name then
      return nil
    end
    local ok
    ok, adapter = pcall(require, string.format('canola.adapters.%s', name))
    if ok then
      adapter.name = name
      M._adapter_by_scheme[scheme] = adapter
    else
      M._adapter_by_scheme[scheme] = false
      adapter = false
    end
  end
  if adapter then
    return adapter
  else
    return nil
  end
end

return M
