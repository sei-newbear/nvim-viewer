-- ===================================================================
-- lua/custom/reset.lua
-- 開きすぎた画面を、最初にファイルを開いた状態へ戻す
--
-- 差分タブ・ツリー・ピッカー・浮動ウィンドウ・分割が積み重なると
-- 何がどこにあるか分からなくなる。1操作で片付けられるようにする。
--
-- 「最初に開いたファイル」は起動時に覚えておき、そこへ戻る。
-- ===================================================================

local M = {}

--- 起動時に開いていたファイルのバッファ
local initial_buf = nil

vim.api.nvim_create_autocmd("VimEnter", {
  group = vim.api.nvim_create_augroup("ViewerReset", { clear = true }),
  once = true,
  callback = function()
    local buf = vim.api.nvim_get_current_buf()
    if vim.bo[buf].buftype == "" and vim.api.nvim_buf_get_name(buf) ~= "" then
      initial_buf = buf
    end
  end,
})

--- 戻り先のバッファを決める
local function home_buf()
  if initial_buf and vim.api.nvim_buf_is_valid(initial_buf)
    and vim.api.nvim_buf_is_loaded(initial_buf) then
    return initial_buf
  end
  -- 起動時のファイルが無ければ、実ファイルのバッファの先頭
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if vim.bo[b].buflisted and vim.bo[b].buftype == ""
      and vim.api.nvim_buf_get_name(b) ~= "" then
      return b
    end
  end
  return nil
end

--- すべて閉じて最初の状態に戻す
---@param opts? { keep_buffers?: boolean }
function M.reset(opts)
  opts = opts or {}
  local closed = { diff = 0, picker = 0, float = 0, tab = 0, win = 0, buf = 0 }

  -- 1) 差分ビューを閉じる（自前のタブページを持つので最初に処理する）
  local ok, lib = pcall(require, "diffview.lib")
  if ok and lib.views then
    for _ = 1, #lib.views do
      if pcall(vim.cmd, "DiffviewClose") then closed.diff = closed.diff + 1 end
    end
  end

  -- 2) ピッカー・ツリーを閉じる
  local ok_s, Snacks = pcall(require, "snacks")
  if ok_s and Snacks.picker then
    for _, p in ipairs(Snacks.picker.get() or {}) do
      if pcall(function() p:close() end) then closed.picker = closed.picker + 1 end
    end
  end

  -- 3) 浮動ウィンドウ（早見表・ホバー・通知など）を閉じる
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local cfg = vim.api.nvim_win_get_config(win)
    if cfg.relative and cfg.relative ~= "" then
      if pcall(vim.api.nvim_win_close, win, true) then closed.float = closed.float + 1 end
    end
  end

  -- 4) 余分なタブページを閉じる
  closed.tab = math.max(0, #vim.api.nvim_list_tabpages() - 1)
  pcall(vim.cmd, "silent! tabonly")

  -- 5) 分割を1つに戻す
  closed.win = math.max(0, #vim.api.nvim_tabpage_list_wins(0) - 1)
  pcall(vim.cmd, "silent! only")

  -- 6) 最初のファイルへ戻る
  local home = home_buf()
  if home then
    pcall(vim.api.nvim_set_current_buf, home)
  end

  -- 7) 他のバッファを片付ける（Space b の一覧も綺麗になる）
  if not opts.keep_buffers then
    for _, b in ipairs(vim.api.nvim_list_bufs()) do
      if b ~= home and vim.api.nvim_buf_is_valid(b) and vim.bo[b].buflisted then
        if pcall(vim.api.nvim_buf_delete, b, { force = true }) then
          closed.buf = closed.buf + 1
        end
      end
    end
  end

  -- 何を片付けたかを伝える（黙って消えると不安なため）
  local parts = {}
  local labels = {
    { closed.diff,   "差分" },
    { closed.picker, "一覧" },
    { closed.float,  "ポップアップ" },
    { closed.tab,    "タブ" },
    { closed.win,    "分割" },
    { closed.buf,    "ファイル" },
  }
  for _, e in ipairs(labels) do
    if e[1] > 0 then table.insert(parts, ("%s%d"):format(e[2], e[1])) end
  end

  local name = home and vim.fn.fnamemodify(vim.api.nvim_buf_get_name(home), ":t") or "[無名]"
  vim.notify(
    #parts > 0
      and ("片付けました（%s）→ %s"):format(table.concat(parts, " / "), name)
      or ("すでに片付いています → %s"):format(name),
    vim.log.levels.INFO)
end

--- 画面だけ片付けて、開いたファイルは残す
function M.reset_layout()
  M.reset({ keep_buffers = true })
end

vim.keymap.set("n", "<leader>0", M.reset,
  { silent = true, desc = "全部閉じて最初の状態に戻す" })

vim.api.nvim_create_user_command("Reset", function(a)
  if a.bang then M.reset_layout() else M.reset() end
end, { bang = true, desc = "全部閉じて最初の状態に戻す（! で開いたファイルは残す）" })

return M
