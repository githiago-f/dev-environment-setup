vim.pack.add({
  {
    src = "https://github.com/nvim-treesitter/nvim-treesitter",
    version = "v0.10.0",
  },
})

require("nvim-treesitter.configs").setup({
  ensure_installed = {
    "go",
    "gomod",
    "gosum",
    "gowork",
    "python",
    "javascript",
    "typescript",
    "tsx",
    "html",
    "css",
    "json",
    "yaml",
    "toml",
    "lua",
    "zig",
    "java",
    "bash",
    "markdown",
    "markdown_inline",
    "vim",
    "vimdoc",
  },
  auto_install = true,
  highlight = { enable = true },
  indent = { enable = true },
})
