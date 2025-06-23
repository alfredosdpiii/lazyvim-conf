# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Architecture Overview

This is a LazyVim-based Neovim configuration optimized for AI-assisted development workflows. The configuration heavily emphasizes AI tools and modern plugin management while maintaining LazyVim's structured approach.

### Core Structure
- **Entry Point**: `init.lua` → loads `config.lazy`
- **Plugin Management**: `lua/config/lazy.lua` bootstraps lazy.nvim and defines plugin specs
- **Configuration**: `lua/config/` contains options, keymaps, autocmds
- **Custom Plugins**: `lua/plugins/` contains plugin-specific configurations
- **Custom LSP**: `iwes` LSP automatically starts for Markdown files with `.iwe` root

### Key Configuration Patterns
- Custom plugins use `lazy = false` by default (immediate loading)
- Plugin configurations follow lazy.nvim specification format
- Multi-plugin files (like `all.lua`) contain multiple related plugins
- Heavy use of terminal splits for external AI tools

## AI Development Workflow

This configuration is built around AI-assisted development with multiple providers:

### RA.Aid Integration (Primary AI Tool)
RA.Aid commands are extensively configured in `autocmds.lua` with optimized model pairings:
- **Default Stack**: openai/o4-mini-high (primary) + openai/gpt-4.1 (expert)
- **Budget Stack**: deepseek/deepseek-chat-v3-0324 + openai/o4-mini-high
- **Latency Stack**: openai/gpt-4.1-nano + openai/o3-mini-high

**Key Commands**:
- `:RAIDCowboy` - Quick edits with no approvals
- `:RAIDCodebase` - Research-only analysis mode  
- `:RAIDCoder` - Aider integration for refactoring
- `:RAIDChat` - Interactive chat mode
- `:RAIDPlainChat` - Chat with current buffer content
- `:RAIDAiderOpen` - Open/reattach Aider session

### Other AI Tools
- **Avante**: Advanced AI coding assistant with multiple providers
- **CodeCompanion**: AI chat interface with model selection
- **Claude Code**: Terminal-based Claude integration (you!)

## Development Commands

### Code Quality
```bash
# Format Lua code
stylua . --config-path stylua.toml
```

### AI Tool Integration
```bash
# RA.Aid with custom model pairing
ra-aid --provider openrouter --model openai/o4-mini-high --expert-provider openrouter --expert-model openai/gpt-4.1

# Iwes LSP for Markdown (auto-starts)
iwes

# OpenCode terminal integration
opencode .
```

### Git Workflow
- Harpoon for file navigation
- Lazygit integration (`:Lazygit`)
- Git worktree management
- Diffview for reviewing changes

## Key Configuration Files

### lua/config/lazy.lua
- Bootstraps lazy.nvim plugin manager
- Loads LazyVim core with selective extras (DAP, Tailwind)
- Sets `lazy = false` default for custom plugins
- Configures performance optimizations

### lua/config/autocmds.lua
- Extensive RA.Aid command definitions with model configurations
- Custom LSP setup for Markdown files
- Augment signin helper with URL capture
- OpenCode terminal integration

### lua/plugins/
Plugin configurations follow lazy.nvim spec:
```lua
return {
  {
    "author/plugin-name",
    lazy = false,
    dependencies = { "required-plugin" },
    config = function()
      require("plugin-name").setup({})
    end,
    keys = {
      { "<leader>x", "<cmd>Command<cr>", desc = "Description" },
    },
  },
}
```

## External Dependencies

Required tools for full functionality:
- `ra-aid` - Primary AI development assistant
- `iwes` - Custom LSP for Markdown
- `opencode` - Code exploration tool
- `stylua` - Lua formatter
- `claude` - Claude Code CLI (terminal integration)

## Model Configuration

AI providers are configured via environment variables and support multiple fallbacks:
- OpenRouter (primary)
- DeepSeek (budget option)
- Local models via Ollama
- Various OpenAI models for different use cases

The configuration prioritizes cost-efficiency while maintaining high code quality through expert model validation.