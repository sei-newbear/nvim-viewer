-- 外部保存を検出し、変更のある作業ツリー差分だけを更新する。
local M = {}
local timer
local uv = vim.uv or vim.loop
local snapshots = setmetatable({}, { __mode = "k" })
local polling = false

local function reload_visible_files(view)
  if view.tabpage ~= vim.api.nvim_get_current_tabpage() then return end
  local seen = {}
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(view.tabpage)) do
    local buf = vim.api.nvim_win_get_buf(win)
    if not seen[buf] and vim.wo[win].diff and vim.bo[buf].buftype == ""
        and not vim.bo[buf].modified and uv.fs_stat(vim.api.nvim_buf_get_name(buf)) then
      seen[buf] = true
      local autoread = vim.bo[buf].autoread
      vim.bo[buf].autoread = true
      local ok, err = pcall(vim.cmd, "checktime " .. buf)
      if vim.api.nvim_buf_is_valid(buf) then vim.bo[buf].autoread = autoread end
      if not ok then vim.notify(err, vim.log.levels.ERROR) end
    end
  end
end

-- 本体のdebounceは完了待ちではない。手動更新・index監視も
-- 直列化し、削除中の一覧を別の更新が触らないようにする。
local function serialize_updates()
  local DiffView = require("diffview.scene.views.diff.diff_view").DiffView
  local update = DiffView.update_files
  local queue, pending = {}, {}
  local busy = false
  local drain
  drain = function()
    if busy or #queue == 0 then return end
    busy = true
    local request = table.remove(queue, 1)
    pending[request.view] = nil
    local function finish(err)
      -- 本体の共有debounceが静まってから次の要求を渡す。
      vim.defer_fn(function()
        busy = false
        drain()
      end, 110)
      for _, callback in ipairs(request.callbacks) do
        local ok, message = pcall(callback, err)
        if not ok then vim.notify(message, vim.log.levels.ERROR) end
      end
    end
    if request.view.closing:check() then
      finish({ "The update was cancelled." })
    else
      reload_visible_files(request.view)
      update(request.view, finish)
    end
  end
  DiffView.update_files = function(view, callback)
    local request = pending[view]
    if not request then
      request = { view = view, callbacks = {} }
      pending[view] = request
      queue[#queue + 1] = request
    end
    if callback then request.callbacks[#request.callbacks + 1] = callback end
    drain()
  end
end

local function signature(root, status)
  local parts = { status }
  -- -z ならファイル名に改行や引用符があっても区別できる。
  local records = vim.split(status, "\0", { plain = true, trimempty = true })
  local i = 1
  while i <= #records do
    local record = records[i]
    local stat = uv.fs_stat(root .. "/" .. record:sub(4))
    if stat then
      parts[#parts + 1] = table.concat({ stat.size, stat.mtime.sec,
        stat.mtime.nsec, stat.ctime.sec, stat.ctime.nsec }, ":")
    else
      parts[#parts + 1] = "missing"
    end
    if record:sub(1, 2):find("[RC]") then i = i + 1 end
    i = i + 1
  end
  return table.concat(parts, "\0")
end

function M.refresh()
  if polling then return end
  local lib = require("diffview.lib")
  local view = lib.get_current_view()
  if not (view and view.ready and view.update_files and view.adapter
      and view.adapter:has_local(view.left, view.right)) then return end
  if view.closing:check() then return end
  local root = view.adapter.ctx.toplevel
  if not root then return end
  polling = true
  vim.system({ "git", "--no-optional-locks", "-C", root, "status",
    "--porcelain=v1", "-z", "--untracked-files=all" }, { text = false }, function(result)
    vim.schedule(function()
      polling = false
      if result.code ~= 0 or view.closing:check() or lib.get_current_view() ~= view then return end
      local current = signature(root, result.stdout)
      if snapshots[view] == current then return end
      view:update_files(function(err)
        if not err then snapshots[view] = current end
      end)
    end)
  end)
end

function M.setup()
  if timer then return end
  serialize_updates()
  timer = assert(uv.new_timer())
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
