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
local tab = state.tabs[state.active]
vim.api.nvim_set_current_win(state.main_win)
vim.api.nvim_win_set_buf(state.main_win, tab.buf)
vim.fn.chansend(tab.job, "printf '\\033]133;A\\007first\\nline\\n\\033]133;A\\007second\\nline\\n'\n")

local prompt_namespace = vim.api.nvim_get_namespaces()["nvim.terminal.prompt"]
assert(vim.wait(1000, function()
  return #vim.api.nvim_buf_get_extmarks(tab.buf, prompt_namespace, 0, -1, {}) >= 2
end), "test terminal must receive OSC 133 prompt marks")

local prompt_marks = vim.api.nvim_buf_get_extmarks(tab.buf, prompt_namespace, 0, -1, {})
local expected_line = prompt_marks[#prompt_marks][2] + 1
vim.api.nvim_win_set_cursor(state.main_win, { vim.api.nvim_buf_line_count(tab.buf), 0 })
local previous_prompt_map = vim.fn.maparg("<C-S-Up>", "n", false, true)
previous_prompt_map.callback()
assert(vim.api.nvim_win_get_cursor(state.main_win)[1] == expected_line, "<C-S-Up> must jump to the previous OSC 133 prompt")

local original_get_mode = vim.api.nvim_get_mode
local original_cmd = vim.cmd
local original_schedule = vim.schedule
local commands = {}
local scheduled = {}
vim.api.nvim_get_mode = function()
  return { mode = "t" }
end
vim.cmd = function(command)
  table.insert(commands, command)
end
vim.schedule = function(callback)
  table.insert(scheduled, callback)
end
local terminal_prompt_map = vim.fn.maparg("<C-S-Up>", "t", false, true)
local callback_ok, callback_error = pcall(terminal_prompt_map.callback)
vim.api.nvim_get_mode = original_get_mode
vim.cmd = original_cmd
vim.schedule = original_schedule
assert(callback_ok, callback_error)
assert(vim.deep_equal(commands, { "stopinsert" }), "terminal prompt navigation must wait for terminal mode to exit")
assert(#scheduled == 1, "terminal prompt navigation must schedule its normal-mode motion")

vim.api.nvim_set_current_buf(state.scratch_buf)
assert(vim.tbl_isempty(vim.fn.maparg("<C-S-Up>", "t", false, true)), "scratch must not get prompt navigation")
