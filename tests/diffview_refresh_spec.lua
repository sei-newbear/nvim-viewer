local repo = vim.fn.getcwd()
vim.opt.rtp:prepend(repo)
local plugins = vim.env.VIEWER_TEST_PLUGIN_DIR or (vim.fn.stdpath("data") .. "/lazy")
for _, name in ipairs({ "plenary.nvim", "nvim-web-devicons", "diffview.nvim" }) do
  vim.opt.rtp:append(plugins .. "/" .. name)
end

local tmp = vim.fn.tempname()
vim.fn.mkdir(tmp, "p")
local function git(...)
  local args = { "git", "-C", tmp }
  vim.list_extend(args, { ... })
  local output = vim.fn.system(args)
  assert(vim.v.shell_error == 0, output)
end
local function write(name, lines) vim.fn.writefile(lines, tmp .. "/" .. name) end
local ok, err = xpcall(function()
  git("init", "-q")
  write("example.txt", { "original" })
  write("removed.txt", { "original" })
  git("add", "example.txt", "removed.txt")
  -- 架空のテスト用著者。ユーザーの Git 設定に依存しない。
  git("-c", "user.name=Test User", "-c", "user.email=test@example.invalid",
    "-c", "commit.gpgsign=false", "commit", "-qm", "fixture")
  vim.cmd.cd(tmp)
  require("diffview").setup(require("plugins.diffview")[1].opts())
  require("diffview").open({})
  local view = require("diffview.lib").get_current_view()
  assert(vim.wait(5000, function() return view.ready end), "差分を開けない")
  vim.wait(300, function() return false end)
  -- 初回の監視を終えてから、無変更時の再構築回数を測る。
  vim.wait(1500, function() return false end)
  local get_updated = view.get_updated_files
  local idle_updates = 0
  view.get_updated_files = function(...)
    idle_updates = idle_updates + 1
    return get_updated(...)
  end
  vim.wait(1300, function() return false end)
  view.get_updated_files = get_updated
  assert(idle_updates == 0, "変更がないのに差分一覧を再構築した")

  -- index を変更せず、外部保存と同じようにディスクだけを変更する。
  write("example.txt", { "changed", "second line" })
  write("added.txt", { "new file" })
  vim.fn.delete(tmp .. "/removed.txt")
  local function entries()
    local found = {}
    for _, entry in ipairs(view.files.working) do found[entry.path] = entry.status end
    return found
  end
  assert(vim.wait(4000, function()
    local found = entries()
    return found["example.txt"] == "M" and found["added.txt"] == "?"
      and found["removed.txt"] == "D"
  end), "外部で変更・追加・削除したファイルが一覧に自動反映されない")

  view:set_file_by_path("example.txt")
  local local_buf
  assert(vim.wait(3000, function()
    local_buf = vim.fn.bufnr(tmp .. "/example.txt")
    if local_buf <= 0 or not vim.api.nvim_buf_is_loaded(local_buf) then return false end
    if vim.api.nvim_buf_get_lines(local_buf, 0, 1, false)[1] ~= "changed" then return false end
    for _, win in ipairs(vim.api.nvim_tabpage_list_wins(view.tabpage)) do
      if vim.wo[win].diff and vim.api.nvim_win_get_buf(win) == local_buf then return true end
    end
    return false
  end))
  -- ステータスM・ファイルサイズが変わらない保存も検出する。
  write("example.txt", { "updated", "second line" })
  assert(vim.wait(4000, function()
    return vim.api.nvim_buf_get_lines(local_buf, 0, 1, false)[1] == "updated"
  end), "同じステータス・同じサイズの外部保存で表示内容が古いまま")

  -- 表示中の未追跡ファイルが外部で削除されると、一覧からも消える。
  view:set_file_by_path("added.txt")
  assert(vim.wait(3000, function()
    return view.cur_entry and view.cur_entry.path == "added.txt" and view.cur_entry.opened
  end), "削除対象のファイルを開けない")
  local async = require("diffview.async")
  local active, peak, completed = 0, 0, 0
  local callbacks, callback_errors = {}, {}
  view.get_updated_files = async.wrap(function(self, callback)
    active = active + 1
    peak = math.max(peak, active)
    vim.defer_fn(function()
      get_updated(self, function(...)
        active = active - 1
        callback(...)
      end)
    end, 1250)
  end, 2)
  vim.fn.delete(tmp .. "/added.txt")
  for i = 1, 5 do
    vim.defer_fn(function()
      view:update_files(function(update_err)
        completed = completed + 1
        callbacks[i] = (callbacks[i] or 0) + 1
        if update_err then callback_errors[#callback_errors + 1] = update_err end
      end)
    end, i * 150)
  end
  assert(vim.wait(8000, function()
    return completed == 5 and active == 0 and entries()["added.txt"] == nil
  end, 20), "表示中ファイルの削除後に更新が完了しない／コールバックが失われた")
  assert(peak == 1, "差分更新が重複して実行された")
  for i = 1, 5 do assert(callbacks[i] == 1, "更新要求の完了通知が重複／欠落した") end
  assert(#callback_errors == 0, vim.inspect(callback_errors))
  view.get_updated_files = get_updated

  write("example.txt", { "original" })
  write("removed.txt", { "original" })
  vim.fn.delete(tmp .. "/added.txt")
  assert(vim.wait(4000, function() return #view.files.working == 0 end),
    "変更を戻しても一覧に残る")

  vim.cmd("tabnew")
  local other_tab = vim.api.nvim_get_current_tabpage()
  write("added.txt", { "background change" })
  vim.wait(1300, function() return false end)
  assert(#view.files.working == 0, "非表示の差分まで定期更新した")
  vim.api.nvim_set_current_tabpage(view.tabpage)
  assert(vim.wait(4000, function() return entries()["added.txt"] == "?" end),
    "差分タブに戻っても一覧が更新されない")

  -- 古いビューが更新待ちでも、閉じて開き直したビューを止めない。
  local started, finished = false, false
  view.get_updated_files = async.wrap(function(self, callback)
    started = true
    vim.defer_fn(function() get_updated(self, callback) end, 1250)
  end, 2)
  view:update_files(function() finished = true end)
  assert(vim.wait(3000, function() return started end))
  require("diffview").close()
  require("diffview").open({})
  local reopened = require("diffview.lib").get_current_view()
  assert(vim.wait(6000, function()
    return finished and reopened.ready and #reopened.files.working > 0
  end), "更新中に閉じると新しい差分ビューの更新も停止した")
  require("diffview").close()

  require("diffview").open({ "HEAD..HEAD" })
  local history = require("diffview.lib").get_current_view()
  assert(vim.wait(5000, function() return history.ready end))
  vim.wait(300, function() return false end)
  local updates = 0
  local update = history.update_files
  history.update_files = function(...) updates = updates + 1; return update(...) end
  vim.wait(1300, function() return false end)
  assert(updates == 0, "固定コミット同士の比較を定期更新した")
  history.update_files = update
  require("diffview").close()
  assert(vim.api.nvim_tabpage_is_valid(other_tab))
end, debug.traceback)
vim.cmd.cd(repo)
vim.fn.delete(tmp, "rf")
assert(ok, err)
print("diffview_refresh_spec: OK")
