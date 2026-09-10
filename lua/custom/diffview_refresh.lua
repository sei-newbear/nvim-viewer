-- 外部エージェントの保存は BufWritePost や index の監視では拾えない。
-- 表示中の作業ツリー差分だけを定期更新する。
local M = {}
local timer

function M.refresh()
  local view = require("diffview.lib").get_current_view()
  if not (view and view.ready and view.update_files and view.adapter
      and view.adapter:has_local(view.left, view.right)) then return end
  if view.closing:check() then return end
  -- index 監視と同じ入口を使う。独自に完了待ちすると、Diffview の
  -- debounce にコールバックが置き換えられた際に更新が止まってしまう。
  view:update_files()
end

function M.setup()
  if timer then return end
  timer = assert((vim.uv or vim.loop).new_timer())
  timer:start(1000, 1000, vim.schedule_wrap(M.refresh))
  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = vim.api.nvim_create_augroup("ViewerDiffviewRefresh", { clear = true }),
    once = true,
    callback = function()
      timer:stop()
      timer:close()
    end,
  })
end

return M
