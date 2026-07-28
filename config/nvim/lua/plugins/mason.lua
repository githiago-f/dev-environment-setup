vim.pack.add({
  {
    src = "https://github.com/williamboman/mason.nvim",
    version = "stable",
  },
})

require("mason").setup({
  ui = {
    border = "rounded",
    icons = {
      package_installed = "✓",
      package_pending = "➜",
      package_uninstalled = "✗",
    },
  },
})

local servers = {
  "basedpyright",
  "gopls",
  "typescript-language-server",
  "html-lsp",
  "css-lsp",
  "json-lsp",
  "lua-language-server",
  "jdtls",
  "zls",
  "prettier",
  "stylua",
  "ruff",
  "google-java-format",
}

local registry = require("mason-registry")
for _, name in ipairs(servers) do
  local ok, package = pcall(registry.get_package, name)
  if ok and not package:is_installed() then
    package:install()
  end
end
