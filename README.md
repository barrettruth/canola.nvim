# canola.nvim

A file manager for Neovim. Edit your filesystem like a buffer.

https://user-images.githubusercontent.com/506791/209727111-6b4a11f4-634a-4efa-9461-80e9717cea94.mp4

## Features

- Edit directory listings as normal text — rename with `cw`, delete with `dd`,
  create with `o`
- Mutations are derived by diffing the buffer against cached state on `:w`
- Cross-directory move, copy, and rename — cut a line in one directory, paste it
  in another
- Move files into new directories by adding `/` to the name
- Inline virtual text columns with eza-like highlighting (permissions, size,
  owner, timestamps)
- Custom columns via `register_column()`
- Decoration provider for semantic name highlights (executable, hidden,
  directory, symlink)
- File preview in split or floating window
- Brace expansion in the mutation pipeline (`{a,b,c}.txt`)
- Rich User autocmd events (`CanolaEnter`, `CanolaReadPost`,
  `CanolaMutationComplete`, `CanolaFloatConfig`, `CanolaWinTitle`,
  `CanolaPreviewDisable`)
- External adapters via
  [canola-collection](https://github.com/barrettruth/canola-collection) (SSH,
  S3, FTP, trash)

## Requirements

- Neovim 0.11+
- (Optional) an icon provider:
  [mini.icons](https://github.com/echasnovski/mini.nvim/blob/main/readmes/mini-icons.md),
  [nvim-web-devicons](https://github.com/nvim-tree/nvim-web-devicons), or
  [nonicons.nvim](https://github.com/barrettruth/nonicons.nvim)

## Installation

Clone into your `pack` directory:

```sh
git clone https://github.com/barrettruth/canola.nvim \
  --branch canola \
  ~/.local/share/nvim/site/pack/canola/start/canola.nvim
```

Or via [luarocks](https://luarocks.org/modules/barrettruth/canola.nvim):

```
luarocks install canola.nvim
```

No `setup()` call. Configure via `vim.g.canola`:

```lua
vim.g.canola = {
  columns = { 'icon', 'size', 'permissions', 'mtime' },
  sort = { by = { { 'type', 'asc' }, { 'name', 'asc' } } },
  keymaps = {
    ['-'] = false,
    ['<bs>'] = { callback = 'actions.parent', mode = 'n' },
  },
}
```

Defaults work out of the box. See `:help canola.nvim` for the full option
reference.

## Documentation

```vim
:help canola.nvim
```

## Acknowledgements

canola.nvim is built on [oil.nvim](https://github.com/stevearc/oil.nvim) by
[stevearc](https://github.com/stevearc).
