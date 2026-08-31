-- ===================================================================
-- lua/core/keymaps.lua : ビューアー向け基本キーバインド
-- ===================================================================

local map = vim.keymap.set

-- 検索ハイライト解除
map("n", "<Esc>", "<cmd>nohlsearch<CR>", { desc = "ハイライト解除" })

-- 閲覧向け: 長い行でも見た目の行で移動
map({ "n", "x" }, "j", "gj", { desc = "下へ（表示行）" })
map({ "n", "x" }, "k", "gk", { desc = "上へ（表示行）" })

-- 半ページスクロール後に中央寄せ（差分を追いやすく）
map("n", "<C-d>", "<C-d>zz", { desc = "半ページ下" })
map("n", "<C-u>", "<C-u>zz", { desc = "半ページ上" })
map("n", "n", "nzzzv", { desc = "次の検索結果" })
map("n", "N", "Nzzzv", { desc = "前の検索結果" })

-- ウィンドウ移動
map("n", "<C-h>", "<C-w>h", { desc = "左のウィンドウへ" })
map("n", "<C-j>", "<C-w>j", { desc = "下のウィンドウへ" })
map("n", "<C-k>", "<C-w>k", { desc = "上のウィンドウへ" })
-- 注意: <C-l> は herdr へのコンテキスト送信に使うため、ウィンドウ移動には割り当てない。
-- 右方向だけ代替として <leader>l を用意する（<C-w>l も従来どおり使える）
map("n", "<leader>l", "<C-w>l", { desc = "右のウィンドウへ" })
map("n", "<leader>h", "<C-w>h", { desc = "左のウィンドウへ" })

-- 差分ハンク間の移動（Diffview 使用時）
map("n", "]c", "]c", { desc = "次の差分ハンク" })
map("n", "[c", "[c", { desc = "前の差分ハンク" })

-- 終了系（ビューアーなので気軽に閉じられるように）
map("n", "<leader>q", "<cmd>quit<CR>", { desc = "ウィンドウを閉じる" })
map("n", "<leader>Q", "<cmd>qall!<CR>", { desc = "Neovimを終了" })

-- 行番号つきでファイル位置をコピー（エージェントに伝える用）
map("n", "<leader>y", function()
  local path = vim.fn.expand("%:p")
  local line = vim.fn.line(".")
  local ref = string.format("%s:%d", path, line)
  vim.fn.setreg("+", ref)
  vim.notify("コピーしました: " .. ref, vim.log.levels.INFO)
end, { desc = "ファイル位置(path:line)をコピー" })
