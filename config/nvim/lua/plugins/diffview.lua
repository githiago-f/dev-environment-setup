vim.pack.add({
  {
    src = "https://github.com/sindrets/diffview.nvim",
  },
})

require("diffview").setup({
  enhanced_diff_hl = true,
  show_help_hint = false,
  signs = {
    fold_closed = "",
    fold_open = "",
    done = "✓",
  },
  view = {
    merge_tool = {
      layout = "diff3_mixed",
    },
  },
  file_panel = {
    listing_style = "tree",
    win_config = {
      position = "left",
      width = 35,
    },
  },
})
