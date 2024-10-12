return {
  {
    "olimorris/codecompanion.nvim",
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
              -- Configure Ollama settings here
              schema = {
                model = {
                  default = "llama3.1", -- or any other model you prefer
                },
              },
            })
          end,
        },
        strategies = {
          chat = {
            adapter = "ollama",
          },
          inline = {
            adapter = "ollama",
          },
          agent = {
            adapter = "ollama",
          },
        },
      })
    end,
    keys = {
      { "<leader>cb", "<cmd>CodeCompanionChat<cr>", desc = "CodeCompanion Chat" },
      { "<leader>cf", "<cmd>CodeCompanionToggle<cr>", desc = "CodeCompanion Toggle" },
      { "<leader>cg", "<cmd>CodeCompanionActions<cr>", mode = { "n", "v" }, desc = "CodeCompanion Actions" },
      { "ga", "<cmd>CodeCompanionChat Add<cr>", mode = "v", desc = "CodeCompanion Add to Chat" },
    },
  },
}
