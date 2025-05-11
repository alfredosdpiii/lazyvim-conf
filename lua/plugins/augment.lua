return {
  {
    "augmentcode/augment.vim",
    dependencies = {
      "nvim-lua/plenary.nvim",
      "MunifTanjim/nui.nvim",
    },
    config = function()
      -- Configure workspace folders to get the most out of Augment
      vim.g.augment_workspace_folders = {
        "~/Projects/puppetmaster/",
        "~/Projects/orchestrator/",
        "~/Projects/builder/",
        "~/.config/nvim/",
        -- Add more paths as needed
      }

      -- Disable default mappings
      vim.g.augment_disable_tab_mapping = false

      -- Custom keymaps with leader 'a'
      vim.keymap.set("n", "<leader>ac", ":Augment Chat<CR>", { noremap = true, silent = true, desc = "Augment chat" })
      vim.keymap.set(
        "n",
        "<leader>at",
        ":Augment chat-toggle<CR>",
        { noremap = true, silent = true, desc = "Augment Chat" }
      )
      vim.keymap.set(
        "n",
        "<leader>ae",
        ":AugmentExplain<CR>",
        { noremap = true, silent = true, desc = "Augment Explain" }
      )
      vim.keymap.set("n", "<leader>af", ":AugmentFix<CR>", { noremap = true, silent = true, desc = "Augment Fix" })
      vim.keymap.set(
        "n",
        "<leader>ar",
        ":AugmentRefactor<CR>",
        { noremap = true, silent = true, desc = "Augment Refactor" }
      )
      vim.keymap.set("n", "<leader>at", ":AugmentTest<CR>", { noremap = true, silent = true, desc = "Augment Test" })
    end,
  },
}
