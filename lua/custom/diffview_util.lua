-- ===================================================================
-- lua/custom/diffview_util.lua
-- 差分を「確実に」閉じる
--
-- `DiffviewClose` は **今いるタブのビューしか閉じない**。
-- 別のタブから呼ぶと何も起きず、通知も出ない。
-- そこから次の不具合が派生していた:
--   - ブレイムの差分を開き直すたびにタブが積み上がる
--   - 「差分を閉じる」を通常タブで押すと無言で空振り
--   - 片付けの集計が、閉じられなかったものを閉じたと数える
--
-- どのタブから呼んでも閉じられるよう、対象のタブへ移ってから閉じる。
-- ===================================================================

local M = {}

--- 開いているビューの一覧
local function views()
  local ok, lib = pcall(require, "diffview.lib")
  if not (ok and lib.views) then return {} end
  return lib.views
end

--- 指定のビュー（省略時は全部）を閉じる
--- 元居たタブへは戻す。閉じた数を返す。
---@param target? table 閉じたいビュー
---@return integer closed
function M.close(target)
  local list = views()
  if #list == 0 then return 0 end

  local origin = vim.api.nvim_get_current_tabpage()
  local n = 0
  -- 閉じると添字がずれるので、対象を先に控える
  local wanted = {}
  for _, v in ipairs(list) do
    if not target or v == target then table.insert(wanted, v) end
  end

  for _, v in ipairs(wanted) do
    if v.tabpage and vim.api.nvim_tabpage_is_valid(v.tabpage) then
      pcall(vim.api.nvim_set_current_tabpage, v.tabpage)
    end
    if pcall(vim.cmd, "DiffviewClose") then n = n + 1 end
  end

  if vim.api.nvim_tabpage_is_valid(origin) then
    pcall(vim.api.nvim_set_current_tabpage, origin)
  end
  return n
end

--- そのタブページに対応するビューを返す
function M.view_at(tabpage)
  for _, v in ipairs(views()) do
    if v.tabpage == tabpage then return v end
  end
  return nil
end

--- 開いているビューの数
function M.count()
  return #views()
end

--- 既にビューが開いていればそのタブへ移り、true を返す
--- 同じ差分を二重に開かないため（キーとボタンで挙動を揃える）
function M.focus_existing()
  local v = views()[1]
  if v and v.tabpage and vim.api.nvim_tabpage_is_valid(v.tabpage) then
    vim.api.nvim_set_current_tabpage(v.tabpage)
    return true
  end
  return false
end

vim.api.nvim_create_user_command("DiffviewCloseAll", function() M.close() end,
  { desc = "開いている差分をすべて閉じる（どのタブからでも）" })

return M
