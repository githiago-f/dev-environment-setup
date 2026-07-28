return {
  cmd = { "basedpyright-langserver", "--stdio" },
  root_markers = { "pyproject.toml", "setup.py", "setup.cfg", "requirements.txt", ".git" },
  filetypes = { "python" },
  settings = {
    basedpyright = {
      analysis = {
        typeCheckingMode = "standard",
      },
    },
  },
}
