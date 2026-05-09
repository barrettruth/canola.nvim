# canola.nvim

[oil.nvim](https://github.com/stevearc/oil.nvim) with
[133 upstream issues and PRs triaged](doc/upstream.md). Drop-in replacement —
zero config changes needed.

https://github.com/user-attachments/assets/a1864956-ad7e-49c4-a7f9-e0ec8799da83

## Installation

Swap `stevearc/oil.nvim` for `barrettruth/canola.nvim`. Everything else is
identical — same module, same config, same keymaps, same
`require('oil').setup(opts)`.

```lua
{ 'barrettruth/canola.nvim', opts = {} }
```

Or via [luarocks](https://luarocks.org/modules/barrettruth/canola.nvim):

```
luarocks install canola.nvim
```

## Quick Start

Put canola on a parent-directory key when you want a vinegar-style entry point.

```lua
vim.keymap.set('n', '-', '<CMD>Oil<CR>', { desc = 'Open parent directory' })
```

Open a project directory when you want to browse and edit it as a buffer.

```sh
nvim .
```

Inside the listing, press `<CR>` to open a file or descend into a directory, and
press `-` to move back up.

Rename, create, or delete entries by editing the listing as text, then write the
buffer to apply the filesystem changes.

```vim
:w
```

See `:help canola` for full documentation.

## Requirements

- Neovim 0.10+
- (Optionally) an icon provider:
  [mini.icons](https://github.com/echasnovski/mini.nvim/blob/main/readmes/mini-icons.md),
  [nvim-web-devicons](https://github.com/nvim-tree/nvim-web-devicons), or
  [nonicons.nvim](https://github.com/barrettruth/nonicons.nvim)

## Similar Projects

- [stevearc/oil.nvim](https://github.com/stevearc/oil.nvim) — the original
- [mini.files](https://github.com/echasnovski/mini.nvim/blob/main/readmes/mini-files.md)
  — cross-directory filesystem-as-buffer with a column view
- [vim-vinegar](https://github.com/tpope/vim-vinegar) — the granddaddy of
  single-directory file browsing
- [dirbuf.nvim](https://github.com/elihunter173/dirbuf.nvim) — filesystem as
  buffer without cross-directory edits
- [lir.nvim](https://github.com/tamago324/lir.nvim) — vim-vinegar style with
  Neovim integration
- [vim-dirvish](https://github.com/justinmk/vim-dirvish) — stable, simple
  directory browser

## Acknowledgements

- [stevearc](https://github.com/stevearc):
  [oil.nvim](https://github.com/stevearc/oil.nvim)
