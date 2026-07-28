vim.pack.add({
  {
    src = "https://github.com/nvim-lua/plenary.nvim",
  },
  {
    src = "https://github.com/NeogitOrg/neogit",
    version = "v3.0.0",
  },
})

require("neogit").setup({
  disable_signs = false,
  disable_context_highlighting = false,
  disable_commit_conflict = false,
  integrations = {
    diffview = true,
  },
})
