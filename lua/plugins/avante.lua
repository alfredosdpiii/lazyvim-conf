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
          model = "deepseek-r1:7b",
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
        first_provider = "ollama", -- the first reference output
        second_provider = "claude", -- the second reference output
        prompt = [[
Based on the two reference outputs below, generate a response that incorporates
elements from both but reflects your own judgment and unique perspective.
Do not provide any explanation, just give the response directly.

Reference Output 1: [{{provider1_output}}],
Reference Output 2: [{{provider2_output}}]
        ]],
        timeout = 80000, -- in milliseconds
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
