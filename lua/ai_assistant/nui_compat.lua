-- /home/bryan/.config/nvim/lua/ai_assistant/nui_compat.lua
-- Compatibility layer for nui.nvim to handle partial installations

local M = {}

-- Create a virtual nui module with the components we can load
function M.get_nui()
  -- Components we'll try to load
  local components = {
    "popup", "split", "input", "layout", "menu", "tree", "text"
  }
  
  local nui = {}
  local loaded_any = false
  
  -- Try to load each component
  for _, component in ipairs(components) do
    local ok, module = pcall(require, 'nui.' .. component)
    if ok then
      -- Convert first letter to uppercase for the component name
      local name = component:sub(1,1):upper() .. component:sub(2)
      nui[name] = module
      loaded_any = true
      print("[AI Assistant] Loaded nui." .. component)
    end
  end
  
  if not loaded_any then
    return nil, "Could not load any nui components"
  end
  
  -- Add standard Neovim events if nui.event isn't available
  local ok_event, event_module = pcall(require, 'nui.event')
  if ok_event then
    nui.event = event_module
    print("[AI Assistant] Loaded nui.event")
  else
    -- Create our own simple event mapping to Neovim autocmd events
    nui.event = {
      BufEnter = "BufEnter",
      BufLeave = "BufLeave",
      BufWinEnter = "BufWinEnter",
      BufWinLeave = "BufWinLeave",
      VimResized = "VimResized"
    }
    print("[AI Assistant] Created fallback event module")
  end
  
  return nui
end

return M
