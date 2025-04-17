-- Enhanced Code Graph module with improved AST parsing, cross-language support,
-- semantic relationship detection, and SQLite storage
--
-- This module exports functions for code indexing and context generation
-- 
-- Improvements:
-- - More robust language detection using vim.bo.filetype.
-- - Configuration table for settings (paths, limits).
-- - Basic structure for language-specific parser modules.
-- - Use of SQLite transactions for potentially faster batch inserts/updates.
-- - Refined Tree-sitter queries (example added for Python).
-- - Asynchronous file finding using vim.fs.dir (more Neovim-idiomatic).
-- - Clearer separation of concerns (e.g., parsing vs. analysis).
-- - Enhanced error handling and logging hints.
-- - More comments explaining logic.
-- - Fixes based on linting/diagnostics.

local api = vim.api
local ts = vim.treesitter
local uv = vim.loop
local fs = vim.fs
local fn = vim.fn
local log = vim.notify -- Use vim.notify for user feedback/logs
local has_sqlite, sqlite = pcall(require, "sqlite")
local has_json, json = pcall(require, "vim.json")

-- =============================================================================
-- Configuration
-- =============================================================================
local config = {
  -- Path for the SQLite database relative to Neovim's data directory
  db_filename = "codebase_graph.db",
  -- Use SQLite's in-memory mode instead of a file (faster for single sessions, no persistence)
  -- Set to false to use the db_filename for persistence.
  use_sqlite_in_memory = true, -- Set to false to persist the DB to db_filename
  -- Maximum size for context generation (bytes)
  max_context_total_size = 50000,
  -- Maximum size for a single node's content in context (bytes)
  max_context_node_size = 2000,
  -- Number of relevant nodes to fetch for context generation
  max_relevant_nodes = 10,
  -- Number of related nodes (incoming/outgoing) to fetch
  max_related_nodes = 5,
  -- Directories/patterns to ignore during indexing (Lua patterns)
  ignored_paths = {
    "/%.git/",
    "/%.svn/",
    "/node_modules/",
    "/dist/",
    "/build/",
    "/target/",
    "/vendor/",
    "%.min.js$", -- Example: ignore minified JS
    -- Add more patterns as needed
  },
  -- File extensions to consider for indexing
  -- Using filetype detection is preferred, but this can be a fallback/filter
  indexed_extensions = {
    "lua",
    "py",
    "js",
    "ts",
    "jsx",
    "tsx",
    "go",
    "rs",
    "c",
    "cpp",
    "h",
    "hpp",
    "java",
    "kt",
    "swift",
    "rb",
    "php",
    "cs",
    "scala",
    "ex",
    "exs",
    "erl",
    "hs",
    "ml",
    "json",
    "yaml",
    "yml",
    "xml",
    "toml",
    "sh",
    "sql",
    "html",
    "css",
    "md",
  },
  -- Log level (0=none, 1=error, 2=warn, 3=info, 4=debug)
  log_level = 5, -- Set to maximum debug level
}

local function should_log(level)
  return config.log_level >= level
end

local function log_msg(level, msg)
  if not should_log(level) then
    return
  end
  local prefix = "[CodeGraph] "
  if level == 1 then
    prefix = prefix .. "ERROR: "
  elseif level == 2 then
    prefix = prefix .. "WARN: "
  elseif level == 3 then
    prefix = prefix .. "INFO: "
  elseif level == 4 then
    prefix = prefix .. "DEBUG: "
  end
  -- Always print debug messages to ensure visibility
  print(prefix .. msg)
  -- Also use normal logging
  log(prefix .. msg, level <= 2 and vim.log.levels.ERROR or vim.log.levels.INFO)
end

-- =============================================================================
-- Utility Functions
-- =============================================================================

-- Safely encode data to JSON, handling potential errors
local function safe_json_encode(data)
  if not has_json or not data then
    return nil
  end
  local success, result = pcall(json.encode, data)
  if not success then
    log_msg(2, "Failed to encode metadata to JSON: " .. tostring(result))
    return nil
  end
  return result
end

-- Safely decode JSON data, handling potential errors
local function safe_json_decode(text)
  if not has_json or not text or text == "" then
    return nil
  end
  local success, result = pcall(json.decode, text)
  if not success then
    -- It's common for metadata to be non-JSON, so log at debug level
    log_msg(4, "Failed to decode metadata from JSON (or metadata was not JSON): " .. tostring(result))
    return nil -- Return nil if not valid JSON
  end
  return result
end

-- =============================================================================
-- Language-Specific Parsers Structure (Example - to be expanded)
-- =============================================================================
-- In a real application, these would likely live in separate files
-- (e.g., enhanced_code_graph/parsers/lua.lua)

local language_parsers = {}

--- Parses Lua files using Tree-sitter.
-- @param graph The EnhancedCodeGraph instance.
-- @param file_path The path to the file.
-- @param content The file content.
-- @param root The Tree-sitter root node.
-- @param file_id The ID of the file node in the graph.
language_parsers.lua = function(graph, file_path, content, root, file_id)
  log_msg(4, "Processing Lua file: " .. file_path)
  -- Extract functions
  if graph.tree_sitter_queries.lua_functions then
    -- Use iter_captures which gives the specific node per capture name
    for id, node, _ in graph.tree_sitter_queries.lua_functions:iter_captures(root, 0) do -- Pass 0 for content index
      local capture_name = graph.tree_sitter_queries.lua_functions.captures[id]
      if capture_name == "function_name" or capture_name == "method_name" then
        local func_name = vim.treesitter.get_node_text(node, content)
        -- Find the definition node associated with this name capture
        -- This still relies on finding the ancestor, which is tricky.
        -- A better query might capture the name and the definition body together.
        local func_def_node = graph:_find_ancestor_capture(node, { "function_def", "func_body" }) -- Adjust captures if needed

        if func_def_node then
          local def_start_row, _, def_end_row, _ = func_def_node:range()
          local func_content = vim.treesitter.get_node_text(func_def_node, content)
          local node_type = capture_name == "method_name" and "method" or "function"
          local func_id =
            graph:add_node(node_type, func_name, file_path, def_start_row + 1, def_end_row + 1, func_content)
          graph:add_edge(file_id, func_id, "contains")
          -- Add to pending analysis for call detection later
          graph.pending_analysis_nodes[func_id] = func_def_node
        else
          log_msg(4, "Could not find function definition node for: " .. func_name .. " in " .. file_path)
        end
      end
    end
  else
    log_msg(2, "Lua function query not available for: " .. file_path)
  end

  -- Extract requires
  if graph.tree_sitter_queries.lua_requires then
    -- Use iter_matches to get all captures for a single require call together
    for _, match, _ in graph.tree_sitter_queries.lua_requires:iter_matches(root, 0) do -- Pass 0 for content index
      -- Access nodes using the capture index directly from the query
      local func_name_node = match[graph.tree_sitter_queries.lua_requires.captures["func_name"]]
      local module_name_node = match[graph.tree_sitter_queries.lua_requires.captures["module_name"]]
      local require_node = match[graph.tree_sitter_queries.lua_requires.captures["require_call"]] -- Get the overall call node

      if func_name_node and module_name_node and require_node then -- Check if all expected captures exist
        local func_name = vim.treesitter.get_node_text(func_name_node, content)
        local module_name = vim.treesitter.get_node_text(module_name_node, content):gsub("^[\"'](.*)[\"']$", "%1")

        if func_name == "require" and module_name then
          local import_name = module_name:match("([^./\\]+)$") or module_name -- Simple basename
          local start_row = 0
          if require_node then -- Check node exists before calling range()
            local r_start, _, _, _ = require_node:range()
            start_row = r_start + 1 -- range is 0-indexed
          end

          local require_id = graph:add_node(
            "require",
            import_name,
            file_path,
            start_row,
            start_row, -- Require is single line
            'require("' .. module_name .. '")'
          )
          graph:add_edge(file_id, require_id, "contains")

          -- Attempt to resolve and track
          graph:_track_import(file_path, import_name, module_name, "require")
        end
      else
        log_msg(4, "Missing captures in lua_requires match for " .. file_path)
      end
    end
  else
    log_msg(2, "Lua require query not available for: " .. file_path)
  end
end

--- Parses JavaScript/TypeScript files using Tree-sitter.
-- @param graph The EnhancedCodeGraph instance.
-- @param file_path The path to the file.
-- @param content The file content.
-- @param root The Tree-sitter root node.
-- @param file_id The ID of the file node in the graph.
language_parsers.javascript = function(graph, file_path, content, root, file_id)
  log_msg(4, "Processing JavaScript/TypeScript file: " .. file_path)
  -- local lang = "javascript" -- Removed, unused variable

  -- Try to use specialized external JS/TS parser for imports/exports first
  local handled_imports_exports = false
  local has_jsts_parser, jsts_parser = pcall(require, "ai_assistant.jsts_parser") -- Assuming this external helper exists
  if has_jsts_parser then
    log_msg(4, "Using external jsts_parser for imports/exports in " .. file_path)
    local success_imports, imports = pcall(jsts_parser.get_imports, file_path, content)
    if success_imports and imports and #imports > 0 then
      handled_imports_exports = true -- Assume exports might be handled too if imports are
      for _, import_info in ipairs(imports) do
        local module_path = import_info.source
        local import_type = import_info.type
        -- TODO: Get line number from import_info if available
        local import_line = import_info.line or 0
        if import_info.names and #import_info.names > 0 then
          for _, name_info in ipairs(import_info.names) do
            local orig_name, alias = name_info, name_info
            if import_type == "named" and type(name_info) == "table" then
              orig_name = name_info.original
              alias = name_info.alias or orig_name
            end
            local import_id = graph:add_node("import", alias, file_path, import_line, import_line, "")
            graph:add_edge(file_id, import_id, "contains")
            graph:_track_import(file_path, alias, module_path, import_type, orig_name)
          end
        else
          -- Handle default or side-effect imports where name might just be the path
          local import_name = module_path:match("([^./\\]+)$") or module_path
          local import_id = graph:add_node("import", import_name, file_path, import_line, import_line, "")
          graph:add_edge(file_id, import_id, "contains")
          graph:_track_import(file_path, import_name, module_path, import_type)
        end
      end
    else
      if not success_imports then
        log_msg(2, "Error calling jsts_parser.get_imports: " .. tostring(imports))
      end
    end
    -- TODO: Add similar handling for jsts_parser.get_exports if available
  end

  if not handled_imports_exports then
    log_msg(4, "Falling back to pattern matching for JS imports/exports in " .. file_path)
    graph:process_js_imports_exports_with_patterns(file_path, content, file_id) -- Use the regex fallback
  end

  -- Extract functions, methods, classes using Tree-sitter
  if graph.tree_sitter_queries.js_defs then
    for id, node, _ in graph.tree_sitter_queries.js_defs:iter_captures(root, 0) do -- Pass 0 for content index
      local capture_name = graph.tree_sitter_queries.js_defs.captures[id]
      local entity_name, node_type, definition_capture
      local entity_name_node = node

      if capture_name == "function_name" then
        node_type = "function"
        definition_capture = "function_def"
      elseif capture_name == "method_name" then
        node_type = "method"
        definition_capture = "method_def"
      elseif capture_name == "class_name" then
        node_type = "class"
        definition_capture = "class_def"
      end

      if node_type then
        entity_name = vim.treesitter.get_node_text(entity_name_node, content)
        -- Try to find the definition node containing this name
        local def_node = graph:_find_ancestor_capture(node, { definition_capture })

        if def_node then
          local start_row, _, end_row, _ = def_node:range()
          local entity_content = vim.treesitter.get_node_text(def_node, content)
          local entity_id =
            graph:add_node(node_type, entity_name, file_path, start_row + 1, end_row + 1, entity_content)
          graph:add_edge(file_id, entity_id, "contains")
          graph.pending_analysis_nodes[entity_id] = def_node -- Queue for call analysis

          -- Tentatively mark top-level functions/classes as exportable
          -- Note: Real export status depends on `export` keyword, handled above/in fallback
          local parent_node = def_node:parent()
          -- Check if parent is program or an export statement
          if parent_node and (parent_node:type() == "program" or parent_node:type() == "export_statement") then
            graph.exports_map[file_path] = graph.exports_map[file_path] or {}
            -- Only add if not already explicitly exported (which might use a different ID)
            if not graph.exports_map[file_path][entity_name] then
              graph.exports_map[file_path][entity_name] = entity_id
            end
          end
        end
      end
    end
  else
    log_msg(2, "JavaScript definition query not available for: " .. file_path)
  end
end

--- Parses Python files using Tree-sitter (Basic Example).
-- @param graph The EnhancedCodeGraph instance.
-- @param file_path The path to the file.
-- @param content The file content.
-- @param root The Tree-sitter root node.
-- @param file_id The ID of the file node in the graph.
language_parsers.python = function(graph, file_path, content, root, file_id)
  log_msg(4, "Processing Python file: " .. file_path)

  -- Initialize maps
  graph.imports_map[file_path] = graph.imports_map[file_path] or {}
  graph.exports_map[file_path] = graph.exports_map[file_path] or {}

  -- Extract imports using Tree-sitter
  if graph.tree_sitter_queries.python_imports then
    for _, match, _ in graph.tree_sitter_queries.python_imports:iter_matches(root, 0) do -- Pass 0 for content index
      -- Determine if it's import_statement or import_from_statement based on captures found
      local import_node = match[graph.tree_sitter_queries.python_imports.captures["import_statement"]]
        or match[graph.tree_sitter_queries.python_imports.captures["import_from_statement"]]

      local start_row = 0
      local line_content = ""
      if import_node then
        local r_start, _, _, _ = import_node:range()
        start_row = r_start + 1
        line_content = vim.treesitter.get_node_text(import_node, content)
      end

      -- Handle `import module` or `import module as alias`
      local module_node = match[graph.tree_sitter_queries.python_imports.captures["module_name"]]
      local alias_node = match[graph.tree_sitter_queries.python_imports.captures["alias_name"]]
      if module_node then
        local module_name = vim.treesitter.get_node_text(module_node, content)
        local alias_name = alias_node and vim.treesitter.get_node_text(alias_node, content)
          or module_name:match("([^.]+)$")
          or module_name -- Simple alias/basename
        local import_id = graph:add_node("import", alias_name, file_path, start_row, start_row, line_content)
        graph:add_edge(file_id, import_id, "contains")
        graph:_track_import(file_path, alias_name, module_name, "module")
      end

      -- Handle `from module import name` or `from module import name as alias`
      local from_module_node = match[graph.tree_sitter_queries.python_imports.captures["from_module_name"]]
      local imported_name_node = match[graph.tree_sitter_queries.python_imports.captures["imported_name"]]
      local imported_alias_node = match[graph.tree_sitter_queries.python_imports.captures["imported_alias"]]
      if from_module_node and imported_name_node then
        local from_module_name = vim.treesitter.get_node_text(from_module_node, content)
        local imported_name = vim.treesitter.get_node_text(imported_name_node, content)
        local alias_name = imported_alias_node and vim.treesitter.get_node_text(imported_alias_node, content) or imported_name
        local import_id = graph:add_node("import", alias_name, file_path, start_row, start_row, line_content)
        graph:add_edge(file_id, import_id, "contains")
        graph:_track_import(file_path, alias_name, from_module_name, "named", imported_name)
      end
    end
  else
    log_msg(2, "Python import query not available for: " .. file_path)
    -- Fallback to regex? Less ideal. Use the generic one if needed.
    -- graph:process_generic_file(file_path, content, root, file_id, 'python')
  end

  -- Extract functions and classes using Tree-sitter
  if graph.tree_sitter_queries.python_defs then
    for id, node, _ in graph.tree_sitter_queries.python_defs:iter_captures(root, 0) do -- Pass 0 for content index
      local capture_name = graph.tree_sitter_queries.python_defs.captures[id]
      local entity_name, node_type, definition_capture
      local entity_name_node = node

      if capture_name == "function_name" then
        node_type = "function"
        definition_capture = "function_def"
      elseif capture_name == "class_name" then
        node_type = "class"
        definition_capture = "class_def"
      end

      if node_type then
        entity_name = vim.treesitter.get_node_text(entity_name_node, content)
        local def_node = graph:_find_ancestor_capture(node, { definition_capture })

        if def_node then
          local start_row, _, end_row, _ = def_node:range()
          local entity_content = vim.treesitter.get_node_text(def_node, content)
          local entity_id =
            graph:add_node(node_type, entity_name, file_path, start_row + 1, end_row + 1, entity_content)
          graph:add_edge(file_id, entity_id, "contains")
          graph.pending_analysis_nodes[entity_id] = def_node -- Queue for call analysis

          -- Mark top-level functions/classes as potentially exported (Python's implicit export)
          -- Basic check: if not nested inside another function/class and name doesn't start with '_'
          local parent_type = def_node:parent() and def_node:parent():type()
          if parent_type and (parent_type == "module" or parent_type == "block") then -- Adjust based on actual Python TS grammar
            -- Use string.sub instead of non-existent startswith
            if not (string.sub(entity_name, 1, 1) == "_") then
              graph.exports_map[file_path][entity_name] = entity_id
            end
          end
        end
      end
    end
  else
    log_msg(2, "Python definition query not available for: " .. file_path)
  end
end

-- =============================================================================
-- Base Enhanced Code Graph Implementation
-- =============================================================================
local EnhancedCodeGraph = {}
EnhancedCodeGraph.__index = EnhancedCodeGraph

-- Create a new EnhancedCodeGraph instance
function EnhancedCodeGraph:new(use_persistent_db)
  local instance = {
    db = nil,
    nodes = {}, -- Used only if use_in_memory = true
    edges = {}, -- Used only if use_in_memory = true
    node_lookup_cache = {}, -- Cache for SQLite node lookups {id = node_data}
    stats = { nodes = 0, edges = 0, files = 0, functions = 0, classes = 0, imports = 0, exports = 0 },
    files_indexed = {}, -- {file_path = true}
    pending_analysis_nodes = {}, -- {node_id = ts_node} nodes needing call analysis
    tree_sitter_queries = {},
    use_in_memory = true,
    imports_map = {}, -- {file_path = {alias = {module, name, type}}}
    exports_map = {}, -- {file_path = {name = node_id, ["_imported_by"] = {importer_path = true}}}
  }
  setmetatable(instance, self) -- Inherit methods

  if has_sqlite and use_persistent_db then
    local db_path = fn.stdpath("data") .. "/" .. config.db_filename
    log_msg(3, "Initializing persistent SQLite database at: " .. db_path)
    local success, db_or_err = pcall(sqlite.open, db_path)
    if success then
      instance.db = db_or_err
      instance.use_in_memory = false
      if not instance:_init_db_schema() then
        log_msg(1, "Failed to initialize DB schema. Falling back to in-memory.")
        instance:close() -- Close potentially broken DB connection
        instance.db = nil
        instance.use_in_memory = true
      end
    else
      log_msg(1, "Failed to open SQLite DB: " .. tostring(db_or_err) .. ". Falling back to in-memory.")
      instance.use_in_memory = true
    end
  elseif has_sqlite and config.use_sqlite_in_memory then
    log_msg(3, "Initializing SQLite in-memory database.")
    -- Use the special :memory: path for true SQLite in-memory DB
    local success, db_or_err = pcall(sqlite.open, ":memory:")
    if success then
      instance.db = db_or_err
      instance.use_in_memory = false -- We are using SQLite, just not persisted
      if not instance:_init_db_schema() then
        log_msg(1, "Failed to initialize in-memory DB schema. Falling back to pure Lua tables.")
        instance:close()
        instance.db = nil
        instance.use_in_memory = true
      end
    else
      log_msg(1, "Failed to open SQLite in-memory DB: " .. tostring(db_or_err) .. ". Falling back to pure Lua tables.")
      instance.use_in_memory = true
    end
  else
    if not has_sqlite then
      log_msg(2, "SQLite not available.")
    end
    log_msg(3, "Using pure Lua tables for in-memory storage.")
    instance.use_in_memory = true
  end

  -- Initialize tree-sitter queries regardless of storage type
  instance:_init_tree_sitter_queries()

  return instance
end

-- Initialize SQLite database schema
function EnhancedCodeGraph:_init_db_schema()
  assert(self.db, "Database must be initialized before schema creation.")
  local success = true
  local function safe_execute(stmt)
    -- Use db:execute for schema changes as per sqlite.lua recommendation
    local ok, err = pcall(self.db.execute, self.db, stmt)
    if not ok then
      log_msg(1, "SQLite schema error: " .. tostring(err) .. " executing: " .. stmt)
      success = false
    end
    return ok
  end

  log_msg(4, "Creating SQLite schema...")
  safe_execute("PRAGMA journal_mode=WAL;") -- Improve concurrency
  safe_execute("PRAGMA synchronous=NORMAL;") -- Improve speed slightly

  -- Nodes Table
  safe_execute([[
        CREATE TABLE IF NOT EXISTS nodes (
            id TEXT PRIMARY KEY,
            type TEXT NOT NULL,
            name TEXT,
            file TEXT,
            start_line INTEGER,
            end_line INTEGER,
            content TEXT
        ) WITHOUT ROWID; -- Use id as primary key directly
    ]])
  -- Edges Table
  safe_execute([[
        CREATE TABLE IF NOT EXISTS edges (
            source_id TEXT NOT NULL,
            target_id TEXT NOT NULL,
            relationship TEXT NOT NULL,
            metadata TEXT,
            PRIMARY KEY(source_id, target_id, relationship),
            FOREIGN KEY(source_id) REFERENCES nodes(id) ON DELETE CASCADE, -- Optional: Add foreign keys
            FOREIGN KEY(target_id) REFERENCES nodes(id) ON DELETE CASCADE
        ) WITHOUT ROWID;
    ]])
  safe_execute("PRAGMA foreign_keys=ON;") -- Enforce foreign key constraints

  -- Indexes (Create only if they don't exist)
  safe_execute("CREATE INDEX IF NOT EXISTS idx_nodes_name ON nodes(name);")
  safe_execute("CREATE INDEX IF NOT EXISTS idx_nodes_file ON nodes(file);")
  safe_execute("CREATE INDEX IF NOT EXISTS idx_nodes_type ON nodes(type);")
  safe_execute("CREATE INDEX IF NOT EXISTS idx_edges_source ON edges(source_id);")
  safe_execute("CREATE INDEX IF NOT EXISTS idx_edges_target ON edges(target_id);")
  safe_execute("CREATE INDEX IF NOT EXISTS idx_edges_rel ON edges(relationship);")

  -- Optional: FTS table for content search (requires FTS5 support)
  -- safe_execute([[
  -- CREATE VIRTUAL TABLE IF NOT EXISTS nodes_fts USING fts5(
  --    id UNINDEXED,
  --    content,
  --    content='nodes', content_rowid='rowid' -- Check sqlite.lua docs for exact syntax
  -- );
  -- ]])

  return success
end

-- Initialize tree-sitter queries for various languages
function EnhancedCodeGraph:_init_tree_sitter_queries()
  log_msg(3, "Initializing Tree-sitter queries...")
  local function parse_query(lang, query_str, query_name)
    local success, query_obj = pcall(function() return vim.treesitter.query.parse(lang, query_str) end)
    if success then
      log_msg(4, "Successfully parsed query: " .. query_name)
      -- Store capture names by ID for easier lookup in iter_matches
      local captures = {}
      for i, name in ipairs(query_obj.captures) do
        captures[name] = i
      end -- name -> id mapping
      query_obj._capture_map = captures
      return query_obj
    else
      log_msg(1, string.format("Failed to parse %s query for %s: %s", query_name, lang, tostring(query_obj)))
      -- Optionally try a simpler fallback query here if needed
      return nil
    end
  end

  -- Lua Queries
  self.tree_sitter_queries.lua_functions = parse_query(
    "lua",
    [[
          (function_declaration
            name: [
              (identifier) @function_name
              (dot_index_expression field: (identifier) @method_name)
              (colon_index_expression field: (identifier) @method_name) ; Added colon for methods
            ]
            body: (_) @body) @function_def

          (assignment_statement
            left: [(variable_list (identifier) @function_name) (identifier) @function_name] ; handle a = function() end
            right: (expression_list (function_definition) @func_body)) @function_def

          (local_declaration
            left: (variable_list (identifier) @function_name)
            right: (expression_list (function_definition) @func_body)) @function_def
        ]],
    "lua_functions"
  )
  self.tree_sitter_queries.lua_requires = parse_query(
    "lua",
    [[
          (call
            function: (identifier) @func_name (#eq? @func_name "require")
            arguments: (arguments (string content: _ @module_name))) @require_call
        ]],
    "lua_requires"
  )
  self.tree_sitter_queries.lua_calls = parse_query(
    "lua",
    [[
            (call
              function: [
                (identifier) @call_name
                (dot_index_expression field: (identifier) @call_name)
                (colon_index_expression field: (identifier) @call_name)
              ]) @call_expr
        ]],
    "lua_calls"
  )

  -- JavaScript Queries (Combined definitions)
  self.tree_sitter_queries.js_defs = parse_query(
    "javascript", -- Also works for typescript often
    [[
          (function_declaration name: (identifier) @function_name) @function_def
          (lexical_declaration (variable_declarator name: (identifier) @function_name value: [(arrow_function) (function)])) @function_def ; const foo = () => {} / function() {}
          (variable_declaration (variable_declarator name: (identifier) @function_name value: (function))) @function_def ; var foo = function() {}
          (method_definition name: (property_identifier) @method_name) @method_def
          (class_declaration name: (identifier) @class_name) @class_def
          (export_statement declaration: [
            (function_declaration name: (identifier) @function_name) @function_def
            (lexical_declaration (variable_declarator name: (identifier) @function_name value: [(arrow_function) (function)])) @function_def
            (variable_declaration (variable_declarator name: (identifier) @function_name value: (function))) @function_def
            (class_declaration name: (identifier) @class_name) @class_def
          ]) ; Handle export function/class directly
        ]],
    "js_defs"
  )
  -- JS Calls (Basic Example)
  self.tree_sitter_queries.js_calls = parse_query(
    "javascript",
    [[
            (call_expression
              function: [
                (identifier) @call_name
                (member_expression property: (property_identifier) @call_name)
                (subscript_expression) ; a[b]() - harder to get name simply
                (optional_expression object: _ property: (property_identifier) @call_name) ; a?.b()
              ]) @call_expr
        ]],
    "js_calls"
  )
  -- Basic JS Imports/Exports (as fallback or supplement)
  self.tree_sitter_queries.js_imports_exports = parse_query(
    "javascript",
    [[
            (import_statement source: (string) @module_path) @import_statement
            (export_statement source: (string) @module_path) @export_statement ; export ... from '...'
            (export_statement) @export_statement ; export const/func/class ...
        ]],
    "js_imports_exports"
  )

  -- Python Queries
  self.tree_sitter_queries.python_imports = parse_query(
    "python",
    [[
            (import_statement name: (dotted_name) @module_name) @import_statement
            (import_statement name: (aliased_import alias: (identifier) @alias_name name: (dotted_name) @module_name)) @import_statement
            (import_from_statement
                module_name: (dotted_name) @from_module_name
                name: [(dotted_name) @imported_name (wildcard_import) @imported_name] ; Handle from mod import *
            ) @import_from_statement
             (import_from_statement
                module_name: (dotted_name) @from_module_name
                name: (aliased_import name: (identifier) @imported_name alias: (identifier) @imported_alias)
            ) @import_from_statement
        ]],
    "python_imports"
  )
  self.tree_sitter_queries.python_defs = parse_query(
    "python",
    [[
            (function_definition name: (identifier) @function_name) @function_def
            (class_definition name: (identifier) @class_name) @class_def
        ]],
    "python_defs"
  )
  self.tree_sitter_queries.python_calls = parse_query(
    "python",
    [[
            (call
                function: [
                    (identifier) @call_name
                    (attribute attribute: (identifier) @call_name)
                    (subscript_expression) ; a[b]() - harder to get name
                ]) @call_expr
        ]],
    "python_calls"
  )

  -- TODO: Add queries for other languages (Go, Ruby, etc.)
  log_msg(3, "Finished initializing Tree-sitter queries.")
end

-- Helper to find the first ancestor node that matches specific capture names in its match
-- This is difficult to implement correctly without re-querying or storing match context.
-- Prefer designing queries that capture the definition and name together.
function EnhancedCodeGraph:_find_ancestor_capture(start_node, capture_names)
  -- Placeholder implementation - tries to find ancestor by type
  local current_node = start_node
  while current_node do
    local parent = current_node:parent()
    if parent then
      local parent_type = parent:type()
      -- Check common definition node types across languages
      -- This mapping needs refinement based on actual TS grammars
      local def_types = {
        function_declaration = true,
        function_definition = true,
        method_definition = true,
        class_declaration = true,
        class_definition = true,
        -- Lua specific
        assignment_statement = true,
        local_declaration = true,
      }
      if def_types[parent_type] then
        -- Crude check: Assume this parent *might* correspond to the definition capture
        -- This is NOT guaranteed to be the node captured by e.g. @function_def
        log_msg(4, "Found potential ancestor definition node by type: " .. parent_type)
        return parent
      end
    else
      break -- Reached root
    end
    current_node = parent
  end
  log_msg(4, "Ancestor definition node not found via type check for names: " .. table.concat(capture_names, ", "))
  return start_node -- Fallback: return original node, maybe it's already the def?
end

-- Add a node, handling both in-memory and SQLite cases, including transactions.
-- Returns the node ID.
function EnhancedCodeGraph:add_node(node_type, name, file, start_line, end_line, content)
  -- Node ID generation - consider stability if lines change often. Hashing content might be an alternative.
  local id = string.format("%s:%s:%s:%d", node_type, file or "unknown", name or "anon", start_line or 0)
  -- Truncate potentially long content before storing
  local stored_content = content
  if stored_content and #stored_content > config.max_context_node_size * 2 then -- Store slightly more than needed for context
    stored_content = stored_content:sub(1, config.max_context_node_size * 2) .. "..."
  end

  local node_data = {
    id = id,
    type = node_type,
    name = name,
    file = file,
    start_line = start_line,
    end_line = end_line,
    content = stored_content, -- Store potentially truncated content
  }

  local is_new = true
  if self.use_in_memory then
    if self.nodes[id] then
      is_new = false
      -- Update existing node (merge?) - current code overwrites
      self.nodes[id] = node_data
    else
      self.nodes[id] = node_data
    end
    -- No reliable way to count changes in pure Lua tables easily
    -- We'll update stats based on is_new later
  else
    assert(self.db, "DB must be available for SQLite operations")
    -- Check if we can use prepared statements or need to fall back to direct execute
    local has_prepare = type(self.db.prepare) == 'function'
    local is_inserted = false
    
    if has_prepare then
      -- Try using prepared statement approach
      local prepare_ok, stmt_or_err = pcall(self.db.prepare, self.db, [[
              INSERT OR REPLACE INTO nodes (id, type, name, file, start_line, end_line, content)
              VALUES (?, ?, ?, ?, ?, ?, ?)
          ]])
          
      if prepare_ok and stmt_or_err then
        local stmt = stmt_or_err
        local ok, err = pcall(stmt.bind_values, stmt, {
          id,
          node_type,
          name,
          file,
          start_line,
          end_line,
          stored_content,
        })
        
        if ok then
          -- Safely check for row changes if possible
          local has_total_changes = type(self.db.total_changes) == 'function'
          local changes_before = 0
          
          if has_total_changes then
            changes_before = self.db:total_changes()
          end
          
          local step_ok, step_err = pcall(stmt.step, stmt)
          if not step_ok then
            log_msg(1, "Failed to step node insert/replace: " .. tostring(step_err))
            is_new = false -- Assume failure means not new
          else
            -- We succeeded, so assume it's a new node unless we can prove otherwise
            is_inserted = true
            
            -- If we can check changes, use that to be more precise
            if has_total_changes then
              local changes_after = self.db:total_changes()
              is_inserted = changes_after > changes_before
            end
          end
        else
          log_msg(1, "Failed to bind values for node insert/replace: " .. tostring(err))
        end
        pcall(function() if stmt.finalize then stmt:finalize() end end) -- Finalize if the method exists
      else
        log_msg(2, "Prepared statements not available: " .. tostring(stmt_or_err) .. ". Falling back to direct execute.")
      end
    end
    
    -- If prepared statement approach failed, try direct execute (less efficient but more compatible)
    if not is_inserted then
      -- Escape values for direct SQL execution
      local sql = string.format(
        "INSERT OR REPLACE INTO nodes VALUES ('%s', '%s', %s, %s, %d, %d, %s)",
        id:gsub("'", "''"), -- Escape single quotes
        node_type:gsub("'", "''"),
        name and ("'" .. name:gsub("'", "''") .. "'") or "NULL",
        file and ("'" .. file:gsub("'", "''") .. "'") or "NULL",
        start_line or 0,
        end_line or 0,
        stored_content and ("'" .. stored_content:gsub("'", "''") .. "'") or "NULL"
      )
      
      -- Same safe check for total_changes
      local has_total_changes = type(self.db.total_changes) == 'function'
      local changes_before = 0
      
      if has_total_changes then
        changes_before = self.db:total_changes()
      end
      
      local exec_ok, exec_err = pcall(self.db.execute, self.db, sql)
      
      if not exec_ok then
        log_msg(1, "Failed to execute direct node insert/replace: " .. tostring(exec_err))
        is_new = false
      else
        -- Assume success unless we can check
        is_inserted = true
        
        if has_total_changes then
          local changes_after = self.db:total_changes()
          is_inserted = changes_after > changes_before
        end
      end
    end
    
    is_new = is_inserted
  end

  -- Update stats counters if it's considered a new node
  if is_new then
    self.stats.nodes = self.stats.nodes + 1
    if node_type == "function" or node_type == "method" then
      self.stats.functions = self.stats.functions + 1
    elseif node_type == "class" then
      self.stats.classes = self.stats.classes + 1
    elseif node_type == "import" or node_type == "require" then
      self.stats.imports = self.stats.imports + 1
    elseif node_type == "export" then
      self.stats.exports = self.stats.exports + 1
    end
  end

  -- Update caches/indexes
  self.node_lookup_cache[id] = node_data -- Update cache if using DB
  -- Removed the simple self.node_by_name index as it was ambiguous and unused effectively

  return id
end

-- Add an edge, handling both in-memory and SQLite cases, including transactions.
function EnhancedCodeGraph:add_edge(source_id, target_id, relationship, metadata)
  if not source_id or not target_id or not relationship then
    log_msg(2, "Attempted to add edge with missing ID or relationship.")
    return
  end

  local metadata_json = safe_json_encode(metadata)
  local is_new = true

  if self.use_in_memory then
    local edge_key = source_id .. "->" .. target_id .. ":" .. relationship -- Simple key for uniqueness
    if not self.edges[edge_key] then
      self.edges[edge_key] = {
        source_id = source_id,
        target_id = target_id,
        relationship = relationship,
        metadata = metadata, -- Store decoded metadata
      }
    else
      is_new = false
      -- Update metadata if needed?
      self.edges[edge_key].metadata = metadata
    end
  else
    assert(self.db, "DB must be available for SQLite operations")
    -- Use INSERT OR IGNORE - don't update existing edges for now
    -- Consider INSERT OR REPLACE if metadata updates are important
    local stmt = self.db:prepare([[
            INSERT OR IGNORE INTO edges (source_id, target_id, relationship, metadata)
            VALUES (?, ?, ?, ?)
        ]])
    if stmt then
      local ok, err = pcall(stmt.bind_values, stmt, { source_id, target_id, relationship, metadata_json })
      if ok then
        local changes_before = self.db:total_changes()
        local step_ok, step_err = pcall(stmt.step, stmt)
        if not step_ok then
          log_msg(1, "Failed to step edge insert: " .. tostring(step_err))
          is_new = false
        else
          local changes_after = self.db:total_changes()
          if changes_after <= changes_before then
            is_new = false
          end -- No rows inserted implies it existed or failed
        end
      else
        log_msg(1, "Failed to bind values for edge insert: " .. tostring(err))
        is_new = false
      end
      pcall(stmt.finalize, stmt)
    else
      log_msg(1, "Failed to prepare edge insert statement.")
      is_new = false
    end
  end

  if is_new then
    self.stats.edges = self.stats.edges + 1
  end
end

-- Internal helper to track imports and setup reverse dependencies
function EnhancedCodeGraph:_track_import(file_path, alias, module_path, import_type, original_name)
  self.imports_map[file_path] = self.imports_map[file_path] or {}
  self.imports_map[file_path][alias] = {
    module = module_path,
    name = original_name, -- Name being imported (for named imports)
    type = import_type,
  }
  -- self.stats.imports = self.stats.imports + 1 -- Handled in add_node for 'import' type now

  local target_file = self:resolve_module_path(file_path, module_path)
  if target_file then
    -- Ensure target file path is absolute and normalized for consistent keys
    local resolved_target = fn.resolve(target_file) or target_file
    self.exports_map[resolved_target] = self.exports_map[resolved_target] or {}
    self.exports_map[resolved_target]["_imported_by"] = self.exports_map[resolved_target]["_imported_by"] or {}
    self.exports_map[resolved_target]["_imported_by"][file_path] = true
    log_msg(4, string.format("Tracking import: %s imports %s (from %s)", file_path, alias, resolved_target))
  else
    log_msg(4, string.format("Could not resolve module path '%s' imported in %s", module_path, file_path))
  end
end

--- Get language from file path or buffer type.
-- More reliable than content sniffing alone.
function EnhancedCodeGraph:_get_language(file_path, content)
  -- 1. Try buffer filetype if available (might require buffer context)
  -- local buf = fn.bufnr(file_path) -- This might not work if not loaded
  -- if buf > 0 then
  --     local ft = api.nvim_buf_get_option(buf, 'filetype')
  --     if ft and ft ~= "" then return ft end
  -- end

  -- 2. Use Tree-sitter's filetype detection based on path
  -- NOTE: ts.language.detect is not a standard function. Use filetype detection.
  local ft = vim.filetype.match({ filename = file_path, buf = 0 }) -- Match based on filename
  if ft then
    log_msg(4, "Detected language '" .. ft .. "' from filetype match: " .. file_path)
    -- Map filetype to the language name expected by tree-sitter parsers if needed
    local ft_map = {
      c = "c",
      cpp = "cpp",
      python = "python",
      javascript = "javascript",
      typescript = "typescript",
      lua = "lua",
      go = "go",
      rust = "rust",
      bash = "bash",
      html = "html",
      css = "css",
    }
    return ft_map[ft] or ft -- Return mapped name or original filetype
  end

  -- 3. Fallback: Use file extension mapping (less reliable for complex cases)
  local ext = file_path:match("%.([^%.\\/]+)$")
  if ext then
    ext = ext:lower()
    local lang_map = { -- Keep this map updated
      lua = "lua",
      py = "python",
      js = "javascript",
      ts = "typescript",
      jsx = "javascript",
      tsx = "typescript",
      go = "go",
      java = "java",
      kt = "kotlin",
      rb = "ruby",
      php = "php",
      cs = "c_sharp",
      cpp = "cpp",
      c = "c",
      h = "c",
      hpp = "cpp",
      rs = "rust",
      sh = "bash",
      -- Add more mappings
    }
    if lang_map[ext] then
      log_msg(4, "Detected language '" .. lang_map[ext] .. "' from extension: " .. file_path)
      return lang_map[ext]
    end
  end

  -- 4. Final fallback: Content sniffing (least reliable)
  local lang = self:_detect_language_from_content(content)
  if lang then
    log_msg(4, "Detected language '" .. lang .. "' from content: " .. file_path)
  end
  return lang
end

-- Basic content sniffing as a last resort
function EnhancedCodeGraph:_detect_language_from_content(content)
  -- Keep this minimal, prefer filetype/extension
  if content:match("^#!.*python") then
    return "python"
  end
  if content:match("^#!.*node") then
    return "javascript"
  end
  if content:match("import java%.") then
    return "java"
  end -- More specific
  if content:match("import kotlin%.") then
    return "kotlin"
  end -- More specific
  if content:match("^package main") and content:match("func main") then
    return "go"
  end
  if content:match("=>") and (content:match("import ") or content:match("export ")) then
    return "javascript"
  end -- Heuristic for JS modules
  if content:match("%f[%w]def%s+[_%w]+%s*%(") and content:match(":") then
    return "python"
  end
  if content:match("%f[%w]class%s+[_%w]+%s*:") then
    return "python"
  end
  if content:match("%f[%w]local%s+function") or content:match("%f[%w]function%s+[_%w]+%.") then
    return "lua"
  end
  return nil
end

-- Parse a single file and add its entities to the graph.
function EnhancedCodeGraph:parse_file(file_path)
  if self.files_indexed[file_path] then
    log_msg(4, "Skipping already indexed file: " .. file_path)
    return true -- Indicate skipped
  end

  log_msg(4, "Parsing file: " .. file_path)
  -- Use async read? For batch indexing, sync might be simpler.
  -- Consider vim.uv.fs_open/read for async if needed later.
  local success, lines = pcall(fn.readfile, file_path)
  if not success or not lines or #lines == 0 then
    log_msg(2, "Empty or unreadable file: " .. file_path .. " Error: " .. tostring(lines))
    self.files_indexed[file_path] = true -- Mark as indexed to avoid retrying
    return false -- Indicate failure
  end
  local content = table.concat(lines, "\n")
  local line_count = #lines
  lines = nil -- Free memory

  -- Determine language using improved method
  local lang = self:_get_language(file_path, content)

  -- Add file node first
  -- Use fn.fnamemodify only for display name, use full path for ID/lookup
  local file_display_name = fn.fnamemodify(file_path, ":t")
  local file_id = self:add_node("file", file_display_name, file_path, 0, line_count, nil)
  self.files_indexed[file_path] = true -- Mark as indexed early
  self.stats.files = self.stats.files + 1

  if not lang then
    log_msg(3, "Could not determine language for: " .. file_path .. ". Added as generic file.")
    return true -- Successfully added file node, but no further parsing
  end

  -- Special handling for JSON files
  if lang == "json" then
    -- JSON files don't need tree-sitter parsing for our purposes
    log_msg(3, "Processing JSON file with basic handling: " .. file_path)
    -- Add simple parsing for JSON if needed (e.g., for package.json)
    -- For now, just add the file node which we've already done
    return true -- Successfully added file node
  end
  
  -- Ensure Tree-sitter parser is available for the detected language
  local has_parser = pcall(function() return vim.treesitter.language.get_parser(lang) end)
  if not has_parser then
    log_msg(
      2,
      string.format(
        "Tree-sitter parser for language '%s' not available. Skipping detailed parsing for: %s",
        lang,
        file_path
      )
    )
    -- Optionally run basic regex import/export scan here if desired for unsupported languages
    -- self:process_generic_file(file_path, content, nil, file_id, lang) -- Pass nil for root
    return true -- Successfully added file node, but no detailed parsing
  end

  -- Parse with Tree-sitter
  local parser
  local ok, p = pcall(function() return vim.treesitter.get_string_parser(content, lang) end)
  if not ok or not p then
    log_msg(
      1,
      "Could not create Tree-sitter parser for: "
        .. file_path
        .. " with language: "
        .. lang
        .. " Error: "
        .. tostring(p)
    )
    return false -- Indicate parser creation failure
  end
  parser = p

  local ok_parse, tree_result = pcall(parser.parse, parser)
  if not ok_parse or not tree_result or #tree_result == 0 then
    log_msg(2, "Parsing resulted in empty or failed tree for: " .. file_path .. " Error: " .. tostring(tree_result))
    pcall(parser.destroy, parser) -- Attempt cleanup even on failure
    return false -- Indicate parsing failure
  end

  local tree = tree_result[1]
  local root = tree:root()

  -- Process using language-specific parser function if available
  if language_parsers[lang] then
    local parse_ok, err = pcall(language_parsers[lang], self, file_path, content, root, file_id)
    if not parse_ok then
      log_msg(1, string.format("Error processing %s file %s: %s", lang, file_path, tostring(err)))
    end
  elseif language_parsers[lang:lower()] then -- Try lowercase mapping
    local parse_ok, err = pcall(language_parsers[lang:lower()], self, file_path, content, root, file_id)
    if not parse_ok then
      log_msg(1, string.format("Error processing %s file %s: %s", lang, file_path, tostring(err)))
    end
  else
    -- Fallback to generic processing ONLY if no specific parser exists
    log_msg(3, "No specific parser for '" .. lang .. "', using generic regex processing for: " .. file_path)
    -- Removed root from generic signature:
    self:process_generic_file(file_path, content, file_id, lang)
  end

  -- Explicitly clean up parser and tree to free memory?
  -- No destroy method available in standard API. Let GC handle it.
  -- pcall(parser.destroy, parser)
  -- pcall(tree.destroy, tree)

  return true -- Indicate success
end

-- Process generic file: Use this as a *fallback* for basic imports/exports if needed,
-- but prioritize language-specific Tree-sitter parsers.
-- The regex patterns here are fragile and should be replaced by Tree-sitter queries.
-- Removed 'root' parameter as it wasn't used.
function EnhancedCodeGraph:process_generic_file(file_path, content, file_id, lang)
  log_msg(3, "Running GENERIC regex processing for language '" .. lang .. "' on: " .. file_path)
  -- Initialize maps
  self.imports_map[file_path] = self.imports_map[file_path] or {}
  self.exports_map[file_path] = self.exports_map[file_path] or {}

  -- **WARNING**: Regex parsing is inherently limited and error-prone for complex languages.
  -- These patterns are examples and may need significant refinement or replacement.

  local line_num = 0
  for line in content:gmatch("([^\n]*)") do
    line_num = line_num + 1

    -- Basic import patterns (adapt per language family)
    local module -- Removed unused 'name', 'alias' declaration
    if lang == "python" then
      module = line:match("^%s*import%s+([%w_.]+)")
      if module then
        self:_track_import(file_path, module:match("([^.]+)$") or module, module, "module")
      end
      local from_module, items = line:match("^%s*from%s+([%w_.]+)%s+import%s+(.+)")
      if from_module and items then
        -- Corrected gmatch pattern for items with aliases
        for item_str in items:gmatch("[^,]+") do
          local imported_name, alias_name = item_str:match("^%s*([%w_]+)%s+as%s+([%w_]+)%s*$")
          if not imported_name then
            imported_name = item_str:match("^%s*([%w_]+)%s*$")
          end
          if imported_name then
            alias_name = alias_name or imported_name
            self:_track_import(file_path, alias_name, from_module, "named", imported_name)
          end
        end
      end
    elseif lang == "go" then -- Go uses `import "path"` or `import (...)`
      module = line:match('^%s*import%s+"([^"]+)"')
      if not module then
        module = line:match('^%s*"([^"]+)"')
      end -- Inside block
      if module then
        self:_track_import(file_path, module:match("([^/]+)$") or module, module, "module")
      end
    elseif lang == "ruby" then
      module = line:match("^%s*require%s+['\"]([^'\"]+)['\"]")
        or line:match("^%s*require_relative%s+['\"]([^'\"]+)['\"]")
      if module then
        self:_track_import(file_path, module:match("([^/]+)$") or module, module, "require")
      end
    elseif lang == "c" or lang == "cpp" then
      module = line:match('^%s*#include%s*[<"]([^>"]+)[>"]')
      if module then
        self:_track_import(file_path, module:match("([^/%.]+)$") or module, module, "include")
      end
    elseif lang == "c_sharp" then
      module = line:match("^%s*using%s+([%w_%.]+)%s*;")
      if module then
        self:_track_import(file_path, module:match("([^%.]+)$") or module, module, "using")
      end
    end
    -- Add more language patterns here...

    -- Basic definition patterns (even more fragile than imports)
    local def_type, def_name = line:match("^%s*(class)%s+([%w_]+)") -- class X
    if not def_name then
      def_type, def_name = line:match("^%s*(?:def|function|func)%s+([%w_]+)")
    end -- def f() / func f() / function f()
    if not def_name and (lang == "c" or lang == "cpp") then
      def_name = line:match("^[%w_%s%*&]+%s+([%w_]+)%s*%([^%)]*%)%s*{?$") -- Basic C/C++ function
      if def_name then
        def_type = "function"
      end
    end

    if def_type and def_name then
      -- Very basic node creation, lacks accurate line numbers and content
      local entity_id = self:add_node(def_type, def_name, file_path, line_num, line_num, line)
      self:add_edge(file_id, entity_id, "contains")
      -- Assume exportable if not starting with underscore (common convention)
      if not (string.sub(def_name, 1, 1) == "_") then
        self.exports_map[file_path][def_name] = entity_id
      end
    end
  end
end

-- Process JS imports/exports using REGEX patterns (Fallback Method)
-- Keep this function separate as it's less reliable than Tree-sitter or jsts_parser
function EnhancedCodeGraph:process_js_imports_exports_with_patterns(file_path, content, file_id)
  log_msg(3, "Processing JS imports/exports with regex patterns for: " .. file_path)
  -- Initialize maps
  self.imports_map[file_path] = self.imports_map[file_path] or {}
  self.exports_map[file_path] = self.exports_map[file_path] or {}

  local line_num = 0
  for line in content:gmatch("([^\n]*)") do
    line_num = line_num + 1
    local added_import = false

    -- ES6 default import: import Name from 'module'
    local name, module_path = line:match("^%s*import%s+([%w_$]+)%s+from%s+['\"]([^'\"]+)['\"]")
    if name and module_path then
      local import_id = self:add_node("import", name, file_path, line_num, line_num, line)
      self:add_edge(file_id, import_id, "contains")
      self:_track_import(file_path, name, module_path, "default")
      added_import = true
    end

    -- ES6 named imports: import { A, B as C } from 'module'
    if not added_import then
      local imports_list_str, module_path_named =
        line:match("^%s*import%s*%{%s*([^}]+)%s*%}%s*from%s+['\"]([^'\"]+)['\"]")
      if imports_list_str and module_path_named then
        for item_str in imports_list_str:gmatch("[^,]+") do
          local orig_name, alias_name = item_str:match("^%s*([%w_$]+)%s+as%s+([%w_$]+)%s*$") -- B as C
          if not orig_name then
            orig_name = item_str:match("^%s*([%w_$]+)%s*$")
          end -- A
          if orig_name then
            alias_name = alias_name or orig_name
            local import_id = self:add_node("import", alias_name, file_path, line_num, line_num, line)
            self:add_edge(file_id, import_id, "contains")
            self:_track_import(file_path, alias_name, module_path_named, "named", orig_name)
            added_import = true
          end
        end
      end
    end

    -- Side effect import: import 'module'
    if not added_import then
      local side_module = line:match("^%s*import%s+['\"]([^'\"]+)['\"]%s*;?$")
      if side_module then
        local import_id = self:add_node("import", side_module, file_path, line_num, line_num, line)
        self:add_edge(file_id, import_id, "contains")
        self:_track_import(file_path, side_module, side_module, "side-effect")
        added_import = true
      end
    end

    -- ES6 namespace import: import * as Name from 'module'
    if not added_import then
      local ns_name, ns_module = line:match("^%s*import%s+%*%s+as%s+([%w_$]+)%s+from%s+['\"]([^'\"]+)['\"]")
      if ns_name and ns_module then
        local import_id = self:add_node("import", ns_name, file_path, line_num, line_num, line)
        self:add_edge(file_id, import_id, "contains")
        self:_track_import(file_path, ns_name, ns_module, "namespace")
        added_import = true
      end
    end

    -- Dynamic import: import('./module') - harder with regex, basic match
    if not added_import then
      local dyn_module = line:match("import%s*%(['\"]([^'\"]+)['\"]%)")
      if dyn_module then
        local import_id = self:add_node("import", dyn_module, file_path, line_num, line_num, line)
        self:add_edge(file_id, import_id, "contains")
        self:_track_import(file_path, dyn_module, dyn_module, "dynamic")
        added_import = true
      end
    end

    -- CommonJS require: const name = require('module')
    if not added_import then
      local req_var, req_module =
        line:match("^%s*(?:const|let|var)%s+([%w_$]+)%s*=%s*require%s*%(['\"]([^'\"]+)['\"]%)")
      if not req_var then -- Handle assignment without declaration: name = require('module')
        req_var, req_module = line:match("^%s*([%w_$]+)%s*=%s*require%s*%(['\"]([^'\"]+)['\"]%)")
      end
      if req_var and req_module then
        local import_id = self:add_node("import", req_var, file_path, line_num, line_num, line)
        self:add_edge(file_id, import_id, "contains")
        self:_track_import(file_path, req_var, req_module, "commonjs")
        added_import = true
      end
    end

    -- Exports (even harder with regex)
    -- export { A, B }
    local exports_list_str = line:match("^%s*export%s*%{%s*([^}]+)%s*%}")
    if exports_list_str then
      -- Use different loop var name to avoid redefining 'name' from outer scope potentially
      for export_item_name in exports_list_str:gmatch("([%w_$]+)") do
        -- Need to link this to the actual node defined elsewhere - difficult with regex alone
        -- Mark as exported, semantic analysis step should try to link later
        local export_id = self:add_node("export", export_item_name, file_path, line_num, line_num, line)
        self:add_edge(file_id, export_id, "contains")
        self.exports_map[file_path][export_item_name] = export_id -- Store export node ID for now
        -- self.stats.exports = (self.stats.exports or 0) + 1 -- Handled by add_node
      end
    end
    -- export default Name;
    local default_export_name = line:match("^%s*export%s+default%s+([%w_$]+)")
    if default_export_name then
      local export_id = self:add_node("export", "default", file_path, line_num, line_num, line)
      self:add_edge(file_id, export_id, "contains")
      self.exports_map[file_path]["default"] = export_id -- Store export node ID
      -- self.stats.exports = (self.stats.exports or 0) + 1 -- Handled by add_node
    end
    -- export const/let/var/function/class Name ...
    -- Removed unused export_type variable
    local export_name = line:match("^%s*export%s+(?:const|let|var|function|class)%s+([%w_$]+)")
    if export_name then
      local export_id = self:add_node("export", export_name, file_path, line_num, line_num, line)
      self:add_edge(file_id, export_id, "contains")
      self.exports_map[file_path][export_name] = export_id -- Store export node ID
      -- self.stats.exports = (self.stats.exports or 0) + 1 -- Handled by add_node
    end
  end
end

-- Helper function to resolve a module path to an actual file path
-- TODO: Improve this significantly for real-world projects (e.g., use LSP, check node_modules, aliases)
function EnhancedCodeGraph:resolve_module_path(current_file, module_path)
  -- Basic cleanup
  module_path = module_path:gsub("^['\"](.+)['\"]$", "%1"):gsub("\\", "/")

  local current_dir = fn.fnamemodify(current_file, ":h")
  local project_root = M.get_project_root() -- Use the shared project root finder

  -- 1. Handle relative paths
  if module_path:startswith("./") or module_path:startswith("../") then
    local full_path = fn.simplify(current_dir .. "/" .. module_path)
    -- Check common extensions
    local extensions = { "", ".lua", ".js", ".ts", ".jsx", ".tsx", ".py" } -- Add more as needed
    for _, ext in ipairs(extensions) do
      if fn.filereadable(full_path .. ext) == 1 then
        return fn.resolve(full_path .. ext)
      end
    end
    -- Check index files
    for _, ext in ipairs(extensions) do
      local index_path = full_path .. "/index" .. ext
      if fn.filereadable(index_path) == 1 then
        return fn.resolve(index_path)
      end
    end
    log_msg(4, "Relative path not found: " .. full_path)
    return nil
  end

  -- 2. Handle project root paths (e.g., starting with alias like '~/' or '/') - requires config
  -- Example: if module_path:startswith("@/") then ... project_root ...

  -- 3. Handle absolute paths (less common for imports)
  if fn.filereadable(module_path) == 1 then
    return fn.resolve(module_path)
  end

  -- 4. Handle bare imports (likely node_modules or stdlib) - Very basic check
  if not module_path:find("/") then
    -- Extremely simplified node_modules check
    local node_modules_path = project_root .. "/node_modules/" .. module_path
    if fn.isdirectory(node_modules_path) == 1 then
      -- Check package.json main or default index files
      -- local pkg_json_path = node_modules_path .. "/package.json"
      -- if fn.filereadable(pkg_json_path) == 1 then
      --   -- TODO: Parse package.json for 'main' field and resolve that path
      -- end
      -- Check common index files
      local extensions = { ".js", ".ts", ".jsx", ".tsx" }
      for _, ext in ipairs(extensions) do
        local index_path = node_modules_path .. "/index" .. ext
        if fn.filereadable(index_path) == 1 then
          return fn.resolve(index_path)
        end
      end
    end
    -- Could also check Python site-packages, Go modules, etc. - very complex
    log_msg(4, "Bare import not resolved: " .. module_path)
    return nil
  end

  -- 5. Default: Try resolving relative to project root
  local path_from_root = project_root .. "/" .. module_path
  local extensions = { "", ".lua", ".js", ".ts", ".jsx", ".tsx", ".py" }
  for _, ext in ipairs(extensions) do
    if fn.filereadable(path_from_root .. ext) == 1 then
      return fn.resolve(path_from_root .. ext)
    end
  end
  for _, ext in ipairs(extensions) do
    local index_path = path_from_root .. "/index" .. ext
    if fn.filereadable(index_path) == 1 then
      return fn.resolve(index_path)
    end
  end

  log_msg(4, "Module path could not be resolved: " .. module_path)
  return nil -- Could not resolve
end

-- Find component usages (kept largely the same, relies on populated exports_map)
function EnhancedCodeGraph:find_component_usages(component_name)
  log_msg(3, "Finding usages for component: " .. component_name)
  local usages = {}
  local found_files = {} -- Avoid duplicates if imported multiple ways

  -- Normalize component name (remove potential quotes, etc.)
  component_name = component_name:gsub("^['\"](.+)['\"]$", "%1"):gsub("%s+", "")

  -- Iterate through all files that have been processed (potential importers)
  for importer_path, imports in pairs(self.imports_map) do
    for alias, import_info in pairs(imports) do
      -- Try to resolve the imported module
      local target_file = self:resolve_module_path(importer_path, import_info.module)
      if target_file then
        target_file = fn.resolve(target_file) -- Normalize path
        local exports = self.exports_map[target_file]

        if exports then
          local match_found = false
          -- Check 1: Does the alias in the importer match the component name,
          -- AND is it importing the 'default' export from the target file?
          if alias == component_name and import_info.type == "default" and exports["default"] then
            match_found = true
          -- Check 2: Is it a named import where the alias matches the component name,
          -- AND the original imported name exists as an export in the target file?
          elseif
            import_info.type == "named"
            and alias == component_name
            and import_info.name
            and exports[import_info.name]
          then -- Check import_info.name exists
            match_found = true
          -- Check 3: Is it a named import where the *original* name matches the component name,
          -- AND that original name exists as an export in the target file?
          elseif import_info.type == "named" and import_info.name == component_name and exports[import_info.name] then
            match_found = true
            -- Note: In this case, the usage is via the alias, not component_name directly
            -- We might want to record `alias` here instead of `component_name`?
            -- Check 4: Is it a namespace import (`* as Name`) where Name matches,
            -- and the target file exports *something*? (Less precise)
          elseif import_info.type == "namespace" and alias == component_name then
            -- This indicates the file is imported, but not a specific component usage match.
            -- We could add it, but it's less direct. Maybe log it?
            log_msg(4, string.format("Namespace import '%s' from %s found in %s", alias, target_file, importer_path))
          -- Check 5: Direct CommonJS/require where variable name matches component name
          elseif import_info.type == "commonjs" and alias == component_name and exports then
            -- Assumes require('./module') exports match component name, could be default or named.
            match_found = true
          end

          if match_found and not found_files[importer_path] then
            table.insert(usages, {
              file = importer_path,
              as = alias, -- Record how it's named in the importing file
            })
            found_files[importer_path] = true
          end
        end
      end
    end
  end

  -- Also check direct exports map for reverse dependencies (more reliable if populated correctly)
  for target_file, exports in pairs(self.exports_map) do
    local uses_component = false
    if exports[component_name] then -- File directly exports the component by name
      uses_component = true
    elseif exports["default"] then
      -- Check if the default export's node name matches (if available)
      local default_node_id = exports["default"]
      -- Check if it's an ID string before trying to fetch
      if type(default_node_id) == "string" then
        local default_node = self:get_node_by_id(default_node_id)
        if default_node and default_node.name == component_name then
          uses_component = true
        end
      end
    end

    if uses_component and exports["_imported_by"] then
      for importer_path, _ in pairs(exports["_imported_by"]) do
        if not found_files[importer_path] then
          -- Find how it was imported in this specific file
          local import_alias = component_name -- Default assumption
          local import_details = self.imports_map[importer_path]
          if import_details then
            for alias, info in pairs(import_details) do
              local resolved_imp = self:resolve_module_path(importer_path, info.module)
              if resolved_imp and fn.resolve(resolved_imp) == fn.resolve(target_file) then
                if info.type == "default" and exports["default"] then
                  import_alias = alias -- Found the default import alias
                  break
                elseif info.type == "named" and info.name == component_name and exports[component_name] then
                  import_alias = alias -- Found the named import alias
                  break
                end
              end
            end
          end

          table.insert(usages, {
            file = importer_path,
            as = import_alias,
          })
          found_files[importer_path] = true
        end
      end
    end
  end

  log_msg(3, "Found " .. #usages .. " usages for " .. component_name)
  return usages
end

-- Find which files import a specific file (using the pre-computed reverse index)
function EnhancedCodeGraph:find_importers_of_file(target_file_path)
  local importers = {}
  local resolved_target_path = fn.resolve(target_file_path) -- Normalize path

  if self.exports_map[resolved_target_path] and self.exports_map[resolved_target_path]["_imported_by"] then
    log_msg(4, "Found importers in reverse index for: " .. resolved_target_path)
    for importer_path, _ in pairs(self.exports_map[resolved_target_path]["_imported_by"]) do
      table.insert(importers, importer_path)
    end
  else
    log_msg(4, "No importers found in reverse index for: " .. resolved_target_path)
    -- Optional: Could perform a slower scan through imports_map if needed, but less efficient
  end
  log_msg(3, "Found " .. #importers .. " importers for file: " .. target_file_path)
  return importers
end

-- Generate context from the graph for a query
function EnhancedCodeGraph:generate_context(query)
  log_msg(3, "Generating context for query: '" .. query .. "'")
  local context = "Codebase Context:\n"
  local current_size = #context

  -- Find relevant nodes based on query
  local success, nodes_or_err = pcall(function() return self:find_relevant_nodes(query) end)
  if not success then
    log_msg(1, "Error finding relevant nodes: " .. tostring(nodes_or_err))
    return "Error: Unable to search codebase - " .. tostring(nodes_or_err)
  end
  local nodes = nodes_or_err
  log_msg(3, string.format("Found %d relevant nodes for query.", #nodes))

  -- Handle specific "usage" queries first
  -- local usage_query_handled = false -- Removed unused variable
  if
    query:match("[Uu]se[s]?%s+this")
    or query:match("[Ii]mport[s]?%s+this")
    or query:match("[Ww]here%s+is%s+.+%s+used")
  then
    local component_name = query:match("[Ww]here%s+is%s+([%w_\"'/%.%-%$]+)%s+used")
    
    -- Extract component from the query string
    if component_name == nil then
      -- Check if "this" or filename is mentioned
      if query:match("[Uu]se[s]?%s+this") or query:match("[Ii]mport[s]?%s+this") then
        component_name = "this"
      end
    end
    
    if component_name then
      -- Simple component name extraction
      component_name = component_name:gsub("['\"]([^'\"]+)['\"]?", "%1")
      component_name = component_name:gsub("^%s+", ""):gsub("%s+$", "")
      
      log_msg(3, "Identified usage query for component: " .. component_name)
      
      -- Special handling for "this" file
      if component_name == "this" then
        local current_file = vim.fn.expand("%:p") -- Get current file path
        if current_file and current_file ~= "" then
          component_name = current_file
          log_msg(3, "Resolving 'this' to current file: " .. component_name)
        end
      end

      -- Extract the file basename for better import detection
      local basename = component_name:match("([^/\\]+)%.%w+$") or component_name
      log_msg(3, "Looking for imports of: " .. basename)
      
      -- Find usages - enhanced detection
      local usages = {}
      
      -- Import pattern detection - multiple formats
      local import_patterns = {
        "import[ \t]*[{][ \t]*['\"]?" .. basename .. "['\"]?[ \t]*[}]", -- import { BaseName }
        "import[ \t]+['\"]?" .. basename .. "['\"]?[ \t]+from", -- import BaseName from
        "import[ \t]+[{][ \t]*['\"]?" .. basename .. "['\"]?[ \t]*[}][ \t]+from", -- import { BaseName } from
        "require[ \t]*[(][ \t]*['\"].*" .. basename .. "['\"][ \t]*[)]", -- require('...BaseName')
        "from[ \t]+['\"].*" .. basename .. "['\"]" -- from '...BaseName'
      }
      
      -- Custom detection for the current file
      local usages_checked = {}
      for _, node in ipairs(nodes) do
        if node.file and node.content and not usages_checked[node.file] then
          usages_checked[node.file] = true

          -- Check for import statements
          local found_import = false
          for _, pattern in ipairs(import_patterns) do
            if node.content:lower():match(pattern:lower()) then
              found_import = true
              break
            end
          end

          -- Also do a more general search
          if not found_import then
            -- Check for the component name in content with common import markers
            if node.content:lower():match("import.*" .. basename:lower()) or
               node.content:lower():match("require.*" .. basename:lower()) or
               node.content:lower():match("from.*" .. basename:lower()) then
              found_import = true
            end
          end

          if found_import then
            -- Found a file that imports this component
            log_msg(3, "Found import in file: " .. node.file)
            table.insert(usages, node)
          end
        end
      end
      
      if #usages > 0 then
        context = context .. "\n### Files that import or use '" .. basename .. "':\n"
        
        -- Create a map to store import details with file paths as keys
        local import_details = {}
        for _, usage in ipairs(usages) do
          if usage.file and usage.file ~= component_name then
            -- Extract import statements from the content
            local file_content = usage.content or ""
            local lines = {}
            for line in file_content:gmatch("[^\n]+") do
              table.insert(lines, line)
            end
            
            -- Find all relevant import lines
            local import_lines = {}
            for _, line in ipairs(lines) do
              if (line:match("import.*" .. basename) or 
                  line:match("require.*" .. basename) or 
                  line:match("from.*" .. basename)) and 
                  not line:match("^%s*//") and -- Skip JavaScript comments
                  not line:match("^%s*#") and -- Skip Python/shell comments
                  not line:match("^%s*%-%-") -- Skip Lua comments
              then
                table.insert(import_lines, line)
              end
            end
            
            -- Store the details
            import_details[usage.file] = import_lines
          end
        end
        
        -- Output the import information in a formatted way
        for file, lines in pairs(import_details) do
          context = context .. "#### File: " .. file .. "\n"
          if #lines > 0 then
            context = context .. "```\n"
            for _, line in ipairs(lines) do
              context = context .. line .. "\n"
            end
            context = context .. "```\n"
          else
            context = context .. "(Referenced, but exact import statement not found)\n"
          end
        end
        
        context = context .. "\n"
      else
        context = context .. "\nNo files found that appear to import or use '" .. component_name .. "'\n\n"
      end
      current_size = #context -- Recalculate size
    end
  end

  -- Add content from relevant nodes and their direct relations
  local added_node_ids = {}
  for _, node in ipairs(nodes) do
    if current_size >= config.max_context_total_size then
      log_msg(2, "Context size limit reached early, truncating.")
      context = context .. "\n\n[Context truncated - maximum size reached]\n"
      break
    end

    if node and node.id and not added_node_ids[node.id] then -- Check node and node.id exist
      added_node_ids[node.id] = true
      local header = string.format(
        "\n--- Relevant: %s '%s' in %s (Lines %d-%d) ---\n",
        node.type or "?",
        node.name or "anonymous",
        node.file or "unknown",
        node.start_line or 0,
        node.end_line or 0
      )
      local node_content = node.content or ""
      -- Truncate individual node content if needed
      if #node_content > config.max_context_node_size then
        node_content = node_content:sub(1, config.max_context_node_size) .. "\n... [content truncated]\n"
      end

      local block = header .. node_content .. "\n"
      if current_size + #block <= config.max_context_total_size then
        context = context .. block
        current_size = current_size + #block

        -- Add directly related nodes (limited number)
        local related = self:get_related_nodes(node.id)
        local related_count = 0
        for _, rel_node_info in ipairs(related) do
          if related_count >= config.max_related_nodes * 2 then
            break
          end -- Limit related nodes shown per relevant node
          if rel_node_info and rel_node_info.id and not added_node_ids[rel_node_info.id] then -- Check rel_node_info and id exist
            added_node_ids[rel_node_info.id] = true
            local rel_header = string.format(
              "\n  Related (%s): %s '%s' in %s\n",
              rel_node_info.relationship or "?",
              rel_node_info.type or "?",
              rel_node_info.name or "anonymous",
              rel_node_info.file or "unknown"
            )
            local rel_content = rel_node_info.content or ""
            -- Truncate related content more aggressively
            if #rel_content > config.max_context_node_size / 2 then
              rel_content = rel_content:sub(1, config.max_context_node_size / 2) .. "\n  ... [content truncated]\n"
            end
            local rel_block = rel_header .. "  " .. rel_content:gsub("\n", "\n  ") .. "\n" -- Indent related content

            if current_size + #rel_block <= config.max_context_total_size then
              context = context .. rel_block
              current_size = current_size + #rel_block
              related_count = related_count + 1
            else
              context = context .. "\n  [Further related content truncated]\n"
              current_size = config.max_context_total_size -- Ensure loop breaks
              break -- Stop adding related for this node
            end
          end
        end
      else
        -- Node itself was too large, stop adding nodes
        context = context .. "\n\n[Context truncated - node too large]\n"
        current_size = config.max_context_total_size
        break
      end
    end
  end

  log_msg(3, string.format("Generated context size: %d bytes", current_size))
  return context
end

-- Find nodes relevant to a query (using scoring for in-memory, basic LIKE for SQLite)
function EnhancedCodeGraph:find_relevant_nodes(query)
  local results = {}
  if not query or query == "" then
    return results
  end

  local words = {}
  for word in query:gmatch("[^%s%p]+") do -- Extract alphanumeric words
    if #word > 1 then
      table.insert(words, word:lower())
    end -- Ignore single chars, use lower
  end
  if #words == 0 then
    log_msg(2, "No valid words extracted from query: " .. query)
    return results
  end

  if self.use_in_memory then
    -- In-memory scoring based implementation
    local scored_results = {}
    -- Use _ instead of id as it's unused
    for _, node in pairs(self.nodes) do
      local score = 0
      local name_lower = node.name and node.name:lower() or ""
      local file_lower = node.file and node.file:lower():gsub("[\\/]", " ") or "" -- Match path parts
      local content_lower = node.content and node.content:lower() or ""

      for _, word in ipairs(words) do
        if name_lower:find(word, 1, true) then
          score = score + 15
        end -- Strong match for name
        if file_lower:find(word, 1, true) then
          score = score + 5
        end -- Medium match for file path
        if content_lower:find(word, 1, true) then
          score = score + 1
        end -- Weak match for content
      end
      -- Boost score for exact name match
      if node.name and node.name:lower() == query:lower() then
        score = score + 50
      end

      if score > 0 then
        table.insert(scored_results, { node = node, score = score })
      end
    end

    table.sort(scored_results, function(a, b)
      return a.score > b.score
    end)

    for i = 1, math.min(config.max_relevant_nodes, #scored_results) do
      table.insert(results, scored_results[i].node)
    end
  else
    -- SQLite implementation (Simple LIKE matching)
    -- TODO: Implement FTS5 search here if enabled for better relevance
    local like_pattern = "%" .. table.concat(words, "%") .. "%"
    local function find_relevant_nodes(like_pattern)
      if like_pattern:match("%s") then
        -- Crude fix for multi-word queries: replace spaces with wildcards
        like_pattern = like_pattern:gsub("%s+", "%%")
      -- First check all tables in the database and determine the correct table name
      local nodes_table_name = "nodes" -- Default table name
      local table_exists = false
      
      if type(self.db.eval) == 'function' then
        local ok, tables = pcall(function()
          return self.db:eval("SELECT name FROM sqlite_master WHERE type='table'")
        end)
        
        if ok and type(tables) == 'table' then
          -- Log available tables for debugging
          local tables_str = ""
          for _, tbl in ipairs(tables) do
            if type(tbl) == 'table' and tbl.name then
              tables_str = tables_str .. tbl.name .. ", "
              -- Check if we have a nodes or equivalent table
              if tbl.name == "nodes" then
                nodes_table_name = "nodes"
                table_exists = true
              end
            end
          end
          
          if tables_str ~= "" then
            log_msg(2, "Database contains tables: " .. tables_str)
          end
          
          if table_exists then
            log_msg(2, "Found nodes table in the database")
          else
            log_msg(2, "Nodes table not found in database - skipping optimized query")
            return {} -- Return empty results if table doesn't exist
          end
        else
          log_msg(2, "Failed to get table list - skipping optimized query")
          return {} -- Return empty results if query fails
        end
      end
      
      if table_exists then
        log_msg(2, "Using kkharji/sqlite.lua optimized query methods")
        -- Use the better parameterized query approach with kkharji/sqlite.lua
        local query_pattern = "%" .. like_pattern .. "%" -- Add wildcards for LIKE
      
        -- Simplify the query to avoid complex syntax issues
        local sql = string.format("SELECT id, type, name, file, start_line, end_line, content FROM %s WHERE name LIKE ? OR file LIKE ? LIMIT ?", nodes_table_name)
      
        -- Try with simpler parameter binding
        local select_ok, rows = pcall(function()
          return self.db:select(sql, query_pattern, query_pattern, config.max_relevant_nodes)
        end)
      
        if select_ok and type(rows) == 'table' then
          log_msg(2, "Found " .. #rows .. " relevant nodes using select with parameters")
          return rows
        else
          log_msg(2, "Select with parameters failed, trying direct eval method")
          
          -- Try a much simpler direct eval approach without complex SQL
          if type(self.db.eval) == 'function' then
            -- First try to get all nodes (limiting results) as a simpler approach
            local simple_sql = string.format("SELECT * FROM %s LIMIT %d", nodes_table_name, config.max_relevant_nodes)
            
            local eval_ok, eval_result = pcall(function()
              return self.db:eval(simple_sql)
            end)
            
            if eval_ok and type(eval_result) == 'table' then
              log_msg(2, "Found " .. #eval_result .. " nodes using simple SELECT")
              
              -- Now filter in Lua instead of SQL to avoid syntax issues
              local filtered_results = {}
              local pattern = like_pattern:lower() -- Case insensitive matching
              
              -- Safer iteration that works with both array and map-style results
              local process_node = function(node)
                if type(node) ~= 'table' then return end
                
                -- Handle both kkharji/sqlite.lua styles (array of tables or direct table)
                local name = node.name or ''
                if type(name) ~= 'string' then name = tostring(name) or '' end
                
                local file = node.file or ''
                if type(file) ~= 'string' then file = tostring(file) or '' end
                
                name = name:lower()
                file = file:lower()
                
                if name:find(pattern, 1, true) or file:find(pattern, 1, true) then
                  table.insert(filtered_results, node)
                end
              end
              
              -- Handle different return formats from different SQLite adapters
              if type(eval_result) == 'table' then
                if #eval_result > 0 then
                  -- Array-like result
                  for i=1, math.min(#eval_result, config.max_relevant_nodes*2) do
                    process_node(eval_result[i])
                    if #filtered_results >= config.max_relevant_nodes then break end
                  end
                else
                  -- Might be direct table result
                  process_node(eval_result)
                end
              end
              
              log_msg(2, "Filtered to " .. #filtered_results .. " relevant nodes after Lua processing")
              return filtered_results
            else
              log_msg(2, "Simple SELECT failed: " .. (type(eval_result) == 'string' and eval_result or "unknown error"))
            end
          end
        end
      end -- Close table_exists conditional
    end
    
    -- Fall back to standard query methods
    if type(self.db.prepare) ~= 'function' then
      log_msg(1, "SQLite prepare function not available for query, trying alternative approaches")
      -- Try fallback with direct execute for simple queries
      local sql = string.format(
        "SELECT id, type, name, file, start_line, end_line, content FROM nodes WHERE name LIKE '%s' OR file LIKE '%s' LIMIT %d",
        like_pattern:gsub("'", "''"), -- Escape quotes (like_pattern already has % symbols)
        like_pattern:gsub("'", "''"),
        config.max_relevant_nodes
      )
      
      -- Try different SQLite execute methods
      if type(self.db.eval) == 'function' then
        log_msg(2, "Trying db.select method for query (kkharji/sqlite.lua)")
        -- For kkharji/sqlite.lua, we should use the specific method for queries
        -- Try first with the select API which is specifically for queries that return data
        local select_ok, rows_or_err = pcall(function()
          -- Method call syntax with colon for kkharji/sqlite.lua
          return self.db:select(sql)
        end)
        
        if select_ok then
          log_msg(3, "Successfully called select method")
          if type(rows_or_err) == 'table' then
            for _, row in ipairs(rows_or_err) do
              table.insert(results, row)
            end
            log_msg(2, "Found " .. #results .. " results with select")
          else
            log_msg(2, "Select returned a non-table result: " .. type(rows_or_err))
          end
        else
          -- Fall back to eval if select isn't available
          log_msg(2, "Select method failed, trying eval: " .. tostring(rows_or_err))
          local eval_ok, eval_result = pcall(function()
            return self.db:eval(sql)
          end)
          
          if eval_ok and type(eval_result) == 'table' then
            for _, row in ipairs(eval_result) do
              table.insert(results, row)
            end
            log_msg(2, "Found " .. #results .. " results with eval fallback")
          elseif eval_ok then
            log_msg(2, "Eval returned a non-table result: " .. type(eval_result))
          end
        end
      elseif type(self.db.execute) == 'function' then
        log_msg(2, "Trying db.execute method for query")
        
        -- Try with method syntax first (self.db:execute)
        local exec_ok, rows_or_err = pcall(function()
          return self.db:execute(sql)
        end)
        
        -- Fall back to functional syntax if method fails
        if not exec_ok then
          exec_ok, rows_or_err = pcall(self.db.execute, self.db, sql)
        end
        
        if exec_ok then
          if type(rows_or_err) == 'table' then
            for _, row in ipairs(rows_or_err) do
              table.insert(results, row)
            end
            log_msg(2, "Successfully executed query with db.execute, found " .. #results .. " results")
          elseif type(rows_or_err) == 'userdata' or type(rows_or_err) == 'function' then
            -- Some SQLite implementations return a statement/object
            log_msg(2, "db.execute returned non-table result, attempting to process")
            local process_ok, process_result = pcall(function()
              local rows = {}
              while rows_or_err:step() do
                table.insert(rows, rows_or_err:get_values())
              end
              return rows
            end)
            if process_ok and type(process_result) == 'table' then
              for _, row in ipairs(process_result) do
                table.insert(results, row)
              end
              log_msg(2, "Successfully processed statement result, found " .. #results .. " results")
            else
              log_msg(1, "Failed to process statement result: " .. tostring(process_result))
            end
          elseif type(rows_or_err) == 'boolean' then
            -- Some SQLite implementations return a boolean success indicator
            -- This likely means there are no results
            if rows_or_err then
              log_msg(2, "Query executed successfully, but returned no results (boolean true)")
              -- Try a direct fetch if possible
              if type(self.db.last_insert_rowid) == 'function' then
                log_msg(2, "Attempting alternative query approach")
                local fetch_ok, fetch_result = pcall(function()
                  -- Try a more direct approach with a different query
                  local alt_query = "SELECT * FROM nodes WHERE name LIKE '%" .. like_pattern:gsub("'", "''") .. "%' LIMIT " .. config.max_relevant_nodes
                  return self.db.execute(self.db, alt_query)
                end)
                if fetch_ok and type(fetch_result) == 'table' and #fetch_result > 0 then
                  for _, row in ipairs(fetch_result) do
                    table.insert(results, row)
                  end
                  log_msg(2, "Alternative query found " .. #results .. " results")
                end
              end
            else
              log_msg(1, "Query execution failed (boolean false)")
            end
          else
            log_msg(1, "Unknown result type from db.execute: " .. type(rows_or_err))
          end
        else
          log_msg(1, "Failed to execute query with db.execute: " .. tostring(rows_or_err))
        end
      elseif type(self.db.exec) == 'function' then
        -- Try with exec method which some SQLite implementations provide
        log_msg(2, "Trying db.exec method for query")
        local exec_ok, exec_result = pcall(self.db.exec, self.db, sql)
        if exec_ok then
          log_msg(2, "Successfully executed query with db.exec, processing results")
          -- Handle result based on its type
          if type(exec_result) == 'table' then
            for _, row in ipairs(exec_result) do
              table.insert(results, row)
            end
            log_msg(2, "Found " .. #results .. " results from exec")
          end
        else
          log_msg(1, "Failed to execute query with db.exec: " .. tostring(exec_result))
        end
      else
        log_msg(1, "No suitable SQLite query execution method found")
      end
      
      return results
    end
    
    -- Normal prepare path if available
    local prepare_ok, stmt_or_err = pcall(self.db.prepare, self.db, query_sql)
    if prepare_ok and stmt_or_err then
      local stmt = stmt_or_err
      -- Use bind_names for named parameters
      local ok, err = pcall(stmt.bind_names, stmt, params)
      if ok then
        local has_step = type(stmt.step) == 'function'
        local has_sqlite = type(sqlite) == 'table' and type(sqlite.ROW) ~= 'nil'
        
        if has_step and has_sqlite then
          while stmt:step() == sqlite.ROW do
            -- sqlite.lua returns a table when using get_values
            if type(stmt.get_values) == 'function' then
              table.insert(results, stmt:get_values())
            end
          end
        elseif has_step then
          -- If we have step but no sqlite.ROW constant, try a simple approach
          while pcall(stmt.step, stmt) do
            if type(stmt.get_values) == 'function' then
              table.insert(results, stmt:get_values())
            else
              break -- Can't get values, no point continuing
            end
          end
        end
      else
        log_msg(1, "Failed to bind values for relevant node query: " .. tostring(err))
      end
      pcall(function() if stmt.finalize then stmt:finalize() end end)
    else
      log_msg(1, "Failed to prepare relevant node query: " .. tostring(stmt_or_err))
    end
  end

  return results
end

-- Get a single node by ID (uses cache if using DB)
function EnhancedCodeGraph:get_node_by_id(node_id)
  if not node_id then
    return nil
  end -- Guard against nil ID

  if self.use_in_memory then
    return self.nodes[node_id]
  else
    -- Check cache first
    if self.node_lookup_cache[node_id] then
      return self.node_lookup_cache[node_id]
    end

    -- Check if prepare method is available
    if type(self.db.prepare) ~= 'function' then
      log_msg(1, "SQLite prepare function not available for get_node_by_id")
      -- Try fallback with direct execute
      local sql = string.format(
        "SELECT id, type, name, file, start_line, end_line, content FROM nodes WHERE id = '%s'",
        node_id:gsub("'", "''")
      )
      
      local exec_ok, rows_or_err = pcall(self.db.execute, self.db, sql)
      if exec_ok and type(rows_or_err) == 'table' and #rows_or_err > 0 then
        local row = rows_or_err[1]
        local node = {
          id = row[1] or row.id,
          type = row[2] or row.type,
          name = row[3] or row.name,
          file = row[4] or row.file,
          start_line = row[5] or row.start_line,
          end_line = row[6] or row.end_line,
          content = row[7] or row.content,
        }
        self.node_lookup_cache[node_id] = node -- Cache for future lookups
        return node
      else
        log_msg(1, "Failed to execute direct node by ID query: " .. tostring(rows_or_err))
        return nil
      end
    end
    
    -- Fetch from DB using prepared statement if available
    local prepare_ok, stmt_or_err = pcall(self.db.prepare, self.db, "SELECT id, type, name, file, start_line, end_line, content FROM nodes WHERE id = ?")
    if prepare_ok and stmt_or_err then
      local stmt = stmt_or_err
      local ok, err = pcall(stmt.bind_values, stmt, { node_id })
      if ok then
        local step_ok, step_result = pcall(stmt.step, stmt)
        local has_sqlite = type(sqlite) == 'table' and type(sqlite.ROW) ~= 'nil'
        
        if step_ok and ((has_sqlite and step_result == sqlite.ROW) or step_result == true) then
          -- Try to get values safely
          if type(stmt.get_value) == 'function' then
            local node = {
              id = stmt:get_value(0),
              type = stmt:get_value(1),
              name = stmt:get_value(2),
              file = stmt:get_value(3),
              start_line = stmt:get_value(4),
              end_line = stmt:get_value(5),
              content = stmt:get_value(6),
            }
            self.node_lookup_cache[node_id] = node -- Cache for future lookups
            pcall(function() if stmt.finalize then stmt:finalize() end end)
            return node
          elseif type(stmt.get_values) == 'function' then
            -- Alternative get_values approach
            local values = stmt:get_values()
            local node = {
              id = values[1] or values.id,
              type = values[2] or values.type,
              name = values[3] or values.name,
              file = values[4] or values.file,
              start_line = values[5] or values.start_line,
              end_line = values[6] or values.end_line,
              content = values[7] or values.content,
            }
            self.node_lookup_cache[node_id] = node
            pcall(function() if stmt.finalize then stmt:finalize() end end)
            return node
          end
        end
      else
        log_msg(1, "Failed to bind values for node by ID query: " .. tostring(err))
      end
      pcall(function() if stmt.finalize then stmt:finalize() end end)
    else
      log_msg(1, "Failed to prepare node by ID query: " .. tostring(stmt_or_err))
    end
  end

  return nil -- Node not found
end

-- Get related nodes for a given node ID (outgoing and incoming edges)
function EnhancedCodeGraph:get_related_nodes(node_id)
  local related = {}
  
  if not self.db then
    log_msg(0, "No database connection available")
    return related
  end
  
  -- In-memory path - simpler implementation
  if self.use_in_memory then
    local added_ids = {} -- Prevent duplicates if related in multiple ways
    
    -- Helper function to add related nodes with relationship info
    local function add_related(target_id, relationship, direction, metadata_str)
      if not target_id or added_ids[target_id] then
        return
      end -- Skip nil or duplicates

      local node = self:get_node_by_id(target_id)
      if node then
        local rel_name = relationship
        if direction == "incoming" then
          -- Try to make the relationship name make sense from the original node's perspective
          if relationship == "calls" then
            rel_name = "is called by"
          elseif relationship == "imports" then
            rel_name = "is imported by"
          elseif relationship == "contains" then
            rel_name = "is contained by"
          else
            rel_name = "related to (" .. relationship .. " from)"
          end
        end
        local metadata = safe_json_decode(metadata_str) -- Decode metadata here
        table.insert(related, {
          id = node.id,
          relationship = rel_name,
          type = node.type,
          name = node.name,
          file = node.file,
          content = node.content,
          metadata = metadata, -- Add decoded metadata
        })
        added_ids[target_id] = true
      end
    end
    
    -- Iterate through all edges (less efficient for large graphs)
    for _, edge in pairs(self.edges) do
      if edge.source_id == node_id then
        add_related(edge.target_id, edge.relationship, "outgoing", safe_json_encode(edge.metadata))
      end -- Encode metadata for consistency
      if edge.target_id == node_id then
        add_related(edge.source_id, edge.relationship, "incoming", safe_json_encode(edge.metadata))
      end
    end
    
    return related
  end
  
  -- SQLite path - handling multiple SQLite library implementations
  
  -- First check if required tables exist
  local edges_exist = false
  local nodes_table_name = "nodes"
  local edges_table_name = "edges"
  
  if type(self.db.eval) == 'function' then
    local ok, tables = pcall(function()
      return self.db:eval("SELECT name FROM sqlite_master WHERE type='table'")
    end)
    
    if ok and type(tables) == 'table' then
      local tables_str = ""
      for _, tbl in ipairs(tables) do
        if type(tbl) == 'table' and tbl.name then
          tables_str = tables_str .. tbl.name .. ", "
          if tbl.name == "edges" then
            edges_exist = true
            edges_table_name = "edges"
          end
          if tbl.name == "nodes" then
            nodes_table_name = "nodes"
          end
        end
      end
      
      if tables_str ~= "" then
        log_msg(2, "Database contains tables: " .. tables_str)
      end
    end
  end
  
  if not edges_exist then
    log_msg(2, "No edges table found, skipping relation lookup")
    return related
  end
  
  -- Use a much simpler query approach that works with kkharji/sqlite.lua
  local related_ids = {}
  local query_ok = false
  
  -- Try to get edges related to this node
  if type(self.db.eval) == 'function' then
    -- First get edges where this node is the source
    local simple_sql = string.format("SELECT * FROM %s WHERE source_id = %d", edges_table_name, node_id)
    
    local eval_ok, out_edges = pcall(function()
      return self.db:eval(simple_sql)
    end)
    
    if eval_ok and type(out_edges) == 'table' then
      for _, edge in ipairs(out_edges) do
        if edge.target_id and not related_ids[edge.target_id] then
          related_ids[edge.target_id] = true
        end
      end
      query_ok = true
    end
    
    -- Then get edges where this node is the target
    simple_sql = string.format("SELECT * FROM %s WHERE target_id = %d", edges_table_name, node_id)
    
    local eval_ok2, in_edges = pcall(function()
      return self.db:eval(simple_sql)
    end)
    
    if eval_ok2 and type(in_edges) == 'table' then
      for _, edge in ipairs(in_edges) do
        if edge.source_id and not related_ids[edge.source_id] then
          related_ids[edge.source_id] = true
        end
      end
      query_ok = true
    end
  end
  
  -- If we got edge data, now get the node data for all related nodes
  if query_ok and next(related_ids) then
    local node_count = 0
    for id, _ in pairs(related_ids) do
      if node_count >= config.max_related_nodes then
        break
      end
      
      local node_sql = string.format("SELECT * FROM %s WHERE id = %d LIMIT 1", nodes_table_name, id)
      
      local node_ok, node_data = pcall(function()
        return self.db:eval(node_sql)
      end)
      
      if node_ok and type(node_data) == 'table' and #node_data > 0 then
        table.insert(related, node_data[1])
        node_count = node_count + 1
      end
    end
  end
  
  return related
end

-- Analyze semantic relationships (primarily function calls)
-- This is the most complex part and needs significant improvement, ideally using Tree-sitter queries.
function EnhancedCodeGraph:analyze_semantic_relationships()
  log_msg(3, "Performing semantic analysis (call linking)...")
  local nodes_to_analyze = self.pending_analysis_nodes
  self.pending_analysis_nodes = {} -- Clear pending list before starting

  if vim.tbl_isempty(nodes_to_analyze) then
    log_msg(3, "No nodes pending semantic analysis.")
    return
  end

  -- Begin transaction if using DB
  if not self.use_in_memory then
    local begin_ok, begin_err = pcall(self.db.exec, self.db, "BEGIN;")
    if not begin_ok then
      log_msg(1, "Failed to begin semantic analysis transaction: " .. tostring(begin_err))
      -- Proceed without transaction? Might be slow.
    end
  end

  local analyzed_count = 0
  for func_id, func_ts_node in pairs(nodes_to_analyze) do
    local func_node_data = self:get_node_by_id(func_id) -- Fetch data (from cache or DB)
    if func_node_data and func_node_data.content and func_ts_node then
      local lang = self:_get_language(func_node_data.file, func_node_data.content)
      if lang then
        -- Use pcall to isolate errors during analysis of one node
        local analysis_ok, analysis_err =
          pcall(self._detect_function_calls_ts, self, func_node_data, func_ts_node, lang)
        if analysis_ok then
          analyzed_count = analyzed_count + 1
        else
          log_msg(
            1,
            string.format(
              "Error analyzing calls in node %s (%s): %s",
              func_id,
              func_node_data.file or "?",
              tostring(analysis_err)
            )
          )
        end
      end
    else
      log_msg(4, "Skipping analysis for node " .. func_id .. " - missing data or TS node.")
    end
    -- Check periodically if analysis is taking too long?
  end

  -- Commit transaction if using DB
  if not self.use_in_memory then
    local ok, err = pcall(self.db.exec, self.db, "COMMIT;")
    if not ok then
      log_msg(1, "Failed to commit semantic analysis transaction: " .. tostring(err))
    end
  end

  log_msg(3, "Semantic analysis completed for " .. analyzed_count .. " nodes.")
end

-- Detect function calls using Tree-sitter queries (More Accurate Method)
function EnhancedCodeGraph:_detect_function_calls_ts(caller_node_data, caller_ts_node, lang)
  local query_name = lang .. "_calls"
  local call_query = self.tree_sitter_queries[query_name]
  if not call_query then
    -- log_msg(4, "No call query available for language: " .. lang)
    -- Fallback to regex? Less ideal.
    -- self:_detect_function_calls_regex(caller_node_data, lang)
    return
  end

  local file_path = caller_node_data.file
  -- Get fresh content for analysis - the stored node content might be truncated
  -- This adds overhead but ensures accuracy. Consider storing full content if performance allows.
  local ok_read, lines = pcall(fn.readfile, file_path)
  if not ok_read or not lines then
    log_msg(2, "Could not read file content for call analysis: " .. file_path)
    return
  end
  local current_content = table.concat(lines, "\n")
  lines = nil -- Free memory

  log_msg(
    4,
    string.format("Analyzing calls in %s:%s using TS", file_path, caller_node_data.name or caller_node_data.id)
  )

  -- Use iter_matches to process whole call expressions
  for _, match, _ in call_query:iter_matches(caller_ts_node, current_content, 0) do -- Pass 0 for content index
    local call_name_node = match[call_query._capture_map["call_name"]] -- Use capture map for lookup
    if call_name_node then
      local called_name = vim.treesitter.get_node_text(call_name_node, current_content)

      -- Attempt to resolve the called_name to a target node ID
      -- Pass the actual TS node for potential scope analysis (though not fully used yet)
      local target_id = self:_resolve_call_target(called_name, file_path, call_name_node)

      if target_id then
        log_msg(4, string.format("Linking call: %s -> %s (Resolved)", caller_node_data.id, target_id))
        local call_site_node = match[call_query._capture_map["call_expr"]]
        -- Recalculate start_row safely
        local start_row = 0
        if call_site_node then
          local r_start, _, _, _ = call_site_node:range()
          start_row = r_start + 1 -- range() is 0-indexed, lines are 1-indexed
        end
        self:add_edge(caller_node_data.id, target_id, "calls", {
          line = start_row,
          target_name = called_name, -- Store the name as it appeared at call site
        })
      else
        log_msg(4, string.format("Could not resolve call target for '%s' in %s", called_name, file_path))
        -- Optional: Add an edge to an "unresolved_call" node?
      end
    end
  end
end

-- Resolve call target based on name, current file, and scope (basic version)
-- THIS IS A VERY SIMPLIFIED RESOLVER AND A MAJOR AREA FOR FUTURE IMPROVEMENT
-- The `current_scope_node` parameter is kept for future scope analysis but currently unused.
function EnhancedCodeGraph:_resolve_call_target(called_name, current_file, current_scope_node) -- Added comment about unused param
  -- 1. Check imports in the current file
  local imports = self.imports_map[current_file] or {}
  if imports[called_name] then
    local import_info = imports[called_name]
    local target_file = self:resolve_module_path(current_file, import_info.module)
    if target_file then
      target_file = fn.resolve(target_file)
      local exports = self.exports_map[target_file] or {}
      local export_name_to_find = import_info.name or "default" -- Find original name or default

      -- Ensure the export value is a string ID
      if type(exports[export_name_to_find]) == "string" then
        log_msg(4, "Resolved call via import: " .. called_name .. " -> " .. exports[export_name_to_find])
        return exports[export_name_to_find] -- Return the node ID of the exported entity
      else
        log_msg(
          4,
          "Export target for imported name '"
            .. export_name_to_find
            .. "' not found or not a node ID in "
            .. target_file
        )
      end
    end
  end

  -- 2. Check for local definitions within the same file
  -- This requires searching nodes defined *only* in `current_file`.
  -- Using the simple `node_by_name` index is insufficient as it's global.
  -- We need a file-specific index or DB query.
  local potential_local_targets = {}
  if self.use_in_memory then
    -- Iterate all nodes (inefficient) - better to have file-specific index
    for id, node in pairs(self.nodes) do
      if
        node.file == current_file
        and node.name == called_name
        and (node.type == "function" or node.type == "method")
      then
        table.insert(potential_local_targets, id)
      end
    end
  else
    -- Query DB for nodes in the same file with the same name
    local stmt = self.db:prepare([[
            SELECT id FROM nodes
            WHERE file = ? AND name = ? AND type IN ('function', 'method')
        ]])
    if stmt then
      pcall(stmt.bind_values, stmt, { current_file, called_name })
      while stmt:step() == sqlite.ROW do
        local vals = stmt:get_values()
        if vals and vals.id then
          table.insert(potential_local_targets, vals.id)
        end
      end
      pcall(stmt.finalize, stmt)
    end
  end

  if #potential_local_targets == 1 then
    log_msg(4, "Resolved call via local definition: " .. called_name .. " -> " .. potential_local_targets[1])
    return potential_local_targets[1]
  elseif #potential_local_targets > 1 then
    -- Ambiguous local definition. TODO: Use scope information from `current_scope_node` TS node passed in.
    log_msg(
      2,
      string.format(
        "Ambiguous local call target for '%s' in %s. TODO: Implement scope check.",
        called_name,
        current_file
      )
    )
    return potential_local_targets[1] -- Return first match for now
  end

  -- 3. Check for method calls (e.g., `object.method`) - Requires type analysis of `object`
  local base_obj, method = called_name:match("^([%w_$]+)%.([%w_$]+)$")
  if base_obj and method then
    -- TODO: Determine type of `base_obj` (from definition, import, etc.) and find `method` there. Very complex.
    log_msg(4, "Method call resolution not fully implemented for: " .. called_name)
  end

  -- 4. Check global scope / built-ins (less common to track explicitly)

  return nil -- Cannot resolve
end

-- Detect function calls using REGEX (Fallback Method - Less Accurate)
-- Keep this only as a last resort if Tree-sitter queries fail or are unavailable.
function EnhancedCodeGraph:_detect_function_calls_regex(func_node_data, lang)
  log_msg(
    3,
    string.format(
      "Analyzing calls in %s:%s using REGEX (less accurate)",
      func_node_data.file,
      func_node_data.name or func_node_data.id
    )
  )

  local function_id = func_node_data.id
  local content = func_node_data.content
  local file_path = func_node_data.file
  -- local name = func_node_data.name -- Removed unused variable

  if not content or content == "" then
    return
  end

  -- local imports = self.imports_map[file_path] or {} -- Removed unused variable
  local call_pattern = "([%w_%.]+)%s*%([^%)]*%)" -- Basic call pattern

  -- Language specific built-ins to ignore
  local ignored_patterns = {
    lua = "^(table|string|math|io|os|debug|coroutine|print|pcall|ipairs|pairs|require|type|tostring|tonumber|assert|error|setmetatable|getmetatable|select|next|_G|_VERSION)",
    javascript = "^(console|Math|Object|Array|String|Number|Boolean|Date|JSON|Promise|require|import|export|document|window|setTimeout|setInterval|clearTimeout|clearInterval|fetch|this)", -- Added fetch, this
    python = "^(print|len|type|int|str|float|list|dict|set|tuple|range|open|super|isinstance|issubclass|hasattr|getattr|setattr|delattr|dir|vars|globals|locals|abs|all|any|bin|bool|bytes|callable|chr|classmethod|compile|complex|enumerate|eval|exec|filter|format|frozenset|hash|help|hex|id|input|iter|map|max|min|next|oct|ord|pow|property|repr|reversed|round|slice|sorted|staticmethod|sum|zip|__import__|self|cls)", -- Added self, cls
    -- Add more for other languages
  }
  local ignore_pat = ignored_patterns[lang]

  for line in content:gmatch("[^\n]+") do
    for called_name in line:gmatch(call_pattern) do
      local is_ignored = false
      if ignore_pat and called_name:match(ignore_pat) then
        is_ignored = true
      end
      -- Ignore constructor calls (often uppercase) - simple heuristic
      if lang == "javascript" or lang == "python" or lang == "java" or lang == "c_sharp" then
        if called_name:match("^[A-Z]") and not called_name:find(".", 1, true) then
          is_ignored = true
        end -- e.g. new Date() but not obj.Method()
      end

      if not is_ignored then
        -- Attempt to resolve (using the simple resolver)
        local target_id = self:_resolve_call_target(called_name, file_path, nil) -- Pass nil scope for regex

        if target_id then
          log_msg(4, string.format("Linking call (regex): %s -> %s", function_id, target_id))
          self:add_edge(function_id, target_id, "calls", { target_name = called_name })
        else
          log_msg(4, string.format("Could not resolve call target (regex) for '%s' in %s", called_name, file_path))
        end
      end
    end
  end
end

-- Index entire codebase starting from a root directory using vim.fs.dir
-- IMPORTANT: To trigger this function, call :AIIndexCodebase or your custom command
function EnhancedCodeGraph:index_project(root_dir)
  print("DEBUG: index_project called with root_dir: " .. tostring(root_dir))
  log_msg(3, "Starting codebase indexing from: " .. root_dir)
  local start_time = uv.hrtime()
  local file_count = 0
  local processed_count = 0
  local error_count = 0

  -- Clear previous state before indexing
  self:clear() -- Add a clear method if re-indexing

  -- Begin transaction if using DB
  if not self.use_in_memory then
    -- Set transaction flag for tracking
    self.transaction_started = false
    
    -- First try with method-style calling (for kkharji/sqlite.lua)
    if type(self.db.eval) == 'function' then
      local begin_ok, begin_err = pcall(function() 
        self.db:eval("BEGIN TRANSACTION;")
        return true
      end)
      if begin_ok then
        log_msg(3, "Started transaction using eval method")
        self.transaction_started = true
      else
        log_msg(2, "Failed to begin transaction with eval: " .. tostring(begin_err))
      end
    elseif type(self.db.exec) == 'function' then
      -- Try with exec function-style (older SQLite implementations)
      local begin_ok, begin_err
      -- Try both calling styles
      begin_ok, begin_err = pcall(function() 
        self.db:exec("BEGIN TRANSACTION;")
        return true 
      end)
      if not begin_ok then
        begin_ok, begin_err = pcall(self.db.exec, self.db, "BEGIN TRANSACTION;")
      end
      if begin_ok then
        log_msg(3, "Started transaction using exec method")
        self.transaction_started = true
      else
        log_msg(1, "Failed to begin indexing transaction: " .. tostring(begin_err))
      end
    else
      log_msg(2, "No suitable transaction method found. Proceeding without transaction.")
    end
  end

  -- Use vim.fs.dir for asynchronous traversal (can be complex to manage state)
  -- For simplicity here, we'll use a synchronous walk.
  -- Replace with async implementation for better performance on large projects.
  log_msg(3, "Scanning project directory (synchronous)...")
  local function walkdir(path)
    -- Use pcall to handle potential errors reading directories (e.g., permissions)
    local iter_ok, iter = pcall(fs.dir, path)
    if not iter_ok or not iter then
      log_msg(2, "Could not read directory: " .. path .. " Error: " .. tostring(iter))
      return
    end
    
    -- Note: If there are many Tree-sitter parsers missing, this directory walk might find files
    -- but fail to parse them. If that's happening, check 'Indexing complete' stats in logs.

    local files = {}
    local dirs = {}
    while true do
      local name, type = iter() -- Removed pcall here, iterator should handle its state
      if not name then
        break
      end -- End of directory

      local full_path = path .. "/" .. name
      full_path = fn.simplify(full_path) -- Normalize path separators

      local ignore = false
      log_msg(4, string.format("Found %s: %s", type, full_path))
      for _, pattern in ipairs(config.ignored_paths) do
        if full_path:find(pattern) then
          log_msg(4, string.format("Ignoring %s due to pattern '%s'", full_path, pattern))
          ignore = true
          break
        end
      end
      if ignore then
        goto continue
      end -- Skip ignored paths

      if type == "file" then
        -- Check extension (optional filter)
        local ext = full_path:match("%.([^%.\\/]+)$")
        local include = false
        if ext and vim.tbl_contains(config.indexed_extensions, ext:lower()) then
          include = true
          log_msg(4, string.format("Including file by extension: %s (.%s)", full_path, ext:lower()))
        elseif not ext then
          log_msg(4, string.format("File has no extension: %s (not included)", full_path))
          -- include = true
        else
          log_msg(4, string.format("Skipping file due to extension: %s (.%s not indexed)", full_path, ext:lower()))
        end
        if include then
          table.insert(files, full_path)
        end
      elseif type == "directory" then
        log_msg(4, string.format("Descending into directory: %s", full_path))
        table.insert(dirs, full_path)
      end
      ::continue::
    end

        -- Process files in current directory
    print("DEBUG: About to process " .. #files .. " files in directory: " .. path)
    for _, file_path in ipairs(files) do
      file_count = file_count + 1
      log_msg(4, string.format("Parsing file: %s", file_path))
      -- Use pcall around parse_file to catch errors per file
      local parse_ok, parse_result = pcall(self.parse_file, self, file_path)
      if parse_ok and parse_result then
        log_msg(4, string.format("Successfully parsed file: %s", file_path))
        processed_count = processed_count + 1
      elseif not parse_ok then
        log_msg(1, string.format("Error parsing file %s: %s", file_path, tostring(parse_result)))
        error_count = error_count + 1
      else -- parse_ok is true, but parse_result is false (e.g., unreadable file)
        log_msg(4, string.format("File not processed (parse_result is false): %s", file_path))
        error_count = error_count + 1
      end

      if processed_count > 0 and processed_count % 100 == 0 then
        log_msg(3, string.format("Processed %d files...", processed_count))
        -- Commit periodically to avoid huge transactions?
        -- if not self.use_in_memory then
        --    local commit_ok, commit_err = pcall(self.db.exec, self.db, "COMMIT; BEGIN;")
        --    if not commit_ok then log_msg(1,"Periodic commit failed: "..tostring(commit_err)) end
        -- end
      end
    end

    -- Recurse into subdirectories
    for _, dir_path in ipairs(dirs) do
      walkdir(dir_path)
    end
  end

  -- Start the walk
  local walk_ok, walk_err = pcall(walkdir, root_dir)
  if not walk_ok then
    log_msg(1, "Directory walk failed: " .. tostring(walk_err))
  end

  -- For kkharji/sqlite.lua, we need not worry about final commit as it's handled automatically
  -- Only attempt commit if we explicitly started a transaction
  if not self.use_in_memory and self.transaction_started then
    log_msg(3, "Attempting to commit final transaction (if needed)")
    -- Try different SQLite adapters' commit methods with error handling
    local commit_attempted = false

    -- First try with eval for kkharji/sqlite.lua
    if type(self.db.eval) == 'function' then
      local commit_ok, commit_err = pcall(function()
        -- Use eval which is recommended for kkharji/sqlite.lua
        return self.db:eval('COMMIT;')
      end)
      commit_attempted = true
      if not commit_ok then
        log_msg(3, "Final commit with eval returned: " .. tostring(commit_err) .. " (might be normal if no transaction active)")
      else
        log_msg(3, "Successfully committed transaction with eval")
      end
    end

    -- Only try these if we couldn't use eval
    if not commit_attempted then
      if type(self.db.exec) == 'function' then
        pcall(function()
          self.db:exec('COMMIT;')
          log_msg(3, "Successfully committed transaction with exec")
        end)
      elseif type(self.db.execute) == 'function' then
        pcall(function()
          self.db:execute('COMMIT;')
          log_msg(3, "Successfully committed transaction with execute")
        end)
      end
    end
    
    -- Clear transaction flag
    self.transaction_started = false
  end
  log_msg(3, "Directory scan complete.")

  -- Perform semantic analysis after all files are parsed
  self:analyze_semantic_relationships()

  local end_time = uv.hrtime()
  local duration_ms = (end_time - start_time) / 1000000
  log_msg(
    3,
    string.format(
      "Indexing complete. Found %d files, processed %d, errors %d.",
      file_count,
      processed_count,
      error_count
    )
  )
  log_msg(3, string.format("Total Nodes: %d, Edges: %d", self.stats.nodes, self.stats.edges))
  log_msg(3, string.format("Indexing took %.2f ms", duration_ms))
end

-- Clear existing graph data (useful before re-indexing)
function EnhancedCodeGraph:clear()
  log_msg(3, "Clearing existing graph data...")
  self.nodes = {}
  self.edges = {}
  self.node_lookup_cache = {}
  self.stats = { nodes = 0, edges = 0, files = 0, functions = 0, classes = 0, imports = 0, exports = 0 }
  self.files_indexed = {}
  self.pending_analysis_nodes = {}
  self.imports_map = {}
  self.exports_map = {}

  if not self.use_in_memory and self.db then
    log_msg(3, "Clearing SQLite tables...")
    local begin_ok, begin_err = pcall(self.db.exec, self.db, "BEGIN;") -- Use transaction for delete
    if begin_ok then
      pcall(self.db.exec, self.db, "DELETE FROM edges;") -- Delete edges first due to potential FKs
      pcall(self.db.exec, self.db, "DELETE FROM nodes;")
      pcall(self.db.exec, self.db, "COMMIT;")
    else
      log_msg(1, "Failed to begin clear transaction: " .. tostring(begin_err))
      -- Try deleting without transaction as fallback
      pcall(self.db.exec, self.db, "DELETE FROM edges;")
      pcall(self.db.exec, self.db, "DELETE FROM nodes;")
    end
    -- Optionally VACUUM if needed, but can be slow
    -- pcall(self.db.exec, self.db, "VACUUM;")
  end
  log_msg(3, "Graph cleared.")
end

-- Clean up resources (close DB connection)
function EnhancedCodeGraph:close()
  log_msg(3, "Closing CodeGraph instance.")
  if not self.use_in_memory and self.db then
    log_msg(4, "Closing SQLite database connection.")
    local ok, err = pcall(self.db.close, self.db)
    if not ok then
      log_msg(1, "Error closing SQLite DB: " .. tostring(err))
    end
    self.db = nil
  end
  -- Clear tables to release memory if instance might be reused (unlikely with singleton pattern below)
  self.nodes = nil
  self.edges = nil
  self.node_lookup_cache = nil
  self.files_indexed = nil
  self.imports_map = nil
  self.exports_map = nil
  self.tree_sitter_queries = nil
end

-- =============================================================================
-- Module Interface (Singleton Pattern)
-- =============================================================================
local M = {}
local graph_instance = nil

-- Get project root (git or cwd) - moved here for module access
function M.get_project_root()
  -- Use vim.fs.find instead of external git command for potentially better cross-platform compatibility
  local git_dir_path = vim.fs.find(".git", { upward = true, type = "directory", stop = vim.env.HOME })
  if git_dir_path and #git_dir_path > 0 then
    -- git_dir_path[1] is the path to the .git directory, we want its parent
    local root = fn.fnamemodify(git_dir_path[1], ":h")
    log_msg(4, "Project root (git): " .. root)
    return root
  end
  local cwd = fn.getcwd()
  log_msg(4, "Project root (cwd): " .. cwd)
  return cwd
end

--- Initialize and index the codebase.
-- Creates or replaces the singleton graph instance.
-- @param force_reindex boolean If true, clears existing data and re-indexes.
-- @param use_persistent_db boolean If true, attempts to use a persistent SQLite DB file.
-- @return number|nil Number of nodes indexed, or nil on error.
-- @return string Project root directory.
function M.index_codebase(force_reindex, use_persistent_db)
  local root = M.get_project_root()

  if graph_instance and not force_reindex then
    log_msg(3, "Codebase already indexed. Use force_reindex=true to re-index.")
    return graph_instance.stats.nodes, root
  end

  -- Close existing instance if forcing reindex
  if graph_instance then
    log_msg(3, "Closing existing graph instance for re-indexing.")
    graph_instance:close()
    graph_instance = nil -- Allow garbage collection
  end

  log_msg(3, "Creating new graph instance...")
  -- Use pcall to catch errors during instance creation (e.g., DB issues)
  local create_ok, instance_or_err = pcall(EnhancedCodeGraph.new, EnhancedCodeGraph, use_persistent_db or false)

  if not create_ok then
    log_msg(1, "Failed to create EnhancedCodeGraph instance: " .. tostring(instance_or_err))
    graph_instance = nil
    return nil, root
  end
  graph_instance = instance_or_err

  -- Perform indexing within a protected call
  local index_success, index_err = pcall(graph_instance.index_project, graph_instance, root)

  if not index_success then
    log_msg(1, "Codebase indexing failed: " .. tostring(index_err))
    -- Clean up potentially partially created instance
    graph_instance:close()
    graph_instance = nil
    return nil, root
  end

  log_msg(3, "Codebase indexing finished.")
  return graph_instance.stats.nodes, root
end

--- Get context from the codebase for a query.
-- Will automatically index if not already done.
-- @param query string The query string.
-- @return string The generated context, or an error message.
function M.get_context(query)
  -- Check if codebase is indexed, index if necessary
  if not M.is_indexed() then
    local root = M.get_project_root()
    log_msg(2, "Indexing codebase at root: " .. root)
    local node_count, err = pcall(function() return M.index_codebase(root) end)
    
    if not node_count then
      log_msg(1, "Error during indexing: " .. tostring(err))
      return "Error indexing codebase: " .. tostring(err)
    end
    
    if type(err) == "number" and err == 0 then
      return "No code indexed from " .. root
    end
    
    if not graph_instance then -- Check again after indexing attempt
      return "Error: Codebase instance unavailable after indexing attempt."
    end
  end

    -- Wrap context generation in pcall to catch errors
  local success, result = pcall(graph_instance.generate_context, graph_instance, query)

  if not success then
    log_msg(1, "Error generating context: " .. tostring(result))
    return "Error generating codebase context: " .. tostring(result)
  end

  return result
end

--- Check if the codebase graph instance exists.
-- @return boolean True if indexed, false otherwise.
function M.is_indexed()
  return graph_instance ~= nil
end

--- Get statistics about the indexed codebase.
-- @return table Statistics table or default values if not indexed.
function M.get_stats()
  if not graph_instance then
    return { nodes = 0, edges = 0, files = 0, functions = 0, classes = 0, imports = 0, exports = 0 }
  end
  -- Return a copy to prevent external modification
  return vim.deepcopy(graph_instance.stats)
end

--- Explicitly close the graph instance and release resources.
function M.close_graph()
  if graph_instance then
    graph_instance:close()
    graph_instance = nil
    log_msg(3, "Codebase graph instance closed.")
  else
    log_msg(3, "No active codebase graph instance to close.")
  end
end

-- Clean up on exit? Neovim might handle this, but explicit cleanup is safer.
api.nvim_create_autocmd("VimLeavePre", {
  pattern = "*",
  callback = function()
    M.close_graph()
  end,
})

  -- This closes the find_relevant_nodes function from line 1802
  return results
end

return M
