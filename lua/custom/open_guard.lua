-- ===================================================================
-- lua/custom/open_guard.lua
-- 差分ウィンドウを別のファイルで乗っ取らせない
--
-- 問題: 差分を開いた状態でツリーやファイル検索からファイルを選ぶと、
-- 差分の左右どちらかのウィンドウが選んだファイルに置き換わり、
-- 差分が壊れる。
--
--   開く前:  diff=true index.ts │ diff=true  index.ts
--   開いた後: diff=true index.ts │ diff=false greeter.ts   ← 壊れる
--
-- 原因: snacks はジャンプ先ウィンドウを「現在タブの通常ファイル窓」から
-- 選ぶが、差分ウィンドウもその条件を満たしてしまう（winfixbuf も見ない）。
--
-- 対処: ツリー・ファイル検索・LSPジャンプはすべて
-- `Snacks.picker.actions.jump` を通るので、そこを1か所だけ包む。
-- 差分ウィンドウが選ばれそうなら、差分でないタブの窓に差し替える。
-- （nvim_set_current_win は他タブの窓でもタブごと切り替えてくれる）
-- ===================================================================

local M = {}

--- 差分ウィンドウを含まないタブの、通常ファイル用ウィンドウを探す
local function find_safe_win()
  local candidates = {}
  for _, tab in ipairs(vim.api.nvim_list_tabpages()) do
    local wins = vim.api.nvim_tabpage_list_wins(tab)
    local has_diff = false
    for _, w in ipairs(wins) do
      if vim.wo[w].diff then has_diff = true break end
    end
    for _, w in ipairs(wins) do
      local cfg = vim.api.nvim_win_get_config(w)
      local buf = vim.api.nvim_win_get_buf(w)
      local usable = (cfg.relative == "" or cfg.relative == nil)
        and not vim.wo[w].diff
        and vim.bo[buf].buftype == ""
      if usable then
        -- 差分を含まないタブの窓を優先する
        table.insert(candidates, { win = w, score = has_diff and 1 or 2 })
      end
    end
  end
  table.sort(candidates, function(a, b) return a.score > b.score end)
  return candidates[1] and candidates[1].win or nil
end

--- ジャンプ先が差分ウィンドウなら、安全な窓へ差し替える
local function ensure_safe(picker)
  local main = picker.main
  if main and vim.api.nvim_win_is_valid(main) and not vim.wo[main].diff then
    return -- そのままで問題ない
  end

  local safe = find_safe_win()
  if not safe then
    -- 差分しかない場合は新しいタブを作る（差分は残したまま別の場所で開く）
    vim.cmd("tabnew")
    safe = vim.api.nvim_get_current_win()
  end

  -- picker.main は内部の Main オブジェクト経由で設定する
  if picker._main and picker._main.set then
    picker._main:set(safe)
  else
    pcall(function() picker.main = safe end)
  end
end

function M.setup()
  local ok, A = pcall(require, "snacks.picker.actions")
  if not ok or type(A.jump) ~= "function" then return false end
  if A.__viewer_guarded then return true end

  local orig = A.jump
  A.jump = function(picker, item, action)
    pcall(ensure_safe, picker)
    return orig(picker, item, action)
  end
  A.__viewer_guarded = true
  return true
end

-- snacks は遅延読み込みされることがあるので、失敗したら後で張り直す
if not M.setup() then
  vim.api.nvim_create_autocmd("User", {
    pattern = "VeryLazy",
    once = true,
    callback = function() M.setup() end,
  })
end

return M
