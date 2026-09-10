-- 2画面差分は変更前を赤、変更後を緑で表示する。
-- 背景色だけを指定して、元の構文ハイライトを残す。
local M = {}

local function define_highlights()
  local colors = vim.o.background == "light"
    and { "#fbe9e7", "#f3b8b3", "#e6f4ea", "#a9dcb8" }
    or { "#302024", "#653039", "#1e3028", "#285c3d" }
  for i, name in ipairs({ "OldLine", "OldText", "NewLine", "NewText" }) do
    vim.api.nvim_set_hl(0, "ViewerDiff" .. name, { bg = colors[i] })
  end
end

function M.apply(_, winid, ctx)
  if not ctx or not ctx.layout_name:match("^diff2_") then return end
  local side = ({ a = "Old", b = "New" })[ctx.symbol]
  if not side or not vim.api.nvim_win_is_valid(winid) then return end
  vim.api.nvim_win_call(winid, function()
    vim.opt_local.winhighlight:append({
      DiffAdd = "ViewerDiff" .. side .. "Line",
      DiffChange = "ViewerDiff" .. side .. "Line",
      DiffText = "ViewerDiff" .. side .. "Text",
      DiffTextAdd = "ViewerDiff" .. side .. "Text",
    })
  end)
end

vim.api.nvim_create_autocmd("ColorScheme", {
  group = vim.api.nvim_create_augroup("ViewerDiffHighlight", { clear = true }),
  callback = define_highlights,
})
define_highlights()

return M
