vim.g.mapleader = " "
require("pi_ide").setup()
require("pi_ide").open()

local terminal_map = vim.fn.maparg("<Space>ag", "t", false, true)
assert(vim.tbl_isempty(terminal_map), "<leader>ag must remain literal terminal input")

local normal_map = vim.fn.maparg("<Space>ag", "n", false, true)
assert(not vim.tbl_isempty(normal_map), "<leader>ag must remain available in normal mode")
