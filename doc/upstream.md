# Upstream Tracker

Triage of [stevearc/oil.nvim](https://github.com/stevearc/oil.nvim) PRs and
issues against this fork.

## Upstream PRs

| PR | Description | Status |
|----|-------------|--------|
| [#495](https://github.com/stevearc/oil.nvim/pull/495) | Cancel visual/operator-pending mode on close | cherry-picked |
| [#537](https://github.com/stevearc/oil.nvim/pull/537) | Configurable file/directory creation permissions | cherry-picked |
| [#618](https://github.com/stevearc/oil.nvim/pull/618) | Opt-in filetype detection for icons | cherry-picked |
| [#644](https://github.com/stevearc/oil.nvim/pull/644) | Pass entry to `is_hidden_file`/`is_always_hidden` | cherry-picked |
| [#697](https://github.com/stevearc/oil.nvim/pull/697) | Recipe for file extension column | cherry-picked |
| [#698](https://github.com/stevearc/oil.nvim/pull/698) | Executable file highlighting | cherry-picked |
| [#717](https://github.com/stevearc/oil.nvim/pull/717) | Add oil-git.nvim to extensions | cherry-picked |
| [#720](https://github.com/stevearc/oil.nvim/pull/720) | Gate `BufAdd` autocmd behind config check | cherry-picked |
| [#722](https://github.com/stevearc/oil.nvim/pull/722) | Fix freedesktop trash URL | cherry-picked |
| [#723](https://github.com/stevearc/oil.nvim/pull/723) | Emit `OilReadPost` event after render | cherry-picked |
| [#725](https://github.com/stevearc/oil.nvim/pull/725) | Normalize keymap keys before config merge | cherry-picked |
| [#727](https://github.com/stevearc/oil.nvim/pull/727) | Clarify `get_current_dir` nil + Telescope recipe | cherry-picked |
| [#739](https://github.com/stevearc/oil.nvim/pull/739) | macOS FreeDesktop trash recipe | cherry-picked |
| [#488](https://github.com/stevearc/oil.nvim/pull/488) | Parent directory in a split | not actionable — empty PR |
| [#493](https://github.com/stevearc/oil.nvim/pull/493) | UNC paths on Windows | not actionable — superseded by [#686](https://github.com/stevearc/oil.nvim/pull/686) |
| [#686](https://github.com/stevearc/oil.nvim/pull/686) | Windows path conversion fix | not actionable — Windows-only |
| [#735](https://github.com/stevearc/oil.nvim/pull/735) | gX opens external program with selection | not actionable — hardcoded Linux-only, incomplete |
| [#591](https://github.com/stevearc/oil.nvim/pull/591) | release-please changelog | not applicable |
| [#667](https://github.com/stevearc/oil.nvim/pull/667) | Virtual text columns + headers | deferred — WIP, conflicting |
| [#708](https://github.com/stevearc/oil.nvim/pull/708) | Move file into new dir by renaming | deferred — needs rewrite |
| [#721](https://github.com/stevearc/oil.nvim/pull/721) | `create_hook` to populate file contents | deferred — fixing via autocmd event |
| [#728](https://github.com/stevearc/oil.nvim/pull/728) | `open_split` for opening oil in a split | deferred — tracked as [#2](https://github.com/barrettruth/canola.nvim/issues/2) |

## Issues — fixed (original)

Issues fixed in this fork that remain open upstream.

| Issue | Description | PR |
|-------|-------------|----|
| [#213](https://github.com/stevearc/oil.nvim/issues/213) | Disable preview for large files | [#85](https://github.com/barrettruth/canola.nvim/pull/85) |
| [#302](https://github.com/stevearc/oil.nvim/issues/302) | `buflisted=true` after jumplist nav | [#71](https://github.com/barrettruth/canola.nvim/pull/71) |
| [#363](https://github.com/stevearc/oil.nvim/issues/363) | `prompt_save_on_select_new_entry` wrong prompt | — |
| [#392](https://github.com/stevearc/oil.nvim/issues/392) | Option to skip delete prompt | — |
| [#393](https://github.com/stevearc/oil.nvim/issues/393) | Auto-save on select | — |
| [#473](https://github.com/stevearc/oil.nvim/issues/473) | Show hidden when dir is all-hidden | [#85](https://github.com/barrettruth/canola.nvim/pull/85) |
| [#486](https://github.com/stevearc/oil.nvim/issues/486) | Directory sizes show misleading 4.1k | [#87](https://github.com/barrettruth/canola.nvim/pull/87) |
| [#578](https://github.com/stevearc/oil.nvim/issues/578) | Hidden file dimming recipe | — |
| [#612](https://github.com/stevearc/oil.nvim/issues/612) | Delete buffers on file delete | — |
| [#615](https://github.com/stevearc/oil.nvim/issues/615) | Cursor at name column on o/O | [#72](https://github.com/barrettruth/canola.nvim/pull/72) |
| [#621](https://github.com/stevearc/oil.nvim/issues/621) | `toggle()` for regular windows | [#88](https://github.com/barrettruth/canola.nvim/pull/88) |
| [#632](https://github.com/stevearc/oil.nvim/issues/632) | Preview + move = copy | [#12](https://github.com/barrettruth/canola.nvim/pull/12) |
| [#642](https://github.com/stevearc/oil.nvim/issues/642) | W10 warning under `nvim -R` | — |
| [#645](https://github.com/stevearc/oil.nvim/issues/645) | `close_float` action | — |
| [#650](https://github.com/stevearc/oil.nvim/issues/650) | LSP `workspace.fileOperations` events | — |
| [#670](https://github.com/stevearc/oil.nvim/issues/670) | Multi-directory cmdline args ignored | [#11](https://github.com/barrettruth/canola.nvim/pull/11) |
| [#673](https://github.com/stevearc/oil.nvim/issues/673) | Symlink newlines crash | — |
| [#683](https://github.com/stevearc/oil.nvim/issues/683) | Path not shown in floating mode | — |
| [#690](https://github.com/stevearc/oil.nvim/issues/690) | `OilFileIcon` highlight group | — |
| [#710](https://github.com/stevearc/oil.nvim/issues/710) | buftype empty on BufEnter | [#10](https://github.com/barrettruth/canola.nvim/pull/10) |

## Issues — resolved (cherry-pick)

Issues addressed by cherry-picking upstream PRs.

| Issue | Description | Upstream PR |
|-------|-------------|-------------|
| [#446](https://github.com/stevearc/oil.nvim/issues/446) | Executable highlighting | [#698](https://github.com/stevearc/oil.nvim/pull/698) |
| [#679](https://github.com/stevearc/oil.nvim/issues/679) | Executable file sign | [#698](https://github.com/stevearc/oil.nvim/pull/698) |
| [#682](https://github.com/stevearc/oil.nvim/issues/682) | `get_current_dir()` nil | [#727](https://github.com/stevearc/oil.nvim/pull/727) |
| [#692](https://github.com/stevearc/oil.nvim/issues/692) | Keymap normalization | [#725](https://github.com/stevearc/oil.nvim/pull/725) |

## Issues — open

| Issue | Description |
|-------|-------------|
| [#85](https://github.com/stevearc/oil.nvim/issues/85) | Git status column |
| [#95](https://github.com/stevearc/oil.nvim/issues/95) | Undo after renaming files |
| [#117](https://github.com/stevearc/oil.nvim/issues/117) | Move file into new dir via slash in name |
| [#156](https://github.com/stevearc/oil.nvim/issues/156) | Paste path of files into oil buffer |
| [#200](https://github.com/stevearc/oil.nvim/issues/200) | Highlights not working when opening a file |
| [#207](https://github.com/stevearc/oil.nvim/issues/207) | Suppress "no longer available" message |
| [#210](https://github.com/stevearc/oil.nvim/issues/210) | FTP support |
| [#226](https://github.com/stevearc/oil.nvim/issues/226) | K8s/Docker adapter |
| [#232](https://github.com/stevearc/oil.nvim/issues/232) | Cannot close last window |
| [#254](https://github.com/stevearc/oil.nvim/issues/254) | Buffer modified highlight group |
| [#263](https://github.com/stevearc/oil.nvim/issues/263) | Diff mode |
| [#276](https://github.com/stevearc/oil.nvim/issues/276) | Archives manipulation |
| [#280](https://github.com/stevearc/oil.nvim/issues/280) | vim-projectionist support |
| [#289](https://github.com/stevearc/oil.nvim/issues/289) | Show absolute path toggle |
| [#294](https://github.com/stevearc/oil.nvim/issues/294) | Can't handle emojis in filenames |
| [#298](https://github.com/stevearc/oil.nvim/issues/298) | Open float on neovim directory startup |
| [#303](https://github.com/stevearc/oil.nvim/issues/303) | Preview in float window mode |
| [#325](https://github.com/stevearc/oil.nvim/issues/325) | oil-ssh error from command line |
| [#332](https://github.com/stevearc/oil.nvim/issues/332) | Buffer not fixed to floating window |
| [#335](https://github.com/stevearc/oil.nvim/issues/335) | Disable editing outside root dir |
| [#349](https://github.com/stevearc/oil.nvim/issues/349) | Parent directory as column/vsplit |
| [#351](https://github.com/stevearc/oil.nvim/issues/351) | Paste deleted file from register |
| [#359](https://github.com/stevearc/oil.nvim/issues/359) | Parse error on filenames differing by space |
| [#360](https://github.com/stevearc/oil.nvim/issues/360) | Pick window to open file into |
| [#371](https://github.com/stevearc/oil.nvim/issues/371) | Constrain cursor in insert mode |
| [#373](https://github.com/stevearc/oil.nvim/issues/373) | Dir from quickfix with bqf/trouble broken |
| [#375](https://github.com/stevearc/oil.nvim/issues/375) | Highlights for file types and permissions |
| [#382](https://github.com/stevearc/oil.nvim/issues/382) | Relative path in window title |
| [#396](https://github.com/stevearc/oil.nvim/issues/396) | Customize preview content |
| [#399](https://github.com/stevearc/oil.nvim/issues/399) | Open file without closing Oil |
| [#416](https://github.com/stevearc/oil.nvim/issues/416) | Cannot remap key to open split |
| [#431](https://github.com/stevearc/oil.nvim/issues/431) | More SSH adapter documentation |
| [#435](https://github.com/stevearc/oil.nvim/issues/435) | Error previewing with semantic tokens LSP |
| [#436](https://github.com/stevearc/oil.nvim/issues/436) | Owner and group columns |
| [#444](https://github.com/stevearc/oil.nvim/issues/444) | Opening behaviour customization |
| [#449](https://github.com/stevearc/oil.nvim/issues/449) | Renaming TypeScript files stopped working |
| [#450](https://github.com/stevearc/oil.nvim/issues/450) | Highlight opened file in directory listing |
| [#457](https://github.com/stevearc/oil.nvim/issues/457) | Custom column API |
| [#466](https://github.com/stevearc/oil.nvim/issues/466) | Select into window on right |
| [#479](https://github.com/stevearc/oil.nvim/issues/479) | Harpoon integration recipe |
| [#521](https://github.com/stevearc/oil.nvim/issues/521) | oil-ssh connection issues |
| [#525](https://github.com/stevearc/oil.nvim/issues/525) | SSH adapter documentation |
| [#570](https://github.com/stevearc/oil.nvim/issues/570) | Improve c0/d0 for renaming |
| [#571](https://github.com/stevearc/oil.nvim/issues/571) | Callback before `highlight_filename` |
| [#599](https://github.com/stevearc/oil.nvim/issues/599) | user:group display and manipulation |
| [#607](https://github.com/stevearc/oil.nvim/issues/607) | Per-host SCP args |
| [#609](https://github.com/stevearc/oil.nvim/issues/609) | Cursor placement via Snacks picker |
| [#617](https://github.com/stevearc/oil.nvim/issues/617) | Filetype by actual filetype |
| [#636](https://github.com/stevearc/oil.nvim/issues/636) | Telescope picker opens in active buffer |
| [#637](https://github.com/stevearc/oil.nvim/issues/637) | Inconsistent symlink resolution |
| [#641](https://github.com/stevearc/oil.nvim/issues/641) | Flicker on `actions.parent` |
| [#646](https://github.com/stevearc/oil.nvim/issues/646) | `get_current_dir` nil on SSH |
| [#655](https://github.com/stevearc/oil.nvim/issues/655) | File statistics as virtual text |
| [#659](https://github.com/stevearc/oil.nvim/issues/659) | Mark and diff files in buffer |
| [#665](https://github.com/stevearc/oil.nvim/issues/665) | Hot load preview fast-scratch buffers |
| [#668](https://github.com/stevearc/oil.nvim/issues/668) | Custom yes/no confirmation |
| [#671](https://github.com/stevearc/oil.nvim/issues/671) | Yanking between nvim instances |
| [#675](https://github.com/stevearc/oil.nvim/issues/675) | Move file into folder by renaming |
| [#678](https://github.com/stevearc/oil.nvim/issues/678) | `buftype='acwrite'` causes `mksession` to skip oil windows |
| [#684](https://github.com/stevearc/oil.nvim/issues/684) | User and group columns |
| [#685](https://github.com/stevearc/oil.nvim/issues/685) | Plain directory paths in buffer names |
| [#699](https://github.com/stevearc/oil.nvim/issues/699) | `select` blocks UI with slow FileType autocmd |
| [#707](https://github.com/stevearc/oil.nvim/issues/707) | Move file/dir into new dir by renaming |
| [#736](https://github.com/stevearc/oil.nvim/issues/736) | Make icons virtual text |
| [#738](https://github.com/stevearc/oil.nvim/issues/738) | Allow changing mtime/atime via time column |

## Issues — not actionable

| Issue | Reason |
|-------|--------|
| [#288](https://github.com/stevearc/oil.nvim/issues/288) | No reliable repro; likely lazy.nvim timing |
| [#330](https://github.com/stevearc/oil.nvim/issues/330) | Telescope opens file in oil float — cross-plugin, no repro |
| [#362](https://github.com/stevearc/oil.nvim/issues/362) | No minimal repro, old nvim version (0.9.5) |
| [#380](https://github.com/stevearc/oil.nvim/issues/380) | Silently overriding `show_hidden` counter to config intent |
| [#404](https://github.com/stevearc/oil.nvim/issues/404) | Windows-only |
| [#483](https://github.com/stevearc/oil.nvim/issues/483) | Spell downloads depend on netrw — fixed in neovim#34940 |
| [#492](https://github.com/stevearc/oil.nvim/issues/492) | j/k remapping question — answered |
| [#507](https://github.com/stevearc/oil.nvim/issues/507) | lacasitos.nvim conflict — cross-plugin + Windows-only |
| [#531](https://github.com/stevearc/oil.nvim/issues/531) | Windows — incomplete drive letters |
| [#533](https://github.com/stevearc/oil.nvim/issues/533) | `constrain_cursor` — needs repro |
| [#587](https://github.com/stevearc/oil.nvim/issues/587) | Alt+h keymap — user config issue |
| [#623](https://github.com/stevearc/oil.nvim/issues/623) | bufferline.nvim interaction — cross-plugin |
| [#624](https://github.com/stevearc/oil.nvim/issues/624) | Mutation race — no reliable repro |
| [#625](https://github.com/stevearc/oil.nvim/issues/625) | E19 mark invalid line — intractable without neovim API changes |
| [#664](https://github.com/stevearc/oil.nvim/issues/664) | Session reload extra buffer — no repro |
| [#676](https://github.com/stevearc/oil.nvim/issues/676) | Windows — path conversion |
| [#714](https://github.com/stevearc/oil.nvim/issues/714) | Support question — answered |
| [#719](https://github.com/stevearc/oil.nvim/issues/719) | Neovim crash on node_modules — libuv/neovim bug |
| [#726](https://github.com/stevearc/oil.nvim/issues/726) | Meta discussion/roadmap |
