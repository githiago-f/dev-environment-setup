require("mini.git").setup({
  options = {
    execute = { async = true },
  },
})

require("mini.diff").setup({
  view = {
    style = "sign",
    signs = {
      add = "+",
      change = "~",
      delete = "_",
    },
  },
  mappings = {
    apply = "<leader>hs",
    reset = "<leader>hr",
    goto_prev = "[h",
    goto_next = "]h",
  },
})
