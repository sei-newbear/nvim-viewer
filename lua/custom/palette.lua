-- ===================================================================
-- lua/custom/palette.lua
-- コマンドパレット（VSCode の Ctrl+Shift+P 相当）
--
-- ショートカットを覚えていなくても、探して実行できるようにする。
-- ここが操作の総合窓口。ツールバーの「コマンド」からも開く。
--
-- 検索は日本語・英語のどちらでも当たる。
-- 表示は日本語のまま、照合用の文字列(item.text)に英語キーワードを混ぜてある。
-- 日本語入力に切り替えずに "diff" や "definition" で引けるようにするため。
-- ===================================================================

local M = {}

--- パレットに並べる操作
--- name: 表示名 / en: 英語での検索語 / key: 対応するキー / run: 実行内容
--- cond: 省略可。false なら一覧に出さない
local function actions()
  local buf = vim.api.nvim_get_current_buf()
  local ok_tb, tb = pcall(require, "custom.toolbar")
  if ok_tb then buf = tb.context_buf() end

  local is_md = vim.bo[buf].filetype == "markdown"
  local has_lsp = #vim.lsp.get_clients({ bufnr = buf }) > 0
  local in_diff = vim.wo.diff or vim.bo.filetype:match("^Diffview") ~= nil

  return {
    -- ---- 差分 ----
    { name = "差分を開く（未コミットの変更）", en = "diff open changes git working tree", key = "Space dd",
      run = function() vim.cmd("DiffviewOpen") end },
    { name = "差分を開く（origin/main と比較）", en = "diff compare main branch", key = "Space dm",
      run = function() vim.cmd("DiffviewOpen origin/main...HEAD") end },
    { name = "このファイルの変更履歴を見る", en = "file history log commits timeline", key = "Space dh",
      run = function() vim.cmd("DiffviewFileHistory %") end },
    { name = "リポジトリ全体の変更履歴を見る", en = "repository history log all commits", key = "Space dH",
      run = function() vim.cmd("DiffviewFileHistory") end },
    { name = "差分から実ファイルを開く", en = "open real file from diff goto file edit", key = "gf",
      cond = in_diff,
      run = function()
        local ok = pcall(function() require("diffview.actions").goto_file_edit() end)
        if not ok then vim.notify("差分表示の中で使えます", vim.log.levels.WARN) end
      end },
    { name = "差分を閉じる", en = "close diff", key = "Space dc",
      run = function() vim.cmd("DiffviewClose") end },

    -- ---- 探す ----
    { name = "ファイル名で探す", en = "go to file quick open find file", key = "Ctrl+p",
      run = function() require("snacks").picker.files() end },
    { name = "最近開いたファイル", en = "recent files open recent", key = "Space r",
      run = function() require("snacks").picker.recent() end },
    { name = "開いているバッファ", en = "buffers open editors", key = "Space b",
      run = function() require("snacks").picker.buffers() end },
    { name = "ファイルの中身を全文検索", en = "search grep find in files text", key = "Space /",
      run = function() require("snacks").picker.grep() end },
    { name = "カーソル下の語を全体から検索", en = "search word under cursor grep", key = "Space *",
      run = function() require("snacks").picker.grep_word() end },
    { name = "ファイルツリーの表示切替", en = "explorer file tree sidebar toggle", key = "Space t",
      run = function()
        local S = require("snacks")
        local ex = (S.picker.get({ source = "explorer" }) or {})[1]
        if ex then ex:close() else S.explorer.reveal() end
      end },

    -- ---- 辿る ----
    { name = "定義へジャンプ", en = "go to definition", key = "gd", cond = has_lsp,
      run = function() require("snacks").picker.lsp_definitions() end },
    { name = "参照一覧（どこから使われているか）", en = "find all references usages", key = "gr", cond = has_lsp,
      run = function() require("snacks").picker.lsp_references() end },
    { name = "実装へジャンプ（インターフェースの実装先）", en = "go to implementation", key = "gi", cond = has_lsp,
      run = function() require("snacks").picker.lsp_implementations() end },
    { name = "型定義へジャンプ", en = "go to type definition", key = "gy", cond = has_lsp,
      run = function() require("snacks").picker.lsp_type_definitions() end },
    { name = "このファイルの関数・型を一覧", en = "go to symbol outline document", key = "Space s", cond = has_lsp,
      run = function() require("snacks").picker.lsp_symbols() end },
    { name = "プロジェクト全体から名前で探す", en = "workspace symbol search", key = "Space S", cond = has_lsp,
      run = function() require("snacks").picker.lsp_workspace_symbols() end },
    { name = "元の位置へ戻る", en = "go back jump previous location", key = "Ctrl+o",
      run = function() vim.cmd("normal! \\<C-o>") end },

    -- ---- マークダウン ----
    { name = "整形表示 ⇄ 生ファイル を切り替え", en = "toggle markdown rendered raw source preview",
      key = "Space m", cond = is_md,
      run = function() require("custom.md_view").toggle() end },
    { name = "ブラウザで開く（mermaid を図で描画）", en = "open in browser mermaid diagram html",
      key = "Space o", cond = is_md,
      run = function() require("custom.md_preview").open() end },

    -- ---- 由来を追う ----
    { name = "ブレイムモード（行ごとの由来を表示）", en = "blame git annotate who changed line author",
      key = "Space g",
      run = function() require("custom.blame").toggle() end },
    { name = "この行を変えたコミットの差分を開く", en = "open commit diff for this line blame",
      key = "Enter（モード中）",
      run = function() require("custom.blame").open_commit() end },
    { name = "前（古い）の変更へ移動", en = "previous older commit history navigate back",
      key = "[h",
      run = function() require("custom.blame").nav_commit(1) end },
    { name = "次（新しい）の変更へ移動", en = "next newer commit history navigate forward",
      key = "]h",
      run = function() require("custom.blame").nav_commit(-1) end },
    { name = "ブレイム表示の密度を切替（変わり目だけ ⇄ 全行）",
      en = "blame density toggle all lines changes only", key = "",
      run = function() require("custom.blame").toggle_density() end },

    -- ---- 表示 ----
    { name = "折り返しの切替（横長の行を折り返す）", en = "toggle word wrap long lines", key = "Space w",
      run = function() require("custom.view_opts").toggle_wrap() end },
    { name = "行番号の表示切替", en = "toggle line numbers", key = "",
      run = function() require("custom.view_opts").toggle_number() end },

    -- ---- エージェント連携 ----
    { name = "現在行をエージェントへ送る", en = "send line to agent context herdr", key = "Ctrl+L",
      run = function() require("custom.herdr_link").send_location() end },
    { name = "送信先のエージェントを確認する", en = "check agent target herdr", key = "",
      run = function() vim.cmd("HerdrTarget") end },
    { name = "現在位置を パス:行番号 でコピー", en = "copy file path line number", key = "Space y",
      run = function() vim.cmd("normal \\<Space>y") end },

    -- ---- 片付け ----
    { name = "全部閉じて最初の状態に戻す", en = "reset close all cleanup restore layout", key = "Space 0",
      run = function() require("custom.reset").reset() end },
    { name = "画面だけ片付ける（開いたファイルは残す）", en = "reset layout only keep buffers windows", key = "",
      run = function() require("custom.reset").reset_layout() end },

    -- ---- その他 ----
    { name = "キー操作早見表を開く", en = "help keybindings cheatsheet shortcuts", key = "?",
      run = function() require("custom.cheatsheet").open() end },
    { name = "全キーマップを検索する", en = "search keymaps bindings", key = "Space ?",
      run = function() require("snacks").picker.keymaps() end },
    { name = "上部メニューバーの表示切替", en = "toggle toolbar menu bar", key = "",
      run = function() require("custom.toolbar").toggle() end },
    { name = "パンくず（ファイルパス）の表示切替", en = "toggle breadcrumb winbar file path", key = "",
      run = function() require("custom.winbar").toggle() end },
    { name = "フッターの表示切替", en = "toggle statusline footer", key = "",
      run = function() vim.cmd("StatuslineToggle") end },
    { name = "使える言語サーバを表示", en = "language server lsp status", key = "",
      run = function() vim.cmd("LspEnabled") end },
    { name = "健全性チェック", en = "checkhealth diagnostics health", key = "",
      run = function() vim.cmd("checkhealth") end },
    { name = "Neovim を終了する", en = "quit exit close neovim", key = "Space Q",
      run = function() vim.cmd("qall!") end },
  }
end

--- パレットを開く
function M.open()
  local items = {}
  for i, a in ipairs(actions()) do
    if a.cond ~= false then
      table.insert(items, {
        idx = i,
        -- ★ 検索対象。日本語名と英語キーワードの両方を含める
        text = a.name .. " " .. (a.en or ""),
        name = a.name,
        key = a.key or "",
        run = a.run,
      })
    end
  end

  local ok, Snacks = pcall(require, "snacks")
  if ok and Snacks.picker then
    local picked = pcall(function()
      Snacks.picker.pick({
        source = "palette",
        title = "コマンドパレット",
        items = items,
        -- 既定のプレビューは項目の内部データを出してしまうので消す。
        -- 中央に一覧だけを出す "select" レイアウトが用途に合う。
        preview = "none",
        layout = { preset = "select" },
        format = function(item)
          local ret = { { " " .. item.name, "SnacksPickerLabel" } }
          if item.key ~= "" then
            local pad = math.max(1, 46 - vim.fn.strdisplaywidth(item.name))
            ret[#ret + 1] = { string.rep(" ", pad) .. item.key, "SnacksPickerComment" }
          end
          return ret
        end,
        confirm = function(picker, item)
          picker:close()
          if not item then return end
          -- 選んだ直後に別のピッカーを開く操作があるため、ひと呼吸置く
          vim.schedule(function()
            local ok2, err = pcall(item.run)
            if not ok2 then
              vim.notify("実行に失敗しました: " .. tostring(err), vim.log.levels.ERROR)
            end
          end)
        end,
      })
    end)
    if picked then return end
  end

  -- ピッカーが使えない環境向けのフォールバック
  vim.ui.select(items, {
    prompt = "コマンドパレット",
    format_item = function(item)
      return item.key ~= "" and string.format("%-44s  %s", item.name, item.key) or item.name
    end,
  }, function(choice)
    if not choice then return end
    vim.schedule(function() pcall(choice.run) end)
  end)
end

-- ---- キーマップ / コマンド ----
-- VSCode の Ctrl+Shift+P に相当。ターミナルでは Ctrl+Shift+ 系が
-- 区別できないことがあるため、F1 と Space c の2通りを用意する。
vim.keymap.set("n", "<F1>", M.open, { silent = true, desc = "コマンドパレットを開く" })
vim.keymap.set("n", "<leader>c", M.open, { silent = true, desc = "コマンドパレットを開く" })

vim.api.nvim_create_user_command("Palette", M.open, { desc = "コマンドパレットを開く" })

return M
