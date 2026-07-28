vim.pack.add({
  {
    src = "https://github.com/saghen/blink.cmp",
    version = "v1.10.2",
  },
})

require("blink.cmp").setup({
  keymap = {
    preset = "default",
  },
  sources = {
    default = { "lsp", "path", "snippets", "buffer" },
  },
  completion = {
    documentation = {
      auto_show = true,
      window = { border = "rounded" },
    },
    menu = {
      border = "rounded",
    },
  },
  signature = {
    enabled = true,
    window = { border = "rounded" },
  },
})
