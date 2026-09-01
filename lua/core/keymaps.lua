-- ===================================================================
-- lua/core/keymaps.lua : ビューアー向け基本キーバインド
-- ===================================================================

local map = vim.keymap.set

-- ---- Neovim 標準キーのうち、閲覧専用に反するものを外す ----
-- Neovim 0.11+ は LSP 用のキーを既定で張る。このうち
--   grn = rename（識別子を一括改名）
--   gra = code action（自動修正の適用）
--   grx = codelens 実行
--   gcc = コメントの切替
-- は **ファイルを書き換える操作**で、閲覧専用の方針に反する。
--
-- さらに実害として、gr で始まるキーが6個あるせいで
-- `gr`（参照一覧）が timeoutlen 分（400ms）待たないと発火せず、
-- 体感で明らかに遅い。読むための操作が遅くなるのは本末転倒なので外す。
-- 残す grr/gri/grt は同等の機能を gr/gi/gy で提供している。
for _, k in ipairs({ "grn", "gra", "grx", "grr", "gri", "grt", "gcc", "gc", "gbc" }) do
  pcall(vim.keymap.del, "n", k)
end
for _, k in ipairs({ "gra", "gc" }) do
  pcall(vim.keymap.del, "x", k)
  pcall(vim.keymap.del, "v", k)
end

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
-- `Space q` は「ウィンドウを閉じる」と案内しているが、窓が1つのときは
-- :quit が Neovim ごと終わらせてしまう。隣の `Space Q`（終了）と
-- 大小の違いしかないのに、片方だけ取り返しがつかない状態だった。
-- 窓が1つなら閉じずに、そう伝える。
map("n", "<leader>q", function()
  local wins = vim.tbl_filter(function(w)
    return vim.api.nvim_win_get_config(w).relative == ""
  end, vim.api.nvim_tabpage_list_wins(0))
  if #wins <= 1 and #vim.api.nvim_list_tabpages() <= 1 then
    vim.notify("これが最後のウィンドウです（終了は Space Q）", vim.log.levels.INFO)
    return
  end
  vim.cmd("quit")
end, { desc = "ウィンドウを閉じる" })

map("n", "<leader>Q", function()
  vim.ui.select({ "いいえ", "はい" }, { prompt = "Neovim を終了しますか？" },
    function(choice)
      if choice == "はい" then vim.cmd("qall!") end
    end)
end, { desc = "Neovimを終了" })

-- 行番号つきでファイル位置をコピー（エージェントに伝える用）
map("n", "<leader>y", function()
  local path = vim.fn.expand("%:p")
  local line = vim.fn.line(".")
  local ref = string.format("%s:%d", path, line)
  vim.fn.setreg("+", ref)
  vim.notify("コピーしました: " .. ref, vim.log.levels.INFO)
end, { desc = "ファイル位置(path:line)をコピー" })
