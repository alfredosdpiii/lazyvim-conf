-- lua/plugins/code_ai.lua
return {

  -- 🧠 MCPHub ---------------------------------------------------------
  {
    "ravitemer/mcphub.nvim",
    lazy = false, -- ensure runtimepath
    build = "npm install -g mcp-hub@latest",
    config = function()
      require("mcphub").setup({
        extensions = {
          codecompanion = {
            show_result_in_chat = true,
            make_vars = true,
            make_slash_commands = true,
          },
        },
      })
    end,
  },
  {
    "Davidyz/VectorCode",
    version = "*", -- optional, depending on whether you're on nightly or release
    build = "uv pip install --system vectorcode", -- optional but recommended. This keeps your CLI up-to-date.
    dependencies = { "nvim-lua/plenary.nvim" },
  },

  -- 💬 CodeCompanion --------------------------------------------------
  --
  {
    "olimorris/codecompanion.nvim",
    config = function()
      local default_model = "x-ai/grok-3-mini-beta"
      local available_models = {
        "google/gemini-2.5-flash-preview",
        "google/gemini-2.5-flash-preview-thinking",
        "google/gemini-2.5-pro-exp-03-25",
        "anthropic/claude-3.7-sonnet",
        "anthropic/claude-3.5-sonnet",
        "openai/o4-mini-high",
      }
      local current_model = default_model

      local function select_model()
        vim.ui.select(available_models, {
          prompt = "Select  Model:",
        }, function(choice)
          if choice then
            current_model = choice
            vim.notify("Selected model: " .. current_model)
          end
        end)
      end

      require("codecompanion").setup({
        strategies = {
          chat = {
            adapter = "openrouter",
          },
          inline = {
            adapter = "openrouter",
          },
        },
        adapters = {
          openrouter = function()
            return require("codecompanion.adapters").extend("openai_compatible", {
              env = {
                url = "https://openrouter.ai/api",
                api_key = "OPENROUTER_API_KEY",
                chat_url = "/v1/chat/completions",
              },
              schema = {
                model = {
                  default = current_model,
                },
              },
            })
          end,
        },
        extensions = {
          mcphub = {
            callback = "mcphub.extensions.codecompanion",
            opts = {
              show_result_in_chat = true, -- Show mcp tool results in chat
              make_vars = true, -- Convert resources to #variables
              make_slash_commands = true, -- Add prompts as /slash commands
            },
          },
          vectorcode = {
            opts = {
              add_tool = true,
            },
          },
        },
      })

      vim.keymap.set({ "n", "v" }, "<leader>ck", "<cmd>CodeCompanionActions<cr>", { noremap = true, silent = true })
      vim.keymap.set({ "n", "v" }, "<leader>ct", "<cmd>CodeCompanionChat Toggle<cr>", { noremap = true, silent = true })
      vim.keymap.set("v", "ga", "<cmd>CodeCompanionChat Add<cr>", { noremap = true, silent = true })

      vim.keymap.set("n", "<leader>cm", select_model, { desc = "Select Gemini Model" })
      -- Expand 'cc' into 'CodeCompanion' in the command line
      vim.cmd([[cab cc CodeCompanion]])
    end,

    dependencies = {
      "nvim-lua/plenary.nvim",
      "nvim-treesitter/nvim-treesitter",
    },
  },
}
