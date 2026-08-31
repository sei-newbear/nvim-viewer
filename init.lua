-- ===================================================================
-- ターミナル専用 高度コードビューアー (Read-Only Neovim)
-- 左ペイン: エージェント / 右ペイン: このビューアー を想定
-- ===================================================================

vim.g.mapleader = " "
vim.g.maplocalleader = " "

-- lazy.nvim ブートストラップ
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not (vim.uv or vim.loop).fs_stat(lazypath) then
  vim.fn.system({
    "git", "clone", "--filter=blob:none",
    "https://github.com/folke/lazy.nvim.git",
    "--branch=stable", lazypath,
  })
end
vim.opt.rtp:prepend(lazypath)

-- コア設定（プラグインより先に読み込む）
require("core.options")
require("core.keymaps")

-- プラグイン読み込み
require("lazy").setup({
  spec = { { import = "plugins" } },
  install = { colorscheme = { "habamax" } },
  checker = { enabled = false },
  change_detection = { notify = false },
})

-- herdr 連携（Ctrl+L）はプラグイン読み込み後に
require("custom.herdr_link")

-- `?` で開くキー操作早見表
require("custom.cheatsheet")

-- マークダウンのブラウザプレビュー（Space p）
require("custom.md_preview")

-- frontmatter を「メタデータ」として明示する
require("custom.frontmatter")

-- マークダウンの表示切替（整形 ⇄ 生）の状態管理
require("custom.md_view")

-- 表示オプションの切替（折り返し・行番号）
require("custom.view_opts")

-- マウスで操作するための入口
require("custom.palette")   -- コマンドパレット（F1 / Space c）
require("custom.toolbar")   -- 上部のクリックできるメニューバー
require("custom.winbar")     -- コード上端のパンくず（ファイルパス）
require("custom.statusline") -- 下部のジャンプメニュー（LSPがあるときだけ）
require("custom.reset")      -- 開きすぎた画面を最初の状態へ戻す
require("custom.open_guard") -- 差分ウィンドウを別ファイルで乗っ取らせない
require("custom.blame")      -- 行ごとの由来（Space g）
