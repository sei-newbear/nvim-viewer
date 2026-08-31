-- ===================================================================
-- lua/plugins/snacks.lua
-- ファイルツリー(explorer) と 各種ピッカー(picker)
-- yazi.nvim の依存として既に入っているものを活用し、プラグインを増やさない
-- ===================================================================

--- ファイルツリーの表示/非表示を切り替える
local function toggle_tree()
  local ok, Snacks = pcall(require, "snacks")
  if not ok then
    vim.notify("snacks.nvim が読み込まれていません", vim.log.levels.ERROR)
    return
  end
  local existing = (Snacks.picker.get({ source = "explorer" }) or {})[1]
  if existing then
    existing:close()
  else
    -- 今開いているファイルの位置までツリーを展開して表示する
    Snacks.explorer.reveal()
  end
end

--- LSPピッカーを呼ぶ。使えない場合は素の vim.lsp.buf.* にフォールバック
local function lsp_pick(source, fallback)
  return function()
    local ok, Snacks = pcall(require, "snacks")
    if ok and Snacks.picker and Snacks.picker[source] then
      Snacks.picker[source]()
    else
      fallback()
    end
  end
end

return {
  {
    "folke/snacks.nvim",
    priority = 1000,
    lazy = false,
    opts = {
      -- ファイルツリー
      explorer = {
        replace_netrw = true, -- ディレクトリを開いたらツリーで開く
      },

      picker = {
        enabled = true,
        -- vim.ui.select を絞り込みピッカーに置き換える。
        -- コマンドパレット(custom/palette.lua)がこれを使う。
        ui_select = true,
        sources = {
          explorer = {
            -- 左側のサイドバーとして常駐させる
            layout = { preset = "sidebar", preview = false },
            auto_close = false,
            follow_file = true,   -- 開いているファイルを自動で追いかける
            git_status = true,    -- 変更のあるファイルに印を付ける
            diagnostics = true,   -- エラーのあるファイルに印を付ける
            win = {
              list = {
                keys = {
                  -- 閲覧専用ビューアーなので、ファイルを壊す操作は塞ぐ。
                  -- 編集・削除・移動は左ペインのエージェントに依頼する運用。
                  ["a"] = false, -- 新規作成
                  ["d"] = false, -- 削除
                  ["r"] = false, -- リネーム
                  ["c"] = false, -- コピー
                  ["m"] = false, -- 移動
                  ["p"] = false, -- 貼り付け
                },
              },
            },
          },
        },
      },

      -- ---- 画像・mermaid のインライン表示 ----
      -- マークダウンを開くと ```mermaid ブロックの位置に図がその場で描画される。
      -- 条件: 外側ターミナルが Kitty graphics 対応（ghostty はOK）かつ
      --       herdr の [experimental] kitty_graphics = true になっていること。
      --       判定は :lua =require("snacks").image.terminal.env() で確認できる。
      image = {
        enabled = true,
        doc = {
          enabled = true,
          inline = true,   -- バッファ内にその場で描く（placeholders 対応時のみ）
          float = true,    -- インライン不可なら浮動ウィンドウにフォールバック
          max_width = 70,
          max_height = 30,
        },
        convert = {
          notify = true,   -- 変換に失敗したら黙らず知らせる
          -- mmdc は Chromium を同梱していないので、既存の google-chrome を使わせる。
          -- -s でスケールを上げて、ターミナル上でも文字が潰れないようにする。
          mermaid = function()
            local theme = vim.o.background == "light" and "neutral" or "dark"
            return {
              "-i", "{src}", "-o", "{file}",
              "-b", "transparent",
              "-t", theme,
              "-s", "4",
              "-p", vim.fn.expand("~/.config/nvim/mermaid-puppeteer.json"),
            }
          end,
        },
      },

      -- Ctrl+L の送信結果などを見やすい通知で出す
      notifier = { enabled = true, timeout = 2500 },

      -- ビューアーには不要なものは切って起動を軽く保つ
      dashboard = { enabled = false },
      scroll = { enabled = false },
      indent = { enabled = false },
      animate = { enabled = false },
    },

    keys = {
      -- ---- ファイルツリー ----
      { "<leader>t", toggle_tree, desc = "ファイルツリーの表示切替" },

      -- ---- コードジャンプ（候補が1つなら即ジャンプ、複数なら一覧）----
      {
        "gr",
        lsp_pick("lsp_references", vim.lsp.buf.references),
        desc = "LSP: 参照一覧（どこから使われているか）",
      },
      {
        "gi",
        lsp_pick("lsp_implementations", vim.lsp.buf.implementation),
        desc = "LSP: 実装へジャンプ（インターフェースの実装先）",
      },
      {
        "gd",
        lsp_pick("lsp_definitions", vim.lsp.buf.definition),
        desc = "LSP: 定義へジャンプ",
      },
      {
        "gy",
        lsp_pick("lsp_type_definitions", vim.lsp.buf.type_definition),
        desc = "LSP: 型定義へジャンプ",
      },
      {
        "gD",
        lsp_pick("lsp_declarations", vim.lsp.buf.declaration),
        desc = "LSP: 宣言へジャンプ",
      },

      -- ---- ファイルを探す（VSCode の Ctrl+P 相当）----
      {
        "<C-p>",
        function() require("snacks").picker.files() end,
        desc = "ファイル名で探す（部分一致）",
      },
      {
        "<leader>r",
        function() require("snacks").picker.recent() end,
        desc = "最近開いたファイル",
      },
      {
        "<leader>b",
        function() require("snacks").picker.buffers() end,
        desc = "開いているバッファ",
      },
      {
        "<leader>/",
        function() require("snacks").picker.grep() end,
        desc = "ファイルの中身を全文検索",
      },
      {
        "<leader>*",
        function() require("snacks").picker.grep_word() end,
        desc = "カーソル下の語をプロジェクト全体から検索",
        mode = { "n", "x" },
      },

      -- ---- シンボル検索 ----
      {
        "<leader>s",
        function() require("snacks").picker.lsp_symbols() end,
        desc = "LSP: このファイルの関数・型を一覧",
      },
      {
        "<leader>S",
        function() require("snacks").picker.lsp_workspace_symbols() end,
        desc = "LSP: プロジェクト全体から名前で探す",
      },
    },
  },
}
