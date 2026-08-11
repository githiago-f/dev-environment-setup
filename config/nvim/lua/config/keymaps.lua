local map = vim.keymap.set

map({ "n", "v" }, "<Space>", "<Nop>", { silent = true })

-- Buffers
map("n", "<leader>bn", "<cmd>bnext<CR>", { desc = "Next buffer" })
map("n", "<leader>bp", "<cmd>bprevious<CR>", { desc = "Previous buffer" })
map("n", "<leader>bd", "<cmd>bdelete<CR>", { desc = "Delete buffer" })
map("n", "<leader>qq", "<cmd>qa<CR>", { desc = "Quit all" })
map("n", "<leader>q", "<cmd>q<CR>", { desc = "Quit" })
map("n", "<leader>wq", "<cmd>wq<CR>", { desc = "Write & quit" })
map("n", "<leader>ww", "<cmd>w<CR>", { desc = "Write" })

-- Windows
map("n", "<leader>sv", "<C-w>v", { desc = "Vertical split" })
map("n", "<leader>sh", "<C-w>s", { desc = "Horizontal split" })
map("n", "<leader>se", "<C-w>=", { desc = "Equalize splits" })
map("n", "<leader>sx", "<cmd>close<CR>", { desc = "Close window" })
map("n", "<C-h>", "<C-w>h", { desc = "Window left" })
map("n", "<C-j>", "<C-w>j", { desc = "Window down" })
map("n", "<C-k>", "<C-w>k", { desc = "Window up" })
map("n", "<C-l>", "<C-w>l", { desc = "Window right" })

-- Explorer
local function toggle_files()
  if not MiniFiles.close() then
    MiniFiles.open()
  end
end

map("n", "-", toggle_files, { desc = "Toggle Explorer" })
map("n", "<leader>e", toggle_files, { desc = "Explorer" })
map("n", "<leader>E", function()
  MiniFiles.open(vim.api.nvim_buf_get_name(0))
end, { desc = "Explorer at current file" })

-- Search
local MiniPick = require("mini.pick")

local function grep_live_with_query(text)
  if text and text ~= "" then
    local gr = vim.api.nvim_create_augroup("MiniGrepQuery", { clear = true })
    vim.api.nvim_create_autocmd("User", {
      group = gr,
      pattern = "MiniPickStart",
      once = true,
      callback = function()
        vim.schedule(function()
          if MiniPick.is_picker_active() then
            MiniPick.set_picker_query(vim.split(text, ""))
          end
        end)
      end,
    })
  end
  MiniPick.builtin.grep_live()
end

local function visual_selection_text()
  local start = vim.fn.getpos("'<")
  local finish = vim.fn.getpos("'>")
  local lines = vim.fn.getline(start[2], finish[2])
  lines[1] = string.sub(lines[1], start[3], -1)
  lines[#lines] = string.sub(lines[#lines], 1, finish[3])
  return table.concat(lines, "\n")
end

map("n", "<leader>ff", "<cmd>Pick files<CR>", { desc = "Find files" })
map("n", "<leader>fg", function() grep_live_with_query() end, { desc = "Live grep" })
map("n", "<leader>fw", function() grep_live_with_query(vim.fn.expand("<cword>")) end, { desc = "Grep word under cursor" })
map("n", "<leader>f/", function()
  MiniPick.builtin.grep_live(
    { globs = { vim.fn.expand("%:t") } },
    { source = { cwd = vim.fn.fnamemodify(vim.fn.expand("%:p"), ":h") } }
  )
end, { desc = "Grep in current buffer" })
map("v", "<leader>fv", function() grep_live_with_query(visual_selection_text()) end, { desc = "Grep visual selection" })
map("n", "<leader>fb", "<cmd>Pick buffers<CR>", { desc = "Find buffers" })
map("n", "<leader>fh", "<cmd>Pick help<CR>", { desc = "Help" })

-- LSP
map("n", "gd", vim.lsp.buf.definition, { desc = "Go to definition" })
map("n", "gr", vim.lsp.buf.references, { desc = "References" })
map("n", "K", vim.lsp.buf.hover, { desc = "Hover" })
map("n", "gi", vim.lsp.buf.implementation, { desc = "Implementation" })
map("n", "<leader>rn", vim.lsp.buf.rename, { desc = "Rename" })
map({ "n", "v" }, "<leader>ca", vim.lsp.buf.code_action, { desc = "Code action" })

-- Git
map("n", "<leader>gg", "<cmd>Neogit<CR>", { desc = "Neogit" })
map("n", "<leader>gs", "<cmd>Neogit status<CR>", { desc = "Status" })
map("n", "<leader>gc", "<cmd>Neogit commit<CR>", { desc = "Commit" })
map("n", "<leader>ga", "<cmd>Neogit stage_all<CR>", { desc = "Stage all" })
map("n", "<leader>gp", "<cmd>Neogit push<CR>", { desc = "Push" })
map("n", "<leader>gl", "<cmd>Neogit pull<CR>", { desc = "Pull" })
map("n", "<leader>gf", "<cmd>Neogit fetch<CR>", { desc = "Fetch" })
map("n", "<leader>gw", "<cmd>Neogit worktree<CR>", { desc = "Worktrees" })
map("n", "<leader>gb", "<cmd>Neogit blame<CR>", { desc = "Blame" })
map("n", "<leader>gh", "<cmd>Neogit log %<CR>", { desc = "File history" })
map("n", "<leader>gd", "<cmd>DiffviewOpen<CR>", { desc = "Diffview" })
map("n", "<leader>gD", "<cmd>DiffviewClose<CR>", { desc = "Diffview close" })
map("n", "]h", function() MiniDiff.goto_hunk("next") end, { desc = "Next hunk" })
map("n", "[h", function() MiniDiff.goto_hunk("prev") end, { desc = "Previous hunk" })
map("n", "<leader>hp", function() MiniDiff.toggle_overlay() end, { desc = "Preview hunk" })
map("n", "<leader>ho", function() MiniDiff.toggle_overlay() end, { desc = "Toggle overlay" })

-- Formatting
map({ "n", "v" }, "<leader>F", function()
  require("conform").format({ lsp_format = "fallback" })
end, { desc = "Format" })

-- Diagnostics
map("n", "]d", vim.diagnostic.goto_next, { desc = "Next diagnostic" })
map("n", "[d", vim.diagnostic.goto_prev, { desc = "Previous diagnostic" })
map("n", "<leader>df", vim.diagnostic.open_float, { desc = "Float diagnostic" })

-- Terminal
map("n", "<leader>tt", "<cmd>term<CR>", { desc = "Terminal" })
map("t", "<Esc>", "<C-\\><C-n>", { desc = "Exit terminal mode" })
