vim.g.mapleader = " "
require("pi_ide").setup()
require("pi_ide").open()

local terminal_map = vim.fn.maparg("<Space>ag", "t", false, true)
assert(vim.tbl_isempty(terminal_map), "<leader>ag must remain literal terminal input")

local normal_map = vim.fn.maparg("<Space>ag", "n", false, true)
assert(not vim.tbl_isempty(normal_map), "<leader>ag must remain available in normal mode")

for _, key in ipairs({ "<C-S-Up>", "<C-S-Down>" }) do
  local terminal_prompt_map = vim.fn.maparg(key, "t", false, true)
  assert(not vim.tbl_isempty(terminal_prompt_map), key .. " must navigate prompts from terminal mode")

  local normal_prompt_map = vim.fn.maparg(key, "n", false, true)
  assert(not vim.tbl_isempty(normal_prompt_map), key .. " must navigate prompts from terminal-normal mode")
end

local state = _G.__pi_ide_state
vim.api.nvim_set_current_buf(state.scratch_buf)
assert(vim.tbl_isempty(vim.fn.maparg("<C-S-Up>", "t", false, true)), "scratch must not get prompt navigation")
