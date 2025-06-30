return {
  {
    "yetone/avante.nvim",
    event = "VeryLazy",
    lazy = false,
    version = false, -- Never set this value to "*"! Never!
    opts = {
      provider = "gemini",
      auto_suggestions_provider = "gemini",
      cursor_applying_provider = "gemini",

      -- Gemini provider configuration
      providers = {
        gemini = {
          model = "gemini-2.5-flash",
          timeout = 30000, -- 30 seconds
          temperature = 0,
          max_tokens = 8192,
          -- api_key_name = "cmd:security find-generic-password -s GEMINI_KEY -w", -- Optional: use macOS keychain
        },
      },

      rag_service = {
        enabled = true, -- Set to true to enable RAG service
        host_mount = os.getenv("HOME"), -- Host mount path for the rag service
        provider = "openai", -- The provider to use for RAG service (e.g. openai or ollama)
        llm_model = "gpt-4o-mini", -- The LLM model to use for RAG service
        embed_model = "text-embedding-3-large", -- The embedding model to use for RAG service
        endpoint = "https://api.openai.com/v1", -- The API endpoint for RAG service
      },

      -- Enable cursor planning mode for better results with open-source models
      behaviour = {
        enable_cursor_planning_mode = true,
        auto_set_highlight_group = true,
        auto_set_keymaps = true,
        auto_apply_diff_after_generation = false,
        support_paste_from_clipboard = false,
        minimize_diff = true,
        enable_token_counting = true,
        auto_focus_sidebar = true, -- New option
        auto_suggestions = false, -- Experimental feature
        auto_approve_tool_permissions = false, -- New security option
      },

      web_search_engine = {
        provider = "tavily", -- tavily, serpapi, searchapi, google, kagi, brave, or searxng
        proxy = nil, -- proxy support, e.g., http://127.0.0.1:7890
      },

      dual_boost = {
        enabled = false,
        first_provider = "architect",
        second_provider = "perplexity",
        prompt = [[
        "test"
        
        ]],
      },

      -- MCP Hub integration
      system_prompt = function()
        local hub = require("mcphub").get_hub_instance()
        return hub:get_active_servers_prompt()
      end,
      custom_tools = function()
        return {
          require("mcphub.extensions.avante").mcp_tool(),
        }
      end,
      -- disabled_tools = {
      --   "list_files",
      --   "search_files",
      --   "read_file",
      --   "create_file",
      --   "rename_file",
      --   "delete_file",
      --   "create_dir",
      --   "rename_dir",
      --   "delete_dir",
      --   "bash",
      -- },
    },
    -- Cross-platform build configuration
    build = function()
      if vim.fn.has("win32") == 1 then
        return "powershell -ExecutionPolicy Bypass -File Build.ps1 -BuildFromSource false"
      else
        return "make"
      end
    end,
    dependencies = {
      "stevearc/dressing.nvim",
      "nvim-lua/plenary.nvim",
      "MunifTanjim/nui.nvim",
      -- optional dependencies
      "echasnovski/mini.pick",
      "nvim-telescope/telescope.nvim",
      "hrsh7th/nvim-cmp",
      "ibhagwan/fzf-lua",
      "nvim-tree/nvim-web-devicons",
      "zbirenbaum/copilot.lua", -- if you'd like to try auto-suggestions from copilot
      {
        "HakonHarnes/img-clip.nvim",
        event = "VeryLazy",
        opts = {
          default = {
            embed_image_as_base64 = false,
            prompt_for_file_name = false,
            drag_and_drop = {
              insert_mode = true,
            },
            -- use_absolute_path = true,
          },
        },
      },
      {
        "MeanderingProgrammer/render-markdown.nvim",
        opts = {
          file_types = { "markdown", "Avante" },
        },
        ft = { "markdown", "Avante" },
      },
    },
  },
}
