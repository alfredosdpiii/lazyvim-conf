return {
  {
    "nvim-telescope/telescope.nvim",
    dependencies = {
      "nvim-lua/plenary.nvim",
      "nvim-telescope/telescope-ui-select.nvim", -- add this dependency
      -- other dependencies
    },
    config = function()
      local actions = require("telescope.actions")
      require("telescope").setup({
        defaults = {
          mappings = {
            i = {
              ["<esc>"] = actions.close,
            },
          },
        },
        extensions = {
          ["ui-select"] = require("telescope.themes").get_dropdown({
            winblend = 30,
            border = false,
            previewer = false,
            prompt_prefix = "  ",
            layout_strategy = "cursor",
            layout_config = {
              width = 35,
              height = 7,
            },
          }),
        },
      })
      require("telescope").load_extension("ui-select")
    end,
  },
  {
    "nvim-telescope/telescope.nvim",
    lazy = false,
    config = function()
      local actions = require("telescope.actions")
      require("telescope").setup({
        defaults = {
          mappings = {
            i = {
              ["<esc>"] = actions.close,
            },
          },
        },
        extensions = {
          ["ui-select"] = {
            require("telescope.themes").get_dropdown({
              winblend = 30,
              border = false,
              previewer = false,
              prompt_prefix = "  ",
              layout_strategy = "cursor",
              layout_config = {
                width = 35,
                height = 7,
              },
            }),
          },
        },
        pickers = {
          tags = {},
          lsp_references = {
            show_line = false,
            trim_text = false,
            include_declaration = true,
            include_current_line = true,
            theme = "dropdown",
            layout_strategy = "horizontal",
            layout_config = {
              horizontal = {
                prompt_position = "top",
                prompt_height = 1,
                results_height = 10,
                preview_width = 0.7,
                width = 0.9,
                height = 0.9,
              },
            },
          },
          git_files = {
            fname_width = 0,
            layout_config = {
              horizontal = {
                prompt_position = "top",
                preview_width = 0.7,
                width = 0.9,
                height = 0.9,
              },
            },
          },
          find_files = {
            fname_width = 0,
            layout_config = {
              horizontal = {
                prompt_position = "top",
                preview_width = 0.7,
                width = 0.9,
                height = 0.9,
              },
            },
          },
          lsp_document_symbols = {
            fname_width = 0,
            symbol_width = 100,
            symbol_type_width = 0,
            symbol_line = false,
            layout_config = {
              horizontal = {
                prompt_position = "top",
                preview_width = 0.7,
                width = 0.9,
                height = 0.9,
              },
            },
          },
          lsp_workspace_symbols = {
            fname_width = 0,
            symbol_width = 100,
            symbol_type_width = 0,
            symbol_line = false,
            layout_config = {
              horizontal = {
                preview_width = 0.5,
                width = 0.9,
                height = 0.9,
              },
            },
          },
        },
      })
      require("telescope").load_extension("ui-select")
    end,
  },
}
