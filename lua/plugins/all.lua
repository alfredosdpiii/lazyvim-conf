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
    lazy = true,
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
}
