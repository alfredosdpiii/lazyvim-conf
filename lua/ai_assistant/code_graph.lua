-- /home/bryan/.config/nvim/lua/ai_assistant/code_graph.lua
-- Module for building and querying a code graph using Treesitter

local api = vim.api
local ts = vim.treesitter

-- Detect language from file content
local function detect_language_from_content(content)
  -- Very basic detection based on common patterns
  if content:match("^#!.*python") then
    return "python"
  elseif content:match("^#!.*node") then
    return "javascript"
  elseif content:match("^#!.*ruby") then
    return "ruby"
  elseif content:match("^#!.*bash") or content:match("^#!.*sh") then
    return "bash"
  elseif content:match("<%.*%>") then
    return "html"
  elseif content:match("package main") then
    return "go"
  elseif content:match("import java") then
    return "java"
  elseif content:match("import kotlin") then
    return "kotlin"
  elseif content:match("import scala") then
    return "scala"
  elseif content:match("function.*%(.*%).*{")
      or content:match("=>")
      or content:match("var")
      or content:match("const") then
    return "javascript"
  elseif content:match("local")
      or content:match("function.*%(.*%)")
      or content:match("end") then
    return "lua"
  elseif content:match("def.*%:")
      or content:match("class.*%:")
      or content:match("import ")
      or content:match("from .* import") then
    return "python"
  else
    return nil
  end
end

-- Graph representation of the codebase
local CodeGraph = {
  -- Nodes store entities (functions, classes, etc.)
  nodes = {},
  -- Edges store relationships between nodes
  edges = {},
  -- Index maps for faster lookups
  node_by_name = {},
  files_indexed = {}
}

-- Node types we care about
local NODE_TYPES = {
  function_definition = "function",
  method_definition = "method",
  class_definition = "class",
  module = "module",
  variable_declaration = "variable",
  lexical_declaration = "variable",
}

-- Initialize the graph
function CodeGraph:new()
  local instance = {
    nodes = {},
    edges = {},
    node_by_name = {},
    files_indexed = {}
  }
  setmetatable(instance, { __index = CodeGraph })
  return instance
end

-- Create a node in the graph
function CodeGraph:add_node(id, node_type, name, file, start_line, end_line, content)
  local node = {
    id = id,
    type = node_type,
    name = name,
    file = file,
    start_line = start_line,
    end_line = end_line,
    content = content
  }
  self.nodes[id] = node
  self.node_by_name[name] = self.node_by_name[name] or {}
  table.insert(self.node_by_name[name], id)
  return node
end

-- Create an edge between nodes
function CodeGraph:add_edge(from_id, to_id, relation_type)
  local edge_id = from_id .. "->" .. to_id
  self.edges[edge_id] = {
    from = from_id,
    to = to_id,
    type = relation_type
  }
end

-- Parse a single file with Treesitter and add to graph
function CodeGraph:parse_file(file_path)
  -- Check if file is already indexed
  if self.files_indexed[file_path] then
    return
  end
  
  -- Read file content
  local file = io.open(file_path, "r")
  if not file then
    print("Error opening file: " .. file_path)
    return
  end
  local content = file:read("*all")
  file:close()
  
  -- Store file in graph
  local file_id = "file:" .. file_path
  self:add_node(file_id, "file", file_path, file_path, 0, #vim.split(content, "\n"), content)
  
  -- Get file extension to determine language
  local ext = file_path:match("%.([^%.]+)$") or ""
  local lang_map = {
    lua = "lua",
    py = "python",
    js = "javascript",
    ts = "typescript",
    jsx = "javascript",
    tsx = "typescript",
    rs = "rust",
    go = "go",
    c = "c",
    cpp = "cpp",
    h = "c",
    hpp = "cpp",
    java = "java",
    kt = "kotlin",
    swift = "swift",
    rb = "ruby",
    php = "php",
    cs = "c_sharp",
    scala = "scala",
    ex = "elixir",
    exs = "elixir",
    erl = "erlang",
    hs = "haskell",
    ml = "ocaml",
    json = "json",
    yaml = "yaml",
    yml = "yaml",
    xml = "xml",
    html = "html",
    css = "css",
    scss = "scss",
    sass = "scss",
    md = "markdown",
    txt = "text",
    vim = "vim",
    sh = "bash",
    bash = "bash",
    zsh = "bash",
  }
  
  local lang = lang_map[ext] or ext
  
  -- Parse with Treesitter
  local success, parser = pcall(function() return ts.get_string_parser(content, lang) end)
  if not success or not parser then
    -- Try to detect language from file content if extension didn't work
    local detected_lang = detect_language_from_content(content)
    if detected_lang and detected_lang ~= lang then
      success, parser = pcall(function() return ts.get_string_parser(content, detected_lang) end)
    end
    
    if not success or not parser then
      -- Add the file as a basic node without parsing
      print("Could not create parser for: " .. file_path .. " with language: " .. lang)
      -- Add basic file content node
      local node_id = "file_content:" .. file_path
      self:add_node(node_id, "file_content", file_path:match("([^/]+)$"), file_path, 0, #vim.split(content, "\n"), content)
      self:add_edge(file_id, node_id, "contains")
      return
    end
  end
  
  local tree_result = parser:parse()
  if #tree_result == 0 then
    print("Parsing resulted in empty tree for: " .. file_path)
    return
  end
  
  local tree = tree_result[1]
  local root = tree:root()
  
  -- Process tree to extract nodes and relationships
  self:process_node(root, file_path, content, file_id)
  
  -- Mark file as indexed
  self.files_indexed[file_path] = true
end

-- Process a Treesitter node recursively
function CodeGraph:process_node(ts_node, file_path, content, parent_id)
  local node_type = ts_node:type()
  
  -- Check if this is a node type we care about
  local entity_type = NODE_TYPES[node_type]
  if entity_type then
    -- Extract name and range
    local name_node = self:find_name_node(ts_node, node_type)
    if name_node then
      local name = self:get_node_text(name_node, content)
      local start_row, start_col, end_row, end_col = ts_node:range()
      local node_text = self:get_node_text(ts_node, content)
      
      -- Create unique ID
      local node_id = entity_type .. ":" .. file_path .. ":" .. name .. ":" .. start_row
      
      -- Add to graph
      self:add_node(node_id, entity_type, name, file_path, start_row, end_row, node_text)
      
      -- Add relationship to parent
      if parent_id then
        self:add_edge(parent_id, node_id, "contains")
      end
      
      -- Update parent for children
      parent_id = node_id
    end
  end
  
  -- Process children
  for child in ts_node:iter_children() do
    self:process_node(child, file_path, content, parent_id)
  end
end

-- Find the name node based on node type
function CodeGraph:find_name_node(node, node_type)
  if node_type == "function_definition" or node_type == "method_definition" then
    -- Find function name
    for child in node:iter_children() do
      if child:type() == "identifier" then
        return child
      end
    end
  elseif node_type == "class_definition" then
    -- Find class name
    for child in node:iter_children() do
      if child:type() == "identifier" then
        return child
      end
    end
  elseif node_type == "variable_declaration" or node_type == "lexical_declaration" then
    -- For variable declarations, look for identifier in declarator
    for child in node:iter_children() do
      if child:type() == "variable_declarator" then
        for subchild in child:iter_children() do
          if subchild:type() == "identifier" then
            return subchild
          end
        end
      end
    end
  end
  return nil
end

-- Get text from a node
function CodeGraph:get_node_text(node, content)
  local start_row, start_col, end_row, end_col = node:range()
  local lines = vim.split(content, "\n")
  
  if start_row == end_row then
    return lines[start_row + 1]:sub(start_col + 1, end_col)
  else
    local result = lines[start_row + 1]:sub(start_col + 1)
    for i = start_row + 2, end_row do
      result = result .. "\n" .. lines[i]
    end
    result = result .. "\n" .. lines[end_row + 1]:sub(1, end_col)
    return result
  end
end

-- Helper function to safely truncate long content
local function truncate_content(content, max_length)
  if not content then return "" end
  
  if #content > max_length then
    return content:sub(1, max_length) .. "\n... [content truncated due to size]\n"
  end
  return content
end

-- Generate context from the graph
function CodeGraph:generate_context(query)
  local context = "Codebase Context:\n"
  local max_total_size = 50000 -- Maximum safe size for Neovim buffers
  local max_node_size = 2000   -- Maximum size for any single node content
  local current_size = #context
  
  -- Find relevant nodes based on the query
  local relevant_nodes = self:find_relevant_nodes(query)
  print(string.format("Found %d relevant nodes for query: %s", #relevant_nodes, query))
  
  -- For each relevant node, get its content and related nodes
  for _, node_id in ipairs(relevant_nodes) do
    if current_size >= max_total_size then
      context = context .. "\n\n[Additional content truncated - query was too broad]\n"
      break
    end
    
    local node = self.nodes[node_id]
    if not node then
      print("Warning: Node not found: " .. node_id)
      goto continue
    end
    
    local node_header = "\n" .. node.type .. " " .. (node.name or "unnamed") .. " in " .. (node.file or "unknown") .. ":\n"
    local node_content = truncate_content(node.content, max_node_size)
    
    -- Check if adding this node would exceed our size limit
    if current_size + #node_header + #node_content > max_total_size then
      context = context .. "\n\n[Additional content truncated - size limit reached]\n"
      break
    end
    
    context = context .. node_header .. node_content .. "\n"
    current_size = current_size + #node_header + #node_content
    
    -- Add directly related nodes (limited)
    local related = self:get_related_nodes(node_id)
    local related_count = 0
    for _, related_id in ipairs(related) do
      if related_count >= 3 or current_size >= max_total_size then break end
      
      local related_node = self.nodes[related_id]
      if not related_node then goto continue_related end
      
      local related_header = "\nRelated " .. related_node.type .. " " .. (related_node.name or "unnamed") .. ":\n"
      local related_content = truncate_content(related_node.content, max_node_size / 2) -- Smaller for related nodes
      
      -- Check if adding this related node would exceed our size limit
      if current_size + #related_header + #related_content > max_total_size then
        context = context .. "\n\n[Additional related content truncated]\n"
        break
      end
      
      context = context .. related_header .. related_content .. "\n"
      current_size = current_size + #related_header + #related_content
      related_count = related_count + 1
      
      ::continue_related::
    end
    
    ::continue::
  end
  
  print(string.format("Generated context size: %d bytes", #context))
  return context
end

-- Find nodes relevant to a query
function CodeGraph:find_relevant_nodes(query)
  local results = {}
  local scored_results = {}
  
  -- Skip empty queries
  if not query or query == "" then
    -- Return top-level nodes like files
    for id, node in pairs(self.nodes) do
      if node.type == "file" then
        table.insert(results, id)
        if #results >= 10 then
          break
        end
      end
    end
    return results
  end
  
  -- Search for keywords
  local keywords = {}
  for word in query:gmatch("%S+") do
    table.insert(keywords, word:lower())
  end
  
  -- Score nodes based on keyword matches
  for id, node in pairs(self.nodes) do
    local score = 0
    
    -- Score based on name match
    if node.name then
      local name_lower = node.name:lower()
      for _, keyword in ipairs(keywords) do
        if name_lower:find(keyword, 1, true) then
          score = score + 10 -- Direct name match is highest priority
        end
      end
    end
    
    -- Score based on content match
    if node.content then
      local content_lower = node.content:lower()
      for _, keyword in ipairs(keywords) do
        if content_lower:find(keyword, 1, true) then
          score = score + 3 -- Content match is medium priority
        end
      end
    end
    
    -- Score based on file path match
    if node.file then
      local file_lower = node.file:lower()
      for _, keyword in ipairs(keywords) do
        if file_lower:find(keyword, 1, true) then
          score = score + 5 -- File path match is high priority
        end
      end
    end
    
    -- If we found any matches
    if score > 0 then
      table.insert(scored_results, {id = id, score = score})
    end
  end
  
  -- Sort by score
  table.sort(scored_results, function(a, b) return a.score > b.score end)
  
  -- Take top results
  for i = 1, math.min(10, #scored_results) do
    table.insert(results, scored_results[i].id)
  end
  
  return results
end

-- Get nodes directly related to a given node
function CodeGraph:get_related_nodes(node_id)
  local related = {}
  
  -- Find edges where this node is source or target
  for _, edge in pairs(self.edges) do
    if edge.from == node_id then
      table.insert(related, edge.to)
    elseif edge.to == node_id then
      table.insert(related, edge.from)
    end
  end
  
  return related
end

-- Index all files in the project
function CodeGraph:index_project(root_dir)
  -- Print info
  print("Indexing codebase from: " .. root_dir)
  
  -- Expanded file types to include more programming languages
  -- Using a simpler approach with string concatenation for shell command to avoid escape issues
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
      -name '*.json' -o -name '*.yaml' -o -name '*.yml' -o -name '*.xml' -o \
      -name '*.html' -o -name '*.css' -o -name '*.scss' -o -name '*.sass' -o \
      -name '*.md' -o -name '*.txt' -o \
      -name '*.vim' -o -name '*.sh' -o -name '*.bash' -o -name '*.zsh' \
    \) | sort
  ]]
              
  -- Print command for debugging
  print("Find command: " .. cmd)
  
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
end

-- Get active project root (based on git or current working directory)
local function get_project_root()
  -- Try using git root  
  local git_cmd = "git -C " .. vim.fn.getcwd() .. " rev-parse --show-toplevel 2>/dev/null"
  local git_root = vim.fn.system(git_cmd):gsub("\n", "")
  if git_root ~= "" and vim.fn.isdirectory(git_root) == 1 then
    return git_root
  end
  
  -- Fall back to current working directory
  return vim.fn.getcwd()
end

-- Create a singleton instance
local graph_instance = CodeGraph:new()

-- Module interface
local M = {}

-- Initialize and index the codebase
function M.index_codebase()
  local root = get_project_root()
  
  -- Clear any existing graph
  graph_instance = CodeGraph:new()
  
  local start_time = os.time()
  print("Starting codebase indexing from " .. root)
  graph_instance:index_project(root)
  local end_time = os.time()
  
  local node_count = 0
  for _ in pairs(graph_instance.nodes) do node_count = node_count + 1 end
  
  print(string.format("Indexed %d nodes from %s in %d seconds", 
                      node_count, root, end_time - start_time))
  return node_count, root
end

-- Get context from the codebase for a query
function M.get_context(query)
  -- Check if codebase is already indexed
  if #graph_instance.nodes == 0 then
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
  return #graph_instance.nodes > 0
end

-- Get statistics about the indexed codebase
function M.get_stats()
  return {
    nodes = #graph_instance.nodes,
    edges = #graph_instance.edges,
    files = #graph_instance.files_indexed
  }
end

return M
