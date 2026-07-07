-- lvim-buf-history.ui: the trail list — the current window's history rendered through the
-- canonical lvim-ui select (centered, themed, cursor-managed). One row per trail entry,
-- oldest first: a lead file icon from lvim-icons (soft dependency — plain labels without
-- it), the buffer's tail name plus its short directory, and the CURRENT position marked
-- with the canonical `➤` pointer (mark_current is off — the pointer IS the marker; the
-- entry still goes in as current_item so the select focuses that row on open). Confirming
-- a row JUMPS the pointer there (history.go — sets the position, never appends).
--
---@module "lvim-buf-history.ui"

local history = require("lvim-buf-history.history")

local api = vim.api

local M = {}

-- The canonical active-item pointer (U+27A4, display width 1); non-current rows pad with
-- a space so every label starts in the same column.
local POINTER = "➤"

--- The lead icon for a trail entry, resolved through lvim-icons (filename chain with a
--- filetype hint; the filetype table for no-name buffers). nil without lvim-icons.
---@param buf integer
---@param name string  full buffer name ("" for no-name)
---@return string|nil
local function icon_for(buf, name)
    local ok, icons = pcall(require, "lvim-icons")
    if not ok then
        return nil
    end
    local ft = vim.bo[buf].filetype
    local res
    if name ~= "" then
        res = icons.get(name, { filetype = ft ~= "" and ft or nil })
    else
        res = icons.by_filetype(ft)
    end
    return res and res.glyph or nil
end

--- The row text for a trail entry: tail filename + its cwd-relative (or ~-shortened)
--- directory, so same-named files in different directories stay tellable apart.
---@param name string  full buffer name ("" for no-name)
---@return string
local function label_for(name)
    if name == "" then
        return "[No Name]"
    end
    local tail = vim.fn.fnamemodify(name, ":t")
    local dir = vim.fn.fnamemodify(name, ":~:.:h")
    if dir == "." or dir == "" then
        return tail
    end
    return tail .. "  " .. dir
end

--- Open the trail list for the current window. Empty trail → an info notify, no window.
---@return nil
function M.list()
    local win = api.nvim_get_current_win()
    local entries, pos = history.get(win)
    if #entries == 0 then
        vim.notify("buf-history: this window has no history yet", vim.log.levels.INFO)
        return
    end
    local ok_ui, ui = pcall(require, "lvim-ui")
    if not ok_ui then
        vim.notify(
            "buf-history: lvim-ui is required for the list (see :checkhealth lvim-buf-history)",
            vim.log.levels.ERROR
        )
        return
    end
    local items = {}
    for i, buf in ipairs(entries) do
        local name = api.nvim_buf_get_name(buf)
        items[i] = {
            label = (i == pos and POINTER or " ") .. " " .. label_for(name),
            icon = icon_for(buf, name),
        }
    end
    ui.select({
        title = "Buffer history",
        items = items,
        current_item = items[pos],
        mark_current = false, -- the ➤ pointer is the marker; current_item only focuses the row
        callback = function(confirmed, index)
            if confirmed and index then
                history.go(win, index)
            end
        end,
    })
end

return M
