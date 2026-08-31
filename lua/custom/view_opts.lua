-- ===================================================================
-- lua/custom/view_opts.lua
-- 表示オプションの切り替え（折り返し・行番号）
--
-- 差分は左右2つの窓で1つの内容を見るものなので、片方だけ折り返すと
-- 行がずれて比較できなくなる。切り替えは常にタブ内の全窓へ適用する。
-- ===================================================================

local M = {}

--- 対象にする窓の一覧
--- タブ内に差分の窓があればそちら（左右まとめて）、無ければ現在の窓だけ
---
--- 「現在の窓が差分か」で判定してはいけない。
--- `Space dd` はカーソルを**ファイル一覧パネル**に置くので、
--- そこから `Space w` を押すとパネルだけが折り返され、
--- 肝心の差分は変わらない。案内している導線の最初の一手で外れていた。
local function target_wins()
  local wins = {}
  for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    -- 差分の窓だけを対象にする（ファイル一覧パネルは除く）
    if vim.wo[w].diff then table.insert(wins, w) end
  end
  if #wins > 0 then return wins, true end
  return { vim.api.nvim_get_current_win() }, false
end

--- 折り返しの切替
function M.toggle_wrap()
  local wins, in_diff = target_wins()
  -- 判定の基準は「今いる窓」。左右で状態がずれていると、
  -- wins[1] を見ていては押しても見た目が変わらないことがある。
  local cur = vim.api.nvim_get_current_win()
  local base = vim.tbl_contains(wins, cur) and cur or wins[1]
  local to = not vim.wo[base].wrap
  for _, w in ipairs(wins) do
    vim.wo[w].wrap = to
    -- off のときも書き戻す。付けっぱなしにすると、その窓のオプションが
    -- 既定から外れたまま残る。
    vim.wo[w].linebreak = to    -- 単語の途中で折らない
    vim.wo[w].breakindent = to  -- 折り返し行のインデントを揃える
  end
  vim.notify(
    ("折り返し: %s%s"):format(to and "する" or "しない",
      in_diff and ("（差分の%d窓に適用）"):format(#wins) or ""),
    vim.log.levels.INFO)
end

--- 行番号の切替
function M.toggle_number()
  local wins = target_wins()
  local cur = vim.api.nvim_get_current_win()
  local base = vim.tbl_contains(wins, cur) and cur or wins[1]
  local to = not vim.wo[base].number
  for _, w in ipairs(wins) do
    vim.wo[w].number = to
  end
  vim.notify("行番号: " .. (to and "表示" or "非表示"), vim.log.levels.INFO)
end

vim.keymap.set("n", "<leader>w", M.toggle_wrap,
  { silent = true, desc = "折り返しの切替（差分では左右同時）" })

vim.api.nvim_create_user_command("WrapToggle", M.toggle_wrap,
  { desc = "折り返しの切替" })

return M
