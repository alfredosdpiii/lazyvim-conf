return {
  {
    "yetone/avante.nvim",
    event = "VeryLazy",
    lazy = false,
    version = "*", -- Or 'false' to track the latest commit
    opts = {
      provider = "claude",
      auto_suggestions_provider = "ollama",
      vendors = {
        -- Example: "deepseek" inherits the same structure as openai
        deepseek = {
          __inherited_from = "openai", -- Use openai-like logic
          api_key_name = "DEEPSEEK_API_KEY", -- so Avante knows which env var to prompt for
          endpoint = "https://api.deepseek.com",
          model = "deepseek-reasoner",
          -- Additional fields if needed
        },
        ollama = {
          __inherited_from = "openai",
          api_key_name = "",
          endpoint = "http://127.0.0.1:11434/v1",
          model = "deepseek-r1:8b",
        },
        groq = {
          __inherited_from = "openai",
          api_key_name = "GROQ_API_KEY",
          endpoint = "https://api.groq.com/openai/v1",
          model = "deepseek-r1-distill-llama-70b",
          max_tokens = 6000,
        },
        perplexity = {
          __inherited_from = "openai",
          api_key_name = "PERPLEXITY_API_KEY",
          endpoint = "https://api.perplexity.ai",
          model = "sonar-reasoning",
        },
        -- perplexity = {
        --   __inherited_from = "openai",
        --   api_key_name = "PERPLEXITY_API_KEY",
        --   endpoint = "https://api.perplexity.ai",
        --   model = "pplx-7b-online",  -- or "pplx-70b-online", "pplx-7b-chat", "pplx-70b-chat"
        -- },
        -- Add an openai vendor if you want to switch to or use with dual-boost
        -- openai = {
        --   endpoint = "https://api.openai.com",
        --   api_key_name = "OPENAI_API_KEY",
        --   model = "gpt-3.5-turbo-0613",
        --   temperature = 0,
        --   max_tokens = 2000,
        -- },
        -- claude = {
        --   endpoint = "https://api.anthropic.com",
        --   model = "claude-3-5-sonnet-20241022",
        --   temperature = 0.7,
        --   max_tokens = 4096,
        -- },
        -- You can add more providers or variants as needed:
        --   azure = {...}   or   claude = {...}, etc.
      },

      dual_boost = {
        enabled = true, -- turn on the dual-boost
        first_provider = "perplexity", -- the first reference output
        second_provider = "ollama", -- the second reference output
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
      -- You can also override other Avante options (mappings, windows, highlights, etc.)
      -- ...
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
