-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here
local keymap = vim.keymap.set
local silent = { silent = true }

table.unpack = table.unpack or unpack -- 5.1 compatibility
keymap("i", "jk", "<Esc>", silent)
keymap("n", "<leader>.", "<cmd>Telescope current_buffer_fuzzy_find<cr>", silent)
keymap("n", "<C-e>", "<cmd>Neotree toggle<cr>", silent)

keymap("n", "<C-h>", ":NavigatorLeft<CR>", silent)
keymap("n", "<C-j>", ":NavigatorDown<CR>", silent)
keymap("n", "<C-k>", ":NavigatorUp<CR>", silent)
keymap("n", "<C-l>", ":NavigatorRight<CR>", silent)

-- Move selected line / block of text in visual mode
keymap("x", "K", ":move '<-2<CR>gv-gv", silent)
keymap("x", "J", ":move '>+1<CR>gv-gv", silent)
