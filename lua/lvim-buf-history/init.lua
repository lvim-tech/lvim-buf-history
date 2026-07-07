-- lvim-buf-history: browser-style back/forward navigation over the buffers each WINDOW has
-- visited. Every window keeps its own ordered trail (recorded on BufEnter/WinEnter, deduped
-- consecutively, forward tail truncated on a fresh visit — exactly a browser history) with
-- a position pointer; back()/forward() move the pointer and show that buffer without the
-- jump re-recording itself (history.lua's reentrancy guard). Wiped/unlisted buffers are
-- pruned lazily on traversal and purged eagerly on BufDelete/BufWipeout; a new split
-- inherits the trail of its origin window (config.inherit). The trail can be browsed as a
-- themed list (lvim-ui select) where confirming a row jumps the pointer to it.
--
-- This module is the thin public face: setup (config merge + one-time registration), the
-- :LvimBufHistory command, the <Plug> maps and the user-facing notifications around the
-- silent history verbs.
--
---@module "lvim-buf-history"

local config = require("lvim-buf-history.config")
local history = require("lvim-buf-history.history")
local ui = require("lvim-buf-history.ui")

local ok_utils, utils = pcall(require, "lvim-utils.utils")

local api = vim.api

local M = {}

---@type boolean  one-time setup (autocmds, command, <Plug> maps) done
local registered = false

--- Step back along the current window's trail; notifies when already at the oldest entry.
---@return nil
function M.back()
    if not history.back() then
        vim.notify("buf-history: already at the oldest buffer", vim.log.levels.INFO)
    end
end

--- Step forward along the current window's trail; notifies when already at the newest entry.
---@return nil
function M.forward()
    if not history.forward() then
        vim.notify("buf-history: already at the newest buffer", vim.log.levels.INFO)
    end
end

--- Open the trail list for the current window (lvim-ui select; confirming jumps the pointer).
---@return nil
function M.list()
    ui.list()
end

--- A pruned snapshot of a window's trail: buffer numbers oldest first, plus the 1-based
--- position pointer (0 when empty). For statuslines / integrations.
---@param win? integer  window id (default: the current window)
---@return integer[] entries
---@return integer pos
function M.history(win)
    return history.get(win or api.nvim_get_current_win())
end

--- Forget a window's trail.
---@param win? integer  window id (default: the current window)
---@return nil
function M.clear(win)
    history.clear(win or api.nvim_get_current_win())
end

--- One status line for the bare :LvimBufHistory (and :checkhealth): trail length and
--- pointer of the current window.
---@return string
function M.status()
    local entries, pos = history.get(api.nvim_get_current_win())
    if #entries == 0 then
        return "buf-history: this window has no history yet"
    end
    return ("buf-history: %d entr%s, position %d"):format(#entries, #entries == 1 and "y" or "ies", pos)
end

--- Whether the one-time registration (autocmds, command, <Plug> maps) has run — i.e.
--- setup() was called. For :checkhealth.
---@return boolean
function M.is_registered()
    return registered
end

--- Define the <Plug> maps (always) and, with map_default_keys on, the concrete default
--- keys from config.keys on top of them.
---@return nil
local function register_keymaps()
    vim.keymap.set("n", "<Plug>(LvimBufHistoryBack)", M.back, { silent = true, desc = "Buffer history: back" })
    vim.keymap.set("n", "<Plug>(LvimBufHistoryForward)", M.forward, { silent = true, desc = "Buffer history: forward" })
    vim.keymap.set("n", "<Plug>(LvimBufHistoryList)", M.list, { silent = true, desc = "Buffer history: list" })
    if config.map_default_keys then
        local keys = config.keys or {}
        if keys.back then
            vim.keymap.set("n", keys.back, "<Plug>(LvimBufHistoryBack)", { desc = "Buffer history: back" })
        end
        if keys.forward then
            vim.keymap.set("n", keys.forward, "<Plug>(LvimBufHistoryForward)", { desc = "Buffer history: forward" })
        end
        if keys.list then
            vim.keymap.set("n", keys.list, "<Plug>(LvimBufHistoryList)", { desc = "Buffer history: list" })
        end
    end
end

--- Register the :LvimBufHistory command (once). Bare invocation reports status.
---@return nil
local function register_command()
    api.nvim_create_user_command("LvimBufHistory", function(cmd)
        local sub = cmd.fargs[1]
        if sub == "back" then
            M.back()
        elseif sub == "forward" then
            M.forward()
        elseif sub == "list" then
            M.list()
        elseif sub == "clear" then
            M.clear()
            vim.notify("buf-history: history cleared for this window", vim.log.levels.INFO)
        else
            vim.notify(M.status(), vim.log.levels.INFO)
        end
    end, {
        nargs = "?",
        complete = function(arg)
            return vim.tbl_filter(function(c)
                return arg == "" or c:find(arg, 1, true) == 1
            end, { "back", "forward", "list", "clear", "status" })
        end,
        desc = "lvim-buf-history: back / forward / list / clear / status",
    })
end

--- Configure and start the plugin. Idempotent — calling again re-merges config; the
--- autocmds, command and <Plug> maps are registered once. Recording begins here: the
--- CURRENT buffer of every existing window is seeded on its next WinEnter/BufEnter.
---@param opts? LvimBufHistoryConfig
---@return nil
function M.setup(opts)
    if ok_utils and utils.merge then
        utils.merge(config, opts or {})
    elseif opts then
        local merged = vim.tbl_deep_extend("force", config, opts)
        for k, v in pairs(merged) do
            config[k] = v
        end
    end
    if registered then
        return
    end
    registered = true
    history.register()
    register_keymaps()
    register_command()
    -- Seed the current window immediately — without this, the buffer the user starts in
    -- would only enter the trail after the first window/buffer switch.
    history.record(api.nvim_get_current_win(), api.nvim_get_current_buf())
end

return M
