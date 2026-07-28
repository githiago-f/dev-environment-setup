vim.pack.add({
    {
        src = "https://github.com/nvim-mini/mini.nvim",
        version = "stable",
    },
})

require("mini.icons").setup()
require("mini.ai").setup()
require("mini.pick").setup()
require("mini.basics").setup()
require("mini.statusline").setup()
require("mini.comment").setup()
require("mini.pairs").setup()
require("mini.surround").setup()
require("mini.files").setup()
require("mini.clue").setup({
  triggers = {
    { mode = "n", keys = "<Leader>" },
    { mode = "x", keys = "<Leader>" },
    { mode = "n", keys = "<Leader>g" },
    { mode = "x", keys = "<Leader>g" },
  },

  clues = {
    require("mini.clue").gen_clues.builtin_completion(),
    require("mini.clue").gen_clues.g(),
    require("mini.clue").gen_clues.marks(),
    require("mini.clue").gen_clues.registers(),
    require("mini.clue").gen_clues.windows(),
    require("mini.clue").gen_clues.z(),
  },

  window = {
    delay = 300,
  },
})
require("mini.tabline").setup({
    show_icons = true,
    tabpage_section = "left",
})
