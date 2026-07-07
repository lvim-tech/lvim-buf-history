-- lvim-buf-history: the live configuration table.
-- Holds the defaults; setup() merges user overrides into it in place, so every
-- require("lvim-buf-history.config") reader sees the effective values. Only OPTIONS live
-- here — the per-window trails themselves are runtime state and belong to history.lua.
-- The ignore defaults keep the trail clean by construction: terminals, prompts and
-- nofile scratch buffers (every lvim-ui frame / panel is a nofile buffer) never enter a
-- window's history, so surfing back can never land in a dead popup.
--
---@module "lvim-buf-history.config"

---@class LvimBufHistoryIgnore
---@field buftype  string[]  'buftype' values never recorded (terminals, prompts, UI scratch)
---@field filetype string[]  filetypes never recorded (extra panel/UI filetypes beyond the buftype net)

---@class LvimBufHistoryKeys
---@field back    string  lhs mapped to <Plug>(LvimBufHistoryBack) when map_default_keys is on
---@field forward string  lhs mapped to <Plug>(LvimBufHistoryForward) when map_default_keys is on
---@field list    string  lhs mapped to <Plug>(LvimBufHistoryList) when map_default_keys is on

---@class LvimBufHistoryConfig
---@field max_len          integer              Entries kept per window (the oldest are ring-trimmed past it)
---@field inherit          boolean              A new window starts with a copy of the trail of the window it was split from
---@field map_default_keys boolean              Map `keys` on setup; off = only the <Plug> maps are defined
---@field keys             LvimBufHistoryKeys   The default keymaps (used only when map_default_keys is true)
---@field ignore           LvimBufHistoryIgnore Buffers that never enter a trail (unlisted ones never do, regardless)

---@type LvimBufHistoryConfig
return {
    max_len = 100,
    inherit = true,
    -- The <Plug> maps are always defined; the concrete keys below are opt-in so the plugin
    -- never claims Neovim's native [b / ]b (:bprevious / :bnext) without being asked.
    map_default_keys = false,
    keys = {
        back = "[b",
        forward = "]b",
        list = "<Leader>bh",
    },
    ignore = {
        buftype = { "terminal", "nofile", "prompt" },
        filetype = {},
    },
}
