-- /home/bryan/.config/nvim/lua/ai_assistant/jsts_parser.lua
-- JavaScript/TypeScript specific parser module for AI Assistant
-- Provides enhanced parsing capabilities for JS/TS imports/exports

local M = {}

-- Helper function to extract import paths from all import styles
function M.extract_imports(content)
  local imports = {}
  
  -- Split content into lines for line-by-line analysis
  for line_num, line in ipairs(vim.split(content, "\n")) do
    -- Check if line contains import statement (handling comments)
    if line:match("^%s*import%s+") and not line:match("^%s*//") then
      -- ES6 default import: import Name from 'module'
      local name, module_path = line:match("import%s+([%w_]+)%s+from%s+['\"](.+)['\"]")
      if name and module_path then
        table.insert(imports, {
          type = "default",
          source = module_path,
          names = {name},
          line = line_num
        })
      end
      
      -- ES6 named imports: import { A, B as C } from 'module'
      local imports_list, named_module = line:match("import%s*{%s*(.-)%s*}%s*from%s*['\"](.+)['\"]")
      if imports_list and named_module then
        local names = {}
        for orig_name, alias in imports_list:gmatch("([%w_]+)%s*(?:as%s+([%w_]+))?%s*,?") do
          table.insert(names, {
            original = orig_name,
            alias = alias or orig_name -- Use original if no alias
          })
        end
        
        table.insert(imports, {
          type = "named",
          source = named_module,
          names = names,
          line = line_num
        })
      end
      
      -- ES6 namespace import: import * as Name from 'module'
      local ns_name, ns_module = line:match("import%s*%*%s*as%s+([%w_]+)%s+from%s+['\"](.+)['\"]")
      if ns_name and ns_module then
        table.insert(imports, {
          type = "namespace",
          source = ns_module,
          names = {ns_name},
          line = line_num
        })
      end
      
      -- Side effect import: import 'module'
      local side_module = line:match("import%s+['\"](.+)['\"]")
      if side_module and not name and not imports_list and not ns_name then
        table.insert(imports, {
          type = "side-effect",
          source = side_module,
          names = {},
          line = line_num
        })
      end
      
      -- Dynamic import: import('./module').then(...)
      local dynamic_module = line:match("import%s*%((['\"].+['\"])%)")
      if dynamic_module then
        table.insert(imports, {
          type = "dynamic",
          source = dynamic_module:gsub("['\"]", ""),
          names = {},
          line = line_num
        })
      end
    end
    
    -- CommonJS require: const x = require('module')
    local req_var, req_module = line:match("(%w+)%s*=%s*require%s*%(%s*['\"](.+)['\"]%s*%)")
    if req_var and req_module then
      table.insert(imports, {
        type = "commonjs",
        source = req_module,
        names = {req_var},
        line = line_num
      })
    end
    
    -- Bare require call: require('module')
    local bare_req = line:match("require%s*%(%s*['\"](.+)['\"]%s*%)")
    if bare_req and not req_var then
      table.insert(imports, {
        type = "commonjs-bare",
        source = bare_req,
        names = {},
        line = line_num
      })
    end
  end
  
  return imports
end

-- Improved module path resolution for JS/TS
function M.resolve_module_path(current_file, module_path, root_dir)
  -- Handle path aliases (like @ or ~ prefixes)
  local aliases = {
    ["@"] = root_dir,
    ["~"] = root_dir,
    ["app"] = root_dir .. "/app", -- For NextJS convention
    ["src"] = root_dir .. "/src",
    ["components"] = root_dir .. "/components",
  }
  
  -- Check for alias prefixes
  for prefix, path in pairs(aliases) do
    local with_slash = prefix .. "/"
    if module_path:sub(1, #with_slash) == with_slash then
      module_path = path .. "/" .. module_path:sub(#with_slash + 1)
      break
    end
  end
  
  -- Process as a normal path
  local extensions = {".tsx", ".ts", ".jsx", ".js", ".json"}
  local search_paths = {}
  
  -- 1. Direct file with extension
  table.insert(search_paths, module_path)
  
  -- 2. Try adding extensions
  for _, ext in ipairs(extensions) do
    table.insert(search_paths, module_path .. ext)
  end
  
  -- 3. Try as directory with index files
  for _, ext in ipairs(extensions) do
    table.insert(search_paths, module_path .. "/index" .. ext)
  end
  
  -- Return all possible paths for the caller to check
  return search_paths
end

-- Function to get all module imports from a file
function M.get_imports(file_path, content, root_dir)
  local imports = M.extract_imports(content)
  
  -- If root_dir not provided, try to detect from file_path
  if not root_dir then
    -- Try to get git root
    local cmd = "git -C " .. vim.fn.fnamemodify(file_path, ":h") .. " rev-parse --show-toplevel 2>/dev/null"
    local git_root = vim.fn.system(cmd):gsub("\n", "")
    
    if git_root ~= "" and vim.fn.isdirectory(git_root) == 1 then
      root_dir = git_root
    else
      -- Fallback to current working directory
      root_dir = vim.fn.getcwd()
    end
  end
  
  -- Process imported modules
  for _, import in ipairs(imports) do
    -- Resolve paths
    local module_path = import.source
    import.resolved_paths = M.resolve_module_path(file_path, module_path, root_dir)
  end
  
  return imports
end

-- Export the module
return M
