-- ===================================================================
-- lua/custom/toolbar.lua
-- 画面上部に常時表示される、マウスでクリックできるメニューバー
--
-- 上下の使い分け:
--   ヘッダー(ここ)      = どこを見るか。移動・グローバルな操作
--   フッター(statusline) = 今のファイルをどう読むか。文脈に依存する操作
-- 「そのファイルに対する操作」(生ファイル⇄整形・ブラウザ・差分から開く・
-- 折り返し)はフッター側に置いてある。ここに混ぜると分類が崩れる。
--
-- ファイル名はフッターに出すので、ここでは出さない（上下で重複させない）。
--
-- ここに置くのは「よく使う移動」だけに絞る。たまにしか使わないもの
-- （画面の片付けなど）はコマンドパレットから辿れるので並べない。
--
-- ショートカットを覚えていなくても操作できるようにするのが目的。
-- herdr は右クリックを自分のペインメニューに使うため（既定）、
-- nvim 側の右クリックメニューは当てにできない。そこで
-- 「常に見えていて、左クリックで押せるバー」を操作の入口にする。
--
-- クリック領域は Neovim 標準の tabline 機能を使う:
--   %<n>@<関数名>@ラベル%X   n がクリック時に minwid として渡る
-- ===================================================================

local M = {}

--- ボタン定義（表示順）
--- prio: 画面が狭いときに残す優先度。大きいほど残る。
---       関数を渡すと、そのときの状況で優先度を変えられる。
---       nil を返すと、そもそも表示しない。
--- 「コマンド」は全操作への入口なので最優先で残す。
local BUTTONS = {
  { label = "コマンド",   hint = "F1", prio = 100, run = function() require("custom.palette").open() end },
  { label = "ツリー",     hint = "␣t", prio = 80,  run = function()
      local S = require("snacks")
      local ex = (S.picker.get({ source = "explorer" }) or {})[1]
      if ex then ex:close() else S.explorer.reveal() end
    end },
  -- 「差分」は行き先であって切り替えではない。
  -- 押したら必ず差分が見える状態にする（開いていればそのタブへ移動）。
  -- トグルにすると、差分を見たくて押したのに閉じてしまい「効かない」と見える。
  -- 閉じるのは Space dc / Space 0 の役目。
  { label = "差分",       hint = "␣dd", prio = 90, run = function()
      local ok, lib = pcall(require, "diffview.lib")
      if ok and lib.views then
        for _, v in ipairs(lib.views) do
          if v.tabpage and vim.api.nvim_tabpage_is_valid(v.tabpage) then
            vim.api.nvim_set_current_tabpage(v.tabpage)
            return
          end
        end
      end
      vim.cmd("DiffviewOpen")
    end },
  { label = "ファイル",   hint = "⌃p", prio = 50,   run = function() require("snacks").picker.files() end },
  { label = "最近",       hint = "␣r", prio = 40,  run = function() require("snacks").picker.recent() end },
  { label = "検索",       hint = "␣/", prio = 60,  run = function() require("snacks").picker.grep() end },
  { label = "ヘルプ",     hint = "?", prio = 70,        run = function() require("custom.cheatsheet").open() end },
}

-- ---- 文脈バッファ ----
-- ピッカーやツリーを開いている間、現在バッファはそれらの特殊バッファになる。
-- そのままだとツールバーの内容（マークダウン用ボタンやファイル名）が
-- 開くたびに入れ替わり、ボタンの位置までずれてしまう。
-- そこで「最後に見ていた実ファイル」を覚えて、それを文脈として使う。
local last_file_buf = nil

vim.api.nvim_create_autocmd({ "BufEnter", "BufWinEnter" }, {
  group = vim.api.nvim_create_augroup("ViewerToolbarContext", { clear = true }),
  callback = function(ev)
    if vim.bo[ev.buf].buftype == "" and vim.api.nvim_buf_get_name(ev.buf) ~= "" then
      last_file_buf = ev.buf
    end
  end,
})

--- 判定に使うバッファを返す
local function context_buf()
  local cur = vim.api.nvim_get_current_buf()
  if vim.bo[cur].buftype == "" and vim.api.nvim_buf_get_name(cur) ~= "" then
    return cur
  end
  if last_file_buf and vim.api.nvim_buf_is_valid(last_file_buf) then
    return last_file_buf
  end
  return cur
end

M.context_buf = context_buf

--- クリックされたときに呼ばれる（tabline から minwid でボタン番号が渡る）
---@param minwid integer ボタン番号(1始まり)
function M.on_click(minwid, _clicks, _button, _modifiers)
  local b = BUTTONS[minwid]
  if not b then return end
  vim.schedule(function()
    local ok, err = pcall(b.run)
    if not ok then
      vim.notify("実行に失敗しました: " .. tostring(err), vim.log.levels.ERROR)
    end
  end)
end

-- tabline から呼べるようグローバルに公開する
_G.ViewerToolbarClick = M.on_click

--- 画面幅に収まるボタンを選ぶ
--- 狭いペインでバーが左に切り詰められると、先頭の「コマンド」が
--- 見えなくなって操作の入口を失うため、あらかじめ間引く。
--- そのときの優先度を求める。nil なら表示しない。
local function priority_of(b)
  if type(b.prio) == "function" then return b.prio() end
  return b.prio or 0
end

--- ラベルを求める。状態で変わるボタンは関数で持つ。
local function label_of(b)
  if type(b.label) == "function" then
    local ok, v = pcall(b.label)
    return ok and v or "?"
  end
  return b.label
end

--- 一覧の表示に必要な幅
--- with_hints=true のときはラベルの後ろにキーも並べる
local function cost(list, with_hints)
  local n = 0
  for _, e in ipairs(list) do
    n = n + vim.fn.strdisplaywidth(label_of(e.button)) + 2 -- ラベル＋左右の余白
    if with_hints and e.button.hint and e.button.hint ~= "" then
      n = n + vim.fn.strdisplaywidth(e.button.hint) + 1
    end
  end
  -- 区切りは "│" の1桁。ここを実際の描画と合わせないと、
  -- 必要以上にボタンを落としてしまう。
  return n + math.max(0, #list - 1) + 1
end

local function fit(width)

  -- まず「今表示する意味のあるもの」だけに絞る。
  -- ラベルは状態で変わりうるので、元の配列の位置(idx)で同一性を保つ。
  local list = {}
  for i, b in ipairs(BUTTONS) do
    local p = priority_of(b)
    if p ~= nil then
      table.insert(list, { idx = i, button = b, prio = p })
    end
  end

  while #list > 1 and cost(list, false) > width do
    local worst, at = math.huge, nil
    for i, e in ipairs(list) do
      if e.prio < worst then worst, at = e.prio, i end
    end
    table.remove(list, at)
  end
  return list
end

--- tabline の文字列を組み立てる
function M.render()
  local width = vim.o.columns
  -- ファイル名はフッターに出すので、ここでは場所を取らない。
  -- 空いた分だけボタンやキーを多く出せる。
  local reserve = 0
  local list = fit(width - reserve)

  -- キーを併記すると幅が3割ほど増える。ボタンを削ってまで出すのは
  -- 本末転倒なので、「全ボタンがキー付きで収まるときだけ」併記する。
  -- 全画面(Ctrl+b z)ではキーが出て、分割中はボタン優先になる。
  local with_hints = cost(list, true) <= (width - reserve)

  local parts = { "%#TabLineFill# " }
  for i, e in ipairs(list) do
    if i > 1 then
      table.insert(parts, "%#NonText#│")
    end
    -- %<番号>@<関数>@ ラベル %X  でクリック領域になる。
    -- 番号は元の配列での位置。間引いても押した先がずれない。
    local hint = ""
    if with_hints and e.button.hint and e.button.hint ~= "" then
      hint = ("%%#Comment#%s%%#TabLine#"):format(" " .. e.button.hint)
    end
    table.insert(parts,
      ("%%%d@v:lua.ViewerToolbarClick@%%#TabLine# %s%s %%X"):format(e.idx, label_of(e.button), hint))
  end
  table.insert(parts, "%#TabLineFill#%=")
  return table.concat(parts)
end

--- ボタンの一覧（他のモジュールから参照する用）
function M.buttons()
  return BUTTONS
end

function M.enable()
  vim.o.showtabline = 2 -- 常に表示する
  vim.o.tabline = "%!v:lua.require'custom.toolbar'.render()"
end

function M.disable()
  vim.o.showtabline = 1
  vim.o.tabline = ""
end

function M.toggle()
  if vim.o.showtabline == 2 and vim.o.tabline ~= "" then
    M.disable()
    vim.notify("メニューバーを隠しました", vim.log.levels.INFO)
  else
    M.enable()
    vim.notify("メニューバーを表示しました", vim.log.levels.INFO)
  end
end

vim.api.nvim_create_user_command("ToolbarToggle", M.toggle,
  { desc = "上部メニューバーの表示切替" })

M.enable()

return M
