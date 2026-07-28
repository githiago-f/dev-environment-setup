return {
  cmd = { "gopls" },
  root_markers = { "go.mod", "go.sum", ".git" },
  filetypes = { "go", "gomod", "gosum", "gowork" },
  settings = {
    gopls = {
      completeUnimported = true,
      usePlaceholders = true,
      analyses = {
        unusedparams = true,
      },
    },
  },
}
