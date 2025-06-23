-- lua/plugins/render-markdown.lua
return {
  'MeanderingProgrammer/render-markdown.nvim',
  opts = {
    -- Add AIChat to the list of filetypes it should render
    file_types = { "markdown", "AIChat" },
  },
  -- Optionally lazy load it on the filetype
  ft = { "markdown", "AIChat" },
}
