-- /home/bryan/.config/nvim/lua/ai_assistant/enhanced_code_graph.lua
-- Enhanced Code Graph module with improved AST parsing, cross-language support,
-- semantic relationship detection, and SQLite storage

local api = vim.api
local ts = vim.treesitter
local uv = vim.loop
local has_sqlite, sqlite = pcall(require, "sqlite")

-- Detect language from file content
local function detect_language_from_content(content)
  -- Very basic detection based on common patterns
  if content:match("^#!.*python") then
    return "python"
  elseif content:match("^#!.*node") then
    return "javascript"
  elseif content:match("import java") then
    return "java"
  elseif content:match("import kotlin") then
    return "kotlin"
  elseif content:match("package main") then
    return "go"
  elseif content:match("function.*%(.*%).*{") or content:match("=>") then
    return "javascript"
  elseif content:match("local") or content:match("function.*%(.*%)") then
    return "lua"
  elseif content:match("def.*%:") or content:match("class.*%:") then
    return "python"
  else
    return nil
  end
end

-- Language-specific parsers
local language_parsers = {
  -- Each language will have customized parsing logic
}

-- Base enhanced code graph implementation
local EnhancedCodeGraph = {}

-- Create a new in-memory instance
function EnhancedCodeGraph:new_in_memory()
  local instance = {
    db = nil,
    nodes = {},
    edges = {},
    node_by_name = {},
    files_indexed = {},
    stats = {
      nodes = 0,
      edges = 0,
      files = 0,
      functions = 0,
      classes = 0,
      imports = 0,
      exports = 0,
    },
    pending_analysis = {},
    tree_sitter_queries = {},
    use_in_memory = true,
    imports_map = {}, -- Map of file to imported modules {file_path = {alias = {module, name}}}
    exports_map = {}, -- Map of file to exported entities {file_path = {name = {node_id}}}
  }
  setmetatable(instance, { __index = self })
  instance:init_tree_sitter_queries()
  return instance
end

-- Create a new EnhancedCodeGraph instance
function EnhancedCodeGraph:new()
  -- Check if sqlite is available
  if not has_sqlite then
    print("SQLite is not available, falling back to in-memory storage")
    return self:new_in_memory()
  end

  -- Initialize SQLite database
  local db_path = vim.fn.stdpath("data") .. "/codebase_graph.db"

  -- Use in-memory mode as a safer default
  local db = sqlite.new(db_path, {
    in_memory = true,
  })

  -- Create schema as separate statements to avoid memory issues
  local function safe_execute(db, stmt)
    local success, err = pcall(function()
      db:execute(stmt)
    end)
    if not success then
      print("SQLite error: " .. tostring(err))
      return false
    end
    return true
  end

  -- Create nodes table
  -- Create nodes table separately to avoid memory issues
  if
    not safe_execute(
      db,
      [[
    CREATE TABLE IF NOT EXISTS nodes (
      id TEXT PRIMARY KEY,
      type TEXT NOT NULL,
      name TEXT,
      file TEXT,
      start_line INTEGER,
      end_line INTEGER,
      content TEXT
    )
  ]]
    )
  then
    print("Falling back to in-memory storage due to SQLite issues")
    return self:new_in_memory()
  end

  -- Create edges table separately
  if
    not safe_execute(
      db,
      [[
    CREATE TABLE IF NOT EXISTS edges (
      source_id TEXT NOT NULL,
      target_id TEXT NOT NULL,
      relationship TEXT NOT NULL,
      metadata TEXT,
      PRIMARY KEY(source_id, target_id, relationship)
    )
  ]]
    )
  then
    print("Falling back to in-memory storage due to SQLite issues")
    return self:new_in_memory()
  end

  -- Create indexes in separate statements
  safe_execute(db, "CREATE INDEX IF NOT EXISTS idx_nodes_name ON nodes(name)")
  safe_execute(db, "CREATE INDEX IF NOT EXISTS idx_nodes_file ON nodes(file)")
  safe_execute(db, "CREATE INDEX IF NOT EXISTS idx_nodes_type ON nodes(type)")
  safe_execute(db, "CREATE INDEX IF NOT EXISTS idx_edges_source ON edges(source_id)")
  safe_execute(db, "CREATE INDEX IF NOT EXISTS idx_edges_target ON edges(target_id)")
  safe_execute(db, "CREATE INDEX IF NOT EXISTS idx_edges_rel ON edges(relationship)")

  local instance = {
    db = db,
    stats = {
      nodes = 0,
      edges = 0,
      files = 0,
      functions = 0,
      classes = 0,
      imports = 0,
      exports = 0,
    },
    files_indexed = {},
    pending_analysis = {},
    tree_sitter_queries = {},
    use_in_memory = false,
    imports_map = {}, -- Map of file to imported modules {file_path = {alias = {module, name}}}
    exports_map = {}, -- Map of file to exported entities {file_path = {name = {node_id}}}
  }

  setmetatable(instance, { __index = self })

  -- Initialize tree-sitter queries
  instance:init_tree_sitter_queries()

  return instance
end

-- Initialize tree-sitter queries for various languages
function EnhancedCodeGraph:init_tree_sitter_queries()
  -- Lua functions with error handling
  local success, lua_func_query = pcall(function()
    return ts.query.parse(
      "lua",
      [[
        (function_declaration 
          name: [
            (identifier) @function_name
            (dot_index_expression field: (identifier) @method_name)
          ]
          parameters: (parameters) @params
          body: (block) @body) @function_def
        
        (function_definition
          parameters: (parameters) @params
          body: (block) @body) @anon_function
          
        (assignment_statement
          left: (variable_list (identifier) @function_name)
          right: (expression_list (function_definition) @func_def))
          
        (local_declaration
          left: (variable_list (identifier) @function_name)
          right: (expression_list (function_definition) @func_def))
      ]]
    )
  end)

  if success then
    self.tree_sitter_queries.lua_functions = lua_func_query
  else
    print("Using fallback Lua function query")
    -- Extremely simple fallback query without any complex patterns
    self.tree_sitter_queries.lua_functions = ts.query.parse(
      "lua",
      [[
        (function_declaration) @function_def
        (function_definition) @anon_function
      ]]
    )
  end

  -- Skip complex requires query in favor of a simple one that is guaranteed to work
  -- Query to extract require calls in Lua
  self.tree_sitter_queries.lua_requires = ts.query.parse(
    "lua",
    [[
      (function_call
        name: (identifier) @func_name
        arguments: (arguments
          (string) @module_name
        )
      ) @require_call
    ]]
  )

  -- JavaScript/TypeScript functions, imports, and classes
  -- Using a try-catch approach to handle potential query syntax differences
  -- Try to use a very minimal query for JavaScript that should work on all versions
  -- Skip complex parsing in favor of minimal functionality that works
  self.tree_sitter_queries.js_functions = ts.query.parse(
    "javascript",
    [[
      (function_declaration) @function_def
    ]]
  )

  -- Add other languages as needed
end

-- Add a node to the graph (either database or in-memory)
function EnhancedCodeGraph:add_node(node_type, name, file, start_line, end_line, content)
  local id = node_type .. ":" .. file .. ":" .. (name or "") .. ":" .. (start_line or 0)

  if self.use_in_memory then
    -- In-memory storage
    if self.nodes[id] then
      -- Update existing node
      self.nodes[id].name = name
      self.nodes[id].file = file
      self.nodes[id].start_line = start_line
      self.nodes[id].end_line = end_line
      self.nodes[id].content = content
    else
      -- Insert new node
      self.nodes[id] = {
        id = id,
        type = node_type,
        name = name,
        file = file,
        start_line = start_line,
        end_line = end_line,
        content = content,
      }
      self.stats.nodes = self.stats.nodes + 1

      -- Add to name index
      if name then
        self.node_by_name[name] = self.node_by_name[name] or {}
        table.insert(self.node_by_name[name], id)
      end

      -- Update type-specific counts
      if node_type == "function" or node_type == "method" then
        self.stats.functions = self.stats.functions + 1
      elseif node_type == "class" then
        self.stats.classes = self.stats.classes + 1
      end
    end
  else
    -- SQLite storage
    local existing = self.db:select("SELECT id FROM nodes WHERE id = ?", id)
    if existing and #existing > 0 then
      -- Update existing node
      self.db:update("nodes", {
        name = name,
        file = file,
        start_line = start_line,
        end_line = end_line,
        content = content,
      }, { id = id })
    else
      -- Insert new node
      self.db:insert("nodes", {
        id = id,
        type = node_type,
        name = name,
        file = file,
        start_line = start_line,
        end_line = end_line,
        content = content,
      })
      self.stats.nodes = self.stats.nodes + 1

      -- Update type-specific counts
      if node_type == "function" or node_type == "method" then
        self.stats.functions = self.stats.functions + 1
      elseif node_type == "class" then
        self.stats.classes = self.stats.classes + 1
      end
    end
  end

  return id
end

-- Add an edge between nodes
function EnhancedCodeGraph:add_edge(source_id, target_id, relationship, metadata)
  if self.use_in_memory then
    -- In-memory storage
    local edge_id = source_id .. "->" .. target_id .. ":" .. relationship
    if not self.edges[edge_id] then
      self.edges[edge_id] = {
        source_id = source_id,
        target_id = target_id,
        relationship = relationship,
        metadata = metadata,
      }
      self.stats.edges = self.stats.edges + 1
    end
  else
    -- SQLite storage
    local existing = self.db:select(
      "SELECT source_id FROM edges WHERE source_id = ? AND target_id = ? AND relationship = ?",
      { source_id, target_id, relationship }
    )

    if not existing or #existing == 0 then
      -- Insert new edge
      self.db:insert("edges", {
        source_id = source_id,
        target_id = target_id,
        relationship = relationship,
        metadata = metadata and vim.json.encode(metadata) or nil,
      })
      self.stats.edges = self.stats.edges + 1
    end
  end
end

-- Parse a file and extract code entities
function EnhancedCodeGraph:parse_file(file_path)
  if self.files_indexed[file_path] then
    return -- Skip already indexed files
  end

  -- Read file content
  local content = vim.fn.readfile(file_path)
  if not content or #content == 0 then
    print("Warning: Empty or unreadable file: " .. file_path)
    return
  end
  content = table.concat(content, "\n")

  -- Determine language
  local ext = file_path:match("%.([^%.]+)$") or ""
  local lang_map = {
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
  }

  local lang = lang_map[ext] or ext
  if not lang or lang == "" then
    -- Try to detect language from content
    lang = detect_language_from_content(content)
    if not lang then
      -- Add as a generic file node
      local file_id = self:add_node("file", file_path:match("([^/]+)$"), file_path, 0, #vim.split(content, "\n"), nil)
      self.files_indexed[file_path] = true
      self.stats.files = self.stats.files + 1
      return
    end
  end

  -- Create a file node
  local file_id = self:add_node("file", file_path:match("([^/]+)$"), file_path, 0, #vim.split(content, "\n"), nil)
  self.files_indexed[file_path] = true
  self.stats.files = self.stats.files + 1

  -- Parse with tree-sitter
  local success, parser = pcall(function()
    return ts.get_string_parser(content, lang)
  end)
  if not success or not parser then
    print("Could not create parser for: " .. file_path .. " with language: " .. lang)
    return
  end

  local tree_result = parser:parse()
  if #tree_result == 0 then
    print("Parsing resulted in empty tree for: " .. file_path)
    return
  end

  local tree = tree_result[1]
  local root = tree:root()

  -- Process with language-specific parsers
  if lang == "lua" then
    self:process_lua_file(file_path, content, root, file_id)
  elseif lang == "javascript" or lang == "typescript" then
    self:process_js_file(file_path, content, root, file_id)
  else
    -- Generic processing
    self:process_generic_file(file_path, content, root, file_id, lang)
  end

  -- Queue for semantic analysis
  self.pending_analysis[file_path] = {
    lang = lang,
  }
end

-- Process a Lua file with tree-sitter
-- Process generic file with language-specific approach
function EnhancedCodeGraph:process_generic_file(file_path, content, root, file_id, lang)
  -- Initialize import/export maps for this file if needed
  self.imports_map[file_path] = self.imports_map[file_path] or {}
  self.exports_map[file_path] = self.exports_map[file_path] or {}

  -- Basic pattern matching for common languages
  if lang == "python" then
    -- Process Python imports and exports
    for line in content:gmatch("[^\n]+") do
      -- import module
      local module = line:match("%f[%w]import%s+([%w_.]+)%s*$")
      if module then
        local import_id = self:add_node("import", module, file_path, 0, 0, line)
        self:add_edge(file_id, import_id, "contains")
        self.imports_map[file_path][module] = { module = module, type = "module" }
        self.stats.imports = self.stats.imports + 1
      end

      -- from module import name, name2
      local from_module, imports_list = line:match("%f[%w]from%s+([%w_.]+)%s+import%s+([^#]+)")
      if from_module and imports_list then
        for name in imports_list:gmatch("([%w_]+)[%s,]*") do
          local import_id = self:add_node("import", name, file_path, 0, 0, line)
          self:add_edge(file_id, import_id, "contains")
          self.imports_map[file_path][name] = { module = from_module, name = name, type = "named" }
          self.stats.imports = self.stats.imports + 1
        end
      end

      -- function and class definitions (potential exports)
      local def_type, name = line:match("%s*(%w+)%s+([%w_]+)%s*%(")
      if def_type == "def" or def_type == "class" then
        local entity_type = def_type == "def" and "function" or "class"

        -- Find this entity in nodes
        for id, node in pairs(self.nodes) do
          if node.name == name and node.file == file_path and node.type == entity_type then
            -- Add to exports (all top-level entities are potentially exported in Python)
            self.exports_map[file_path][name] = id
            break
          end
        end
      end
    end
  elseif lang == "golang" or lang == "go" then
    -- Process Go imports and exports
    local is_in_import_block = false

    for line in content:gmatch("[^\n]+") do
      -- Check for import block start/end
      if line:match("%f[%w]import%s+%(") then
        is_in_import_block = true
      elseif is_in_import_block and line:match("%)") then
        is_in_import_block = false
      elseif is_in_import_block then
        -- Process each import in block
        local import_path = line:match('"([^"]+)"')
        if import_path then
          local import_name = import_path:match("([^/]+)$") or import_path
          local import_id = self:add_node("import", import_name, file_path, 0, 0, line)
          self:add_edge(file_id, import_id, "contains")
          self.imports_map[file_path][import_name] = { module = import_path, type = "module" }
          self.stats.imports = self.stats.imports + 1
        end
      else
        -- Single line import
        local import_path = line:match('import%s+"([^"]+)"')
        if import_path then
          local import_name = import_path:match("([^/]+)$") or import_path
          local import_id = self:add_node("import", import_name, file_path, 0, 0, line)
          self:add_edge(file_id, import_id, "contains")
          self.imports_map[file_path][import_name] = { module = import_path, type = "module" }
          self.stats.imports = self.stats.imports + 1
        end

        -- Function definitions (potential exports - uppercase first letter = exported in Go)
        local func_name = line:match("%f[%w]func%s+([A-Z][%w_]*)%s*%(")
        if func_name then
          -- Find this function in nodes
          for id, node in pairs(self.nodes) do
            if node.name == func_name and node.file == file_path and node.type == "function" then
              self.exports_map[file_path][func_name] = id
              local export_id = self:add_node("export", func_name, file_path, 0, 0, line)
              self:add_edge(file_id, export_id, "contains")
              self:add_edge(export_id, id, "exports")
              self.stats.exports = self.stats.exports + 1
              break
            end
          end
        end
      end
    end
  elseif lang == "java" or lang == "kotlin" then
    -- Process Java and Kotlin imports
    for line in content:gmatch("[^\n]+") do
      local module = line:match("^%s*import%s+([%w_%.%*]+)%s*;?")
      if module then
        local import_name = module:match("([^%.%*]+)$") or module
        local import_id = self:add_node("import", import_name, file_path, 0, 0, line)
        self:add_edge(file_id, import_id, "contains")
        self.imports_map[file_path][import_name] = { module = module, type = "module" }
        self.stats.imports = self.stats.imports + 1
      end
    end
  elseif lang == "ruby" then
    -- Process Ruby require and require_relative
    for line in content:gmatch("[^\n]+") do
      local req_mod = line:match("^%s*require_relative%s+['\"]([^'\"]+)['\"]")
      if req_mod then
        local import_name = req_mod:match("([^/\\]+)$") or req_mod
        local import_id = self:add_node("import", import_name, file_path, 0, 0, line)
        self:add_edge(file_id, import_id, "contains")
        self.imports_map[file_path][import_name] = { module = req_mod, type = "require_relative" }
        self.stats.imports = self.stats.imports + 1
      else
        local req_mod2 = line:match("^%s*require%s+['\"]([^'\"]+)['\"]")
        if req_mod2 then
          local import_name = req_mod2:match("([^/\\]+)$") or req_mod2
          local import_id = self:add_node("import", import_name, file_path, 0, 0, line)
          self:add_edge(file_id, import_id, "contains")
          self.imports_map[file_path][import_name] = { module = req_mod2, type = "require" }
          self.stats.imports = self.stats.imports + 1
        end
      end
    end
  elseif lang == "php" then
    -- Process PHP require/include statements
    for line in content:gmatch("[^\n]+") do
      local inc_mod = line:match("^%s*(?:require_once|require|include_once|include)%s*%(?['\"]?([^'\")]+)['\"]?%)?;")
      if inc_mod then
        local import_name = inc_mod:match("([^/\\]+)$") or inc_mod
        local import_id = self:add_node("import", import_name, file_path, 0, 0, line)
        self:add_edge(file_id, import_id, "contains")
        self.imports_map[file_path][import_name] = { module = inc_mod, type = "include" }
        self.stats.imports = self.stats.imports + 1
      end
    end
  elseif lang == "c" or lang == "cpp" or lang == "c_sharp" then
    -- Process C/C++ includes and C# using directives
    for line in content:gmatch("[^\n]+") do
      local inc = line:match('^%s*#include%s*[<"]([^>"]+)[>"]')
      if inc then
        local import_id = self:add_node("import", inc, file_path, 0, 0, line)
        self:add_edge(file_id, import_id, "contains")
        self.imports_map[file_path][inc] = { module = inc, type = "include" }
        self.stats.imports = self.stats.imports + 1
      end
      local using_ns = line:match("^%s*using%s+([%w_%.]+)%s*;")
      if using_ns then
        local import_name = using_ns:match("([^%.]+)$") or using_ns
        local import_id = self:add_node("import", import_name, file_path, 0, 0, line)
        self:add_edge(file_id, import_id, "contains")
        self.imports_map[file_path][import_name] = { module = using_ns, type = "using" }
        self.stats.imports = self.stats.imports + 1
      end
    end
  end
  -- For other languages, try basic function/class detection
  if
    lang ~= "python"
    and lang ~= "golang"
    and lang ~= "go"
    and lang ~= "javascript"
    and lang ~= "typescript"
    and lang ~= "lua"
  then
    self:detect_generic_entities(file_path, content, file_id, lang)
  end
end

-- Helper function to detect common code structures across languages
function EnhancedCodeGraph:detect_generic_entities(file_path, content, file_id, lang)
  -- Simple patterns for common programming constructs
  local patterns = {
    -- function/method pattern (works in many C-like languages)
    { pattern = "[%w_]+%s+([%w_]+)%s*%(.-%)%s*{?", type = "function" },
    -- class/struct pattern
    { pattern = "class%s+([%w_]+)", type = "class" },
    { pattern = "struct%s+([%w_]+)", type = "class" },
    -- interface pattern
    { pattern = "interface%s+([%w_]+)", type = "interface" },
  }

  -- Extract line numbers for context
  local lines = {}
  local line_number = 1
  for line in content:gmatch("[^\n]+") do
    lines[line_number] = line
    line_number = line_number + 1
  end

  for _, pattern_info in ipairs(patterns) do
    -- Find all occurrences in the content
    for name in content:gmatch(pattern_info.pattern) do
      if name and #name > 0 then
        -- Add as a node of the appropriate type
        local entity_id = self:add_node(pattern_info.type, name, file_path, 0, 0, "")
        self:add_edge(file_id, entity_id, "contains")

        -- Consider everything potentially exported
        self.exports_map[file_path][name] = entity_id
      end
    end
  end
end

function EnhancedCodeGraph:process_lua_file(file_path, content, root, file_id)
  -- Extract functions
  for pattern, captures in self.tree_sitter_queries.lua_functions:iter_matches(root, content) do
    for id, node in pairs(captures) do
      local name = self.tree_sitter_queries.lua_functions.captures[id]

      if name == "function_name" or name == "method_name" then
        local func_name = vim.treesitter.get_node_text(node, content)
        local start_row, start_col, end_row, end_col = node:range()

        -- Find the function definition node
        local func_def_node = nil
        for i, capture_node in pairs(captures) do
          local capture_name = self.tree_sitter_queries.lua_functions.captures[i]
          if capture_name == "function_def" or capture_name == "func_def" then
            func_def_node = capture_node
            break
          end
        end

        if func_def_node then
          local def_start_row, def_start_col, def_end_row, def_end_col = func_def_node:range()
          local func_content = vim.treesitter.get_node_text(func_def_node, content)

          -- Add function node
          local node_type = name == "method_name" and "method" or "function"
          local func_id =
            self:add_node(node_type, func_name, file_path, def_start_row + 1, def_end_row + 1, func_content)

          -- Connect to file
          self:add_edge(file_id, func_id, "contains")

          -- Extract function calls within this function
          self:extract_lua_function_calls(func_def_node, content, func_id)
        end
      end
    end
  end

  -- Extract requires
  for pattern, captures in self.tree_sitter_queries.lua_requires:iter_matches(root, content) do
    local func_name, module_name
    for id, node in pairs(captures) do
      local cap = self.tree_sitter_queries.lua_requires.captures[id]
      if cap == "func_name" then
        func_name = vim.treesitter.get_node_text(node, content)
      elseif cap == "module_name" then
        module_name = vim.treesitter.get_node_text(node, content):gsub("^[\"'](.+)[\"']$", "%1")
      end
    end
    if func_name == "require" and module_name then
      local import_name = module_name:match("([^/\\]+)$") or module_name
      -- Add require dependency
      local require_id = self:add_node("require", import_name, file_path, 0, 0, 'require("' .. module_name .. '")')
      -- Connect to file
      self:add_edge(file_id, require_id, "contains")
      -- Add module dependency
      local module_id = self:add_node("module", module_name, nil, 0, 0, nil)
      self:add_edge(require_id, module_id, "imports")
      self.imports_map[file_path][import_name] = { module = module_name, type = "require" }
      self.stats.imports = self.stats.imports + 1
      local module_file = self:resolve_module_path(file_path, module_name)
      if module_file then
        -- Add direct reverse import tracking
        self.exports_map[module_file] = self.exports_map[module_file] or {}
        self.exports_map[module_file]["_imported_by"] = self.exports_map[module_file]["_imported_by"] or {}
        self.exports_map[module_file]["_imported_by"][file_path] = true
      end
    end
  end
end

-- Extract function calls within Lua code
function EnhancedCodeGraph:extract_lua_function_calls(node, content, parent_id)
  -- Create a query to find function calls
  local query = ts.query.parse(
    "lua",
    [[
      (function_call
        name: [
          (identifier) @func_name
          (dot_index_expression 
            field: (identifier) @method_name)
        ]
        arguments: (arguments) @args) @func_call
    ]]
  )

  for pattern, captures in query:iter_matches(node, content) do
    for id, call_node in pairs(captures) do
      local name = query.captures[id]

      if name == "func_name" or name == "method_name" then
        local func_name = vim.treesitter.get_node_text(call_node, content)
        local call_id = self:add_node("call", func_name, nil, call_node:range() + 1, call_node:range() + 1, nil)

        -- Connect call to parent
        self:add_edge(parent_id, call_id, "calls")
      end
    end
  end
end

-- Process JavaScript/TypeScript files with tree-sitter
function EnhancedCodeGraph:process_js_file(file_path, content, root, file_id)
  -- Initialize import/export maps for this file if needed
  self.imports_map[file_path] = self.imports_map[file_path] or {}
  self.exports_map[file_path] = self.exports_map[file_path] or {}

  -- Use tree-sitter to extract functions and classes
  local success, js_query = pcall(function()
    return ts.query.parse(
      "javascript",
      [[
        (function_declaration
          name: (identifier) @function_name
          body: (statement_block) @function_body) @function_def
          
        (method_definition
          name: (property_identifier) @method_name
          body: (statement_block) @method_body) @method_def
          
        (class_declaration
          name: (identifier) @class_name
          body: (class_body) @class_body) @class_def
      ]]
    )
  end)

  if success then
    for pattern, captures in js_query:iter_matches(root, content) do
      for id, node in pairs(captures) do
        local name = js_query.captures[id]

        if name == "function_name" then
          local func_name = vim.treesitter.get_node_text(node, content)

          -- Find the function definition node
          local func_def_node = nil
          for i, capture_node in pairs(captures) do
            if js_query.captures[i] == "function_def" then
              func_def_node = capture_node
              break
            end
          end

          if func_def_node then
            local start_row, start_col, end_row, end_col = func_def_node:range()
            local func_content = vim.treesitter.get_node_text(func_def_node, content)

            -- Add function node
            local func_id = self:add_node("function", func_name, file_path, start_row + 1, end_row + 1, func_content)

            -- Connect to file
            self:add_edge(file_id, func_id, "contains")

            -- Add to exports (assume top-level functions are exported unless explicitly non-exported)
            self.exports_map[file_path][func_name] = func_id
          end
        elseif name == "method_name" or name == "class_name" then
          -- Similar processing for methods and classes...
          local entity_name = vim.treesitter.get_node_text(node, content)
          local entity_type = name == "method_name" and "method" or "class"
          local entity_def_node = nil

          for i, capture_node in pairs(captures) do
            if js_query.captures[i] == (name == "method_name" and "method_def" or "class_def") then
              entity_def_node = capture_node
              break
            end
          end

          if entity_def_node then
            local start_row, start_col, end_row, end_col = entity_def_node:range()
            local entity_content = vim.treesitter.get_node_text(entity_def_node, content)

            -- Add entity node
            local entity_id =
              self:add_node(entity_type, entity_name, file_path, start_row + 1, end_row + 1, entity_content)

            -- Connect to file
            self:add_edge(file_id, entity_id, "contains")

            -- Add classes to exports
            if entity_type == "class" then
              self.exports_map[file_path][entity_name] = entity_id
            end
          end
        end
      end
    end
  end

  -- Process imports and exports with pattern matching
  self:process_js_imports_exports(file_path, content, file_id)
end

-- Helper function to resolve a module path to an actual file path
function EnhancedCodeGraph:resolve_module_path(current_file, module_path)
  -- Strip quotes if present
  module_path = module_path:gsub("^['\"](.+)['\"]$", "%1")

  -- Handle different import path formats
  if module_path:match("^~/") then
    -- Handle project root relative paths like ~/components/...
    local project_root = vim.fn.getcwd() -- Default to current working directory
    -- Try to get git root if available
    local git_cmd = "git -C " .. vim.fn.getcwd() .. " rev-parse --show-toplevel 2>/dev/null"
    local git_root = vim.fn.system(git_cmd):gsub("\n", "")
    if git_root ~= "" and vim.fn.isdirectory(git_root) == 1 then
      project_root = git_root
    end
    return module_path:gsub("^~/", project_root .. "/")
  elseif module_path:match("^%.%./") or module_path:match("^%./") then
    -- Handle relative paths like ../utils or ./helpers
    local current_dir = vim.fn.fnamemodify(current_file, ":h")
    return vim.fn.simplify(current_dir .. "/" .. module_path)
  elseif not module_path:match("/") then
    -- Handle bare imports like 'react' - these are likely from node_modules
    -- We won't try to resolve these to actual files for now
    return nil
  else
    -- For other paths, try to find the file in the project
    local project_root = vim.fn.getcwd()
    -- Try to get git root if available
    local git_cmd = "git -C " .. vim.fn.getcwd() .. " rev-parse --show-toplevel 2>/dev/null"
    local git_root = vim.fn.system(git_cmd):gsub("\n", "")
    if git_root ~= "" and vim.fn.isdirectory(git_root) == 1 then
      project_root = git_root
    end
    local potential_paths = {
      module_path .. ".js",
      module_path .. ".jsx",
      module_path .. ".ts",
      module_path .. ".tsx",
      module_path .. "/index.js",
      module_path .. "/index.jsx",
      module_path .. "/index.ts",
      module_path .. "/index.tsx",
    }

    for _, path in ipairs(potential_paths) do
      local full_path = project_root .. "/" .. path
      if vim.fn.filereadable(full_path) == 1 then
        return full_path
      end
    end
  end

  return nil
end

function EnhancedCodeGraph:process_js_imports_exports(file_path, content, file_id)
  -- Try to use specialized JS/TS parser if available
  local has_jsts_parser, jsts_parser = pcall(require, "ai_assistant.jsts_parser")
  if has_jsts_parser then
    local imports = jsts_parser.get_imports(file_path, content)
    if imports and #imports > 0 then
      for _, import in ipairs(imports) do
        local import_type = import.type
        local module_path = import.source
        if import.names and #import.names > 0 then
          for _, name_info in ipairs(import.names) do
            local orig_name, alias = name_info, name_info
            if import_type == "named" and type(name_info) == "table" then
              orig_name = name_info.original
              alias = name_info.alias or orig_name
            end
            local import_id = self:add_node("import", alias, file_path, 0, 0, "")
            self:add_edge(file_id, import_id, "contains")
            if import_type == "named" then
              self.imports_map[file_path][alias] = {module = module_path, name = orig_name, type = "named"}
            elseif import_type == "namespace" then
              self.imports_map[file_path][alias] = {module = module_path, type = "namespace"}
            else
              self.imports_map[file_path][alias] = {module = module_path, type = import_type}
            end
            self.stats.imports = self.stats.imports + 1
            local target_file = nil
            if import.resolved_paths then
              for _, resolved_path in ipairs(import.resolved_paths) do
                if vim.fn.filereadable(resolved_path) == 1 then
                  target_file = resolved_path
                  break
                end
              end
            end
            if not target_file then
              target_file = self:resolve_module_path(file_path, module_path)
            end
            if target_file then
              self.exports_map[target_file] = self.exports_map[target_file] or {}
              self.exports_map[target_file]['_imported_by'] = self.exports_map[target_file]['_imported_by'] or {}
              self.exports_map[target_file]['_imported_by'][file_path] = true
            end
          end
        else
          local import_id = self:add_node("import", module_path, file_path, 0, 0, "")
          self:add_edge(file_id, import_id, "contains")
          self.imports_map[file_path][module_path] = {module = module_path, type = import_type}
          self.stats.imports = self.stats.imports + 1
          local target_file = nil
          if import.resolved_paths then
            for _, resolved_path in ipairs(import.resolved_paths) do
              if vim.fn.filereadable(resolved_path) == 1 then
                target_file = resolved_path
                break
              end
            end
          end
          if not target_file then
            target_file = self:resolve_module_path(file_path, module_path:gsub("['\"]",''))
          end
          if target_file then
            self.exports_map[target_file] = self.exports_map[target_file] or {}
            self.exports_map[target_file]['_imported_by'] = self.exports_map[target_file]['_imported_by'] or {}
            self.exports_map[target_file]['_imported_by'][file_path] = true
          end
        end
      end
    end
  else
    self:process_js_imports_exports_with_patterns(file_path, content, file_id)
  end
end

-- Original pattern-matching implementation moved to this function
function EnhancedCodeGraph:process_js_imports_exports_with_patterns(file_path, content, file_id)
  -- Process imports
  for line in content:gmatch("[^\n]+") do
    -- ES6 default import: import Name from 'module'
    local name, module_path = line:match("%f[%w]import%s+([%w_]+)%s+from%s+['\"](.+)['\"]")
    if name and module_path then
      local import_id = self:add_node("import", name, file_path, 0, 0, line)
      self:add_edge(file_id, import_id, "contains")
      self.imports_map[file_path][name] = { module = module_path, type = "default" }
      self.stats.imports = self.stats.imports + 1

      -- Add a reverse relationship to track usage properly
      -- Find the target module file path from the import path
      local target_file = self:resolve_module_path(file_path, module_path)
      if target_file then
        -- Add direct reverse import tracking
        self.exports_map[target_file] = self.exports_map[target_file] or {}
        self.exports_map[target_file]["_imported_by"] = self.exports_map[target_file]["_imported_by"] or {}
        self.exports_map[target_file]["_imported_by"][file_path] = true
      end
    end

    -- ES6 named imports: import { A, B as C } from 'module'
    local imports_list, module_path = line:match("%f[%w]import%s*{%s*([^}]+)%s*}%s*from%s*['\"](.+)['\"]")
    if imports_list and module_path then
      -- Find the target module file path from the import path
      local target_file = self:resolve_module_path(file_path, module_path)

      -- Process each named import, handling aliases (B as C)
      for orig_name, alias in imports_list:gmatch("([%w_]+)%s*(?:as%s+([%w_]+))?%s*,?") do
        local import_name = alias or orig_name
        local import_id = self:add_node("import", import_name, file_path, 0, 0, line)
        self:add_edge(file_id, import_id, "contains")
        self.imports_map[file_path][import_name] = { module = module_path, name = orig_name, type = "named" }
        self.stats.imports = self.stats.imports + 1

        -- Add a reverse relationship to track usage properly
        if target_file then
          -- Add direct reverse import tracking
          self.exports_map[target_file] = self.exports_map[target_file] or {}
          self.exports_map[target_file]["_imported_by"] = self.exports_map[target_file]["_imported_by"] or {}
          self.exports_map[target_file]["_imported_by"][file_path] = true
        end
      end
    end

    -- Side effect import: import 'module'
    local side_module = line:match("%f[%w]import%s+['\"](.+)['\"]%s*;?$")
    if side_module and not line:match("from") then
      local import_id = self:add_node("import", side_module, file_path, 0, 0, line)
      self:add_edge(file_id, import_id, "contains")
      self.imports_map[file_path][side_module] = { module = side_module, type = "side-effect" }
      self.stats.imports = self.stats.imports + 1

      -- Add reverse relationship
      local target_file = self:resolve_module_path(file_path, side_module)
      if target_file then
        self.exports_map[target_file] = self.exports_map[target_file] or {}
        self.exports_map[target_file]["_imported_by"] = self.exports_map[target_file]["_imported_by"] or {}
        self.exports_map[target_file]["_imported_by"][file_path] = true
      end
    end

    -- ES6 namespace import: import * as Name from 'module'
    local ns_name, ns_module = line:match("%f[%w]import%s*%*%s*as%s+([%w_]+)%s+from%s+['\"](.+)['\"]")
    if ns_name and ns_module then
      local import_id = self:add_node("import", ns_name, file_path, 0, 0, line)
      self:add_edge(file_id, import_id, "contains")
      self.imports_map[file_path][ns_name] = { module = ns_module, type = "namespace" }
      self.stats.imports = self.stats.imports + 1

      -- Add a reverse relationship to track usage properly
      local target_file = self:resolve_module_path(file_path, ns_module)
      if target_file then
        -- Add direct reverse import tracking
        self.exports_map[target_file] = self.exports_map[target_file] or {}
        self.exports_map[target_file]["_imported_by"] = self.exports_map[target_file]["_imported_by"] or {}
        self.exports_map[target_file]["_imported_by"][file_path] = true
      end
    end

    -- Dynamic import: import('./module')
    local dynamic_module = line:match("import%s*%((['\"].+['\"])%)")
    if dynamic_module then
      local module_path = dynamic_module:gsub("['\"]", '"')
      local import_id = self:add_node("import", module_path, file_path, 0, 0, line)
      self:add_edge(file_id, import_id, "contains")
      self.imports_map[file_path][module_path] = { module = module_path, type = "dynamic" }
      self.stats.imports = self.stats.imports + 1

      -- Add reverse relationship
      local target_file = self:resolve_module_path(file_path, module_path:gsub("['\"]", ""))
      if target_file then
        self.exports_map[target_file] = self.exports_map[target_file] or {}
        self.exports_map[target_file]["_imported_by"] = self.exports_map[target_file]["_imported_by"] or {}
        self.exports_map[target_file]["_imported_by"][file_path] = true
      end
    end

    -- CommonJS require
    local req_var, req_module = line:match("([%w_%.]+)%s*=%s*require%s*%(%s*['\"]([^'\"]+)['\"]%s*%)")
    if not req_var then
      -- Try to match with const/let/var
      req_var, req_module = line:match("[%w_]+%s+([%w_%.]+)%s*=%s*require%s*%(%s*['\"]([^'\"]+)['\"]%s*%)")
    end

    if req_var and req_module then
      local import_id = self:add_node("import", req_var, file_path, 0, 0, line)
      self:add_edge(file_id, import_id, "contains")
      self.imports_map[file_path][req_var] = { module = req_module, type = "commonjs" }
      self.stats.imports = self.stats.imports + 1

      -- Add reverse relationship
      local target_file = self:resolve_module_path(file_path, req_module)
      if target_file then
        self.exports_map[target_file] = self.exports_map[target_file] or {}
        self.exports_map[target_file]["_imported_by"] = self.exports_map[target_file]["_imported_by"] or {}
        self.exports_map[target_file]["_imported_by"][file_path] = true
      end
    end

    -- ES6 named exports: export { A, B }
    local exports_list = line:match("%f[%w]export%s*{%s*([^}]+)%s*}")
    if exports_list then
      for name in exports_list:gmatch("([%w_]+)[%s,]*") do
        -- Only process if we have this entity in our nodes
        for id, node in pairs(self.nodes) do
          if node.name == name and node.file == file_path then
            -- Add to exports (all top-level entities are potentially exported in Python)
            self.exports_map[file_path][name] = id

            -- Create export edge
            local export_id = self:add_node("export", name, file_path, 0, 0, line)
            self:add_edge(file_id, export_id, "contains")
            self:add_edge(export_id, id, "exports")
            self.stats.exports = self.stats.exports + 1
            break
          end
        end
      end
    end

    -- ES6 default export: export default Name
    local default_export = line:match("%f[%w]export%s+default%s+([%w_]+)")
    if default_export then
      -- Try to find the default export entity
      for id, node in pairs(self.nodes) do
        if node.name == default_export and node.file == file_path then
          -- Add to exports
          self.exports_map[file_path] = self.exports_map[file_path] or {}
          self.exports_map[file_path]["default"] = id

          -- Create export edge
          local export_id = self:add_node("export", "default", file_path, 0, 0, line)
          self:add_edge(file_id, export_id, "contains")
          self:add_edge(export_id, id, "exports")
          self.stats.exports = self.stats.exports + 1
          break
        end
      end
    end

    -- Export declarations: export const x = ...
    local export_type, export_name = line:match("%f[%w]export%s+(%a+)%s+([%w_]+)")
    if
      export_type
      and export_name
      and export_type ~= "default"
      and export_type ~= "function"
      and export_type ~= "class"
    then
      -- Direct variable export
      self.exports_map[file_path] = self.exports_map[file_path] or {}
      local export_id = self:add_node("export", export_name, file_path, 0, 0, line)
      self:add_edge(file_id, export_id, "contains")
      self.stats.exports = self.stats.exports + 1
    end

    -- Export function/class: export function x() or export class X
    local export_decl, export_decl_name = line:match("%f[%w]export%s+(%a+)%s+([%w_]+)")
    if export_decl and export_decl_name and (export_decl == "function" or export_decl == "class") then
      -- Find declaration in nodes
      for id, node in pairs(self.nodes) do
        if
          node.name == export_decl_name
          and node.file == file_path
          and (
            (export_decl == "function" and (node.type == "function" or node.type == "method"))
            or (export_decl == "class" and node.type == "class")
          )
        then
          -- Add to exports
          self.exports_map[file_path] = self.exports_map[file_path] or {}
          self.exports_map[file_path][export_decl_name] = id

          -- Create export edge
          local export_id = self:add_node("export", export_decl_name, file_path, 0, 0, line)
          self:add_edge(file_id, export_id, "contains")
          self:add_edge(export_id, id, "exports")
          self.stats.exports = self.stats.exports + 1
          break
        end
      end
    end
  end
end

-- Find component usages throughout the codebase
function EnhancedCodeGraph:find_component_usages(component_name)
  local usages = {}

  -- Look through all files in exports_map for components matching the name
  for file_path, exports in pairs(self.exports_map) do
    -- Check for export with this name
    if exports[component_name] then
      -- This file exports the component - find all imports of it
      if type(exports[component_name]) == "table" and exports[component_name]._imported_by then
        for importing_file, _ in pairs(exports[component_name]._imported_by) do
          table.insert(usages, {
            file = importing_file,
            as = importing_file,
          })
        end
      end
    elseif exports["default"] and type(exports["default"]) == "table" and exports["default"]._imported_by then
      -- Check for default export usage with this name
      for importing_file, _ in pairs(exports["default"]._imported_by) do
        if importing_file == component_name then
          table.insert(usages, {
            file = importing_file,
            as = component_name,
          })
        end
      end
    end
  end

  return usages
end

-- New function to find which files import a specific file
function EnhancedCodeGraph:find_importers_of_file(target_file_path)
  local importers = {}

  -- Normalize the target path (e.g., resolve symlinks, make absolute)
  local resolved_target_path = vim.fn.resolve(target_file_path)

  -- Check if the target file exists in our exports map
  if self.exports_map[resolved_target_path] and self.exports_map[resolved_target_path]["_imported_by"] then
    -- Collect all file paths from the _imported_by table
    for importer_path, _ in pairs(self.exports_map[resolved_target_path]["_imported_by"]) do
      table.insert(importers, importer_path)
    end
  end

  return importers
end

-- Generate context from the graph
function EnhancedCodeGraph:generate_context(query)
  local context = "Codebase Context:\n"
  local max_total_size = 50000
  local max_node_size = 2000
  local current_size = #context

  -- Find relevant nodes based on query
  local nodes = self:find_relevant_nodes(query)
  print(string.format("Found %d relevant nodes for query: %s", #nodes, query))

  -- Handle specific queries about component/function usage
  if query:match("use[s]?%s+this") or query:match("import[s]?%s+this") or query:match("where%s+is%s+.+%s+used") then
    local component_name = query:match("where%s+is%s+(.+)%s+used")
      or query:match("what%s+file[s]?%s+use[s]?%s+(.+)")
      or query:match("what%s+file[s]?%s+import[s]?%s+(.+)")

    if component_name then
      component_name =
        component_name:gsub("['\"](.+)['\"]$", "%1"):gsub("component", ""):gsub("^%s+", ""):gsub("%s+$", "")
      local usages = self:find_component_usages(component_name)
      if #usages > 0 then
        context = context .. "\nFiles that use or import '" .. component_name .. "':\n"
        for _, usage in ipairs(usages) do
          context = context .. "- " .. usage.file
          if usage.as and usage.as ~= component_name then
            context = context .. " (imported as '" .. usage.as .. "')"
          end
          context = context .. "\n"
        end
        context = context .. "\n"
      else
        context = context .. "\nNo files found that import or use '" .. component_name .. "'\n\n"
      end
    end
  end

  -- Add each node to context
  for _, node in ipairs(nodes) do
    if current_size >= max_total_size then
      context = context .. "\n\n[Additional content truncated - query was too broad]\n"
      break
    end

    -- Add node header and content
    local header = string.format("\n%s %s in %s:\n", node.type, node.name or "unnamed", node.file or "unknown")

    -- Truncate content if needed
    local content = node.content
    if content and #content > max_node_size then
      content = content:sub(1, max_node_size) .. "\n... [content truncated due to size]\n"
    end

    if content then
      context = context .. header .. content .. "\n"
      current_size = current_size + #header + #content
    end

    -- Add related nodes
    local related = self:get_related_nodes(node.id)
    for _, rel_node in ipairs(related) do
      if current_size >= max_total_size then
        context = context .. "\n\n[Additional related content truncated]\n"
        break
      end

      local rel_header = string.format("\nRelated %s %s:\n", rel_node.relationship, rel_node.name or "unnamed")

      -- Truncate related content
      local rel_content = rel_node.content
      if rel_content and #rel_content > (max_node_size / 2) then
        rel_content = rel_content:sub(1, max_node_size / 2) .. "\n... [content truncated]\n"
      end

      if rel_content then
        context = context .. rel_header .. rel_content .. "\n"
        current_size = current_size + #rel_header + #rel_content
      end
    end
  end

  print(string.format("Generated context size: %d bytes", #context))
  return context
end

-- Find nodes relevant to a query
function EnhancedCodeGraph:find_relevant_nodes(query)
  local results = {}

  -- Skip empty queries
  if not query or query == "" then
    return results
  end

  -- Split query into words for better matching
  local words = {}
  for word in query:gmatch("%S+") do
    table.insert(words, word:lower())
  end

  if self.use_in_memory then
    -- In-memory implementation
    local scored_results = {}

    -- Score each node based on match
    for id, node in pairs(self.nodes) do
      local score = 0

      -- Score based on name match
      if node.name then
        local name_lower = node.name:lower()
        for _, word in ipairs(words) do
          if name_lower:find(word, 1, true) then
            score = score + 10 -- Higher priority for name matches
          end
        end
      end

      -- Score based on content match
      if node.content then
        local content_lower = node.content:lower()
        for _, word in ipairs(words) do
          if content_lower:find(word, 1, true) then
            score = score + 3 -- Lower priority for content matches
          end
        end
      end

      -- Score based on file path match
      if node.file then
        local file_lower = node.file:lower()
        for _, word in ipairs(words) do
          if file_lower:find(word, 1, true) then
            score = score + 5 -- Medium priority for file matches
          end
        end
      end

      if score > 0 then
        table.insert(scored_results, { id = id, node = node, score = score })
      end
    end

    -- Sort by score
    table.sort(scored_results, function(a, b)
      return a.score > b.score
    end)

    -- Get top results
    for i = 1, math.min(10, #scored_results) do
      table.insert(results, scored_results[i].node)
    end
  else
    -- SQLite implementation
    -- Build pattern for LIKE queries
    local like_pattern = "%" .. table.concat(words, "%") .. "%"

    -- First get name matches (higher priority)
    local name_matches = self.db:select(
      [[
      SELECT * FROM nodes
      WHERE name LIKE ?
      LIMIT 5
    ]],
      { like_pattern }
    )

    -- Add name matches
    for _, node in ipairs(name_matches or {}) do
      table.insert(results, node)
    end

    -- Then content matches if needed
    if #results < 10 then
      local content_matches = self.db:select(
        [[
        SELECT * FROM nodes
        WHERE content LIKE ?
        LIMIT ?
      ]],
        { like_pattern, 10 - #results }
      )

      for _, node in ipairs(content_matches or {}) do
        table.insert(results, node)
      end
    end
  end

  return results
end

-- Ensure FTS tables exist for faster search (SQLite only)
function EnhancedCodeGraph:ensure_fts_tables()
  if self.use_in_memory then
    return -- Skip for in-memory mode
  end

  -- Check if FTS tables already exist
  local has_fts = self.db:select([[
    SELECT name FROM sqlite_master
    WHERE type='table' AND name='nodes_fts'
  ]])

  if not has_fts or #has_fts == 0 then
    -- Create FTS table - skip for now as it requires FTS5 support
    -- which may not be available in all SQLite builds
  end
end

-- Get related nodes for a given node ID
function EnhancedCodeGraph:get_related_nodes(node_id)
  local related = {}

  if self.use_in_memory then
    -- Get outgoing relationships
    for edge_id, edge in pairs(self.edges) do
      if edge.source_id == node_id then
        local target_node = self.nodes[edge.target_id]
        if target_node then
          table.insert(related, {
            id = edge.target_id,
            relationship = edge.relationship,
            type = target_node.type,
            name = target_node.name,
            file = target_node.file,
            content = target_node.content,
          })
        end
      end
    end

    -- Get incoming relationships
    for edge_id, edge in pairs(self.edges) do
      if edge.target_id == node_id then
        local source_node = self.nodes[edge.source_id]
        if source_node then
          table.insert(related, {
            id = edge.source_id,
            relationship = "is " .. edge.relationship .. " by", -- Reverse relationship
            type = source_node.type,
            name = source_node.name,
            file = source_node.file,
            content = source_node.content,
          })
        end
      end
    end
  else
    -- Get outgoing relationships using SQLite
    local outgoing = self.db:select(
      [[
      SELECT e.target_id, e.relationship, n.type, n.name, n.file, n.content
      FROM edges e
      JOIN nodes n ON e.target_id = n.id
      WHERE e.source_id = ?
      LIMIT 5
    ]],
      { node_id }
    )

    for _, node in ipairs(outgoing or {}) do
      table.insert(related, {
        id = node.target_id,
        relationship = node.relationship,
        type = node.type,
        name = node.name,
        file = node.file,
        content = node.content,
      })
    end

    -- Get incoming relationships
    local incoming = self.db:select(
      [[
      SELECT e.source_id, e.relationship, n.type, n.name, n.file, n.content
      FROM edges e
      JOIN nodes n ON e.source_id = n.id
      WHERE e.target_id = ?
      LIMIT 5
    ]],
      { node_id }
    )

    for _, node in ipairs(incoming or {}) do
      table.insert(related, {
        id = node.source_id,
        relationship = "is " .. node.relationship .. " by", -- Reverse relationship
        type = node.type,
        name = node.name,
        file = node.file,
        content = node.content,
      })
    end
  end

  return related
end

-- Analyze semantic relationships in the codebase
function EnhancedCodeGraph:analyze_semantic_relationships()
  print("Performing semantic analysis...")

  -- Skip if no functions to analyze
  if vim.tbl_isempty(self.pending_analysis) then
    return
  end

  for file_path, item in pairs(self.pending_analysis) do
    local lang = item.lang
    local funcs = {}

    if self.use_in_memory then
      -- Get functions from in-memory storage
      for id, node in pairs(self.nodes) do
        if node.file == file_path and (node.type == "function" or node.type == "method") then
          table.insert(funcs, node)
        end
      end
    else
      -- Load all functions from this file using SQLite
      funcs = self.db:select(
        "SELECT id, name, content FROM nodes WHERE file = ? AND type IN ('function', 'method')",
        { file_path }
      ) or {}
    end

    -- For each function, look for calls to other functions
    for _, func in ipairs(funcs) do
      self:detect_function_calls(func, lang)
    end
  end

  -- Clear pending analysis
  self.pending_analysis = {}
end

-- Detect function calls and create relationships
function EnhancedCodeGraph:detect_function_calls(func, lang)
  -- Skip if we don't have content to analyze
  if not func or not func.content or func.content == "" then
    return
  end

  local function_id = func.id
  local content = func.content
  local file_path = func.file
  local name = func.name

  -- Get imports for this file to check for cross-file calls
  local imports = self.imports_map[file_path] or {}

  -- Process according to language
  if lang == "lua" then
    -- Find function calls in the form: module.function(), function()
    for line in content:gmatch("[^\n]+") do
      -- Look for function calls
      for called_name in line:gmatch("([%w_%.]+)%s*%(.-%)") do
        -- Skip common Lua built-ins and operators
        if
          not called_name:match("^table")
          and not called_name:match("^string")
          and not called_name:match("^math")
          and not called_name:match("^io")
          and not called_name:match("^os")
          and not called_name:match("^debug")
          and not called_name:match("^coroutine")
          and not called_name:match("^print")
          and not called_name:match("^pcall")
          and not called_name:match("^ipairs")
          and not called_name:match("^pairs")
          and not called_name:match("^require")
        then
          -- Check if it's a method call (module.function)
          local module_name, method_name = called_name:match("([%w_]+)%.([%w_]+)")

          if module_name and method_name then
            -- Check if module is imported
            if imports[module_name] then
              -- Get all functions in the target module
              local import_info = imports[module_name]
              local target_file = self:resolve_module_path(file_path, import_info.module)

              if target_file and self.exports_map[target_file] then
                -- Look for the exported function
                local target_id = self.exports_map[target_file][method_name]
                if target_id then
                  -- Create cross-file call relationship
                  self:add_edge(function_id, target_id, "calls", {
                    type = "cross_file",
                    source_file = file_path,
                    target_file = target_file,
                  })
                end
              end
            else
              -- Could be local module, check in same file
              -- This is more complex in JS due to object methods
              -- For simplicity, just log potential calls
              local potential_call = string.format("%s.%s called from %s", module_name, method_name, name)
            end
          else
            -- Direct function call
            -- Check if it's an imported function first
            if imports[called_name] then
              -- Get target through imports
              local import_info = imports[called_name]
              local target_file = self:resolve_module_path(file_path, import_info.module)

              if target_file and self.exports_map[target_file] then
                -- Find the actual export (could be named or default)
                local export_name = import_info.name or "default"
                local target_id = self.exports_map[target_file][export_name]

                if target_id then
                  -- Create cross-file call relationship
                  self:add_edge(function_id, target_id, "calls", {
                    type = "cross_file",
                    source_file = file_path,
                    target_file = target_file,
                  })
                end
              end
            else
              -- Check for local function in same file
              local target_id = nil

              -- Look in node_by_name index for same file
              if self.node_by_name[file_path] and self.node_by_name[file_path][called_name] then
                target_id = self.node_by_name[file_path][called_name]

                -- Create same-file call relationship
                self:add_edge(function_id, target_id, "calls", {
                  type = "same_file",
                  source_name = name,
                  target_name = called_name,
                })
              end
            end
          end
        end
      end
    end
  elseif lang == "javascript" or lang == "typescript" then
    -- Find function calls in JavaScript/TypeScript
    for line in content:gmatch("[^\n]+") do
      -- Match patterns like: functionName(), object.method(), imported.function()
      for called_name in line:gmatch("([%w_%.]+)%s*%(.-%)") do
        -- Skip console.log and other builtins
        if
          not called_name:match("^console")
          and not called_name:match("^Math")
          and not called_name:match("^Object")
          and not called_name:match("^Array")
          and not called_name:match("^String")
          and not called_name:match("^Number")
          and not called_name:match("^Boolean")
          and not called_name:match("^Date")
        then
          -- Is it a method call? (object.method)
          local object_name, method_name = called_name:match("([%w_]+)%.([%w_]+)")

          if object_name and method_name then
            -- Check if object is an imported module
            if imports[object_name] then
              -- Find target file through imports
              local import_info = imports[object_name]
              local target_file = self:resolve_module_path(file_path, import_info.module)

              if target_file and self.exports_map[target_file] then
                -- Check if method is exported from that file
                local target_id = self.exports_map[target_file][method_name]
                  or (
                    self.exports_map[target_file].default
                    and method_name == "default"
                    and self.exports_map[target_file].default.id
                  )

                if target_id then
                  -- Create cross-file call relationship
                  self:add_edge(function_id, target_id, "calls", {
                    type = "cross_file",
                    source_file = file_path,
                    target_file = target_file,
                    via_import = object_name,
                  })
                end
              end
            else
              -- Could be local object, check same file
              -- This is more complex in JS due to object methods
              -- For simplicity, just log potential calls
              local potential_call = string.format("%s.%s called from %s", object_name, method_name, name)
            end
          else
            -- Direct function call
            -- Check if it's an imported function first
            if imports[called_name] then
              -- Get target through imports
              local import_info = imports[called_name]
              local target_file = self:resolve_module_path(file_path, import_info.module)

              if target_file and self.exports_map[target_file] then
                -- Find the actual export (could be named or default)
                local export_name = import_info.name or "default"
                local target_id = self.exports_map[target_file][export_name]

                if target_id then
                  -- Create cross-file call relationship
                  self:add_edge(function_id, target_id, "calls", {
                    type = "cross_file",
                    source_file = file_path,
                    target_file = target_file,
                  })
                end
              end
            else
              -- Check for local function in same file
              local target_id = nil

              -- Look in node_by_name index for same file
              if self.node_by_name[file_path] and self.node_by_name[file_path][called_name] then
                target_id = self.node_by_name[file_path][called_name]

                -- Create same-file call relationship
                self:add_edge(function_id, target_id, "calls", {
                  type = "same_file",
                  source_name = name,
                  target_name = called_name,
                })
              end
            end
          end
        end
      end
    end
  else
    -- Generic approach for other languages - basic pattern matching
    for line in content:gmatch("[^\n]+") do
      -- Match function call patterns common in many languages
      for called_name in line:gmatch("([%w_%.]+)%s*%(.-%)") do
        -- Skip common built-ins based on language
        if not called_name:match("^print") and not called_name:match("^log") and not called_name:match("^assert") then
          -- Look for local calls first (easier)
          local target_id = nil

          -- Check node_by_name index in same file
          if self.node_by_name[file_path] and self.node_by_name[file_path][called_name] then
            target_id = self.node_by_name[file_path][called_name]

            -- Create same-file call relationship
            self:add_edge(function_id, target_id, "calls", {
              type = "same_file",
              source_name = name,
              target_name = called_name,
            })
          end

          -- For cross-file calls, it's language dependent
          -- We can use a simple heuristic - check all exported functions with same name
          local module_name, func_name = called_name:match("([%w_]+)%.([%w_]+)")

          if module_name and func_name and imports[module_name] then
            -- Import found, try to resolve to target file
            local import_info = imports[module_name]
            local target_file = self:resolve_module_path(file_path, import_info.module)

            if target_file and self.exports_map[target_file] and self.exports_map[target_file][func_name] then
              -- Create cross-file call
              self:add_edge(function_id, self.exports_map[target_file][func_name], "calls", {
                type = "cross_file",
                source_file = file_path,
                target_file = target_file,
              })
            end
          end
        end
      end
    end
  end
end

-- Index entire codebase starting from a root directory
function EnhancedCodeGraph:index_project(root_dir)
  print("Indexing codebase from: " .. root_dir)

  -- Find all relevant code files
  local cmd = [[
    find ]] .. root_dir .. [[ -type f \
    -not -path '*/\.*' \
    -not -path '*/node_modules/*' \
    -not -path '*/build/*' \
    -not -path '*/dist/*' \
    -and \( \
      -name '*.lua' -o -name '*.py' -o -name '*.js' -o -name '*.ts' -o \
      -name '*.jsx' -o -name '*.tsx' -o -name '*.go' -o -name '*.rs' -o \
      -name '*.c' -o -name '*.cpp' -o -name '*.h' -o -name '*.hpp' -o \
      -name '*.java' -o -name '*.kt' -o -name '*.swift' -o -name '*.rb' -o \
      -name '*.php' -o -name '*.cs' -o -name '*.scala' -o -name '*.ex' -o \
      -name '*.exs' -o -name '*.erl' -o -name '*.hs' -o -name '*.ml' -o \
      -name '*.json' -o -name '*.yaml' -o -name '*.yml' -o -name '*.xml' \
    \) | sort
  ]]

  local handle = io.popen(cmd)
  if handle then
    local count = 0
    for file in handle:lines() do
      count = count + 1
      if count % 50 == 0 then
        print(string.format("Indexed %d files...", count))
      end
      self:parse_file(file)
    end
    handle:close()
    print(string.format("Completed indexing %d files", count))
  else
    print("Error: could not execute find command")
  end

  -- Perform semantic analysis
  print("Performing semantic analysis...")
  self:analyze_semantic_relationships()

  print(string.format("Indexed %d nodes and %d edges from %s", self.stats.nodes, self.stats.edges, root_dir))
end

-- Clean up resources
function EnhancedCodeGraph:close()
  if not self.use_in_memory and self.db then
    -- No explicit close needed for sqlite.lua
    self.db = nil
  end
end

-- Create a singleton instance
local graph_instance = nil

-- Module interface
local M = {}

-- Initialize and index the codebase
function M.index_codebase()
  local root = M.get_project_root()

  -- Close existing instance if any
  if graph_instance then
    graph_instance:close()
  end

  -- Create new instance
  graph_instance = EnhancedCodeGraph:new()

  local start_time = os.time()
  print("Starting codebase indexing from " .. root)
  graph_instance:index_project(root)
  local end_time = os.time()

  print(
    string.format("Indexed %d nodes from %s in %d seconds", graph_instance.stats.nodes, root, end_time - start_time)
  )

  return graph_instance.stats.nodes, root
end

-- Get context from the codebase for a query
function M.get_context(query)
  -- Check if codebase is already indexed
  if not graph_instance then
    print("Codebase not indexed yet, indexing now...")
    M.index_codebase()
  end

  -- Wrap in pcall to catch any errors
  local success, result = pcall(function()
    return graph_instance:generate_context(query)
  end)

  if not success then
    print("Error generating context: " .. tostring(result))
    return "Error generating codebase context: " .. tostring(result)
  end

  return result
end

-- Check if the codebase is indexed
function M.is_indexed()
  return graph_instance ~= nil
end

-- Get statistics about the indexed codebase
function M.get_stats()
  if not graph_instance then
    return { nodes = 0, edges = 0, files = 0, functions = 0, classes = 0 }
  end

  return graph_instance.stats
end

-- Get project root (git or cwd)
function M.get_project_root()
  local git_cmd = "git -C " .. vim.fn.getcwd() .. " rev-parse --show-toplevel 2>/dev/null"
  local git_root = vim.fn.system(git_cmd):gsub("\n", "")
  if git_root ~= "" and vim.fn.isdirectory(git_root) == 1 then
    return git_root
  end

  return vim.fn.getcwd()
end

return M
