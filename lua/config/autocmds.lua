-- Autocmds are automatically loaded on the VeryLazy event
-- Default autocmds that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/autocmds.lua
-- Add any additional autocmds here
vim.api.nvim_create_autocmd("FileType", {
  pattern = "markdown",
  callback = function(args)
    vim.lsp.start({
      name = "iwes",
      cmd = { "iwes" },
      root_dir = vim.fs.root(args.buf, { ".iwe" }),
      flags = {
        debounce_text_changes = 500,
      },
    })
  end,
})
