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

--- 現在の差分ビューにあるファイル一覧の操作名を返す。
--- 差分ビューでなければ nil。
---@param tabpage? integer
---@return string?
function M.file_panel_label(tabpage)
  local view = M.view_at(tabpage or vim.api.nvim_get_current_tabpage())
  if not (view and view.panel and view.panel.is_open) then return nil end
  return view.panel:is_open() and "一覧を隠す" or "一覧を表示"
end

--- 現在の差分ビューのファイル一覧を開閉する。
---@return boolean toggled
function M.toggle_file_panel()
  if not M.file_panel_label() then return false end
  require("diffview.actions").toggle_files()
  vim.schedule(function() pcall(vim.cmd, "redrawstatus") end)
  return true
end

local default_resize_api = {
  list_wins = function(tabpage) return vim.api.nvim_tabpage_list_wins(tabpage) end,
  get_option = function(win, name) return vim.api.nvim_get_option_value(name, { win = win }) end,
  set_option = function(win, name, value)
    vim.api.nvim_set_option_value(name, value, { win = win })
  end,
  get_width = vim.api.nvim_win_get_width,
  set_width = vim.api.nvim_win_set_width,
}

--- タブ内に左右2つの差分窓があれば、その幅を均等にする。
--- ファイル一覧など差分以外の窓は一時的に幅固定して維持する。
---@param tabpage? integer
---@param api? table テスト用のウィンドウ操作
---@return boolean equalized
function M.equalize_diff_windows(tabpage, api)
  tabpage = tabpage or 0
  api = api or default_resize_api

  local wins = api.list_wins(tabpage)
  local diff_wins = {}
  for _, win in ipairs(wins) do
    if api.get_option(win, "diff") then
      table.insert(diff_wins, win)
    end
  end
  if #diff_wins ~= 2 then return false end

  local original = {}
  local original_widths = {}
  local ok = pcall(function()
    -- 先に全設定を読み取る。途中で読めなくても、窓の状態はまだ変わらない。
    for _, win in ipairs(wins) do
      original[win] = api.get_option(win, "winfixwidth")
    end
    for _, win in ipairs(wins) do
      api.set_option(win, "winfixwidth", not api.get_option(win, "diff"))
    end
    for _, win in ipairs(diff_wins) do
      original_widths[win] = api.get_width(win)
    end
    local total = original_widths[diff_wins[1]] + original_widths[diff_wins[2]]
    api.set_width(diff_wins[1], math.floor(total / 2))
    api.set_width(diff_wins[2], math.ceil(total / 2))
  end)

  if not ok then
    for win, width in pairs(original_widths) do
      pcall(api.set_width, win, width)
    end
  end
  local restored = true
  for _, win in ipairs(wins) do
    if original[win] ~= nil then
      restored = pcall(api.set_option, win, "winfixwidth", original[win]) and restored
    end
  end
  return ok and restored
end

local resize_pending = false
vim.api.nvim_create_autocmd("VimResized", {
  group = vim.api.nvim_create_augroup("ViewerDiffviewResize", { clear = true }),
  callback = function()
    if resize_pending then return end
    resize_pending = true
    vim.schedule(function()
      resize_pending = false
      pcall(function()
        local tabpage = vim.api.nvim_get_current_tabpage()
        if M.view_at(tabpage) then M.equalize_diff_windows(tabpage) end
      end)
    end)
  end,
  desc = "外側のペイン変更時に左右の差分幅を揃える",
})

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
