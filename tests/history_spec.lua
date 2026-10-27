-- The trail, as a state machine.
--
-- Three rules carry it, and all three are statable without touching the editor's UI:
--
-- 1. browser semantics -- going back and then somewhere NEW discards what was forward;
-- 2. the pointer always describes what is on screen. It may only move once the buffer switch
--    has actually happened, because Neovim is allowed to refuse one ('nohidden' plus unsaved
--    changes is E37), and a pointer that moved anyway makes the trail lie;
-- 3. a dead buffer is never a target. Pruning happens before every traversal and read, and
--    collapses the duplicates it exposes.

local history = require("lvim-buf-history.history")
local config = require("lvim-buf-history.config")

--- A listed, named, real buffer -- the only kind that may enter a trail.
---@param name string
---@return integer
local function listed_buffer(name)
    local buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_name(buf, name)
    return buf
end

--- A window with a trail of its own, recorded from `bufs` in order, and cleaned up by the
--- caller through history.clear.
---@param bufs integer[]
---@return integer win
local function window_with_trail(bufs)
    local win = vim.api.nvim_get_current_win()
    history.clear(win)
    for _, b in ipairs(bufs) do
        history.record(win, b)
    end
    return win
end

--- Run `fn` with the plugin's own autocmds silenced.
---
--- setup() has run by the time this spec does (the baseline calls it), so BufEnter is live and
--- RECORDS. Deleting the buffer a window is showing makes that window fall back to another one,
--- which is a real visit and lands in the trail -- correct behaviour that has nothing to do with
--- the rule under test. 'eventignore' keeps the editor's own reaction out of the measurement.
---@param fn fun()
local function without_events(fn)
    local was = vim.o.eventignore
    vim.o.eventignore = "all"
    local ok, err = pcall(fn)
    vim.o.eventignore = was
    truthy(ok, tostring(err))
end

local function fresh(n, tag)
    local out = {}
    for i = 1, n do
        out[i] = listed_buffer(vim.fn.tempname() .. "/" .. tag .. i .. ".txt")
    end
    return out
end

describe("lvim-buf-history: recording a visit")

it("appends in visit order", function()
    local b = fresh(3, "append")
    local win = window_with_trail(b)
    local entries, pos = history.get(win)
    eq(b, entries)
    eq(3, pos, "the pointer sits on the newest entry")
end)

it("standing on a buffer again is not a second entry", function()
    local b = fresh(2, "dup")
    local win = window_with_trail({ b[1], b[2], b[2], b[2] })
    local entries = history.get(win)
    eq({ b[1], b[2] }, entries)
end)

it("visiting somewhere new discards the forward tail", function()
    local b = fresh(4, "tail")
    local win = window_with_trail({ b[1], b[2], b[3] })
    -- stand mid-trail, as two backs would leave it
    history.go(win, 1)
    eq(1, select(2, history.get(win)))

    history.record(win, b[4])
    local entries, pos = history.get(win)
    eq({ b[1], b[4] }, entries, "b2 and b3 were forward of the pointer and are gone")
    eq(2, pos)
end)

it("the trail is ring-trimmed at max_len, carrying the pointer with it", function()
    local b = fresh(5, "ring")
    local was = config.max_len
    config.max_len = 3
    local win = window_with_trail(b)
    config.max_len = was

    local entries, pos = history.get(win)
    eq({ b[3], b[4], b[5] }, entries, "the oldest entries fall off the front")
    eq(3, pos, "the pointer still names the newest entry after the trim")
end)

it("an unlisted buffer is never recorded", function()
    local scratch = vim.api.nvim_create_buf(false, true) -- unlisted
    local win = window_with_trail({ scratch })
    eq({}, (history.get(win)))
end)

it("a buffer whose filetype is on the ignore list is never recorded", function()
    local buf = listed_buffer(vim.fn.tempname() .. "/ignored.txt")
    vim.bo[buf].filetype = "lvim-history-spec-ft"
    local was = config.ignore
    config.ignore = { filetype = { "lvim-history-spec-ft" }, buftype = {} }
    local win = window_with_trail({ buf })
    config.ignore = was
    eq({}, (history.get(win)))
end)

describe("lvim-buf-history: the pointer describes what is on screen")

it("back and forward walk the trail and come back", function()
    local b = fresh(3, "walk")
    local win = window_with_trail(b)
    vim.api.nvim_win_set_buf(win, b[3])

    truthy(history.back())
    eq(b[2], vim.api.nvim_get_current_buf())
    eq(2, select(2, history.get(win)))

    truthy(history.back())
    eq(b[1], vim.api.nvim_get_current_buf())

    truthy(history.forward())
    truthy(history.forward())
    eq(b[3], vim.api.nvim_get_current_buf())
    eq(3, select(2, history.get(win)))
end)

it("the oldest entry has no back, the newest no forward", function()
    local b = fresh(2, "edge")
    local win = window_with_trail(b)
    vim.api.nvim_win_set_buf(win, b[2])
    eq(false, history.forward(), "already on the newest")
    truthy(history.back())
    eq(false, history.back(), "already on the oldest")
end)

it("a REFUSED switch leaves the pointer where it was", function()
    local b = fresh(3, "refused")
    local win = window_with_trail(b)
    vim.api.nvim_win_set_buf(win, b[3])

    -- 'nohidden' plus unsaved changes: Neovim will not leave this buffer (E37).
    local was_hidden = vim.o.hidden
    vim.o.hidden = false
    vim.api.nvim_buf_set_lines(b[3], 0, -1, false, { "unsaved" })

    eq(false, history.back(), "the switch cannot happen, so the move did not happen")
    eq(3, select(2, history.get(win)), "the pointer may not move without the buffer")
    eq(false, history.back())
    eq(3, select(2, history.get(win)), "and not twice, either")
    eq(b[3], vim.api.nvim_get_current_buf())

    vim.bo[b[3]].modified = false
    vim.o.hidden = was_hidden
    -- With the refusal gone, the trail is still intact and back works from where it really is.
    truthy(history.back())
    eq(b[2], vim.api.nvim_get_current_buf())
end)

describe("lvim-buf-history: a dead buffer is never a target")

it("a wiped buffer is dropped from the trail before a traversal", function()
    local b = fresh(3, "wiped")
    local win = window_with_trail(b)
    vim.api.nvim_win_set_buf(win, b[3])
    vim.api.nvim_buf_delete(b[2], { force = true })

    local entries = history.get(win)
    eq({ b[1], b[3] }, entries)
    truthy(history.back())
    eq(b[1], vim.api.nvim_get_current_buf(), "back skips over what is gone")
end)

it("pruning collapses the duplicates it exposes", function()
    local b = fresh(3, "collapse")
    -- A, B, A, where B dies: without collapsing, the trail would read A, A.
    local win = window_with_trail({ b[1], b[2], b[1] })
    eq({ b[1], b[2], b[1] }, (history.get(win)), "precondition")
    vim.api.nvim_buf_delete(b[2], { force = true })
    eq({ b[1] }, (history.get(win)))
end)

it("the pointer lands on the nearest survivor at or before it", function()
    local b = fresh(4, "survivor")
    local win = window_with_trail(b)
    history.go(win, 3)
    eq(3, select(2, history.get(win)), "precondition")

    without_events(function()
        vim.api.nvim_buf_delete(b[3], { force = true })
    end)
    local entries, pos = history.get(win)
    eq({ b[1], b[2], b[4] }, entries)
    eq(2, pos, "the entry the pointer was on is gone; back resumes from the one before it")
end)

it("purge removes a buffer from every window's trail", function()
    local b = fresh(2, "purge")
    local win = window_with_trail(b)
    history.purge(b[1])
    eq({ b[2] }, (history.get(win)))
end)

describe("lvim-buf-history: what a reader may touch")

it("get hands back a copy, not the trail itself", function()
    local b = fresh(2, "copy")
    local win = window_with_trail(b)
    local entries = history.get(win)
    entries[1] = -1
    entries[#entries + 1] = -2
    eq(b, (history.get(win)), "a reader cannot reach the module's own state")
end)

it("an unknown window has an empty trail rather than an error", function()
    local entries, pos = history.get(123456)
    eq({}, entries)
    eq(0, pos)
end)

it("go refuses an index outside the trail", function()
    local b = fresh(2, "range")
    local win = window_with_trail(b)
    eq(false, history.go(win, 0))
    eq(false, history.go(win, 3))
    eq(false, history.go(win, 2), "already there")
end)

it("stats counts the trails and reports no out-of-range pointer", function()
    local b = fresh(2, "stats")
    local win = window_with_trail(b)
    local s = history.stats()
    truthy(s.windows >= 1, "the window with a trail has to be counted")
    truthy(s.entries >= 2)
    eq(0, s.bad, "every mutation re-clamps the pointer; a bad one is a defect")
    history.clear(win)
end)
