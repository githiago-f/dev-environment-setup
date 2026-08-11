return {
  cmd = { vim.fn.expand("~/.local/share/coursier/bin/metals") },
  filetypes = { "scala", "sbt" },
  root_markers = { "build.sbt", "build.sc", "build.gradle", "pom.xml", "mill", ".metals", ".git" },
  init_options = {
    statusBarProvider = "show-message",
    isHttpEnabled = true,
    compilerOptions = {
      snippetAutoIndent = false,
    },
  },
  capabilities = {
    workspace = {
      configuration = false,
    },
  },
}
