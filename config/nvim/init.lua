vim.g.mapleader = " "
vim.g.maplocalleader = " "

vim.keymap.set({ "n", "v" }, "<Space>", "<Nop>", {
  silent = true,
})

require("config.options")
require("config.diagnostics")

require("plugins/mini")
require("plugins/mason")
require("plugins/treesitter")
require("plugins/blink")
require("plugins/conform")
require("plugins/git")
require("plugins/neogit")
require("plugins/diffview")
require("plugins/plantuml")

require("config.keymaps")

vim.lsp.enable({
  "basedpyright",
  "gopls",
  "ts_ls",
  "html",
  "cssls",
  "jsonls",
  "lua_ls",
  "jdtls",
  "zls",
})
