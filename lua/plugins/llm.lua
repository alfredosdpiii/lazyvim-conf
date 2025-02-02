return {
  {
    "huggingface/llm.nvim",
    lazy = false,
    priority = 1000,
    opts = {
      backend = "ollama",
      model = "deepseek-r1:1.5b",
      url = "http://localhost:11434/api/generate",
      accept_keymap = "<C-a>",
      lsp = {
        bin_path = vim.api.nvim_call_function("stdpath", { "data" }) .. "/.local/share/nvim/mason/bin/llm-ls",
      },
      dismiss_keymap = "<C-n>",
      request_body = {
        stop = { "\n```", "</code>", "</think>" }, -- Stop tokens for code and thinking blocks
        options = {
          temperature = 0.2, -- Slightly higher for better reasoning
          top_p = 0.3, -- More focused selection
          top_k = 30, -- Tighter token choices
          num_ctx = 4096, -- Larger context for reasoning
          repeat_penalty = 1.2, -- Stronger repetition prevention
          seed = 42, -- Keep responses consistent
        },
      },
      tokens_to_clear = {
        "Let me analyze", -- Remove common prefixes
        "I'm thinking about",
        "Let's examine",
        "Based on the",
        "Looking at",
        "<think>", -- Remove thinking markers
        "</think>",
        "<code>", -- Remove code markers
        "</code>",
        "\n```",
      },
      callbacks = {
        response_post = function(response)
          -- Enhanced response cleaning
          response = response:gsub("^%s+", "") -- Leading whitespace
          response = response:gsub("%s+$", "") -- Trailing whitespace
          response = response:gsub("```%w*\n?", "") -- Code fences
          response = response:gsub("<think>.*</think>", "") -- Remove thinking blocks
          response = response:gsub("%s*\n%s*\n%s*\n", "\n\n") -- Excess newlines
          return response
        end,
        error = function(err)
          vim.notify(err, vim.log.levels.ERROR)
          return nil
        end,
      },
    },
  },
}
