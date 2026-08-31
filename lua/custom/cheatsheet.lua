-- ===================================================================
-- lua/custom/cheatsheet.lua
-- `?` で開くキー操作の早見表（フローティングウィンドウ）
--
-- herdr のキー（Ctrl+b 系）は Neovim の外で処理されるため which-key には
-- 出てこない。2つの層をまとめて1画面で見られるようにするのがこの画面の役目。
-- ===================================================================

local M = {}

-- { セクション見出し, { キー, 説明 } ... }
local SECTIONS = {
  {
    "ショートカットを覚えていなくても使う",
    {
      { "上部バーをクリック", "メニューバーの項目を左クリックで実行できる" },
      { "下部バーをクリック", "ジャンプ系（定義・参照・実装…）を実行できる" },
      { "F1",          "コマンドパレット（全操作を日本語で検索して実行）" },
      { "<Space>c",    "同上" },
      { "左クリック",  "カーソル移動。ツリーやファイル一覧の選択も可" },
      { "ホイール",    "スクロール" },
    },
  },
  {
    "herdr — ペインを行き来する（Ctrl+b を押して離してから次のキー）",
    {
      { "Ctrl+b  h",   "左へ — エージェントのところへ戻る" },
      { "Ctrl+b  l",   "右へ — ビューアーへ行く" },
      { "Ctrl+b  z",   "全画面の切り替え（差分を読むときはこれ）" },
      { "Ctrl+b  x",   "今いるペインを閉じる" },
      { "Ctrl+b  v",   "縦に分割する" },
    },
  },
  {
    "コードをエージェントに渡す",
    {
      { "V → Ctrl+L",     "選んだ行の場所を送る（コードは送らない）" },
      { "v → Ctrl+L",     "選んだ文字を添えて送る" },
      { "Ctrl+L",         "ノーマルモードなら現在行の場所を送る" },
      { "",               "差分中は Commit と Side、ブレイム中は Commit も付く" },
      { "",               "Enter は押されないので質問を書き足せる" },
      { ":HerdrTarget",   "どのペインに送られるか確認する" },
    },
  },
  {
    "コードを辿る",
    {
      { "gd",          "定義へジャンプ" },
      { "gr",          "参照一覧（どこから使われているか）" },
      { "gi",          "実装へジャンプ（インターフェースの実装先）" },
      { "gy",          "型定義へジャンプ" },
      { "K",           "型・ドキュメントをポップアップ表示" },
      { "Ctrl+o",      "ジャンプ元へ戻る（進むのは Ctrl+i）" },
      { "<Space>s",    "このファイルの関数・型を一覧" },
      { "<Space>S",    "プロジェクト全体から名前で探す" },
      { "/単語 Enter", "検索してカーソルを飛ばす（次は n）" },
    },
  },
  {
    "差分を見る",
    {
      { "<Space>dd",   "差分を開く（未コミットの変更）" },
      { "<Space>dm",   "差分を開く（origin/main と比較）" },
      { "<Space>dh",   "このファイルの変更履歴" },
      { "Tab / S-Tab", "次 / 前のファイルへ" },
      { "gf",          "★差分から実ファイルを開く（同じ行に着地）" },
      { "<Space>w",    "折り返しの切替（差分では左右同時）" },
      { "]c / [c",     "次 / 前の変更箇所へ" },
      { "<Space>e",    "ファイル一覧の表示切替（差分が広くなる）" },
      { "q",           "差分を閉じて戻る" },
      { "<Space>dc",   "差分を閉じる（同じ）" },
    },
  },
  {
    "マークダウンを読む",
    {
      { "<Space>m",    "整形表示 ⇄ 生ファイル を切り替え" },
      { "<Space>o",    "ブラウザで開く（mermaid が図として出る）" },
    },
  },
  {
    "行の由来を追う（ブレイム）",
    {
      { "<Space>g",    "ブレイムモードの切替。行ごとに「なぜ変わったか」が出る" },
      { "Enter",       "その行を変えたコミットの差分を開く（そのファイルだけ）" },
      { "ダブルクリック", "同上" },
      { "[h / ]h",     "★差分を開いたまま 前 / 次 の変更へ移動" },
      { "q",           "★差分を閉じて元の位置に戻る" },
      { ":BlameDensity", "変わり目だけ ⇄ 全行 を切り替え" },
    },
  },
  {
    "ファイルを探す",
    {
      { "Ctrl+p",      "ファイル名で探す（部分一致）" },
      { "<Space>r",    "最近開いたファイル" },
      { "<Space>b",    "開いているバッファ" },
      { "<Space>/",    "ファイルの中身を全文検索" },
      { "<Space>*",    "カーソル下の語をプロジェクト全体から検索" },
      { "<Space>t",    "ファイルツリーの表示切替" },
      { "l / h",       "ツリー内で 開く / 閉じる" },
      { "]g / [g",     "ツリー内で 次 / 前の変更ファイルへ" },
      { "H / I",       "隠しファイル / gitignore対象の表示切替" },
    },
  },
  {
    "その他",
    {
      { "<Space>l / <Space>h", "Neovim内で 右 / 左のウィンドウへ" },
      { "<Space>y",    "現在位置を パス:行番号 でコピー" },
      { "<Space>w",    "折り返しの切替（横長の行を折り返す）" },
      { "<Space>?",    "全キーマップを検索する" },
      { "<Space>q",    "ウィンドウを閉じる" },
      { "<Space>Q",    "Neovim を終了する" },
      { "Esc",         "困ったらまずこれ。普通の状態に戻る" },
      { "<Space>0",    "★開きすぎた画面を全部閉じて最初の状態に戻す" },
      { ":LspEnabled", "使える言語サーバを表示" },
      { ":checkhealth","全体の健全性チェック" },
    },
  },
}

local KEY_WIDTH = 17

--- 表示用の行と、ハイライト位置を組み立てる
local function build()
  local lines, marks = {}, {}
  local function add(text, hl, col_start, col_end)
    table.insert(lines, text)
    if hl then
      table.insert(marks, { row = #lines - 1, hl = hl, s = col_start or 0, e = col_end or -1 })
    end
  end

  add("  閲覧専用コードビューアー — キー操作早見表", "Title")
  add("")

  for _, section in ipairs(SECTIONS) do
    local heading, rows = section[1], section[2]
    add("  " .. heading, "Function")
    for _, row in ipairs(rows) do
      local key, desc = row[1], row[2]
      local pad = string.rep(" ", math.max(1, KEY_WIDTH - vim.fn.strdisplaywidth(key)))
      local text = "    " .. key .. pad .. desc
      add(text)
      -- キー部分だけ色を変える
      table.insert(marks, {
        row = #lines - 1, hl = "Identifier",
        s = 4, e = 4 + #key,
      })
    end
    add("")
  end

  add("  ?  この画面を閉じる      q / Esc  も同じ", "Comment")
  return lines, marks
end

function M.open()
  -- 既に開いていれば閉じる（トグル）
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local buf = vim.api.nvim_win_get_buf(win)
    if vim.b[buf].viewer_cheatsheet then
      vim.api.nvim_win_close(win, true)
      return
    end
  end

  local lines, marks = build()

  local width = 0
  for _, l in ipairs(lines) do
    width = math.max(width, vim.fn.strdisplaywidth(l))
  end
  width = math.min(width + 4, vim.o.columns - 4)
  local height = math.min(#lines, vim.o.lines - 6)

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

  local ns = vim.api.nvim_create_namespace("viewer_cheatsheet")
  for _, m in ipairs(marks) do
    pcall(vim.api.nvim_buf_set_extmark, buf, ns, m.row, m.s, {
      end_col = m.e == -1 and #lines[m.row + 1] or m.e,
      hl_group = m.hl,
    })
  end

  vim.bo[buf].modifiable = false
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.b[buf].viewer_cheatsheet = true

  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = math.floor((vim.o.lines - height) / 2) - 1,
    col = math.floor((vim.o.columns - width) / 2),
    style = "minimal",
    border = "rounded",
    -- 内容が画面に収まらず末尾が見切れても操作方法が分かるよう、枠に出す
    title = " キー操作早見表   j/k スクロール   q 閉じる ",
    title_pos = "center",
  })
  vim.wo[win].wrap = false
  vim.wo[win].cursorline = false

  for _, key in ipairs({ "q", "<Esc>", "?" }) do
    vim.keymap.set("n", key, function()
      if vim.api.nvim_win_is_valid(win) then
        vim.api.nvim_win_close(win, true)
      end
    end, { buffer = buf, nowait = true, silent = true, desc = "早見表を閉じる" })
  end
end

-- ---- キーマップ ----
-- `?` は本来「後方検索」だが、ビューアーではヘルプの方が有用なので割り当てる。
-- 後方検索が必要なときは `/単語` を打ってから `N` で遡れる。
vim.keymap.set("n", "?", M.open, { silent = true, desc = "キー操作早見表を開く" })

vim.api.nvim_create_user_command("Cheatsheet", M.open, { desc = "キー操作早見表を開く" })

return M
