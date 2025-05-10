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

-- Add Augment signin fix command that copies URL to clipboard
vim.api.nvim_create_user_command("AugmentSigninFix", function()
  -- Create a temporary file to store the URL
  local temp_file = vim.fn.tempname()

  -- Temporarily disable Noice if it exists
  local has_noice = package.loaded["noice"] ~= nil
  if has_noice then
    vim.cmd("Noice disable")
  end

  -- Create a custom redirection function for Augment login response
  vim.cmd([[
    function! CaptureAugmentURL() abort
      redir => g:augment_url_output
      silent Augment signin
      redir END
      
      " Extract URL from the output
      let url_pattern = 'https://[a-zA-Z0-9:/?=&._-]\+'
      let url_matches = matchlist(g:augment_url_output, url_pattern)
      
      if len(url_matches) > 0
        let g:augment_signin_url = url_matches[0]
        " Copy to clipboard
        let @+ = g:augment_signin_url
        let @* = g:augment_signin_url
        
        " Also write to temp file as backup
        call writefile([g:augment_signin_url], ']] .. temp_file .. [[')
        
        echo "\nURL copied to clipboard: " . g:augment_signin_url
      else
        echo "Could not extract URL from Augment output"
      endif
    endfunction
  ]])

  -- Call the capture function
  vim.cmd("call CaptureAugmentURL()")

  -- Read from temp file as backup in case clipboard doesn't work
  vim.defer_fn(function()
    if vim.fn.filereadable(temp_file) == 1 then
      local url = vim.fn.readfile(temp_file)[1]
      if url then
        print("\nBackup URL (in case clipboard failed): " .. url)

        -- Try to open URL automatically based on OS
        local open_cmd = nil
        if vim.fn.has("mac") == 1 then
          open_cmd = { "open", url }
        elseif vim.fn.has("unix") == 1 then
          open_cmd = { "xdg-open", url }
        elseif vim.fn.has("win32") == 1 then
          open_cmd = { "cmd", "/c", "start", url }
        end

        if open_cmd then
          vim.fn.jobstart(open_cmd)
        end
      end
    end

    -- Restore Noice
    if has_noice then
      vim.cmd("Noice enable")
    end
  end, 1000)
end, {})

-- Keymap for easier access
vim.keymap.set("n", "<leader>as", ":AugmentSigninFix<CR>", { desc = "Augment Signin with URL copy" })

vim.api.nvim_create_user_command("OpenCodeTerminal", function()
  vim.cmd("vsplit | terminal opencode .")
end, {})
