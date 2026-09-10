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
