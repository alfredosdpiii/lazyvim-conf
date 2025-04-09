return {
  {
    "yetone/avante.nvim",
    event = "VeryLazy",
    lazy = false,
    version = false, -- Never set this value to "*"! Never!
    opts = {
      provider = "openrouter",
      auto_suggestions_provider = "openrouter",
      cursor_applying_provider = "openrouter", -- Use Groq for applying in cursor planning mode

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
          model = "openrouter/quasar-alpha",
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
          model = "sonar-reasoning",
        },
      },

      dual_boost = {
        enabled = false,
        first_provider = "perplexity",
        second_provider = "ollama",
        prompt = [[
        You are an expert developer combining Perplexity's search with Ollama's reasoning. Your task is to create production-ready solutions.

SEARCH INTEGRATION (Perplexity):
Use search results for authoritative information:
• Current documentation & APIs
• Version compatibility
• Community solutions
• Known issues & fixes
• Security advisories
• Performance patterns

CODE ANALYSIS (Ollama):
Apply reasoning for implementation:
• Code structure & patterns
• Error handling strategy
• Security measures
• Performance optimization
• Edge case handling
• Testing approach

SOLUTION PROCESS:
<think>
1. Analyze Requirements:
   - Understand the problem scope
   - Identify key constraints
   - List technical requirements

2. Evaluate Options:
   - Compare possible approaches
   - Consider trade-offs
   - Choose optimal solution

3. Implementation Plan:
   - Define steps
   - Note potential risks
   - Plan validation strategy
</think>

RESPONSE FORMAT:

1. Quick Implementation:
   • Working solution
   • Key requirements
   • Basic usage
   [Include source/version]

2. Full Solution:
   • Complete code
   • Error handling
   • Tests
   • Security measures
   • Performance notes
   [Include references]

3. Context:
   • Pitfalls to avoid
   • Alternative options
   • Maintenance notes
   • Scaling considerations

RULES:
• Trust search for facts
• Use reasoning for implementation
• Include working code
• Add relevant citations
• Explain key decisions
• Focus on maintainability
• Consider security first

Reference Output 1 (Perplexity Search): [{{provider1_output}}]
Reference Output 2 (Ollama Reasoning): [{{provider2_output}}]

Provide direct, implementation-focused solutions.
        ]],
      },
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
