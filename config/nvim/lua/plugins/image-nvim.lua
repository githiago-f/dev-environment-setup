vim.pack.add({ "https://github.com/3rd/image.nvim" })

require("image").setup({
  backend = "kitty",
  processor = "magick_cli"
})
