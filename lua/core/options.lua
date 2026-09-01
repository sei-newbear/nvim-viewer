-- ===================================================================
-- lua/core/options.lua : 閲覧専用(Read-Only)設定 + ビューアー向けUI
-- ===================================================================

local opt = vim.opt

-- ---- 閲覧に最適化したUI設定 ----
opt.number = true            -- 行番号の表示
opt.relativenumber = false   -- ビューアーなので絶対行番号（エージェントに行番号を伝えやすい）
opt.signcolumn = "yes"       -- LSP/Diffのサイン列を固定（表示ガタつき防止）
opt.cmdheight = 1
opt.wrap = false             -- 折り返し無効（Diffを見やすくするため）
opt.cursorline = true
opt.scrolloff = 4
opt.sidescrolloff = 8
opt.termguicolors = true
opt.mouse = "a"              -- マウスでのスクロール/選択を許可
opt.clipboard = "unnamedplus"
opt.splitright = true
opt.splitbelow = true
opt.ignorecase = true
opt.smartcase = true
opt.updatetime = 250
opt.timeoutlen = 400
opt.laststatus = 3           -- グローバルステータスライン（分割時に見やすい）

-- 閲覧専用なのでスワップ/バックアップ/undoファイルは不要
opt.swapfile = false
opt.backup = false
opt.writebackup = false
opt.undofile = false

-- 差分表示の品質を上げる
opt.diffopt:append({ "linematch:60", "algorithm:histogram" })
opt.fillchars:append({ diff = "╱" })

-- ---- 文章系のファイルは折り返す ----
-- wrap=false は差分を見やすくするための設定だが、マークダウンには不向き。
-- 特にスキルファイルの frontmatter は description が非常に長い1行になるため、
-- 折り返さないと画面端で切れて読めない。
vim.api.nvim_create_autocmd("FileType", {
  group = vim.api.nvim_create_augroup("ViewerWrapText", { clear = true }),
  pattern = { "markdown", "text", "gitcommit", "help" },
  callback = function()
    vim.opt_local.wrap = true
    vim.opt_local.linebreak = true    -- 単語の途中で折らない
    vim.opt_local.breakindent = true  -- 折り返し行のインデントを揃える
    vim.opt_local.showbreak = "  ↪ "  -- 折り返しの目印
  end,
})

-- ---- ビューアー専用: ファイル変更を防止するフック ----
-- 注意: pattern="*" で無条件に readonly にすると Diffview / yazi / lazy.nvim 等の
-- 特殊バッファまで壊れるため、「通常の実ファイルバッファ」のみを対象にする。
local readonly_group = vim.api.nvim_create_augroup("ViewerReadOnly", { clear = true })

-- 書き換えを許可する（＝除外する）バッファ種別
local function should_lock(bufnr)
  -- buftype が空 = 通常のファイルバッファのみ対象
  if vim.bo[bufnr].buftype ~= "" then
    return false
  end
  local ft = vim.bo[bufnr].filetype
  -- プラグインのUI系ファイルタイプは除外
  local skip_ft = {
    DiffviewFiles = true, DiffviewFileHistory = true, DiffviewFHOptionPanel = true,
    lazy = true, mason = true, help = true, qf = true,
    gitcommit = true, gitrebase = true, TelescopePrompt = true, yazi = true,
  }
  if skip_ft[ft] then
    return false
  end
  return true
end

vim.api.nvim_create_autocmd({ "BufReadPost", "BufNewFile", "BufWinEnter" }, {
  group = readonly_group,
  pattern = "*",
  callback = function(args)
    local bufnr = args.buf
    if not vim.api.nvim_buf_is_valid(bufnr) then return end
    if should_lock(bufnr) then
      vim.bo[bufnr].modifiable = false
      -- readonly は付けない。
      -- 付けると `:w` が E45（英語）で弾かれ、しかも
      -- `add ! to override` という**実際には効かない案内**が出る。
      -- 保存は下の BufWriteCmd が日本語で説明して受け止める。
      vim.bo[bufnr].readonly = false

      -- 編集しようとしたときに、この道具の前提を日本語で伝える。
      -- 何も出さないと E21 という英語の内部エラーしか見えず、
      -- 「編集はエージェントに頼む」という一番大事な前提が伝わらない。
      local function explain()
        vim.notify("このビューアーは編集しません。修正は左ペインのエージェントへ依頼してください",
          vim.log.levels.INFO)
      end
      for _, k in ipairs({ "i", "I", "a", "A", "o", "O", "c", "C", "s", "S",
                           "x", "X", "d", "D", "p", "P", "r", "R", "u", "J" }) do
        vim.keymap.set("n", k, explain,
          { buffer = bufnr, silent = true, desc = "閲覧専用（編集はエージェントへ）" })
      end

      -- ビューアーにマクロ記録は不要。誤って q を押して "recording @x" に
      -- 入ってしまう事故を防ぐ（help や quickfix の q は従来どおり残す）
      vim.keymap.set("n", "q", "<Nop>", { buffer = bufnr, desc = "マクロ記録を無効化" })
    end
  end,
})

-- 誤って :w しようとした場合に、はっきり知らせる
vim.api.nvim_create_autocmd("BufWriteCmd", {
  group = readonly_group,
  pattern = "*",
  callback = function()
    vim.notify("このビューアーは保存しません。修正は左ペインのエージェントへ依頼してください",
      vim.log.levels.WARN)
  end,
})
