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
---@return boolean 切り替えた後、整形表示なら true
function M.toggle(buf)
  buf = buf or vim.api.nvim_get_current_buf()
  local to_rendered = not M.is_rendered(buf)
  rendered[buf] = to_rendered

  local ok = pcall(function()
    if to_rendered then
      require("render-markdown.api").buf_enable()
    else
      require("render-markdown.api").buf_disable()
    end
  end)
  if not ok then
    pcall(function() require("render-markdown").buf_toggle() end)
  end

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
