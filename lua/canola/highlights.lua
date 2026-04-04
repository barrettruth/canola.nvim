local M = {}

M._get_highlights = function()
  return {
    {
      name = 'CanolaEmpty',
      link = 'Comment',
      desc = 'Empty column values',
    },
    {
      name = 'CanolaHidden',
      link = 'Comment',
      desc = 'Hidden entry in an oil buffer',
    },
    {
      name = 'CanolaDir',
      terminal_color = 4,
      bold = true,
      desc = 'Directory names in an oil buffer',
    },
    {
      name = 'CanolaDirHidden',
      link = 'CanolaHidden',
      desc = 'Hidden directory names in an oil buffer',
    },
    {
      name = 'CanolaDirIcon',
      link = 'CanolaDir',
      desc = 'Icon for directories',
    },
    {
      name = 'CanolaFileIcon',
      link = nil,
      desc = 'Icon for files',
    },
    {
      name = 'CanolaSocket',
      terminal_color = 5,
      bold = true,
      desc = 'Socket files in an oil buffer',
    },
    {
      name = 'CanolaSocketHidden',
      link = 'CanolaHidden',
      desc = 'Hidden socket files in an oil buffer',
    },
    {
      name = 'CanolaLink',
      terminal_color = 6,
      bold = true,
      desc = 'Soft links in an oil buffer',
    },
    {
      name = 'CanolaOrphanLink',
      link = 'DiagnosticError',
      bold = true,
      desc = 'Arrow separator for orphaned soft links',
    },
    {
      name = 'CanolaLinkHidden',
      link = 'CanolaHidden',
      desc = 'Hidden soft links in an oil buffer',
    },
    {
      name = 'CanolaOrphanLinkHidden',
      link = 'CanolaLinkHidden',
      desc = 'Hidden orphaned soft links in an oil buffer',
    },
    {
      name = 'CanolaLinkTarget',
      link = 'Comment',
      desc = 'The target of a soft link',
    },
    {
      name = 'CanolaOrphanLinkTarget',
      link = 'DiagnosticError',
      bold = true,
      underline = true,
      desc = 'The target of an orphaned soft link',
    },
    {
      name = 'CanolaLinkTargetHidden',
      link = 'CanolaHidden',
      desc = 'The target of a hidden soft link',
    },
    {
      name = 'CanolaOrphanLinkTargetHidden',
      link = 'CanolaOrphanLinkTarget',
      desc = 'The target of an hidden orphaned soft link',
    },
    {
      name = 'CanolaLinkArrow',
      terminal_color = 8,
      bold = true,
      desc = 'The arrow separator (-> ) between a soft link and its target',
    },
    {
      name = 'CanolaLinkArrowHidden',
      link = 'CanolaHidden',
      desc = 'Hidden arrow separator for soft links',
    },
    {
      name = 'CanolaLinkPath',
      terminal_color = 6,
      bold = true,
      desc = 'The directory prefix of a soft link target path',
    },
    {
      name = 'CanolaLinkPathHidden',
      link = 'CanolaHidden',
      desc = 'Hidden directory prefix of a soft link target path',
    },
    {
      name = 'CanolaFile',
      link = nil,
      desc = 'Normal files in an oil buffer',
    },
    {
      name = 'CanolaFileHidden',
      link = 'CanolaHidden',
      desc = 'Hidden normal files in an oil buffer',
    },
    {
      name = 'CanolaExecutable',
      terminal_color = 2,
      bold = true,
      desc = 'Executable files in an oil buffer',
    },
    {
      name = 'CanolaExecutableHidden',
      link = 'CanolaHidden',
      desc = 'Hidden executable files in an oil buffer',
    },
    {
      name = 'CanolaCreate',
      link = 'DiagnosticInfo',
      desc = 'Create action in the oil preview window',
    },
    {
      name = 'CanolaDelete',
      link = 'DiagnosticError',
      desc = 'Delete action in the oil preview window',
    },
    {
      name = 'CanolaMove',
      link = 'DiagnosticWarn',
      desc = 'Move action in the oil preview window',
    },
    {
      name = 'CanolaCopy',
      link = 'DiagnosticHint',
      desc = 'Copy action in the oil preview window',
    },
    {
      name = 'CanolaChange',
      link = 'Special',
      desc = 'Change action in the oil preview window',
    },
    {
      name = 'CanolaPermUserRead',
      terminal_color = 3,
      bold = true,
      desc = 'User read permission',
    },
    {
      name = 'CanolaPermUserWrite',
      terminal_color = 1,
      bold = true,
      desc = 'User write permission',
    },
    {
      name = 'CanolaPermUserExec',
      terminal_color = 2,
      bold = true,
      desc = 'User execute permission',
    },
    {
      name = 'CanolaPermGroupRead',
      terminal_color = 3,
      desc = 'Group read permission',
    },
    {
      name = 'CanolaPermGroupWrite',
      terminal_color = 1,
      desc = 'Group write permission',
    },
    {
      name = 'CanolaPermGroupExec',
      terminal_color = 2,
      desc = 'Group execute permission',
    },
    {
      name = 'CanolaPermOtherRead',
      terminal_color = 3,
      desc = 'Other read permission',
    },
    {
      name = 'CanolaPermOtherWrite',
      terminal_color = 1,
      desc = 'Other write permission',
    },
    {
      name = 'CanolaPermOtherExec',
      terminal_color = 2,
      desc = 'Other execute permission',
    },
    {
      name = 'CanolaPermNone',
      link = 'Comment',
      desc = 'No permission (dash)',
    },
    {
      name = 'CanolaPermSpecial',
      link = 'Special',
      desc = 'Special permission bit (setuid/setgid/sticky)',
    },
    {
      name = 'CanolaSizeBytes',
      link = 'DiagnosticOk',
      desc = 'File size in bytes',
    },
    {
      name = 'CanolaSizeKilo',
      link = 'DiagnosticOk',
      bold = true,
      desc = 'File size in kilobytes',
    },
    {
      name = 'CanolaSizeMega',
      link = 'DiagnosticWarn',
      desc = 'File size in megabytes',
    },
    {
      name = 'CanolaSizeGiga',
      link = 'DiagnosticError',
      desc = 'File size in gigabytes',
    },
    {
      name = 'CanolaOwnerSelf',
      link = 'DiagnosticWarn',
      bold = true,
      desc = 'File owner matching current user',
    },
    {
      name = 'CanolaOwnerOther',
      link = 'DiagnosticError',
      desc = 'File owner not matching current user',
    },
    {
      name = 'CanolaGroupSelf',
      link = 'DiagnosticWarn',
      bold = true,
      desc = 'File group matching current user group',
    },
    {
      name = 'CanolaGroupOther',
      link = 'DiagnosticError',
      desc = 'File group not matching current user group',
    },
    {
      name = 'CanolaDate',
      link = 'Directory',
      desc = 'File modification date',
    },
  }
end

M.set_colors = function()
  for _, conf in ipairs(M._get_highlights()) do
    if conf.terminal_color then
      local fg = vim.g['terminal_color_' .. conf.terminal_color]
      if fg then
        vim.api.nvim_set_hl(0, conf.name, {
          default = true,
          fg = fg,
          ctermfg = conf.terminal_color,
          bold = conf.bold or nil,
          underline = conf.underline or nil,
        })
      end
    elseif conf.link then
      if conf.bold or conf.underline then
        local base = vim.api.nvim_get_hl(0, { name = conf.link, link = false })
        vim.api.nvim_set_hl(0, conf.name, {
          default = true,
          fg = base.fg,
          ctermfg = base.ctermfg,
          bold = conf.bold or nil,
          underline = conf.underline or nil,
        })
      else
        vim.api.nvim_set_hl(0, conf.name, { default = true, link = conf.link })
      end
    end
  end
end

return M
