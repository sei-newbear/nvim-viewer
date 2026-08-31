-- ===================================================================
-- lua/custom/view_opts.lua
-- 表示オプションの切り替え（折り返し・行番号）
--
-- 差分は左右2つの窓で1つの内容を見るものなので、片方だけ折り返すと
-- 行がずれて比較できなくなる。切り替えは常にタブ内の全窓へ適用する。
-- ===================================================================

local M = {}

--- 対象にする窓の一覧
--- 差分表示中はタブ内の全窓、そうでなければ現在の窓だけ
local function target_wins()
  local cur = vim.api.nvim_get_current_win()
  local in_diff = vim.wo[cur].diff

  if not in_diff then
    return { cur }
  end

  local wins = {}
  for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    -- 差分の窓だけを対象にする（ファイル一覧パネルは除く）
    if vim.wo[w].diff then table.insert(wins, w) end
  end
  return #wins > 0 and wins or { cur }
end

--- 折り返しの切替
function M.toggle_wrap()
  local wins = target_wins()
  local to = not vim.wo[wins[1]].wrap
  for _, w in ipairs(wins) do
    vim.wo[w].wrap = to
    if to then
      vim.wo[w].linebreak = true    -- 単語の途中で折らない
      vim.wo[w].breakindent = true  -- 折り返し行のインデントを揃える
    end
  end
  vim.notify(
    ("折り返し: %s%s"):format(to and "する" or "しない",
      #wins > 1 and ("（差分の%d窓に適用）"):format(#wins) or ""),
    vim.log.levels.INFO)
end

--- 行番号の切替
function M.toggle_number()
  local wins = target_wins()
  local to = not vim.wo[wins[1]].number
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
