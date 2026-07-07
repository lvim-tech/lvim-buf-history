-- lvim-buf-history.history: the per-window trail bookkeeping — record, back/forward,
-- prune, purge — plus the autocmds that drive it. The trails are MODULE state keyed by
-- winid (not `w:` variables: window vars can be cleared by consumers and are awkward to
-- purge across every window on a BufDelete; a module table survives `:e` and is swept in
-- one pass). The subtle parts, spelled out:
--   • BufEnter/WinEnter RECORD the entered buffer; a switch performed by back()/forward()/
--     go() fires the very same BufEnter, so those set the `navigating` reentrancy guard for
--     the duration of nvim_set_current_buf — the pointer MOVES along the trail instead of
--     the navigation appending a new entry (the standard reentrancy discipline, same shape
--     as lvim-keys-helper's `mutating` flag around its own keymap churn).
--   • Visiting a NEW buffer while the pointer sits mid-trail truncates the forward tail
--     first (browser semantics: going back and then somewhere new discards "forward").
--   • Dead buffers are pruned LAZILY: rebuild() drops invalid/unlisted entries (collapsing
--     the adjacent duplicates that pruning exposes) right before any traversal or read, so
--     a wiped buffer can never be a back/forward target; BufDelete/BufWipeout additionally
--     purge the buffer from EVERY window's trail eagerly.
--   • WinNew fires with the NEW window current and winnr("#") still naming the window the
--     split originated from (verified), so inheritance copies the origin's trail there.
--
---@module "lvim-buf-history.history"

local config = require("lvim-buf-history.config")

local api = vim.api

local M = {}

---@class LvimBufHistoryStack
---@field entries integer[]  visited buffer numbers, oldest first
---@field pos     integer    1-based pointer into entries (0 only while empty)

---@type table<integer, LvimBufHistoryStack>  winid → trail
local stacks = {}

---@type boolean  reentrancy guard: our own nvim_set_current_buf re-fires BufEnter — skip recording it
local navigating = false

--- Whether `buf` may enter a trail: it must be a valid, LISTED buffer whose buftype and
--- filetype are not on the ignore lists (unlisted covers most transient UI already; the
--- buftype list catches terminals/prompts/scratch that some consumer listed anyway).
---@param buf integer
---@return boolean
local function recordable(buf)
    if not api.nvim_buf_is_valid(buf) or vim.fn.buflisted(buf) ~= 1 then
        return false
    end
    local ignore = config.ignore or {}
    local bt = vim.bo[buf].buftype
    for _, v in ipairs(ignore.buftype or {}) do
        if bt == v then
            return false
        end
    end
    local ft = vim.bo[buf].filetype
    for _, v in ipairs(ignore.filetype or {}) do
        if ft == v then
            return false
        end
    end
    return true
end

--- Whether a trail entry is still a live target (valid + listed). Ignore-list changes are
--- deliberately NOT re-applied here — an already-recorded visit stays navigable.
---@param buf integer
---@return boolean
local function alive(buf)
    return api.nvim_buf_is_valid(buf) and vim.fn.buflisted(buf) == 1
end

--- Rebuild a trail dropping dead entries (and `drop`, when given), collapsing the adjacent
--- duplicates the removals expose. The pointer is remapped to the nearest SURVIVING entry
--- at or before its old target (falling back toward older — the direction "back" resumes
--- from), clamped into range.
---@param st LvimBufHistoryStack
---@param drop? integer  additionally remove this buffer everywhere (BufDelete purge)
---@return nil
local function rebuild(st, drop)
    local kept = {}
    local pos = 0
    for i, b in ipairs(st.entries) do
        if b ~= drop and alive(b) and kept[#kept] ~= b then
            kept[#kept + 1] = b
        end
        if i == st.pos then
            pos = #kept -- the survivor count so far = the nearest kept index at/before pos
        end
    end
    st.entries = kept
    st.pos = #kept == 0 and 0 or math.max(1, math.min(pos, #kept))
end

--- Switch the current window to `buf` without the jump being re-recorded (the guard makes
--- the BufEnter it fires a no-op).
---@param buf integer
---@return boolean ok
local function switch(buf)
    navigating = true
    local ok = pcall(api.nvim_set_current_buf, buf)
    navigating = false
    return ok
end

--- Record a visit of `buf` in `win`'s trail: truncate the forward tail (browser semantics),
--- append, move the pointer to the top and ring-trim the oldest entries past max_len.
--- Consecutive duplicates never stack (re-entering the pointer's buffer is a no-op).
---@param win integer
---@param buf integer
---@return nil
function M.record(win, buf)
    if navigating or not recordable(buf) then
        return
    end
    local st = stacks[win]
    if not st then
        st = { entries = {}, pos = 0 }
        stacks[win] = st
    end
    if st.entries[st.pos] == buf then
        return -- already standing on it (WinEnter after a window switch, :e reload, …)
    end
    for i = #st.entries, st.pos + 1, -1 do
        st.entries[i] = nil -- visiting anew discards the forward tail
    end
    st.entries[#st.entries + 1] = buf
    st.pos = #st.entries
    local max = config.max_len or 100
    while #st.entries > max do
        table.remove(st.entries, 1)
        st.pos = st.pos - 1
    end
end

--- Step the current window one entry BACK along its trail. Prunes first, so a wiped buffer
--- is skipped rather than jumped to. Returns false when already at the oldest entry (or no
--- trail exists) — the caller owns the user-facing message.
---@return boolean moved
function M.back()
    local st = stacks[api.nvim_get_current_win()]
    if not st then
        return false
    end
    rebuild(st)
    if st.pos <= 1 then
        return false
    end
    st.pos = st.pos - 1
    return switch(st.entries[st.pos])
end

--- Step the current window one entry FORWARD along its trail (the mirror of back()).
---@return boolean moved
function M.forward()
    local st = stacks[api.nvim_get_current_win()]
    if not st then
        return false
    end
    rebuild(st)
    if st.pos >= #st.entries then
        return false
    end
    st.pos = st.pos + 1
    return switch(st.entries[st.pos])
end

--- Jump `win`'s pointer to trail index `index` (1-based, oldest first) and show that
--- buffer — the list UI's confirm action. SETS the position (the trail is untouched);
--- recording stays suppressed via the guard, exactly like back/forward.
---@param win integer
---@param index integer
---@return boolean moved
function M.go(win, index)
    local st = stacks[win]
    if not st then
        return false
    end
    rebuild(st)
    if index < 1 or index > #st.entries or index == st.pos then
        return false
    end
    st.pos = index
    if api.nvim_get_current_win() ~= win and api.nvim_win_is_valid(win) then
        api.nvim_set_current_win(win) -- the list UI runs its callback after its float closed; make sure
    end
    return switch(st.entries[st.pos])
end

--- A pruned SNAPSHOT of `win`'s trail: a copy of the entries (oldest first) and the pointer.
--- The copy keeps the module state private — readers cannot desync the pointer.
---@param win integer
---@return integer[] entries
---@return integer pos
function M.get(win)
    local st = stacks[win]
    if not st then
        return {}, 0
    end
    rebuild(st)
    local copy = {}
    for i, b in ipairs(st.entries) do
        copy[i] = b
    end
    return copy, st.pos
end

--- Purge `buf` from EVERY window's trail (BufDelete/BufWipeout), collapsing the adjacent
--- duplicates the removal exposes and dropping trails that end up empty.
---@param buf integer
---@return nil
function M.purge(buf)
    for win, st in pairs(stacks) do
        rebuild(st, buf)
        if #st.entries == 0 then
            stacks[win] = nil
        end
    end
end

--- Forget `win`'s trail entirely (WinClosed, :LvimBufHistory clear).
---@param win integer
---@return nil
function M.clear(win)
    stacks[win] = nil
end

--- Seed the CURRENT (newly created) window with a copy of the trail of the window it was
--- split from — WinNew fires with the new window current and winnr("#") still naming the
--- origin (see the header). No-op when the origin has no trail yet.
---@return nil
function M.inherit()
    local win = api.nvim_get_current_win()
    if stacks[win] then
        return
    end
    local origin = vim.fn.win_getid(vim.fn.winnr("#"))
    local src = origin ~= 0 and stacks[origin] or nil
    if not src then
        return
    end
    local copy = {}
    for i, b in ipairs(src.entries) do
        copy[i] = b
    end
    stacks[win] = { entries = copy, pos = src.pos }
end

--- Trail totals + sanity for :checkhealth — windows tracked, entries held, and any stack
--- whose pointer fell out of range (must never happen; every mutation re-clamps it).
---@return { windows: integer, entries: integer, bad: integer }
function M.stats()
    local windows, entries, bad = 0, 0, 0
    for _, st in pairs(stacks) do
        windows = windows + 1
        entries = entries + #st.entries
        local ok = (#st.entries == 0 and st.pos == 0) or (st.pos >= 1 and st.pos <= #st.entries)
        if not ok then
            bad = bad + 1
        end
    end
    return { windows = windows, entries = entries, bad = bad }
end

--- Install the autocmds that drive the trails (once; called from setup). BufEnter covers
--- buffer switches inside a window, WinEnter seeds/refreshes on window focus (a window
--- created before setup gets a trail on first entry); ev.buf is the entered buffer for
--- both. WinClosed carries the closing winid in ev.match, BEFORE the window is gone.
---@return nil
function M.register()
    local grp = api.nvim_create_augroup("lvim_buf_history", { clear = true })
    api.nvim_create_autocmd({ "BufEnter", "WinEnter" }, {
        group = grp,
        callback = function(ev)
            M.record(api.nvim_get_current_win(), ev.buf)
        end,
    })
    api.nvim_create_autocmd("WinNew", {
        group = grp,
        callback = function()
            if config.inherit then
                M.inherit()
            end
        end,
    })
    api.nvim_create_autocmd("WinClosed", {
        group = grp,
        callback = function(ev)
            local win = tonumber(ev.match)
            if win then
                stacks[win] = nil
            end
        end,
    })
    -- :bdelete fires BufDelete (still listed→unlisted), :bwipeout only BufWipeout — hook
    -- both so either form of removal purges the buffer from every trail eagerly.
    api.nvim_create_autocmd({ "BufDelete", "BufWipeout" }, {
        group = grp,
        callback = function(ev)
            M.purge(ev.buf)
        end,
    })
    -- :terminal ENTERS its buffer while 'buftype' is still "" (the terminal state is only
    -- assigned afterwards, announced by TermOpen), so the BufEnter filter above cannot see
    -- it and records the visit. TermOpen is the event for that state change — re-apply the
    -- record filter there (now that the real buftype is visible) and purge retroactively,
    -- keeping the ignore.buftype "terminal" default honest. A user who removed "terminal"
    -- from the ignore list keeps the recorded visit.
    api.nvim_create_autocmd("TermOpen", {
        group = grp,
        callback = function(ev)
            if not recordable(ev.buf) then
                M.purge(ev.buf)
            end
        end,
    })
end

return M
