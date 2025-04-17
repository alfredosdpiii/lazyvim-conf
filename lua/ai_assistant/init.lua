-- /home/bryan/.config/nvim/lua/ai_assistant/init.lua

local api = vim.api
local curl = require("plenary.curl")
local ts_context = require("ai_assistant.treesitter_context") -- Our Treesitter module
-- Try loading the enhanced code graph first, but fall back to regular code_graph if it fails
local enhanced_code_graph_ok, enhanced_code_graph = pcall(require, "ai_assistant.enhanced_code_graph")
local code_graph

if enhanced_code_graph_ok and type(enhanced_code_graph) == 'table' and enhanced_code_graph.index_codebase then
  code_graph = enhanced_code_graph
  vim.notify("Using enhanced code graph for codebase indexing", vim.log.levels.INFO)
else
  code_graph = require("ai_assistant.code_graph")
  vim.notify("Using regular code graph for codebase indexing", vim.log.levels.INFO)
end

-- Create a safe json module that works in both sync and async contexts
local safe_json = {}
function safe_json.decode(json_str)
  local status, result = pcall(function()
    return vim.json.decode(json_str)
  end)
  if not status then
    error("JSON decode error: " .. tostring(result))
  end
  return result
end

function safe_json.encode(data)
  local status, result = pcall(function()
    return vim.json.encode(data)
  end)
  if not status then
    error("JSON encode error: " .. tostring(result))
  end
  return result
end

local M = {}

-- --- Configuration ---
-- TODO: Load these securely (e.g., environment variables, config file)
-- Load API key from environment variable
local OPENROUTER_API_KEY = vim.env.OPENROUTER_API_KEY
if not OPENROUTER_API_KEY or #OPENROUTER_API_KEY == 0 then
  -- Use vim.notify for user visibility
  vim.notify("AI Assistant ERROR: OPENROUTER_API_KEY environment variable not set!", vim.log.levels.ERROR)
end
local OPENROUTER_API_URL = "https://openrouter.ai/api/v1/chat/completions"
-- TODO: Make model configurable
local DEFAULT_MODEL = "openai/gpt-4.1" -- Example model

-- Agent Modes Configuration
local agent_modes = {
  ["code"] = {
    name = "Code Mode",
    system_prompt = "You are a helpful AI programming assistant integrated into Neovim. Focus on generating, completing, or modifying code based on user requests.",
  },
  ["explain"] = {
    name = "Explain Mode",
    system_prompt = "You are an expert programmer specializing in explaining code. Given code context and a user query, explain the code's purpose, logic, and potential improvements clearly and concisely.",
  },
  ["refactor"] = {
    name = "Refactor Mode",
    system_prompt = "You are an expert programmer focused on refactoring code. Given code context and a user query, suggest specific refactoring improvements, explain the benefits, and provide refactored code examples when applicable.",
  },
  ["architect"] = {
    name = "Architect Mode",
    system_prompt = "You are a senior software architect. Focus on high-level design, system structure, trade-offs, patterns, and technical planning based on the user's query and any provided context.",
  },
  ["ask"] = {
    name = "Ask Mode",
    system_prompt = "You are an informative assistant. Answer the user's questions clearly and accurately. If the question is about code, use the provided context, otherwise answer generally.",
  },
  ["debug"] = {
    name = "Debug Mode",
    system_prompt = "You are a debugging expert. Analyze the provided code context and user description of a problem. Suggest potential causes, debugging steps, and code fixes to resolve the issue systematically.",
  },
  -- TODO: Add mechanism for custom user modes later
}

-- Window Configuration
local config = {
  windows = {
    position = "bottom", -- 'right', 'left', 'top', 'bottom'
    width = 40, -- Percentage or absolute width
    height = 30, -- Percentage or absolute height (used for top/bottom split)
    display_border = "rounded",
    display_title = " AI Chat ",
    input_border = "rounded",
    input_title = " Input ",
    input_prefix = "> ",
    input_height = 5, -- Lines for the input window
    wrap = true,
  },
}

local current_mode_name = "code" -- Default mode

-- List of modes that should utilize code context when available
local modes_requiring_context = {
  ["code"] = true,
  ["explain"] = true,
  ["refactor"] = true,
  ["debug"] = true,
  ["architect"] = true, -- Architect might benefit from context too
}

-- --- State ---
-- Store buffer and window IDs for the chat interface
local chat_bufnr = nil
local chat_winnr = nil
local conversation_history = {} -- Simple history for now
local nui_component = nil -- To hold the main NuiSplit component
local input_bufnr = nil -- Buffer number for the input window
local input_winnr = nil -- Window ID for the input window

-- Store selected files for context
local selected_files = {}
local last_processed_input = ""
local is_indexing_codebase = false

-- --- Helper Functions ---

-- --- Helper Functions ---

-- Function to log messages (replace with proper logging later)
local function log_message(level, message)
  print(string.format("[%s] AI Assistant: %s", level, message))
end

-- Find the full path of a file from a relative path or filename
local function find_file_path(file_path)
  -- Check if the file exists directly
  if vim.fn.filereadable(file_path) == 1 then
    return file_path
  end

  -- Check in the current directory
  local current_dir = vim.fn.expand("%:p:h")
  local potential_path = current_dir .. "/" .. file_path
  if vim.fn.filereadable(potential_path) == 1 then
    return potential_path
  end

  -- Check in the project root (using git as a heuristic)
  local git_root = vim.fn.system("git rev-parse --show-toplevel 2>/dev/null"):gsub("\n", "")
  if git_root ~= "" then
    potential_path = git_root .. "/" .. file_path
    if vim.fn.filereadable(potential_path) == 1 then
      return potential_path
    end
  end

  -- Try to find using find command (limited to common files to avoid too much searching)
  local cmd = 'find . -type f -name "' .. file_path .. '" -o -name "*' .. file_path .. '*" | head -n 1'
  local found_path = vim.fn.system(cmd):gsub("\n", "")
  if found_path ~= "" and vim.fn.filereadable(found_path) == 1 then
    return found_path
  end

  return nil
end

-- Read the content of a file
local function read_file_content(file_path)
  local file = io.open(file_path, "r")
  if not file then
    log_message("ERROR", "Could not open file: " .. file_path)
    return nil
  end

  local content = file:read("*all")
  file:close()

  return content
end

-- Process @ commands in the input text
local function process_at_commands(input_text)
  local processed_text = input_text
  local file_contexts = {}

  -- Look for @filename patterns
  -- Check for @codebase command first
  if input_text:match("@codebase") then
    log_message("DEBUG", "Found @codebase command")

    -- Check if codebase is already indexed
    if not code_graph.is_indexed() then
      is_indexing_codebase = true
      -- Inform the user
      table.insert(file_contexts, "Indexing codebase for the first time... This may take a moment.")

      -- Schedule the indexing but store a reference to append_to_chat first
      local append_to_chat_ref = append_to_chat -- Create a local reference to the function
      vim.schedule(function()
        local node_count, root_dir = code_graph.index_codebase()
        is_indexing_codebase = false
        -- Use the reference to the function instead of the direct global call
        if append_to_chat_ref then
          append_to_chat_ref(string.format("Codebase indexed: %d entities found in %s", node_count, root_dir))
        end
      end)
    end

    -- Store that we're using codebase context in a flag rather than adding to file_contexts
    local query = input_text:gsub("@codebase", ""):gsub("^%s+", ""):gsub("%s+$", "")
    -- We'll set a special flag to handle codebase context directly in the API call
    M._using_codebase_context = true
    M._codebase_query = query

    -- Just add a short note to file_contexts to indicate we're using codebase
    table.insert(file_contexts, "[Using codebase context for query: " .. query .. "]")

    -- Replace @codebase with a more descriptive phrase
    processed_text = processed_text:gsub("@codebase", "the codebase context")
  end

  -- Process regular @file references
  for file_path in input_text:gmatch("@([^%s]+)") do
    -- Skip processing @codebase since we already handled it
    if file_path ~= "codebase" then
      log_message("DEBUG", "Found file reference: " .. file_path)

      -- Try to find the file
      local full_path = find_file_path(file_path)
      if full_path then
        log_message("DEBUG", "Found file at: " .. full_path)

        -- Read file content
        local file_content = read_file_content(full_path)
        if file_content then
          table.insert(file_contexts, "File: " .. file_path .. "\n" .. file_content)
          -- Add to selected files for persistent tracking
          selected_files[file_path] = full_path
        end
      end

      -- Remove the @file from the input text
      processed_text = processed_text:gsub("@" .. file_path, "the file '" .. file_path .. "'")
    end
  end

  return processed_text, file_contexts
end

-- Internal function to append text to the chat window
-- Safe to use in async contexts
local function append_to_chat(text)
  -- Use vim.schedule to safely call Neovim API functions from async contexts
  vim.schedule(function()
    -- Check buffer validity inside the scheduled callback
    if not chat_bufnr or not api.nvim_buf_is_valid(chat_bufnr) then
      log_message("ERROR", "Chat buffer is not valid for appending.")
      return
    end

    -- Get current content
    local current_lines = api.nvim_buf_get_lines(chat_bufnr, 0, -1, false)

    -- Add new content
    if type(text) == "string" then
      -- Split multiline text into individual lines
      for line in string.gmatch(text, "[^\n]+") do
        table.insert(current_lines, line)
      end
    elseif type(text) == "table" then
      -- Append table of lines
      for _, line in ipairs(text) do
        table.insert(current_lines, line)
      end
    end

    -- Update buffer with new content
    api.nvim_buf_set_lines(chat_bufnr, 0, -1, false, current_lines)

    -- Scroll to bottom of buffer
    if chat_winnr and api.nvim_win_is_valid(chat_winnr) then
      local line_count = api.nvim_buf_line_count(chat_bufnr)
      api.nvim_win_set_cursor(chat_winnr, { line_count, 0 })
    end
  end)
end

-- Function to list and display selected files
local function display_selected_files()
  local files_list = {}
  for file_path, _ in pairs(selected_files) do
    table.insert(files_list, file_path)
  end

  if #files_list == 0 then
    append_to_chat("No files selected. Use @filename to add files to context.")
  else
    append_to_chat("Selected files:")
    for _, file in ipairs(files_list) do
      append_to_chat("- " .. file)
    end
  end
end

-- Function to clear selected files
local function clear_selected_files()
  selected_files = {}
  append_to_chat("All selected files cleared.")
end

-- Add commands to list and clear files
function M.list_files_command()
  display_selected_files()
end

function M.clear_files_command()
  clear_selected_files()
end

local function open_chat_window()
  log_message("INFO", "Creating chat window with simple splits...")

  -- First check if the window already exists
  if chat_winnr and api.nvim_win_is_valid(chat_winnr) and input_winnr and api.nvim_win_is_valid(input_winnr) then
    log_message("INFO", "Chat window already exists, focusing it")
    api.nvim_set_current_win(input_winnr)
    vim.cmd("startinsert")
    return
  end

  -- Create a new split at the bottom of the screen for the chat window
  vim.cmd("botright new")
  local main_winnr = api.nvim_get_current_win()
  local main_bufnr = api.nvim_create_buf(false, true)
  api.nvim_win_set_buf(main_winnr, main_bufnr)

  -- Set up the main chat buffer
  api.nvim_buf_set_name(main_bufnr, "AI-Assistant-Chat")
  api.nvim_buf_set_option(main_bufnr, "buftype", "nofile")
  api.nvim_buf_set_option(main_bufnr, "swapfile", false)
  api.nvim_buf_set_option(main_bufnr, "modifiable", true)
  api.nvim_win_set_option(main_winnr, "wrap", true)
  api.nvim_win_set_option(main_winnr, "linebreak", true)

  -- Add a welcome message
  api.nvim_buf_set_lines(main_bufnr, 0, -1, false, {
    "Welcome to AI Assistant - " .. agent_modes[current_mode_name].name,
    "Type your questions in the input area below and press Enter.",
    "",
  })

  -- Store the chat buffer/window
  chat_bufnr = main_bufnr
  chat_winnr = main_winnr

  -- Create an input split at the bottom
  vim.cmd("botright 5new")
  local input_winnr = api.nvim_get_current_win()
  local input_bufnr = api.nvim_create_buf(false, true)
  api.nvim_win_set_buf(input_winnr, input_bufnr)

  -- Set up the input buffer
  api.nvim_buf_set_name(input_bufnr, "AI-Assistant-Input")
  api.nvim_buf_set_option(input_bufnr, "buftype", "nofile")
  api.nvim_buf_set_option(input_bufnr, "swapfile", false)
  api.nvim_buf_set_option(input_bufnr, "modifiable", true)
  api.nvim_win_set_option(input_winnr, "wrap", true)
  api.nvim_win_set_option(input_winnr, "linebreak", true)

  -- Add @ file completion
  _G._ai_assistant_file_completion = function()
    -- Get cursor position
    local cursor = api.nvim_win_get_cursor(input_winnr)
    local row, col = cursor[1] - 1, cursor[2]
    local line = api.nvim_buf_get_lines(input_bufnr, row, row + 1, false)[1]

    -- Insert @ first
    local new_line = line:sub(1, col) .. "@" .. line:sub(col + 1)
    api.nvim_buf_set_lines(input_bufnr, row, row + 1, false, { new_line })
    api.nvim_win_set_cursor(input_winnr, { row + 1, col + 1 })

    -- Special options first
    local special_options = {
      "codebase - Analyze entire codebase",
    }

    -- Get a list of files
    local files = {}

    -- Try from current directory
    local current_dir = vim.fn.getcwd()
    local cmd = "find " .. current_dir .. " -type f -not -path '*/\\.*' | sort"
    local handle = io.popen(cmd)

    if handle then
      for file in handle:lines() do
        local relative_path = file:gsub(current_dir .. "/", "")
        table.insert(files, relative_path)
      end
      handle:close()
    end

    -- Combine special options with files
    local options = {}
    for _, opt in ipairs(special_options) do
      table.insert(options, opt)
    end
    for _, file in ipairs(files) do
      table.insert(options, file)
    end

    -- Show selection UI
    vim.ui.select(options, {
      prompt = "Select reference type:",
      format_item = function(item)
        return item
      end,
    }, function(selected)
      if selected then
        -- Remove the @ we just inserted
        local current_line = api.nvim_buf_get_lines(input_bufnr, row, row + 1, false)[1]
        local prefix = current_line:sub(1, col)
        local suffix = current_line:sub(col + 2) -- +2 to skip the @

        if selected:sub(1, 8) == "codebase" then
          -- Special case for codebase
          local new_content = prefix .. "@codebase" .. suffix
          api.nvim_buf_set_lines(input_bufnr, row, row + 1, false, { new_content })
          api.nvim_win_set_cursor(input_winnr, { row + 1, col + 1 + 9 })
        else
          -- Regular file
          local new_content = prefix .. "@" .. selected .. suffix
          api.nvim_buf_set_lines(input_bufnr, row, row + 1, false, { new_content })
          api.nvim_win_set_cursor(input_winnr, { row + 1, col + 1 + #selected + 1 })
        end
      end
    end)
  end

  -- Store global references
  input_bufnr = input_bufnr
  input_winnr = input_winnr

  -- Log the window/buffer creation
  log_message(
    "DEBUG",
    string.format(
      "Created windows directly - Chat: %s/%s, Input: %s/%s",
      tostring(chat_bufnr),
      tostring(chat_winnr),
      tostring(input_bufnr),
      tostring(input_winnr)
    )
  )

  -- Set up keymaps
  if input_bufnr and type(input_bufnr) == "number" then
    log_message("DEBUG", "Setting up keymaps for input buffer " .. input_bufnr)

    -- Create a direct global function for the keymap
    -- This avoids module resolution issues
    _G._ai_assistant_submit = function()
      log_message("DEBUG", "Submit function called via global function")

      -- Get input directly in the global function to avoid scope issues
      local lines = api.nvim_buf_get_lines(input_bufnr, 0, -1, false)
      local text = table.concat(lines, "\n")

      -- Clear input immediately
      api.nvim_buf_set_lines(input_bufnr, 0, -1, false, { "" })

      -- Check for specific code graph queries before general processing
      local target_filename = text:match("^[Ww]ho imports (.+)$") or text:match("^[Ww]hich files import (.+)$")
      if target_filename then
        log_message("DEBUG", "Handling 'who imports' query for: " .. target_filename)
        append_to_chat("User: " .. text) -- Show the user's query
        
        -- Attempt to find the full path of the target file
        local full_path = find_file_path(target_filename)
        
        if not full_path then
          append_to_chat("Assistant: Could not find file '" .. target_filename .. "' in the project.")
          return -- Exit early
        end
        
        if not code_graph.is_indexed() then
            append_to_chat("Assistant: Codebase is not indexed. Please run :AIIndexCodebase first.")
            return -- Exit early
        end

        -- Query the code graph
        local importers = code_graph:find_importers_of_file(full_path)
        
        if #importers > 0 then
          local result_message = "Assistant: Files importing '" .. target_filename .. "':\n"
          for _, importer_path in ipairs(importers) do
            result_message = result_message .. "- " .. importer_path .. "\n"
          end
          append_to_chat(result_message)
        else
          append_to_chat("Assistant: No files found importing '" .. target_filename .. "'.")
        end
        
        return -- IMPORTANT: Return early to bypass the standard LLM call
      end

      -- Only process non-empty input
      if text and #vim.trim(text) > 0 then
        log_message("DEBUG", "Processing input: '" .. text .. "'")

        -- Add to chat window
        if chat_bufnr and api.nvim_buf_is_valid(chat_bufnr) then
          append_to_chat("User: " .. text)
          append_to_chat("Assistant: _thinking..._")

          -- Process the input for @ file mentions
          local processed_input, file_contexts = process_at_commands(text)
          last_processed_input = processed_input

          -- Get context from the original buffer
          local buffer_context = ""
          local ctx_buf = M._last_invoked_bufnr

          if ctx_buf and api.nvim_buf_is_valid(ctx_buf) then
            local buf_lines = api.nvim_buf_get_lines(ctx_buf, 0, -1, false)
            buffer_context = table.concat(buf_lines, "\n")
          end

          -- Combine contexts
          local context = ""
          if #file_contexts > 0 then
            context = context .. "\n\n--- File Contexts: ---\n" .. table.concat(file_contexts, "\n\n")
          end
          if buffer_context ~= "" then
            context = context .. "\n\n--- Current Buffer Context: ---\n" .. buffer_context
          end

          -- Send to API
          M.send_to_openrouter(processed_input, context, function(success, response)
            if not success then
              append_to_chat("_Error: " .. response .. "_")
              return
            end

            -- Replace thinking message with actual response
            local content = api.nvim_buf_get_lines(chat_bufnr, 0, -1, false)
            for i = #content, 1, -1 do
              if content[i]:match("^Assistant: _thinking..._$") then
                content[i] = "Assistant: " .. response:sub(1, 6)
                table.remove(content, i)
                break
              end
            end

            -- Add the response
            append_to_chat(response)

            -- Return focus to input
            if input_winnr and api.nvim_win_is_valid(input_winnr) then
              api.nvim_set_current_win(input_winnr)
              vim.cmd("startinsert")
            end
          end)
        else
          log_message("ERROR", "Chat buffer invalid during submission")
        end
      end
    end

    -- Set keymaps to trigger our global function
    api.nvim_buf_set_keymap(
      input_bufnr,
      "i",
      "<CR>",
      "<Cmd>lua _G._ai_assistant_submit()<CR>",
      { noremap = true, silent = true }
    )

    api.nvim_buf_set_keymap(
      input_bufnr,
      "n",
      "<CR>",
      "<Cmd>lua _G._ai_assistant_submit()<CR>",
      { noremap = true, silent = true }
    )

    -- Add file selection on @ key
    api.nvim_buf_set_keymap(
      input_bufnr,
      "i",
      "@",
      "<Cmd>lua _G._ai_assistant_file_completion()<CR>",
      { noremap = true, silent = true }
    )
  else
    log_message("ERROR", "Cannot set keymaps - invalid input buffer ID")
  end

  -- Focus input window and start insert mode
  api.nvim_set_current_win(input_winnr)
  vim.cmd("startinsert")
end

-- Function to toggle the chat window visibility
function M.toggle_chat_window()
  -- Check if our windows exist
  if chat_winnr and api.nvim_win_is_valid(chat_winnr) and input_winnr and api.nvim_win_is_valid(input_winnr) then
    -- Windows exist, close them
    log_message("INFO", "Closing chat windows")
    api.nvim_win_close(chat_winnr, true)
    api.nvim_win_close(input_winnr, true)
    chat_winnr = nil
    input_winnr = nil
  else
    -- Windows don't exist, create them
    log_message("INFO", "Opening chat windows")
    open_chat_window()
  end
end

-- Function to handle input submission - now we use _G._ai_assistant_submit directly
-- This is kept for API compatibility
function M.handle_input_submission()
  if _G._ai_assistant_submit then
    log_message("DEBUG", "Forwarding to global submit function")
    _G._ai_assistant_submit()
  else
    log_message("ERROR", "Global submit function not available!")
  end
end

-- Function to send messages to OpenRouter API
function M.send_to_openrouter(prompt, context, callback)
  if not OPENROUTER_API_KEY or #OPENROUTER_API_KEY == 0 then
    callback(false, "OpenRouter API key not set. Please set the OPENROUTER_API_KEY environment variable.")
    return
  end

  -- Prepare the API request
  local system_prompt =
    "You are a helpful AI programming assistant integrated into Neovim. Help the user with coding questions, explanations, and suggestions based on their query and the provided code context."

  local messages = {
    { role = "system", content = system_prompt },
  }

  -- Add context if available
  if context and #context > 0 then
    table.insert(messages, {
      role = "user",
      content = "Here is the current file content for context:\n```\n" .. context .. "\n```\n",
    })
    table.insert(messages, {
      role = "assistant",
      content = "I'll help you with this code. What would you like to know or do?",
    })
  end

  -- Add the user's current question
  table.insert(messages, { role = "user", content = prompt })

  -- Check if we need to get codebase context
  local codebase_context = ""
  if M._using_codebase_context and M._codebase_query then
    codebase_context = code_graph.get_context(M._codebase_query)
    -- Reset the flag after using it
    M._using_codebase_context = false
    M._codebase_query = nil

    -- Add codebase context to system message if it's the first message
    if #messages > 0 and messages[1].role == "system" then
      local existing_content = messages[1].content
      messages[1].content = existing_content .. "\n\nCODEBASE CONTEXT:\n" .. codebase_context
    end
  end

  local request_data = {
    model = DEFAULT_MODEL,
    messages = messages,
    temperature = 0.2,
    max_tokens = 1500,
  }

  -- Use our safe encode function
  local request_json = safe_json.encode(request_data)

  -- Disable SSL verification if needed
  -- local ssl_option = "--insecure"
  local ssl_option = ""

  -- Make the API request
  curl.post(OPENROUTER_API_URL, {
    body = request_json,
    headers = {
      ["Content-Type"] = "application/json",
      ["Authorization"] = "Bearer " .. OPENROUTER_API_KEY,
      ["HTTP-Referer"] = "https://github.com/neovim/neovim",
      ["X-Title"] = "Neovim AI Assistant Plugin",
    },
    callback = function(response)
      if response.status ~= 200 then
        log_message("ERROR", "OpenRouter API request failed: " .. (response.body or "Unknown error"))
        callback(false, "API request failed: " .. (response.body or "Unknown error"))
        return
      end

      -- Process the response safely in an async context
      vim.schedule(function()
        local ok, decoded_response = pcall(safe_json.decode, response.body)
        if not ok or not decoded_response or not decoded_response.choices or #decoded_response.choices == 0 then
          log_message(
            "ERROR",
            "Invalid response from OpenRouter API: " .. (not ok and decoded_response or "unknown error")
          )
          callback(false, "Invalid response from API")
          return
        end

        local message_content = decoded_response.choices[1].message.content
        callback(true, message_content)
      end)
      return -- Early return since we're handling callback in scheduled function
    end,
  })
end

-- Add more debug logging
log_message("DEBUG", "All functions defined, now defining M.ask_command")

-- Trigger function for AI ask command
function M.ask_command()
  -- Store the buffer where the command was invoked
  M._last_invoked_bufnr = api.nvim_get_current_buf()
  log_message("DEBUG", "AIAsk invoked from buffer: " .. M._last_invoked_bufnr)
  -- Open or focus the chat window
  open_chat_window()
  -- Focus input window
  if input_winnr and api.nvim_win_is_valid(input_winnr) then
    api.nvim_set_current_win(input_winnr)
    log_message("DEBUG", "Focus set to Nui input window.")
  end
end

-- Setup function to register commands
function M.setup(opts)
  -- Define user commands
  api.nvim_create_user_command("AIAsk", M.ask_command, { nargs = 0, desc = "Ask the AI Assistant" })
  api.nvim_create_user_command(
    "AIToggle",
    "lua require('ai_assistant').toggle_chat_window()",
    { nargs = 0, desc = "Toggle AI Assistant Chat Window" }
  )
  api.nvim_create_user_command("AIMode", function(cmd_opts)
    M.set_mode(cmd_opts.args)
  end, {
    nargs = 1,
    complete = function(arg_lead)
      local modes = {}
      for m in pairs(agent_modes) do
        if m:sub(1, #arg_lead) == arg_lead then
          table.insert(modes, m)
        end
      end
      table.sort(modes)
      return modes
    end,
    desc = "Set AI Assistant Mode",
  })

  -- Commands for file management
  api.nvim_create_user_command(
    "AIListFiles",
    M.list_files_command,
    { nargs = 0, desc = "List files selected for AI context" }
  )
  api.nvim_create_user_command(
    "AIClearFiles",
    M.clear_files_command,
    { nargs = 0, desc = "Clear files selected for AI context" }
  )

  -- Command to index the codebase
  api.nvim_create_user_command("AIIndexCodebase", function()
    vim.notify("Indexing codebase...", vim.log.levels.INFO)
    vim.schedule(function()
      local node_count, root_dir = code_graph.index_codebase()
      vim.notify(string.format("Codebase indexed: %d entities from %s", node_count, root_dir), vim.log.levels.INFO)
    end)
  end, { nargs = 0, desc = "Index the codebase for AI context" })

  -- Command to show codebase stats
  api.nvim_create_user_command("AICodebaseStats", function()
    if code_graph.is_indexed() then
      local stats = code_graph.get_stats()
      vim.notify(
        string.format("Codebase stats: %d nodes, %d edges, %d files", stats.nodes, stats.edges, stats.files),
        vim.log.levels.INFO
      )
    else
      vim.notify("Codebase not indexed yet. Run :AIIndexCodebase first.", vim.log.levels.WARN)
    end
  end, { nargs = 0, desc = "Show statistics about indexed codebase" })

  -- Apply provided options
  if opts and opts.default_model then
    DEFAULT_MODEL = opts.default_model
    log_message("INFO", "Default model set to: " .. DEFAULT_MODEL)
  end

  log_message("INFO", "AI Assistant setup complete. Available modes: " .. table.concat(vim.tbl_keys(agent_modes), ", "))
end

-- Function to change AI mode
function M.set_mode(mode)
  if not mode or not agent_modes[mode] then
    vim.notify("[AI Assistant] Invalid mode: " .. tostring(mode), vim.log.levels.ERROR)
    return
  end
  current_mode_name = mode
  vim.notify("[AI Assistant] Mode set to: " .. agent_modes[mode].name, vim.log.levels.INFO)
  log_message("INFO", "Mode changed to: " .. mode)
end

return M
