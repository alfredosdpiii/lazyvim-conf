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

-- Helper to build the RA.Aid command string
local function build_raid_cmd(flags, prompt)
  return string.format(
    [[split | terminal ra-aid %s --provider openrouter --model google/gemini-2.5-pro-preview --use-aider -m "%s"]],
    flags,
    prompt
  )
end

-- 1. Cowboy Mode (default)
vim.api.nvim_create_user_command("RAIDCowboy", function()
  vim.cmd(build_raid_cmd("--cowboy-mode", "Describe your task here"))
end, {
  desc = "Open RA.Aid in cowboy mode (no approvals) in a split terminal",
})

-- 2. Research-Only Mode
vim.api.nvim_create_user_command("RAIDCodebase", function()
  vim.cmd(build_raid_cmd("--research-only --cowboy-mode", "Research: analyze the current codebase"))
end, {
  desc = "Open RA.Aid in research-only mode (analysis only) in a split terminal",
})

-- 3. Coder Mode (Aider Integration)
vim.api.nvim_create_user_command("RAIDCoder", function()
  vim.cmd(build_raid_cmd("--use-aider --cowboy-mode", "Refactor this file"))
end, {
  desc = "Run RA.Aid with Aider for code edits on the current file",
})

-- 4. Interactive Chat Mode
vim.api.nvim_create_user_command("RAIDChat", function()
  vim.cmd(
    string.format(
      "vsplit | terminal ra-aid --chat --provider openrouter --model google/gemini-2.5-pro-preview --cowboy-mode"
    )
  )
end, {
  desc = "Open RA.Aid in interactive chat mode in a vertical split terminal",
})

-- Helper builder for RA.Aid + Aider
local function raid_aider_cmd(extra_flags, prompt)
  return string.format(
    'split | terminal ra-aid --use-aider %s --provider openrouter --model google/gemini-2.5-pro-preview -m "%s"',
    extra_flags,
    prompt
  )
end

-- 1.1. Open Aider Session (reattach if exists)
vim.api.nvim_create_user_command("RAIDAiderOpen", function()
  vim.cmd(raid_aider_cmd("", "Aider: Start or reattach session"))
end, {
  desc = "Open or reattach to an Aider-powered RA.Aid session in a split terminal",
})

-- 1.2. Add All Modified Git Files to Session
vim.api.nvim_create_user_command("RAIDAiderAddModified", function()
  vim.cmd(raid_aider_cmd('--aider-args="--add-modified"', "Aider: Add all git-modified files"))
end, {
  desc = "Add all git-modified files to the current Aider session",
})

-- 1.3. Send Current Buffer to Aider
vim.api.nvim_create_user_command("RAIDAiderSendBuffer", function()
  vim.cmd(raid_aider_cmd('--aider-args="--send-buffer"', "Aider: Send current buffer"))
end, {
  desc = "Send the entire current buffer to Aider for context or edits",
})

-- 1.4. Send Selected Lines to Aider
vim.api.nvim_create_user_command("RAIDAiderSendSelection", function(opts)
  -- opts.args captures a range like `'<,'>` for visual selection
  vim.cmd(
    string.format(
      "range %s | %s | normal! gv",
      opts.line1 .. "," .. opts.line2,
      raid_aider_cmd('--aider-args="--send-selection"', "Aider: Send visual selection")
    )
  )
end, {
  desc = "Send the visually selected text to Aider",
  range = true,
})

-- 1.5. Send Buffer Diagnostics to Aider
vim.api.nvim_create_user_command("RAIDAiderDiagnostics", function()
  vim.cmd(raid_aider_cmd('--aider-args="--send-diagnostics"', "Aider: Send buffer diagnostics"))
end, {
  desc = "Send current buffer diagnostics (lint errors, warnings) to Aider",
})

-- 1.6. Reset Aider Session
vim.api.nvim_create_user_command("RAIDAiderReset", function()
  vim.cmd(raid_aider_cmd('--aider-args="--reset"', "Aider: Reset session"))
end, {
  desc = "Clear all files and chat history from the current Aider session",
})

-- vim.cmd([[
--   augroup RAIDAdvancedAider
--     autocmd!
--     " On saving any code file, add and send changes to Aider for review
--     autocmd BufWritePost *.py,*.js,*.ts lua vim.cmd("RAIDAiderAddModified") | vim.cmd("RAIDAiderSendBuffer")
--     " On opening a file, reattach to the session for continuity
--     autocmd BufReadPost * lua vim.cmd("RAIDAiderOpen")
--     " On entering visual mode, map <leader>a to send selection
--     autocmd FileType * vnoremap <buffer> <leader>a :RAIDAiderSendSelection<CR>
--     " On requesting diagnostics (e.g., via :RAIDAiderDiagnostics)
--   augroup END
-- ]])
