# lvim-buf-history

Browser-style **back / forward navigation over the buffers each window has visited** — part
of the lvim-tech ecosystem. Every window keeps its own ordered history of visited buffers
with a position pointer, exactly like a browser tab: surf back through where you have been,
forward again, or pick any point of the trail from a themed list.

- **Per-window trails** — recorded automatically on `BufEnter` / `WinEnter`, deduped
  consecutively. Each window remembers *its own* path, so two splits over the same files
  keep independent histories.
- **Browser semantics** — going back and then visiting a *new* buffer discards the forward
  tail, exactly like a browser. Navigation performed by the plugin itself is never
  re-recorded (the pointer moves; nothing is appended).
- **Clean by construction** — unlisted buffers, terminals, prompts and `nofile` scratch/UI
  buffers never enter a trail (configurable `ignore` lists). Deleted or wiped buffers are
  purged from every window's trail; anything that dies in between is pruned on traversal,
  so back/forward can never land in a dead buffer.
- **Split inheritance** — a new window starts with a copy of the trail of the window it was
  split from (`inherit = true`), so surfing continues seamlessly after `:split` / `:vsplit`.
- **Trail list** — `:LvimBufHistory list` opens the window's history in the centered,
  themed lvim-ui select: file icons from lvim-icons, the current position marked with `➤`
  and focused on open. Confirming a row *jumps the pointer* to that entry (it does not
  append a new visit).
- Trails are capped at `max_len` entries per window (the oldest are trimmed) and forgotten
  when the window closes.

[![License: BSD-3-Clause](https://img.shields.io/badge/License-BSD--3--Clause-blue.svg)](https://github.com/lvim-tech/lvim-buf-history/blob/main/LICENSE)

## Requirements

- Neovim >= 0.12
- [lvim-utils](https://github.com/lvim-tech/lvim-utils) (config merge)
- [lvim-ui](https://github.com/lvim-tech/lvim-ui) (the trail list; back/forward work without it)
- [lvim-icons](https://github.com/lvim-tech/lvim-icons) (optional — file icons in the list)

## Installation

### lvim-installer (recommended)

Install and manage it from the LVIM package manager — open the **Plugins** tab and install /
update / pin it:

```vim
:LvimInstaller plugins
```

lvim-installer installs plugins through Neovim's built-in `vim.pack`, so no external plugin
manager is needed.

### Native (vim.pack)

```lua
vim.pack.add({
    { src = "https://github.com/lvim-tech/lvim-utils" },
    { src = "https://github.com/lvim-tech/lvim-ui" },
    { src = "https://github.com/lvim-tech/lvim-icons" },
    { src = "https://github.com/lvim-tech/lvim-buf-history" },
})
require("lvim-buf-history").setup({})
```

`setup()` is required — it installs the recording autocmds, the `:LvimBufHistory` command
and the `<Plug>` maps.

## Usage

### Command

```vim
:LvimBufHistory            " status: trail length + position of the current window
:LvimBufHistory back       " go to the previous buffer in this window's history
:LvimBufHistory forward    " go to the next buffer in this window's history
:LvimBufHistory list       " browse the trail (confirm = jump the pointer there)
:LvimBufHistory clear      " forget this window's history
```

### Keymaps

Three `<Plug>` maps are always defined — bind whatever you like:

```lua
vim.keymap.set("n", "[b", "<Plug>(LvimBufHistoryBack)", { desc = "Buffer history: back" })
vim.keymap.set("n", "]b", "<Plug>(LvimBufHistoryForward)", { desc = "Buffer history: forward" })
vim.keymap.set("n", "<Leader>bh", "<Plug>(LvimBufHistoryList)", { desc = "Buffer history: list" })
```

Or let the plugin map exactly those defaults for you with `map_default_keys = true` (off by
default — Neovim maps `[b` / `]b` to `:bprevious` / `:bnext` natively, and the plugin never
claims them without being asked; the keys themselves are configurable via `keys`).

## Default configuration

The full option set at its defaults — pass only what you want to change:

```lua
require("lvim-buf-history").setup({
    max_len = 100, -- entries kept per window (the oldest are trimmed past it)
    inherit = true, -- a new split starts with a copy of its origin window's trail
    map_default_keys = false, -- map `keys` below on setup; off = only the <Plug> maps
    keys = {
        back = "[b", -- → <Plug>(LvimBufHistoryBack)   (only with map_default_keys)
        forward = "]b", -- → <Plug>(LvimBufHistoryForward)
        list = "<Leader>bh", -- → <Plug>(LvimBufHistoryList)
    },
    ignore = {
        -- buffers that never enter a trail (unlisted buffers never do, regardless)
        buftype = { "terminal", "nofile", "prompt" },
        filetype = {},
    },
})
```

## API

```lua
local bh = require("lvim-buf-history")

bh.setup(opts) -- configure + start (idempotent)
bh.back() -- previous buffer in the current window's trail
bh.forward() -- next buffer in the current window's trail
bh.list() -- open the trail list (lvim-ui select)
bh.history(win) -- snapshot: entries (bufnrs, oldest first), position — default: current window
bh.clear(win) -- forget a window's trail (default: current window)
bh.status() -- one status line (trail length + position)
```

## Health

```vim
:checkhealth lvim-buf-history
```

Verifies the runtime (Neovim version, lvim-utils / lvim-ui / lvim-icons), that setup() ran
and recording is live, the trail-pointer invariant, and the config values.

## License

BSD 3-Clause — see [LICENSE](LICENSE).
