vim.pack.add({ "https://github.com/githiago-f/plantuml.nvim" })

vim.keymap.set("n", "<leader>puml", "<cmd>PlantumlPreviewToggle<CR>", {
  desc = "Toggle PlantUML preview",
})
