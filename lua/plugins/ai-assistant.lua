-- /home/bryan/.config/nvim/lua/plugins/ai-assistant.lua
return {
  {
    "ai_assistant", -- Name doesn't strictly matter with 'dir'
    dir = vim.fn.stdpath("config") .. "/lua/ai_assistant", -- Load from local directory
    event = "VeryLazy", -- Load lazily
    dependencies = {
      "kkharji/sqlite.lua", -- Required for enhanced code graph
    },
    config = function()
      require("ai_assistant").setup({
        default_model = "openai/gpt-4.1", -- Example override
        log_level = vim.log.levels.DEBUG, -- Add debug logging
        windows = { -- Example window overrides
          position = "left",
          width = 50,
          input_height = 3,
          display_border = "single",
          input_border = "double",
          input_prefix = "🤖 ",
        },
      })
    end,
  },
}
