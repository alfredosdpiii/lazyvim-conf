-- /home/bryan/.config/nvim/lua/ai_assistant/treesitter_context.lua

local ts_utils = require 'nvim-treesitter.ts_utils'
local ts_query = require 'vim.treesitter.query' -- For future use
local api = vim.api

local M = {}

-- Helper function to get the parser for the current buffer
local function get_parser(bufnr)
  bufnr = bufnr or api.nvim_get_current_buf()
  local ok, parser = pcall(require('nvim-treesitter.parsers').get_parser, bufnr)
  if not ok or not parser then
    -- Consider adding a vim.notify warning here
    return nil
  end
  return parser
end

-- Helper function to safely get node text
local function get_text_for_node(node, bufnr)
  if not node then return "" end
  bufnr = bufnr or api.nvim_get_current_buf()
  -- Use pcall for safety in case node is invalid or buffer ops fail
  local ok, lines = pcall(vim.treesitter.get_node_text, node, bufnr)
  if not ok or not lines then
    return ""
  end
  return table.concat(lines, "\n")
end

--- Gets the Treesitter node directly under the cursor.
--- @param winnr integer? Window ID (defaults to current window)
--- @return TSNode|nil node The node at the cursor, or nil if not found.
function M.get_node_at_cursor(winnr)
  winnr = winnr or 0 -- 0 means current window
  -- Use pcall as ts_utils might error if parser not ready
  local ok, node = pcall(ts_utils.get_node_at_cursor, winnr)
  if not ok then return nil end
  return node
end

--- Traverses upwards from a node to find the nearest ancestor matching a type.
--- Common types: 'function_definition', 'class_definition', 'method_definition', 'block', etc.
--- (Exact types depend on the language parser)
--- @param start_node TSNode The node to start searching from.
--- @param target_type string|string[] The node type(s) to find (e.g., "function_definition" or {"func..", "method.."}).
--- @return TSNode|nil containing_node The ancestor node, or nil if not found.
function M.get_containing_node(start_node, target_type)
  local current_node = start_node
  local types_to_match = {}
  if type(target_type) == "string" then
    types_to_match = { target_type }
  elseif type(target_type) == "table" then
    types_to_match = target_type
  else
    return nil -- Invalid target_type
  end

  while current_node do
    local node_type = current_node:type()
    for _, t_type in ipairs(types_to_match) do
      if node_type == t_type then
        return current_node
      end
    end
    current_node = current_node:parent()
  end
  return nil
end

--- Finds the containing function/method/block node for the node at the cursor.
--- Adjust function_types based on languages you target.
--- @param winnr integer? Window ID (defaults to current window)
--- @return TSNode|nil function_node The containing function/method/block node, or nil.
function M.get_surrounding_definition_node(winnr)
  local node = M.get_node_at_cursor(winnr)
  if not node then return nil end

  -- List may need expansion for more languages/constructs
  -- Check Treesitter playgrounds (https://tree-sitter.github.io/tree-sitter/) for specific node types
  local definition_types = {
    -- Common function/method types
    "function_definition",
    "method_definition",
    "function_declaration",
    "arrow_function",
    "lambda_expression",
    -- Common class/struct/interface types
    "class_definition",
    "class_declaration",
    "struct_definition",
    "interface_definition",
    -- General block scope (fallback?)
    "block",
    "statement_block",
  }

  return M.get_containing_node(node, definition_types)
end


--- Gets the text content of the node at the cursor.
--- @param winnr integer? Window ID (defaults to current window)
--- @return string text The text content of the node at the cursor.
function M.get_text_at_cursor(winnr)
    local node = M.get_node_at_cursor(winnr)
    return get_text_for_node(node, api.nvim_win_get_buf(winnr or 0))
end

--- Gets the text content of the surrounding definition (function/method/class/block).
--- @param winnr integer? Window ID (defaults to current window)
--- @return string text The text content of the surrounding definition.
function M.get_surrounding_definition_text(winnr)
    local def_node = M.get_surrounding_definition_node(winnr)
    return get_text_for_node(def_node, api.nvim_win_get_buf(winnr or 0))
end

-- Placeholder for future query-based context extraction
-- function M.get_context_via_query(query_string, start_node, bufnr)
--   bufnr = bufnr or api.nvim_get_current_buf()
--   local lang = M.get_language_at_cursor(bufnr) -- Need to implement this
--   if not lang then return nil end
--   local parser = get_parser(bufnr)
--   if not parser then return nil end
--
--   local query = ts_query.parse(lang, query_string)
--   if not query then return nil end
--
--   local results = {}
--   start_node = start_node or parser:parse()[1]:root() -- Default to root if no start node
--
--   for id, node, metadata in query:iter_captures(start_node, bufnr, 0, -1) do
--     local capture_name = query.captures[id]
--     results[capture_name] = results[capture_name] or {}
--     table.insert(results[capture_name], { node = node, metadata = metadata, text = get_text_for_node(node, bufnr) })
--   end
--   return results
-- end


return M
