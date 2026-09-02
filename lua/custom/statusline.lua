-- ===================================================================
-- lua/custom/statusline.lua
-- 画面下部のフッター。「いま見ているファイルに対する操作」を並べる。
--
-- 上下の使い分け:
--   ヘッダー(toolbar) = どこを見るか。移動・グローバルな操作
--   フッター(ここ)    = 今のファイルをどう読むか。文脈に依存する操作
--
-- 状況で出す項目が変わる:
--   LSPが繋がっている  → 定義・参照・実装・型・一覧・戻る
--   マークダウン        → 生ファイル⇄整形・ブラウザ
--   差分を見ている      → ファイルを開く
--   常時               → 折り返し
-- LSP のジャンプ系とマークダウンの表示切替は、同じファイルで同時に出ない
-- （マークダウンには LSP が繋がらない）ので、実際には混雑しない。
--
-- ファイル名は出さない。パスは winbar（パンくず）が担当する。
-- ここでファイル名も出すと幅を奪い合い、長いファイル名のときに
-- ジャンプ項目が半減してしまう。
--
-- クリック領域は %@関数@ラベル%X で作る。ラベルの横にキーも出して、
-- 押しているうちにショートカットを覚えられるようにする。
-- ===================================================================

local M = {}

--- 判定に使うバッファ（ピッカー上でも内容が揺れないようにする）
local function ctx_buf()
  local cur = vim.api.nvim_get_current_buf()
  if vim.bo[cur].buftype == "" and vim.api.nvim_buf_get_name(cur) ~= "" then
    return cur
  end
  local ok, tb = pcall(require, "custom.toolbar")
  if ok then return tb.context_buf() end
  return cur
end

local function has_lsp()
  return #vim.lsp.get_clients({ bufnr = ctx_buf() }) > 0
end

local function is_md()
  return vim.bo[ctx_buf()].filetype == "markdown"
end

local function in_diff()
  for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.wo[w].diff then return true end
  end
  return false
end

--- フッターに並べる操作
--- when: 出す条件 / prio: 幅が足りないとき残る優先度（大きいほど残る）
--- ブレイムから差分を開いている最中か
local function in_blame_nav()
  local ok, b = pcall(require, "custom.blame")
  return ok and b.nav_state() ~= nil
end

local ITEMS = {
  -- 履歴の移動。差分を開いたまま前後のコミットへ行ける。
  -- キーを知らなくても押せるよう、クリックできる形でここに出す。
  { label = "◀ 前の変更", key = "[h", prio = 99, when = in_blame_nav,
    run = function() require("custom.blame").nav_commit(1) end },
  { label = function()
      local ok, b = pcall(require, "custom.blame")
      local st = ok and b.nav_state()
      return st and ("%d/%d"):format(st.idx, st.total) or ""
    end,
    key = "", prio = 98, when = in_blame_nav,
    run = function() end }, -- 現在位置の表示（押しても何もしない）
  { label = "次の変更 ▶", key = "]h", prio = 97, when = in_blame_nav,
    run = function() require("custom.blame").nav_commit(-1) end },
  { label = "閉じる", key = "q", prio = 96, when = in_blame_nav,
    run = function()
      -- 今いるタブの差分を閉じる。lib.views[1] を決め打ちすると
      -- 別の差分（作業ツリー差分など）を閉じてしまう。
      local okd, dv = pcall(require, "custom.diffview_util")
      if not okd then return end
      local here = dv.view_at(vim.api.nvim_get_current_tabpage())
      dv.close(here)
    end },

  -- 差分から実ファイルへ。「差分→全体→定義」の流れの要なので最優先。
  { label = "ファイルを開く", key = "gf", prio = 100, when = in_diff,
    run = function()
      local ok = pcall(function() require("diffview.actions").goto_file_edit() end)
      if not ok then vim.notify("差分表示の中で使えます", vim.log.levels.WARN) end
    end },

  -- コードを辿る
  { label = "定義", key = "gd", prio = 95, when = has_lsp,
    run = function() require("snacks").picker.lsp_definitions() end },
  { label = "戻る", key = "⌃o", prio = 92, when = has_lsp,
    run = function()
      -- ジャンプ履歴が無いと無反応になり、押せたのか分からない
      local jumps = vim.fn.getjumplist()
      if #jumps[1] == 0 or jumps[2] == 0 then
        vim.notify("戻る場所がありません（まだどこにもジャンプしていません）",
          vim.log.levels.INFO)
        return
      end
      vim.cmd("normal! " .. vim.api.nvim_replace_termcodes("<C-o>", true, false, true))
    end },
  { label = "参照", key = "gr", prio = 90, when = has_lsp,
    run = function() require("snacks").picker.lsp_references() end },
  { label = "実装", key = "gi", prio = 80, when = has_lsp,
    run = function() require("snacks").picker.lsp_implementations() end },
  { label = "型", key = "gy", prio = 60, when = has_lsp,
    run = function() require("snacks").picker.lsp_type_definitions() end },
  { label = "一覧", key = "␣s", prio = 50, when = has_lsp,
    run = function() require("snacks").picker.lsp_symbols() end },

  -- マークダウンの見方（そのファイルに対する操作なので下に置く）
  { label = function() return require("custom.md_view").toggle_label(ctx_buf()) end,
    key = "␣m", prio = 95, when = is_md,
    run = function() require("custom.md_view").toggle(ctx_buf()) end },
  { label = "ブラウザ", key = "␣o", prio = 90, when = is_md,
    run = function() require("custom.md_preview").open(ctx_buf()) end },

  -- 行ごとの由来。モード中はラベルを変えて「押すと終わる」ことを示す
  { label = function()
      local ok, b = pcall(require, "custom.blame")
      -- ここは英語のまま。フッターは幅が狭く、`blame` の方が短く収まる。
      -- パレットや早見表では日本語で説明しているので、意味は辿れる。
      return (ok and b.is_on(ctx_buf())) and "blame終了" or "blame"
    end,
    key = "␣g", prio = 45,
    when = function()
      local buf = ctx_buf()
      return vim.bo[buf].buftype == "" and vim.api.nvim_buf_get_name(buf) ~= ""
    end,
    run = function() require("custom.blame").toggle(ctx_buf()) end },

  -- 今のウィンドウの見え方
  { label = "折り返し", key = "␣w", prio = 40,
    run = function() require("custom.view_opts").toggle_wrap() end },
}

local function label_of(it)
  if type(it.label) == "function" then
    local ok, v = pcall(it.label)
    return ok and v or "?"
  end
  return it.label
end

function M.on_click(minwid, _clicks, _button, _mods)
  local it = ITEMS[minwid]
  if not it then return end
  vim.schedule(function()
    local ok, err = pcall(it.run)
    if not ok then
      vim.notify("実行に失敗しました: " .. tostring(err), vim.log.levels.ERROR)
    end
  end)
end

_G.ViewerStatusJumpClick = M.on_click

--- 幅に収まる項目を選ぶ
local function fit(width)
  local function cost(list)
    local n = 0
    for _, e in ipairs(list) do
      -- strdisplaywidth は現在窓の折り返し設定（wrap / showbreak /
      -- breakindent）を勘定に入れるため、狭い窓では値が跳ね上がる。
      -- ここで測りたいのは素の文字幅なので strwidth を使う。
      n = n + vim.fn.strwidth(label_of(e.it))
        + (e.it.key ~= "" and (vim.fn.strwidth(e.it.key) + 1) or 0) + 2
    end
    return n + math.max(0, #list - 1) -- 区切り "│"
  end

  local list = {}
  for i, it in ipairs(ITEMS) do
    if not it.when or it.when() then
      table.insert(list, { idx = i, it = it })
    end
  end
  while #list > 0 and cost(list) > width do
    local worst, at = math.huge, nil
    for i, e in ipairs(list) do
      if e.it.prio < worst then worst, at = e.it.prio, i end
    end
    table.remove(list, at)
  end
  return list
end

function M.render()
  -- ファイル名・パスは winbar（パンくず）に出すので、ここでは持たない。
  -- 幅の奪い合いが無くなり、ジャンプ項目を削らずに済む。
  -- 右端の「行:桁」は桁数で幅が変わる（1:1 は5桁、11111:12 は8桁）。
  -- 10 桁固定で予約していたため、大きな行番号ではみ出し、
  -- 左端が切られてクリック位置まで1桁ずれていた。実測して渡す。
  local pos = (" %d:%d "):format(vim.fn.line("."), vim.fn.col("."))
  local right = "%#StatusLine#" .. pos
  -- mid は先頭に空白1つを持つので、その分も引く
  local list = fit(math.max(0, vim.o.columns - vim.fn.strwidth(pos) - 1))
  if #list == 0 then
    return "%#StatusLine#%=" .. right
  end

  local mid = { "%#StatusLine# " }
  for i, e in ipairs(list) do
    if i > 1 then table.insert(mid, "%#NonText#│") end
    -- キーはヘッダーと同じく淡色にする（ラベルと同じ濃さだと読みにくい）
    local key = e.it.key ~= "" and ("%#Comment# " .. e.it.key .. "%#StatusLine#") or ""
    table.insert(mid,
      ("%%%d@v:lua.ViewerStatusJumpClick@%%#StatusLine# %s%s %%X")
        :format(e.idx, label_of(e.it), key))
  end

  return table.concat(mid) .. "%#StatusLine#%=" .. right
end

function M.enable()
  vim.o.laststatus = 3 -- 分割しても1本だけ出す
  vim.o.statusline = "%!v:lua.require'custom.statusline'.render()"
end

function M.disable()
  vim.o.statusline = ""
end

local sl_group = vim.api.nvim_create_augroup("ViewerStatusline", { clear = true })

vim.api.nvim_create_autocmd(
  { "LspAttach", "LspDetach", "BufEnter", "WinEnter", "TabEnter", "TabClosed" }, {
  group = sl_group,
  callback = function() vim.cmd("redrawstatus") end,
})

-- 差分を閉じた直後は、閉じる処理の途中で描き直されて古い内容が残ることがある。
-- 完全に閉じ切ってからもう一度描く。
vim.api.nvim_create_autocmd("User", {
  group = sl_group,
  pattern = { "DiffviewViewClosed", "DiffviewViewOpened" },
  callback = function()
    vim.schedule(function() pcall(vim.cmd, "redrawstatus") end)
  end,
})

vim.api.nvim_create_user_command("StatuslineToggle", function()
  if vim.o.statusline == "" then M.enable() else M.disable() end
end, { desc = "フッターの表示切替" })

M.enable()

return M
