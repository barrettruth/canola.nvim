# canola.nvim

[oil.nvim](https://github.com/stevearc/oil.nvim) with 133 upstream issues and
PRs triaged. Drop-in replacement — zero config changes needed.

[Full upstream triage](doc/upstream.md)

https://user-images.githubusercontent.com/506791/209727111-6b4a11f4-634a-4efa-9461-80e9717cea94.mp4

## Migration from oil.nvim

Swap the plugin source. Everything else is identical — same module, same config,
same keymaps.

```lua
-- before
{ 'stevearc/oil.nvim' }

-- after
{ 'barrettruth/canola.nvim' }
```

`require('oil').setup(opts)` works unchanged.

## Requirements

- Neovim 0.10+
- (Optional) icon provider:
  [mini.icons](https://github.com/echasnovski/mini.nvim/blob/main/readmes/mini-icons.md),
  [nvim-web-devicons](https://github.com/nvim-tree/nvim-web-devicons), or
  [nonicons.nvim](https://github.com/barrettruth/nonicons.nvim)

## Installation

```lua
{ 'barrettruth/canola.nvim', opts = {} }
```

Or via [luarocks](https://luarocks.org/modules/barrettruth/canola.nvim):

```
luarocks install canola.nvim
```

## Documentation

```vim
:help canola.nvim
```

## FAQ

**Q: Why "canola"?**

Canola oil.

**Q: Why "oil"?**

From the [vim-vinegar](https://github.com/tpope/vim-vinegar) README, a quote by
Drew Neil:

> Split windows and the project drawer go together like oil and vinegar

**Q: What are some alternatives?**

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
