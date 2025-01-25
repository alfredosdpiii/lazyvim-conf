return {
  {
    "numToStr/Navigator.nvim",
    lazy = false,
    config = function()
      require("Navigator").setup()
    end,
  },
  -- {
  --   "MeF0504/vim-pets",
  --   lazy = false,
  --   priority = 99999,
  --   config = function()
  --     vim.g.pets_default_pet = "cat"
  --     vim.g.pets_lifetime_enable = 0
  --     vim.g.pets_birth_enable = 0
  --     vim.g.pets_garden_width = 8
  --     vim.g.pets_garden_height = 8
  --     vim.cmd([[Pets cat Linux]])
  --     vim.cmd([[PetsJoin cat Biscuit]])
  --     vim.cmd([[PetsJoin cat Iggy]])
  --   end,
  -- },
  {
    "tpope/vim-dadbod",
    lazy = false,
  },

  {
    "kristijanhusak/vim-dadbod-ui",
    lazy = false,
  },
  {
    "kdheepak/lazygit.nvim",
    config = function()
      vim.g.lazygit_floating_window_scaling_factor = 1
    end,
  },
  {
    "ThePrimeagen/harpoon",
    lazy = false,
    dependencies = {
      "nvim-lua/plenary.nvim",
    },
    config = true,
    keys = {
      { "<leader>hm", "<cmd>lua require('harpoon.mark').add_file()<cr>", desc = "Mark file with harpoon" },
      { "<leader>hn", "<cmd>lua require('harpoon.ui').nav_next()<cr>", desc = "Go to next harpoon mark" },
      { "<leader>hp", "<cmd>lua require('harpoon.ui').nav_prev()<cr>", desc = "Go to previous harpoon mark" },
      { "<leader>ha", "<cmd>lua require('harpoon.ui').toggle_quick_menu()<cr>", desc = "Show harpoon marks" },
    },
  },
  {
    "ThePrimeagen/git-worktree.nvim",
    lazy = false,
    config = function()
      require("git-worktree").setup()
    end,
    keys = {
      {
        "<leader>gt",
        "<CMD>lua require('telescope').extensions.git_worktree.git_worktrees()<CR>",
        desc = "Show Worktrees",
      },
      {
        "<leader>gT",
        "<CMD>lua require('telescope').extensions.git_worktree.create_git_worktree()<CR>",
        desc = "Add Worktree",
      },
    },
  },
  {
    "olimorris/codecompanion.nvim",
    lazy = false,
    dependencies = {
      "nvim-lua/plenary.nvim",
      "nvim-treesitter/nvim-treesitter",
    },
    config = function()
      require("codecompanion").setup({
        adapters = {
          chat = require("codecompanion.adapters").extend(
            "ollama",
            { schema = { model = { default = "deepseek-r1:8b" } } }
          ),
          inline = require("codecompanion.adapters").extend(
            "ollama",
            { schema = { model = { default = "deepseek-r1:8b" } } }
          ),
        },
      })
    end,
  },
}
