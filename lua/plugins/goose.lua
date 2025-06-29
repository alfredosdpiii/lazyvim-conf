return {
  {
    "azorng/goose.nvim",
    branch = "main",
    config = function()
      require("goose").setup({
        keymap = {
          global = {
            toggle = "<leader>gp", -- Open goose. Close if opened
          },
        },
      })
    end,
    dependencies = {
      "nvim-lua/plenary.nvim",
      {
        "MeanderingProgrammer/render-markdown.nvim",
        opts = {
          anti_conceal = { enabled = false },
        },
      },
    },
  },
}
