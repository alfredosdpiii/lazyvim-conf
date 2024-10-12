return {
  {
    "numToStr/Navigator.nvim",
    lazy = false,
    config = function()
      require("Navigator").setup()
    end,
  },

  {
    "epwalsh/obsidian.nvim",
    lazy = false,
    config = function()
      local obs = require("obsidian")
      obs.setup({
        dir = "~/Documents/notes",
        completion = {
          nvim_cmp = true, -- if using nvim-cmp, otherwise set to false
        },
      })
    end,
  },
  {
    "hrsh7th/nvim-cmp",
    dependencies = { "epwalsh/obsidian.nvim" },
    ---@param opts cmp.ConfigSchema
    opts = function(_, opts)
      local cmp = require("cmp")
      opts.sources = cmp.config.sources(vim.list_extend(opts.sources, { { name = "obsidian" } }))
    end,
  },
  {
    "MeF0504/vim-pets",
    lazy = false,
    priority = 99999,
    config = function()
      vim.g.pets_default_pet = "cat"
      vim.g.pets_lifetime_enable = 0
      vim.g.pets_birth_enable = 0
      vim.g.pets_garden_width = 8
      vim.g.pets_garden_height = 8
      vim.cmd([[Pets cat Linux]])
      vim.cmd([[PetsJoin cat Biscuit]])
      vim.cmd([[PetsJoin cat Iggy]])
    end,
  },
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
  -- {
  --   "David-Kunz/gen.nvim",
  --   opts = {
  --     model = "mistral", -- The default model to use.
  --     display_mode = "split", -- The display mode. Can be "float" or "split".
  --     show_prompt = true, -- Shows the Prompt submitted to Ollama.
  --     show_model = true, -- Displays which model you are using at the beginning of your chat session.
  --     no_auto_close = true, -- Never closes the window automatically.
  --     init = function(options)
  --       pcall(io.popen, "ollama serve > /dev/null 2>&1 &")
  --     end,
  --     -- Function to initialize Ollama
  --     command = "curl --silent --no-buffer -X POST http://localhost:11434/api/generate -d $body",
  --     -- The command for the Ollama service. You can use placeholders $prompt, $model and $body (shellescaped).
  --     -- This can also be a lua function returning a command string, with options as the input parameter.
  --     -- The executed command must return a JSON object with { response, context }
  --     -- (context property is optional).
  --     list_models = "<function>", -- Retrieves a list of model names
  --     debug = false, -- Prints errors and the command which is run.
  --   },
  -- },
}
