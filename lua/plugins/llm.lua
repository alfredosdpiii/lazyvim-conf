return {
  {
    "huggingface/llm.nvim",
    lazy = false,
    opts = {
      enable_suggestions_on_startup = true,
      enable_suggestions_on_files = "*",
      debounce_ms = 150,
      accept_keymap = "<Tab>",
      dismiss_keymap = "<S-Tab>",
      tls_skip_verify_insecure = false,
      backend = "ollama", -- backend ID, "huggingface" | "ollama" | "openai" | "tgi"
      url = "http://localhost:11434/api/generate", -- the http url of the backend
      tokens_to_clear = { "<|endoftext|>" }, -- tokens to remove from the model's output
      lsp = {
        bin_path = vim.api.nvim_call_function("stdpath", { "data" }) .. "/.local/share/nvim/mason/bin/llm-ls",
      },
      model = "starcoder2:15b", -- the model ID, behavior depends on backend
      -- request_body = {
      -- Modelfile options for the model you use
      -- options = {
      --   temperature = 0.2,
      --   top_p = 0.95,
      -- },
      -- },
      tokenizer = {
        repository = "bigcode/starcoder2-15b",
      },
    },
  },
}
