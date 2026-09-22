# canola.nvim

A refined [`oil.nvim`](https://github.com/stevearc/oil.nvim)

<video src="https://forge.barrettruth.com/attachments/c1a10e1f-2c5b-4f73-a2c8-834b352993f9" poster="https://forge.barrettruth.com/attachments/8be3923f-9a3e-404a-907d-79d02802f29a" controls preload="metadata" muted playsinline width="100%"></video>

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
  [canola-collection](https://forge.barrettruth.com/barrettruth/canola-collection) (git,
  SSH, trash, etc.)

## Requirements

- Neovim 0.12+
- (Optional) an icon provider:
  [mini.icons](https://github.com/echasnovski/mini.nvim/blob/main/readmes/mini-icons.md),
  [nvim-web-devicons](https://github.com/nvim-tree/nvim-web-devicons), or
  [nonicons.nvim](https://forge.barrettruth.com/barrettruth/nonicons.nvim)

## Installation

Install with your package manager of choice. Use the `canola` branch:

```lua
{ 'https://forge.barrettruth.com/barrettruth/canola.nvim', branch = 'canola' }
```
## Quick Start

Put canola on a parent-directory key when you want a vinegar-style entry point.

```lua
vim.keymap.set('n', '-', '<CMD>Canola<CR>', { desc = 'Open parent directory' })
```

Open a project directory when you want to browse and edit it as a buffer.

```sh
nvim .
```

Open another directory from inside Neovim when you already know the path.

```vim
:Canola <path>
```

Inside the listing, press `<CR>` to open a file or descend into a directory, and
press `-` to move back up.

Rename, create, or delete entries by editing the listing as text, then write the
buffer to apply the filesystem changes.

```vim
:w
```

## Migration/Setup

Configure via `vim.g.canola` before the plugin loads:

```lua
-- Before (oil.nvim)
require('oil').setup({ columns = { 'icon' } })

-- After (canola.nvim)
vim.g.canola = { columns = { 'icon' } }
```

See `:help canola-migration` for the canonical re-mapping of every oil.nvim
option to its canola equivalent.

All adapters have been moved to
[`canola-collection`](https://forge.barrettruth.com/barrettruth/canola-collection).

## Documentation

```vim
:help canola
```

# Acknowledgements

- [`oil.nvim`](https://github.com/stevearc/oil.nvim)
- [@llakala](https://github.com/llakala) — `confirm` option on `select()`
