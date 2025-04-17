return {
  {
    "yetone/avante.nvim",
    event = "VeryLazy",
    lazy = false,
    version = false, -- Never set this value to "*"! Never!
    opts = {
      provider = "openrouter",
      auto_suggestions_provider = "openrouter",
      cursor_applying_provider = "openrouter", -- Use Groq for applying in cursor planning mode

      -- Move ollama out of vendors to be a top-level config as recommended
      ollama = {
        endpoint = "http://127.0.0.1:11434", -- Note: no /v1 at the end
        model = "deepcoder",
      },

      -- Add RAG service configuration
      rag_service = {
        enabled = true, -- Set to true to enable RAG service
        host_mount = os.getenv("HOME"), -- Host mount path for the rag service
        provider = "openai", -- The provider to use for RAG service (e.g. openai or ollama)
        llm_model = "gpt-4o-mini", -- The LLM model to use for RAG service
        embed_model = "text-embedding-3-large", -- The embedding model to use for RAG service
        endpoint = "https://api.openai.com/v1", -- The API endpoint for RAG service
      },

      -- Enable cursor planning mode for better results with open-source models
      behaviour = {
        enable_cursor_planning_mode = true,
        auto_set_highlight_group = true,
        auto_set_keymaps = true,
        auto_apply_diff_after_generation = false,
        support_paste_from_clipboard = false,
        minimize_diff = true,
        enable_token_counting = true,
      },

      web_search_engine = {
        provider = "tavily", -- tavily, serpapi, searchapi, google, kagi, brave, or searxng
        proxy = nil, -- proxy support, e.g., http://127.0.0.1:7890
      },

      vendors = {
        deepseek = {
          __inherited_from = "openai", -- Use openai-like logic
          api_key_name = "DEEPSEEK_API_KEY",
          endpoint = "https://api.deepseek.com",
          model = "deepseek-reasoner",
        },
        openrouter = {
          __inherited_from = "openai",
          api_key_name = "OPENROUTER_API_KEY",
          endpoint = "https://openrouter.ai/api/v1",
          model = "openai/gpt-4.1-mini",
        },
        architect = {
          __inherited_from = "openai",
          api_key_name = "OPENROUTER_API_KEY",
          endpoint = "https://openrouter.ai/api/v1",
          model = "openai/o3-mini",
        },
        groq = {
          __inherited_from = "openai",
          api_key_name = "GROQ_API_KEY",
          endpoint = "https://api.groq.com/openai/v1",
          model = "llama-3.3-70b-versatile", -- Updated to recommended model for cursor planning
          max_completion_tokens = 32768, -- Increased as recommended for cursor planning mode
        },
        perplexity = {
          __inherited_from = "openai",
          api_key_name = "PERPLEXITY_API_KEY",
          endpoint = "https://api.perplexity.ai",
          model = "sonar-deep-research",
        },
      },

      dual_boost = {
        enabled = false,
        first_provider = "architect",
        second_provider = "perplexity",
        prompt = [[
        You are an AI assistant specialized in synthesizing expert inputs to create production-ready code solutions. You will receive two distinct inputs:

1.  **Architect's Plan (`provider1_output`):** This input comes from an AI focused on reasoning, code structure, architectural patterns, potential algorithms, and implementation strategies. It outlines *how* a solution could be built conceptually.
2.  **Researcher's Findings (`provider2_output`):** This input comes from an AI (`sonar-deep-research`) skilled in retrieving current, factual information. It provides relevant documentation, API details, version compatibility, community best practices, known issues, security considerations, and real-world examples based on search results. It provides the *what* and *why* based on authoritative sources.

**Your Task:**
Combine the strategic plan from the Architect with the factual grounding from the Researcher to generate a comprehensive, accurate, and practical solution.

**Synthesis Process:**
<think>
1.  **Understand the Core Request:** Identify the user's underlying problem or goal.
2.  **Analyze Architect's Plan (`provider1_output`):** Evaluate the proposed structure, logic, and high-level design. Note the key steps and potential trade-offs identified.
3.  **Integrate & Validate with Researcher's Findings (`provider2_output`):**
    * Use the factual data (APIs, versions, docs) to refine and concretize the Architect's plan.
    * Verify the Architect's assumptions against the latest information.
    * Incorporate specific code snippets, library recommendations, or configuration details provided by the Researcher.
    * Address any potential issues, security warnings, or performance patterns highlighted by the Researcher.
4.  **Construct the Final Solution:** Synthesize the validated plan and factual details into a cohesive, actionable response. Resolve any conflicts, prioritizing the Researcher's factual data for accuracy while leveraging the Architect's structure.
5.  **Format the Output:** Present the solution clearly according to the required format.
</think>

**RESPONSE FORMAT:**

1.  **Quick Implementation:**
    * Minimal working code addressing the core requirement.
    * Highlight key libraries/APIs used.
    * Mention essential configuration or setup.
    * *Source/Version Info (from Researcher's findings)*

2.  **Full Solution:**
    * Complete, runnable code example.
    * Robust error handling.
    * Relevant tests (unit, integration ideas).
    * Security considerations addressed.
    * Performance notes and potential optimizations.
    * *References (links to docs, relevant discussions from Researcher's findings)*

3.  **Context & Rationale:**
    * Explanation of key design choices made during synthesis.
    * Potential pitfalls or common mistakes to avoid (informed by both inputs).
    * Alternative approaches considered and why the chosen one is preferred.
    * Maintenance and scalability considerations.

**Guiding Principles:**
* **Prioritize Factual Accuracy:** Rely on the Researcher (`provider2_output`) for specific details like API usage, versions, and documented facts.
* **Leverage Architectural Structure:** Use the Architect's plan (`provider1_output`) as a blueprint for the solution's design and logic, but adapt it based on factual research.
* **Generate Actionable Code:** Provide code that is as close to production-ready as possible.
* **Explain Your Synthesis:** Briefly clarify how the two inputs were combined, especially if there were discrepancies.
* **Be Comprehensive:** Ensure error handling, security, and maintainability are considered.

Architect's Plan: [{{provider1_output}}]
Researcher's Findings: [{{provider2_output}}]

Now, generate the synthesized response based on the user's request and the provided inputs.
        ]],
      },
    },
    build = "make",
    dependencies = {
      "stevearc/dressing.nvim",
      "nvim-lua/plenary.nvim",
      "MunifTanjim/nui.nvim",
      -- optional dependencies
      "echasnovski/mini.pick",
      "nvim-telescope/telescope.nvim",
      "hrsh7th/nvim-cmp",
      "ibhagwan/fzf-lua",
      "nvim-tree/nvim-web-devicons",
      "zbirenbaum/copilot.lua", -- if you'd like to try auto-suggestions from copilot
      {
        "HakonHarnes/img-clip.nvim",
        event = "VeryLazy",
        opts = {
          default = {
            embed_image_as_base64 = false,
            prompt_for_file_name = false,
            drag_and_drop = {
              insert_mode = true,
            },
            -- use_absolute_path = true,
          },
        },
      },
      {
        "MeanderingProgrammer/render-markdown.nvim",
        opts = {
          file_types = { "markdown", "Avante" },
        },
        ft = { "markdown", "Avante" },
      },
    },
  },
}
