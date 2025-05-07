return {
  {
    "crspeller/aider-nvim",
    cmd = {
      "Aider",
      "AiderAddFile",
      "AiderDropFile",
      "AiderDropAll",
      "AiderClear",
      "AiderCodeSearch",
      "AiderIndexCode",
    },
    keys = {
      { "<leader>ic", ":Aider<CR>", desc = "Aider: open chat" },
      { "<leader>ia", ":AiderAddFile<CR>", desc = "Aider: add file" },
      { "<leader>id", ":AiderDropFile<CR>", desc = "Aider: drop file" },
      { "<leader>ir", ":AiderClear<CR>", desc = "Aider: clear context" },
      { "<leader>is", ":AiderCodeSearch<CR>", desc = "Aider: open with codesearch results" },
      { "<leader>ii", ":AiderIndexCode<CR>", desc = "Aider: index codebase" },
    },
    opts = {
      terminal_height = 15,
      command = "aider",
    },
    config = function(_, opts)
      require("aider-nvim").setup(opts)
      vim.keymap.set("t", "<Esc>", [[<C-\><C-n>]], { noremap = true, silent = true })

      vim.api.nvim_create_user_command("AiderCodeSearch", function()
        local regex = vim.fn.input("Regex pattern: ")
        if regex == "" then
          return
        end
        local files = vim.fn.systemlist("csearch -l " .. vim.fn.shellescape(regex))
        if #files == 0 then
          print("No files found matching pattern")
          return
        end
        local file_args = table.concat(
          vim.tbl_map(function(file)
            return "--file " .. vim.fn.shellescape(file)
          end, files),
          " "
        )
        local cmd = "aider " .. file_args
        vim.cmd(string.format("belowright %dsplit | terminal %s", opts.terminal_height, cmd))
      end, { nargs = 0 })

      vim.api.nvim_create_user_command("AiderIndexCode", function()
        local dir = vim.fn.getcwd()
        vim.cmd("!cindex " .. vim.fn.shellescape(dir))
      end, { nargs = 0 })
    end,
  },
}
