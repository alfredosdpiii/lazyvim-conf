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

-- RA.Aid Neovim Integration (updated with cost‑efficient model pairings)
-- Recommended default primary: openai/o4-mini-high (fast + cheap)
-- Recommended default expert : openai/gpt-4.1 (high patch accuracy)
--
-- Change PRIMARY_MODEL and EXPERT_MODEL below to switch stack easily.
local PROVIDER = "openrouter"
local PRIMARY_MODEL = "openai/o4-mini-high"
local EXPERT_MODEL = "openai/gpt-4.1"

---------------------------------------------------------------------
-- Core helper: build a generic RA.Aid command string
---------------------------------------------------------------------
local function build_raid_cmd(flags, prompt)
  return string.format(
    [[split | terminal ra-aid %s --provider %s --model %s --expert-provider %s --expert-model %s -m "%s"]],
    flags,
    PROVIDER,
    PRIMARY_MODEL,
    PROVIDER,
    EXPERT_MODEL,
    prompt
  )
end

---------------------------------------------------------------------
-- 1. Cowboy Mode (default – quick, no approvals)
---------------------------------------------------------------------
vim.api.nvim_create_user_command("RAIDCowboy", function()
  vim.cmd(build_raid_cmd("--use aider --cowboy-mode", "Describe your task here"))
end, { desc = "Open RA.Aid in cowboy mode in a horizontal split terminal" })

---------------------------------------------------------------------
-- 2. Research‑Only Mode (analysis, no code edits)
---------------------------------------------------------------------
vim.api.nvim_create_user_command("RAIDCodebase", function()
  vim.cmd(build_raid_cmd("--use-aider --research-only --cowboy-mode", "Research: analyze the current codebase"))
end, { desc = "Open RA.Aid in research‑only mode" })

---------------------------------------------------------------------
-- 3. Coder Mode (Aider Integration for code refactors)
---------------------------------------------------------------------
vim.api.nvim_create_user_command("RAIDCoder", function()
  vim.cmd(build_raid_cmd("--use-aider --cowboy-mode", "Refactor this file"))
end, { desc = "Run RA.Aid with Aider for code edits on the current file" })

---------------------------------------------------------------------
-- 4. Interactive Chat Mode (manual conversation)
---------------------------------------------------------------------
vim.api.nvim_create_user_command("RAIDChat", function()
  vim.cmd(
    string.format(
      [[vsplit | terminal ra-aid --chat --provider %s --model %s --expert-provider %s --expert-model %s --cowboy-mode]],
      PROVIDER,
      PRIMARY_MODEL,
      PROVIDER,
      EXPERT_MODEL
    )
  )
end, { desc = "Open RA.Aid in interactive chat mode in a vertical split" })

---------------------------------------------------------------------
-- 5. Plain Chat with Current Buffer Content (NEW)
--    Sends the *entire current buffer* as the initial message so you
--    can discuss code or text without Aider’s structured diff logic.
---------------------------------------------------------------------
vim.api.nvim_create_user_command("RAIDPlainChat", function()
  local bufpath = vim.fn.expand("%:p")
  if bufpath == "" then
    vim.notify("Current buffer has no file on disk", vim.log.levels.ERROR)
    return
  end
  vim.cmd(
    string.format(
      [[split | terminal ra-aid --chat --provider %s --model %s --expert-provider %s --expert-model %s --msg-file "%s" --cowboy-mode]],
      PROVIDER,
      PRIMARY_MODEL,
      PROVIDER,
      EXPERT_MODEL,
      bufpath
    )
  )
end, { desc = "Chat with RA.Aid using entire current buffer as prompt" })

---------------------------------------------------------------------
-- 6. Alternative Ready‑made Stacks
---------------------------------------------------------------------
local function build_pair_cmd(primary, expert, flags, prompt)
  return string.format(
    [[split | terminal ra-aid %s --provider %s --model %s --expert-provider %s --expert-model %s -m "%s"]],
    flags,
    PROVIDER,
    primary,
    PROVIDER,
    expert,
    prompt
  )
end

-- 6.1 Ultra‑Budget: DeepSeek V3 + o4-mini-high
vim.api.nvim_create_user_command("RAIDBudget", function()
  vim.cmd(
    build_pair_cmd("deepseek/deepseek-chat-v3-0324", "openai/o4-mini-high", "--cowboy-mode", "Describe your task here")
  )
end, { desc = "RA.Aid with DeepSeek V3 primary and o4-mini-high expert" })

-- 6.2 Latency‑Optimised: GPT-4.1 nano + o3-mini-high
vim.api.nvim_create_user_command("RAIDLatency", function()
  vim.cmd(build_pair_cmd("openai/gpt-4.1-nano", "openai/o3-mini-high", "--cowboy-mode", "Describe your task here"))
end, { desc = "RA.Aid with GPT‑4.1 nano primary and o3-mini-high expert" })

---------------------------------------------------------------------
-- 7. Aider Convenience Helpers (reuse current PRIMARY/EXPERT models)
---------------------------------------------------------------------
local function raid_aider_cmd(extra_flags, prompt)
  return string.format(
    [[split | terminal ra-aid --use-aider %s --provider %s --model %s --expert-provider %s --expert-model %s -m "%s"]],
    extra_flags,
    PROVIDER,
    PRIMARY_MODEL,
    PROVIDER,
    EXPERT_MODEL,
    prompt
  )
end

vim.api.nvim_create_user_command("RAIDAiderOpen", function()
  vim.cmd(raid_aider_cmd("", "Aider: Start or reattach session"))
end, { desc = "Open or reattach to an Aider session" })

vim.api.nvim_create_user_command("RAIDAiderAddModified", function()
  vim.cmd(raid_aider_cmd('--aider-args="--add-modified"', "Aider: Add all git‑modified files"))
end, { desc = "Add all git‑modified files to Aider" })

vim.api.nvim_create_user_command("RAIDAiderSendBuffer", function()
  vim.cmd(raid_aider_cmd('--aider-args="--send-buffer"', "Aider: Send current buffer"))
end, { desc = "Send entire current buffer to Aider" })

vim.api.nvim_create_user_command("RAIDAiderSendSelection", function(opts)
  vim.cmd(
    string.format(
      "range %s | %s | normal! gv",
      opts.line1 .. "," .. opts.line2,
      raid_aider_cmd('--aider-args="--send-selection"', "Aider: Send visual selection")
    )
  )
end, { desc = "Send visually selected text to Aider", range = true })

vim.api.nvim_create_user_command("RAIDAiderDiagnostics", function()
  vim.cmd(raid_aider_cmd('--aider-args="--send-diagnostics"', "Aider: Send buffer diagnostics"))
end, { desc = "Send diagnostics to Aider" })

vim.api.nvim_create_user_command("RAIDAiderReset", function()
  vim.cmd(raid_aider_cmd('--aider-args="--reset"', "Aider: Reset session"))
end, { desc = "Reset current Aider session" })

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
