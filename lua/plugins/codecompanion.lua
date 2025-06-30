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
  {
    "olimorris/codecompanion.nvim",
    config = function()
      -- Available models configuration
      local available_models = {
        gemini = {
          "google/gemini-2.5-flash-preview-05-20",
          "google/gemini-2.5-flash-preview",
          "google/gemini-2.5-flash-preview-thinking",
          "google/gemini-2.5-flash",
          "google/gemini-2.5-pro",
        },
        openrouter = {
          "anthropic/claude-3.7-sonnet",
          "anthropic/claude-3.5-sonnet",
          "openai/o4-mini-high",
          "openai/gpt-4.1",
          "x-ai/grok-3-mini-beta",
          "deepseek/deepseek-chat-v3-0324",
          "openai/o3-mini-high",
        },
      }

      -- Current model selections
      local current_adapter = "openrouter"
      local current_models = {
        gemini = available_models.gemini[1],
        openrouter = available_models.openrouter[1],
      }

      -- Model selection function
      local function select_model()
        -- First select adapter
        vim.ui.select({ "gemini", "openrouter" }, {
          prompt = "Select Adapter:",
        }, function(adapter_choice)
          if not adapter_choice then
            return
          end
          current_adapter = adapter_choice

          -- Then select model for that adapter
          vim.ui.select(available_models[adapter_choice], {
            prompt = "Select Model for " .. adapter_choice .. ":",
          }, function(model_choice)
            if model_choice then
              current_models[adapter_choice] = model_choice
              vim.notify("Selected: " .. adapter_choice .. " / " .. model_choice, vim.log.levels.INFO)

              -- Update the configuration
              local codecompanion = require("codecompanion")
              codecompanion.setup({
                strategies = {
                  chat = {
                    adapter = current_adapter,
                  },
                  inline = {
                    adapter = current_adapter,
                  },
                },
              })
            end
          end)
        end)
      end

      -- Main setup
      require("codecompanion").setup({
        -- General options
        opts = {
          log_level = "ERROR", -- DEBUG for troubleshooting
          language = "English",
          send_code = true,
          use_default_actions = true,
          use_default_prompt_library = true,
        },

        -- Display settings
        display = {
          action_palette = {
            provider = "default", -- "telescope", "mini_pick" or "snacks"
          },
          chat = {
            show_settings = true,
            show_token_count = true,
            show_header_separator = true,
            auto_scroll = true,
            intro_message = "Welcome to CodeCompanion! Type your message below.",
            window = {
              layout = "vertical", -- "vertical", "horizontal", "float" or "buffer"
              width = 0.45,
              height = 0.8,
              border = "rounded",
              opts = {
                cursorcolumn = false,
                cursorline = false,
                number = false,
                relativenumber = false,
                signcolumn = "no",
                spell = false,
                wrap = true,
              },
            },
          },
          inline = {
            diff = {
              enabled = true,
              close_chat_at = 240, -- Close if more than 240 lines
            },
          },
        },

        -- Strategies configuration
        strategies = {
          chat = {
            adapter = "openrouter",
            roles = {
              llm = "CodeCompanion",
              user = "User",
            },
            slash_commands = {
              ["buffer"] = {
                opts = {
                  provider = "default", -- telescope or fzf
                  contains_code = true,
                },
              },
            },
            tools = {
              groups = {
                ["full_stack_dev"] = {
                  opts = {
                    collapse_tools = false,
                  },
                },
                ["files"] = {
                  opts = {
                    collapse_tools = false,
                  },
                },
              },
            },
          },
          inline = {
            adapter = "openrouter",
          },
        },

        -- Adapter configurations
        adapters = {
          -- Gemini adapter
          gemini = function()
            return require("codecompanion.adapters").extend("gemini", {
              env = {
                api_key = "GEMINI_API_KEY",
              },
              schema = {
                model = {
                  default = current_models.gemini,
                },
                temperature = {
                  default = 0.7,
                },
                max_tokens = {
                  default = 4096,
                },
              },
            })
          end,

          -- OpenRouter adapter (OpenAI compatible)
          openrouter = function()
            return require("codecompanion.adapters").extend("openai_compatible", {
              env = {
                url = "https://openrouter.ai",
                api_key = "OPENROUTER_API_KEY",
                chat_url = "/api/v1/chat/completions",
              },
              schema = {
                model = {
                  default = current_models.openrouter,
                },
                temperature = {
                  default = 0.7,
                },
                max_tokens = {
                  default = 4096,
                },
              },
              headers = {
                ["HTTP-Referer"] = "https://github.com/olimorris/codecompanion.nvim",
                ["X-Title"] = "CodeCompanion.nvim",
              },
            })
          end,
        },

        -- Extensions
        extensions = {
          mcphub = {
            callback = "mcphub.extensions.codecompanion",
            opts = {
              show_result_in_chat = true,
              make_vars = true,
              make_slash_commands = true,
            },
          },
          vectorcode = {
            opts = {
              add_tool = true,
            },
          },
        },

        -- Prompt library additions
        prompt_library = {
          ["Custom: Explain Code"] = {
            strategy = "chat",
            description = "Explain the selected code in detail",
            opts = {
              index = 10,
              is_default = true,
              is_slash_cmd = true,
              short_name = "explain",
            },
            prompts = {
              {
                role = "user",
                content = function(context)
                  local code = require("codecompanion.helpers.actions").get_code(context.start_line, context.end_line)
                  return "Please explain the following code in detail:\n\n```"
                    .. context.filetype
                    .. "\n"
                    .. code
                    .. "\n```"
                end,
              },
            },
          },
          ["Custom: Optimize Code"] = {
            strategy = "inline",
            description = "Optimize the selected code for performance",
            opts = {
              index = 11,
              is_default = true,
            },
            prompts = {
              {
                role = "user",
                content = function(context)
                  local code = require("codecompanion.helpers.actions").get_code(context.start_line, context.end_line)
                  return "Optimize this code for better performance:\n\n```"
                    .. context.filetype
                    .. "\n"
                    .. code
                    .. "\n```"
                end,
              },
            },
          },
        },
      })

      -- Keymaps
      vim.keymap.set({ "n", "v" }, "<leader>cc", "<cmd>CodeCompanion<cr>", { desc = "CodeCompanion" })
      vim.keymap.set({ "n", "v" }, "<leader>ca", "<cmd>CodeCompanionActions<cr>", { desc = "CodeCompanion Actions" })
      vim.keymap.set({ "n", "v" }, "<leader>ct", "<cmd>CodeCompanionChat Toggle<cr>", { desc = "Toggle Chat" })
      vim.keymap.set("v", "<leader>ce", "<cmd>CodeCompanionChat Add<cr>", { desc = "Add to Chat" })
      vim.keymap.set("n", "<leader>cp", select_model, { desc = "Select AI Model" })

      -- Additional convenience mappings
      vim.keymap.set("n", "<leader>cs", function()
        vim.cmd("CodeCompanion /selection")
      end, { desc = "Chat with selection" })

      vim.keymap.set("n", "<leader>cb", function()
        vim.cmd("CodeCompanion /buffer")
      end, { desc = "Chat with buffer" })

      vim.keymap.set("n", "<leader>cl", function()
        vim.cmd("CodeCompanion /lsp")
      end, { desc = "Chat with LSP" })

      -- Quick adapter switching
      vim.keymap.set("n", "<leader>cg", function()
        current_adapter = "gemini"
        require("codecompanion").setup({
          strategies = {
            chat = { adapter = "gemini" },
            inline = { adapter = "gemini" },
          },
        })
        vim.notify("Switched to Gemini adapter", vim.log.levels.INFO)
      end, { desc = "Switch to Gemini" })

      vim.keymap.set("n", "<leader>co", function()
        current_adapter = "openrouter"
        require("codecompanion").setup({
          strategies = {
            chat = { adapter = "openrouter" },
            inline = { adapter = "openrouter" },
          },
        })
        vim.notify("Switched to OpenRouter adapter", vim.log.levels.INFO)
      end, { desc = "Switch to OpenRouter" })

      -- Expand 'cc' into 'CodeCompanion' in the command line
      vim.cmd([[cab cc CodeCompanion]])
    end,

    dependencies = {
      "nvim-lua/plenary.nvim",
      "nvim-treesitter/nvim-treesitter",
    },
  },
}

