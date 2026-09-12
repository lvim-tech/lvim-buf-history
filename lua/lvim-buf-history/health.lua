-- lvim-buf-history: :checkhealth lvim-buf-history.
-- Diagnoses what makes per-window history misbehave invisibly: setup() never ran (no
-- autocmds → nothing records), a missing lvim-ui (the list has no window to open), a
-- config that filters everything out or trims the trail to nothing, and — the internal
-- invariant — a pointer that fell outside its trail (every mutation re-clamps it, so a
-- bad stack means a real bug). Everything here is read-only reporting.
--
---@module "lvim-buf-history.health"

local config = require("lvim-buf-history.config")
local history = require("lvim-buf-history.history")

local M = {}

--- Validate the live config table; error on each violation, ok when clean.
---@param health table  the vim.health reporter
---@return nil
local function check_config(health)
    local problems = 0

    if type(config.max_len) ~= "number" or config.max_len < 1 then
        health.error(("max_len must be a number >= 1 (got %s)"):format(vim.inspect(config.max_len)))
        problems = problems + 1
    end

    for _, field in ipairs({ "inherit", "map_default_keys" }) do
        if type(config[field]) ~= "boolean" then
            health.error(("%s must be a boolean (got %s)"):format(field, vim.inspect(config[field])))
            problems = problems + 1
        end
    end

    local ignore = config.ignore
    if type(ignore) ~= "table" then
        health.error(("ignore must be a table (got %s)"):format(type(ignore)))
        problems = problems + 1
    else
        for _, list in ipairs({ "buftype", "filetype" }) do
            if type(ignore[list]) ~= "table" then
                health.error(("ignore.%s must be a list of strings (got %s)"):format(list, vim.inspect(ignore[list])))
                problems = problems + 1
            end
        end
    end

    local keys = config.keys
    if type(keys) ~= "table" then
        health.error(("keys must be a table (got %s)"):format(type(keys)))
        problems = problems + 1
    else
        for _, k in ipairs({ "back", "forward", "list" }) do
            if keys[k] ~= nil and type(keys[k]) ~= "string" then
                health.error(("keys.%s must be a string (got %s)"):format(k, vim.inspect(keys[k])))
                problems = problems + 1
            end
        end
    end

    if problems == 0 then
        health.ok("config valid")
    end
end

--- Run the health report.
---@return nil
function M.check()
    local health = vim.health
    health.start("lvim-buf-history")

    if vim.fn.has("nvim-0.12") == 1 then
        health.ok("Neovim >= 0.12")
    else
        health.error("Neovim >= 0.12 is required (the lvim-tech set targets 0.12)")
    end

    local ok_utils, utils = pcall(require, "lvim-utils.utils")
    if ok_utils and type(utils.merge) == "function" then
        health.ok("lvim-utils found (merge)")
    else
        health.warn("lvim-utils not found — setup() falls back to tbl_deep_extend")
    end

    local ok_ui = pcall(require, "lvim-ui")
    if ok_ui then
        health.ok("lvim-ui found (trail list)")
    else
        health.warn("lvim-ui not found — :LvimBufHistory list cannot open (back/forward still work)")
    end

    if pcall(require, "lvim-icons") then
        health.ok("lvim-icons found (list file icons)")
    else
        health.info("lvim-icons not found — the trail list shows plain labels")
    end

    local ok_bh, bh = pcall(require, "lvim-buf-history")
    if not ok_bh then
        health.error("lvim-buf-history failed to load: " .. tostring(bh))
        return
    end

    if bh.is_registered() then
        local stats = history.stats()
        health.ok(
            ("recording — %d window trail(s), %d entr%s held"):format(
                stats.windows,
                stats.entries,
                stats.entries == 1 and "y" or "ies"
            )
        )
        -- The pointer invariant: 1 <= pos <= #entries on every non-empty trail. Every
        -- mutation re-clamps it, so a violation is a plugin bug, not a config problem.
        if stats.bad > 0 then
            health.error(("%d trail(s) have an out-of-range pointer — please report this"):format(stats.bad))
        else
            health.ok("all trail pointers in range")
        end
    else
        health.warn("setup() has not run — nothing is recorded (call require('lvim-buf-history').setup({}))")
    end

    health.info(
        ("max_len=%s  inherit=%s  map_default_keys=%s  ignore: %d buftype(s), %d filetype(s)"):format(
            tostring(config.max_len),
            tostring(config.inherit),
            tostring(config.map_default_keys),
            #((config.ignore or {}).buftype or {}),
            #((config.ignore or {}).filetype or {})
        )
    )

    check_config(health)
end

return M
