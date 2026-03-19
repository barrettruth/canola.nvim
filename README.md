# canola.nvim

A refined [oil.nvim](https://github.com/stevearc/oil.nvim) — edit your
filesystem like a buffer, with bug fixes and community PRs that haven't landed
upstream.

[Upstream tracker](doc/upstream.md) — full PR and issue triage against
[oil.nvim](https://github.com/stevearc/oil.nvim)

https://user-images.githubusercontent.com/506791/209727111-6b4a11f4-634a-4efa-9461-80e9717cea94.mp4

## Features

- Edit directory listings as normal buffers — mutations are derived by diffing
- Cross-directory move, copy, and rename across any adapter
- Adapters for local filesystem, SSH, S3, and OS trash
- File preview in split or floating window
- Configurable columns (icon, size, permissions, timestamps)
- Executable file highlighting and filetype-aware icons
- Floating window and split layouts

## Requirements

- Neovim 0.11+
- (Optionally) any of the following icon providers:
  - [mini.icons](https://github.com/nvim-mini/mini.nvim/blob/main/readmes/mini-icons.md)
  - [nvim-web-devicons](https://github.com/nvim-tree/nvim-web-devicons)
  - [nonicons.nvim](https://github.com/barrettruth/nonicons.nvim)

## Installation

Install with your package manager of choice or via
[luarocks](https://luarocks.org/modules/barrettruth/canola.nvim):

```
luarocks install canola.nvim
```

## Documentation

```vim
:help canola.nvim
```

## FAQ

**Q: How do I migrate from `stevearc/oil.nvim`?**

Simply change the plugin source from `stevearc/oil.nvim` to
`barretruth/oil.nvim`.

Before (`stevearc/oil.nvim`):

```lua
{
  'stevearc/oil.nvim',
  opts = { ... },
  config = function(_, opts)
    require('oil').setup(opts)
  end,
}
```

After (`barrettruth/oil.nvim`):

```lua
{
  'barrettruth/oil.nvim',
  opts = { ... },
  config = function(_, opts)
    require('oil').setup(opts)
  end,
}
```

`init` runs before the plugin loads; `config` runs after. oil.nvim reads
`vim.g.canola` at load time, so `init` is the correct hook. Do not use `config`,
`opts`, or `lazy` — oil.nvim loads itself when you open a directory.

**Q: Why "canola"?**

Canola oil! But...

**Q: Why "oil"?**

From the [vim-vinegar](https://github.com/tpope/vim-vinegar) README, a quote by
Drew Neil:

> Split windows and the project drawer go together like oil and vinegar

**Q: What are some alternatives?**

- [stevearc/oil.nvim](https://github.com/stevearc/oil.nvim): the original
- [mini.files](https://github.com/nvim-mini/mini.nvim/blob/main/readmes/mini-files.md):
  cross-directory filesystem-as-buffer with a column view
- [vim-vinegar](https://github.com/tpope/vim-vinegar): the granddaddy of
  single-directory file browsing
- [dirbuf.nvim](https://github.com/elihunter173/dirbuf.nvim): filesystem as
  buffer without cross-directory edits
- [lir.nvim](https://github.com/tamago324/lir.nvim): vim-vinegar style with
  Neovim integration
- [vim-dirvish](https://github.com/justinmk/vim-dirvish): stable, simple
  directory browser

## Acknowledgements

- [stevearc](https://github.com/stevearc):
  [oil.nvim](https://github.com/stevearc/oil.nvim)
