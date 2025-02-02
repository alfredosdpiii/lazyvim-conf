return {
  {
    "olimorris/codecompanion.nvim",
    lazy = false, -- Ensure plugin loads immediately
    priority = 50, -- Load early in the startup sequence
    dependencies = {
      "nvim-lua/plenary.nvim",
      "nvim-treesitter/nvim-treesitter",
      "hrsh7th/nvim-cmp",
      "nvim-telescope/telescope.nvim",
      { "stevearc/dressing.nvim", opts = {} },
    },
    config = function()
      require("codecompanion").setup({
        adapters = {
          ollama = function()
            return require("codecompanion.adapters").extend("ollama", {
              schema = {
                model = {
                  default = "deepseek-r1:7b", -- More reliable for code tasks
                  fallback = "deepseek-r1:7b",
                },
                options = {
                  temperature = 0.1, -- More deterministic responses
                  top_p = 0.8, -- Focus on higher probability tokens
                  num_ctx = 4096, -- Standard context size
                  repeat_penalty = 1.2, -- Stronger repetition prevention
                },
              },
              url = "http://localhost:11434/api/generate",
            })
          end,
        },
        strategies = {
          chat = {
            adapter = "ollama",
            auto_focus = true,
            auto_follow = true,
            show_language = true,
            error_handler = function(err)
              vim.notify(err, vim.log.levels.ERROR)
            end,
            language_detection = true, -- Auto-detect file language
            max_lines = 1000, -- Prevent excessive output
            trim_response = true, -- Remove redundant whitespace
            save_context = true, -- Remember chat context
          },
          inline = {
            adapter = "ollama",
            show_provider = true,
            clear_on_done = false, -- Keep suggestions visible
          },
          agent = {
            adapter = "ollama",
            commands = {
              explain = "Explain how this code works, including edge cases and assumptions",
              improve = "Suggest improvements focusing on performance, readability, and maintainability",
              fix = "Find and fix issues, including potential security vulnerabilities",
              test = "Generate comprehensive unit tests with edge cases",
              doc = "Generate documentation following language-specific conventions",
              refactor = "Suggest refactoring options prioritizing code reusability",
              security = "Perform security analysis and suggest hardening measures",
              perf = "Analyze performance implications and suggest optimizations",
              types = "Suggest type annotations and interface improvements",
            },
          },
        },
        window = {
          layout = "float",
          width = 0.55, -- Wider for better code visibility
          height = 0.7, -- Taller for context
          border = "rounded",
          win_opts = {
            wrap = false, -- Better for code
            number = true, -- Line numbers
            foldcolumn = "0", -- Save space
            cursorline = true, -- Easier navigation
          },
          position = "bottom-right", -- Consistent positioning
        },
        highlight = {
          enable = true,
          timeout = 1000,
        },
      })
    end,
    keys = {
      { "<leader>cc", "<cmd>CodeCompanionChat<cr>", desc = "Open Chat" },
      { "<leader>ce", "<cmd>CodeCompanionChat explain<cr>", mode = { "n", "v" }, desc = "Explain Code" },
      { "<leader>ci", "<cmd>CodeCompanionChat improve<cr>", mode = { "n", "v" }, desc = "Improve Code" },
      { "<leader>ct", "<cmd>CodeCompanionChat test<cr>", mode = { "n", "v" }, desc = "Generate Tests" },
      { "<leader>cd", "<cmd>CodeCompanionChat doc<cr>", mode = { "n", "v" }, desc = "Generate Docs" },
      { "<leader>cf", "<cmd>CodeCompanionToggle<cr>", desc = "Toggle Window" },
      { "<leader>ca", "<cmd>CodeCompanionActions<cr>", mode = { "n", "v" }, desc = "Show Actions" },
      { "ga", "<cmd>CodeCompanionChat Add<cr>", mode = "v", desc = "Add to Chat" },
    },
  },
}
