-- ===================================================================
-- lua/custom/view_opts.lua
-- 表示オプションの切り替え（折り返し・行番号）
--
-- 差分は左右2つの窓で1つの内容を見るものなので、片方だけ折り返すと
-- 行がずれて比較できなくなる。左右へ同時に適用し、次のファイルにも引き継ぐ。
-- ===================================================================

local M = {}
local wrap_preference

--- 一度選んだ折返しを、以後表示する通常ファイルと差分へ引き継ぐ。
function M.apply_wrap(win)
  win = win or vim.api.nvim_get_current_win()
  if wrap_preference == nil or not vim.api.nvim_win_is_valid(win) then return false end
  local buf = vim.api.nvim_win_get_buf(win)
  if vim.api.nvim_win_get_config(win).relative ~= "" then return false end
  if not vim.wo[win].diff and (vim.bo[buf].buftype ~= ""
      or vim.bo[buf].filetype:match("^Diffview")) then return false end
  vim.wo[win].wrap = wrap_preference
  vim.wo[win].linebreak = wrap_preference
  vim.wo[win].breakindent = wrap_preference
  return true
end

vim.api.nvim_create_autocmd({ "BufWinEnter", "WinEnter", "FileType" }, {
  group = vim.api.nvim_create_augroup("ViewerWrapPreference", { clear = true }),
  callback = function() M.apply_wrap() end,
})

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
  wrap_preference = to
  for _, w in ipairs(vim.api.nvim_list_wins()) do
    M.apply_wrap(w)
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
