return {
  {
    "0xrusowsky/nvim-ctx-ingest",
    dependencies = {
      "nvim-web-devicons", -- required for file icons
    },
    config = function()
      require("nvim-ctx-ingest").setup({
        -- your config options here
      })
    end,
  },
}
