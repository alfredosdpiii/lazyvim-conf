return {
  {
    "huggingface/llm.nvim",
    lazy = false,
    priority = 1000,
    opts = {
      backend = "ollama",
      model = "qwen2.5-coder:3b",
      url = "http://localhost:11434/api/generate",
      accept_keymap = "<C-a>",
      lsp = {
        bin_path = vim.api.nvim_call_function("stdpath", { "data" }) .. "/.local/share/nvim/mason/bin/llm-ls",
      },
      dismiss_keymap = "<C-n>",
      context_window = 32768, -- Qwen supports up to 128K tokens
      tokenizer = {
        repository = "Qwen/Qwen2.5-0.5B", -- Explicitly set the tokenizer repository
      },
      fim = {
        enabled = true,
        prefix = "<|fim_prefix|>",
        middle = "<|fim_middle|>",
        suffix = "<|fim_suffix|>",
      },
      request_body = {
        options = {
          temperature = 0.7, -- Optimal value for qwen2.5-coder
          top_p = 0.8, -- Recommended for code generation
          top_k = 40, -- Default for Qwen models
          num_ctx = 32768, -- Maximum context window (supports up to 128K tokens)
          repeat_penalty = 1.05, -- Prevents repetition
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
        "<|endoftext|>",
        "<|fim_prefix|>", -- Qwen special tokens
        "<|fim_middle|>",
        "<|fim_suffix|>",
        "<|fim_pad|>",
        "<|repo_name|>",
        "<|file_sep|>",
        "<|im_start|>",
        "<|im_end|>",
      },
      error = function(err)
        vim.notify(err, vim.log.levels.ERROR)
        return nil
      end,
    },
  },
}
