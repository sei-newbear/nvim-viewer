-- ===================================================================
-- lua/custom/md_view.lua
-- マークダウンの「整形表示 ⇄ 生ファイル」の切り替えを一箇所で管理する
--
-- キーマップ・ツールバー・コマンドパレットの3箇所から呼ばれるため、
-- 状態の持ち主を1つに決めておかないと、ボタンの表示と実際の状態がずれる。
--
-- 注意: このビューアーは「最初から整形表示」が既定。
-- VSCode のように「生で開いてプレビューに入る」のとは逆なので、
-- ボタンには **押すと何になるか**（行き先）を表示する。
-- ===================================================================

local M = {}

--- バッファごとの状態。true/nil = 整形表示, false = 生ファイル
local rendered = {}

---@return boolean 整形表示中なら true
function M.is_rendered(buf)
  buf = buf or vim.api.nvim_get_current_buf()
  return rendered[buf] ~= false
end

--- 整形表示 ⇄ 生ファイル を切り替える
---
--- 対象バッファは必ず引数で受ける。
--- render-markdown の `api.buf_enable/buf_disable` は buf を取らず
--- **常に現在バッファ**へ作用するため、フッターのボタンのように
--- 「別のバッファを指しながら押す」経路では、記録した状態と実際が食い違う。
--- buf を取れる `core.manager.set_buf` を直接呼ぶ。
---@return boolean 切り替えた後、整形表示なら true
function M.toggle(buf)
  buf = buf or vim.api.nvim_get_current_buf()

  -- 対象外のバッファでは何も起きない（set_buf は無言の no-op）。
  -- 記録だけ書き換えると、以後ラベルと実際がずれ続ける。
  local mok, mgr = pcall(require, "render-markdown.core.manager")
  if not (mok and mgr.attached and mgr.attached(buf)) then
    vim.notify("このバッファは整形表示の対象ではありません", vim.log.levels.WARN)
    return M.is_rendered(buf)
  end

  local to_rendered = not M.is_rendered(buf)
  rendered[buf] = to_rendered

  pcall(mgr.set_buf, buf, to_rendered)

  -- frontmatter の装飾も一緒に付け外しする。
  -- 片方だけ残ると「生ファイル」にならない。
  pcall(function() require("custom.frontmatter").set(buf, to_rendered) end)

  vim.notify(to_rendered and "整形表示" or "生ファイル", vim.log.levels.INFO)
  return to_rendered
end

--- ボタンに出すラベル（行き先を示す）
function M.toggle_label(buf)
  return M.is_rendered(buf) and "生ファイル" or "整形表示"
end

vim.api.nvim_create_autocmd("BufDelete", {
  group = vim.api.nvim_create_augroup("ViewerMdView", { clear = true }),
  callback = function(ev) rendered[ev.buf] = nil end,
})

return M
