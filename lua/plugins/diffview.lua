-- ===================================================================
-- lua/plugins/diffview.lua : サイドバイサイド差分ビューアー
-- ===================================================================
return {
  {
    "sindrets/diffview.nvim",
    dependencies = { "nvim-lua/plenary.nvim", "nvim-tree/nvim-web-devicons" },
    cmd = { "DiffviewOpen", "DiffviewFileHistory", "DiffviewClose", "DiffviewToggleFiles" },
    keys = {
      { "<leader>dd", "<cmd>DiffviewOpen<CR>",                desc = "差分を開く (作業ツリー)" },
      { "<leader>dm", "<cmd>DiffviewOpen origin/main...HEAD<CR>", desc = "差分を開く (vs origin/main)" },
      { "<leader>dh", "<cmd>DiffviewFileHistory %<CR>",       desc = "このファイルの履歴" },
      { "<leader>dH", "<cmd>DiffviewFileHistory<CR>",         desc = "リポジトリの履歴" },
      { "<leader>dc", "<cmd>DiffviewClose<CR>",               desc = "差分を閉じる" },
    },
    opts = function()
      local actions = require("diffview.actions")
      return {
        enhanced_diff_hl = true,   -- 差分の色分けを強調
        view = {
          -- 左右分割のサイドバイサイド表示
          default = { layout = "diff2_horizontal", winbar_info = true },
          merge_tool = { layout = "diff3_horizontal", disable_diagnostics = true },
          file_history = { layout = "diff2_horizontal", winbar_info = true },
        },
        file_panel = {
          listing_style = "tree",
          win_config = { position = "left", width = 32 },
        },
        keymaps = {
          -- Diffview は既定で <leader>c 系にマージ競合の解決キー
          -- (ours/theirs/base/all を選ぶ)を8個割り当てる。これは
          --   1) ファイルを書き換える操作なので閲覧専用の方針に反する
          --   2) <leader>c（コマンドパレット）を潰してしまう
          -- ため、すべて無効化する。マージ作業は別のツールで行う。
          disable_defaults = false,
          view = {
            { "n", "<leader>co", false },
            { "n", "<leader>ct", false },
            { "n", "<leader>cb", false },
            { "n", "<leader>ca", false },
            { "n", "<leader>cO", false },
            { "n", "<leader>cT", false },
            { "n", "<leader>cB", false },
            { "n", "<leader>cA", false },
            { "n", "dx", false },
            { "n", "dX", false },
            { "n", "<leader>dc", actions.close,          { desc = "差分を閉じる" } },
            { "n", "<Tab>",      actions.select_next_entry, { desc = "次のファイル" } },
            { "n", "<S-Tab>",    actions.select_prev_entry, { desc = "前のファイル" } },
            { "n", "gf",         actions.goto_file_edit,    { desc = "実ファイルを開く" } },
            { "n", "<leader>e",  actions.toggle_files,      { desc = "ファイル一覧の表示切替" } },
          },
          file_panel = {
            { "n", "<leader>cO", false },
            { "n", "<leader>cT", false },
            { "n", "<leader>cB", false },
            { "n", "<leader>cA", false },
            { "n", "dX", false },
            { "n", "<Tab>",     actions.select_next_entry, { desc = "次のファイル" } },
            { "n", "<S-Tab>",   actions.select_prev_entry, { desc = "前のファイル" } },
            { "n", "gf",        actions.goto_file_edit,    { desc = "実ファイルを開く" } },
            { "n", "<leader>e", actions.toggle_files,      { desc = "ファイル一覧の表示切替" } },
            { "n", "<leader>dc", actions.close,            { desc = "差分を閉じる" } },
          },
        },
      }
    end,
  },
}
