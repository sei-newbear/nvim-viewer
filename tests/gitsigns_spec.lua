local repo = vim.fn.getcwd()
vim.opt.rtp:prepend(repo)
vim.opt.rtp:append((vim.env.VIEWER_TEST_PLUGIN_DIR or (vim.fn.stdpath("data") .. "/lazy")) .. "/gitsigns.nvim")
local tmp = vim.fn.tempname()
vim.fn.mkdir(tmp, "p")
local function git(...)
  local args = { "git", "-C", tmp }
  vim.list_extend(args, { ... })
  local output = vim.fn.system(args)
  assert(vim.v.shell_error == 0, output)
end
local ok, err = xpcall(function()
  git("init", "-q")
  local original = {}
  for i = 1, 15 do original[i] = ("example line %02d"):format(i) end
  vim.fn.writefile(original, tmp .. "/example.txt")
  git("add", "example.txt")
  git("-c", "user.name=Test User", "-c", "user.email=test@example.invalid",
    "-c", "commit.gpgsign=false", "commit", "-qm", "fixture")
  local changed = vim.deepcopy(original)
  changed[3] = "changed example"
  table.remove(changed, 7)
  table.insert(changed, 11, "added example")
  vim.fn.writefile(changed, tmp .. "/example.txt")
  vim.cmd.cd(tmp)
  local spec = require("plugins.gitsigns")[1]
  spec.config(nil, spec.opts)
  vim.cmd.edit(tmp .. "/example.txt")
  assert(not vim.wo.diff, "通常表示になっていない")
  assert(vim.wait(5000, function()
    local status = vim.b.gitsigns_status_dict
    return status and status.added == 1 and status.changed == 1 and status.removed == 1
  end, 20), "通常のファイル表示で追加・変更・削除を取得できない")
  vim.cmd("redraw")
  local found = {}
  for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(0, -1, 0, -1, { details = true })) do
    local details = mark[4]
    if details.sign_hl_group then
      found[details.sign_hl_group] = true
      assert(details.number_hl_group, "行番号の色が設定されていない")
      assert(not details.line_hl_group, "通常表示の行全体を塗ってしまった")
    end
  end
  assert(found.GitSignsAdd and found.GitSignsChange and found.GitSignsDelete,
    "行番号横に3種類の変更印が出ない: " .. vim.inspect(found))
  vim.fn.writefile({ "new example" }, tmp .. "/new.txt")
  vim.cmd.edit(tmp .. "/new.txt")
  assert(vim.wait(5000, function()
    return vim.b.gitsigns_status_dict and vim.b.gitsigns_status_dict.added == 1
  end, 20), "未追跡の新規ファイルに追加印が付かない")
  vim.cmd("colorscheme habamax")
  assert(vim.api.nvim_get_hl(0, { name = "GitSignsAddNr" }).fg == 0x80c990)
end, debug.traceback)
require("gitsigns").detach_all()
vim.cmd.cd(repo)
vim.fn.delete(tmp, "rf")
assert(ok, err)
print("gitsigns_spec: OK")
