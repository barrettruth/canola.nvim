# canola.nvim

A file manager for Neovim. Edit your filesystem like a buffer.

https://user-images.githubusercontent.com/506791/209727111-6b4a11f4-634a-4efa-9461-80e9717cea94.mp4

## Features

- Edit directory listings as normal text — rename with `cw`, delete with `dd`,
  create with `o`
- Advanced move, copy, and rename (enhanced from oil.nvim)
- Inline virtual text columns with
  [eza](https://github.com/eza-community/eza)-like highlighting (permissions,
  size, owner, timestamps)
- Custom column API
- Improved decorations for semantic name highlights (executable, hidden,
  directory, symlink, etc.)
- File preview in split/floating window
- Extended-glob file-creation syntax
- External adapters via
  [canola-collection](https://github.com/barrettruth/canola-collection) (git,
  SSH, trash, etc.)

## Requirements

- Neovim 0.11+
- (Optional) an icon provider:
  [mini.icons](https://github.com/echasnovski/mini.nvim/blob/main/readmes/mini-icons.md),
  [nvim-web-devicons](https://github.com/nvim-tree/nvim-web-devicons), or
  [nonicons.nvim](https://github.com/barrettruth/nonicons.nvim)

## Installation

Install with your package manager of choice or via
[luarocks](https://luarocks.org/modules/barrettruth/canola.nvim):

```
luarocks install canola.nvim
```

## Migration/Setup

Configure via `vim.g.canola`:

```lua
-- Before (oil.nvim)
require('oil').setup({ columns = { 'icon' } })

-- After (canola.nvim)
vim.g.canola = { columns = { 'icon' } }
```

See `:help canola-migration` for the canonical re-mapping of every oil.nvim
option to its canola equivalent.

All adapters have been moved to
[`canola-collection`](https://github.com/barrettruth/canola-collection).

## Documentation

```vim
:help canola.nvim
```

## Acknowledgements

canola.nvim is built on [oil.nvim](https://github.com/stevearc/oil.nvim) by
[stevearc](https://github.com/stevearc).
