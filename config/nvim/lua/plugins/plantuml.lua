vim.pack.add({ "https://github.com/githiago-f/plantuml.nvim" })
vim.pack.add({ "https://github.com/aklt/plantuml-syntax" })

require("plantuml").setup({
  output = { format = "png", float = false },
  cmd = {
    exec = "plantuml",
    debounce_ms = 2500,
    temp_dir = "/tmp/nvim-puml",
  },
})

vim.keymap.set("n", "<leader>puml", "<cmd>PlantumlPreviewToggle<CR>", {
  desc = "Toggle PlantUML preview",
})
