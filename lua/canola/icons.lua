local M = {}

---@alias canola.IconProvider fun(type: string, name: string, conf: table?, ft: string?): (icon: string, hl: string)

--- Check for an icon provider and return a common icon provider API
---@return (canola.IconProvider)?
M.get_icon_provider = function()
  -- prefer mini.icons
  local _, mini_icons = pcall(require, 'mini.icons')
  -- selene: allow(global_usage)
  ---@diagnostic disable-next-line: undefined-field
  if _G.MiniIcons then
    return function(type, name, conf, ft)
      if ft then
        return mini_icons.get('filetype', ft)
      end
      return mini_icons.get(type == 'directory' and 'directory' or 'file', name)
    end
  end

  local has_nonicons, nonicons = pcall(require, 'nonicons')
  if has_nonicons and nonicons.get_icon then
    local has_devicons, devicons = pcall(require, 'nvim-web-devicons')
    if not has_devicons then
      devicons = nil
    end
    return function(type, name, conf, ft)
      if type == 'directory' then
        local icon, hl = nonicons.get('file-directory-fill')
        return icon or (conf and conf.directory or ''), hl or 'CanolaDirIcon'
      end
      if ft then
        local ft_icon, ft_hl = nonicons.get_icon_by_filetype(ft)
        if ft_icon then
          return ft_icon, ft_hl or 'CanolaFileIcon'
        end
      end
      local icon, hl = nonicons.get_icon(name)
      if icon then
        return icon, hl or 'CanolaFileIcon'
      end
      local fallback, fallback_hl = nonicons.get('file')
      return fallback or (conf and conf.default_file or ''), fallback_hl or 'CanolaFileIcon'
    end
  end

  local has_devicons, devicons = pcall(require, 'nvim-web-devicons')

  if not has_devicons then
    return
  end

  return function(type, name, conf, ft)
    if type == 'directory' then
      return conf and conf.directory or '', 'CanolaDirIcon'
    else
      if ft then
        local ft_icon, ft_hl = devicons.get_icon_by_filetype(ft)
        if ft_icon and ft_icon ~= '' then
          return ft_icon, ft_hl
        end
      end
      local icon, hl = devicons.get_icon(name)
      hl = hl or 'CanolaFileIcon'
      icon = icon or (conf and conf.default_file or '')
      return icon, hl
    end
  end
end

return M
