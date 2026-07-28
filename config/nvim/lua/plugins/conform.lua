vim.pack.add({
  {
    src = "https://github.com/stevearc/conform.nvim",
  },
})

require("conform").setup({
  formatters_by_ft = {
    go = { "gofmt" },
    python = { "ruff_format" },
    javascript = { "prettier" },
    typescript = { "prettier" },
    javascriptreact = { "prettier" },
    typescriptreact = { "prettier" },
    html = { "prettier" },
    css = { "prettier" },
    lua = { "stylua" },
    java = { "google-java-format" },
    zig = { "zigfmt" },
  },
  format_on_save = {
    timeout_ms = 500,
    lsp_format = "fallback",
  },
})
