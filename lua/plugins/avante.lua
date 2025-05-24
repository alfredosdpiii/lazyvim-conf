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

      -- Gemini-specific configuration
      gemini = {
        endpoint = "https://generativelanguage.googleapis.com/v1beta/models",
        model = "gemini-2.5-flash-preview-05-20",
        timeout = 30000,
        temperature = 0,
        max_tokens = 8192,
        api_key_name = "GEMINI_API_KEY",
      },

      -- Move ollama out of vendors to be a top-level config as recommended
      ollama = {
        endpoint = "http://127.0.0.1:11434", -- Note: no /v1 at the end
        model = "deepcoder",
      },
      -- Add RAG service configuration
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
      },

      web_search_engine = {
        provider = "tavily", -- tavily, serpapi, searchapi, google, kagi, brave, or searxng
        proxy = nil, -- proxy support, e.g., http://127.0.0.1:7890
      },

      vendors = {
        deepseek = {
          __inherited_from = "openai", -- Use openai-like logic
          api_key_name = "DEEPSEEK_API_KEY",
          endpoint = "https://api.deepseek.com",
          model = "deepseek-reasoner",
        },
        openrouter = {
          __inherited_from = "openai",
          api_key_name = "OPENROUTER_API_KEY",
          endpoint = "https://openrouter.ai/api/v1",
          model = "openai/o4-mini",
        },
        architect = {
          __inherited_from = "openai",
          api_key_name = "OPENROUTER_API_KEY",
          endpoint = "https://openrouter.ai/api/v1",
          model = "x-ai/grok-3-mini-beta",
          -- temperature = 0.3,
        },
        coder = {
          __inherited_from = "openai",
          api_key_name = "OPENROUTER_API_KEY",
          endpoint = "https://openrouter.ai/api/v1",
          model = "openai/gpt-4.1",
          -- temperature = 0.1,
        },
        groq = {
          __inherited_from = "openai",
          api_key_name = "GROQ_API_KEY",
          endpoint = "https://api.groq.com/openai/v1",
          model = "llama-3.3-70b-versatile", -- Updated to recommended model for cursor planning
          max_completion_tokens = 32768, -- Increased as recommended for cursor planning mode
        },
        perplexity = {
          __inherited_from = "openai",
          api_key_name = "PERPLEXITY_API_KEY",
          endpoint = "https://api.perplexity.ai",
          model = "sonar-deep-research",
        },
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
    build = "make",
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
