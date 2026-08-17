vim.pack.add({ "https://github.com/githiago-f/plantuml.nvim" })
vim.pack.add({ "https://github.com/aklt/plantuml-syntax" })

vim.cmd.packadd("plantuml-syntax")

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

-- Toggle preview
vim.keymap.set("n", "<leader>puml", "<cmd>PlantumlPreviewToggle<CR>", {
	desc = "Toggle PlantUML preview",
})

-- Cycle through diagrams (multi-diagram files)
vim.keymap.set("n", "<leader>pun", "<cmd>PlantumlPreviewNext<CR>", {
	desc = "Next PlantUML diagram",
})
vim.keymap.set("n", "<leader>pup", "<cmd>PlantumlPreviewPrev<CR>", {
	desc = "Previous PlantUML diagram",
})

-- Zoom the preview image
vim.keymap.set("n", "<leader>pzi", "<cmd>PlantumlPreviewZoomIn<CR>", {
	desc = "Zoom in PlantUML preview",
})
vim.keymap.set("n", "<leader>pzo", "<cmd>PlantumlPreviewZoomOut<CR>", {
	desc = "Zoom out PlantUML preview",
})

-- Pan the focused viewport while zoomed in
vim.keymap.set("n", "<leader>puu", "<cmd>PlantumlPreviewPanUp<CR>", {
	desc = "Pan PlantUML preview up",
})
vim.keymap.set("n", "<leader>pud", "<cmd>PlantumlPreviewPanDown<CR>", {
	desc = "Pan PlantUML preview down",
})
vim.keymap.set("n", "<leader>pul", "<cmd>PlantumlPreviewPanLeft<CR>", {
	desc = "Pan PlantUML preview left",
})
vim.keymap.set("n", "<leader>pur", "<cmd>PlantumlPreviewPanRight<CR>", {
	desc = "Pan PlantUML preview right",
})
