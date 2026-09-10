local repo = vim.fn.getcwd()
vim.opt.rtp:prepend(repo)
local plugins = vim.fn.stdpath("data") .. "/lazy"
for _, name in ipairs({ "plenary.nvim", "nvim-web-devicons", "diffview.nvim" }) do
  vim.opt.rtp:append(plugins .. "/" .. name)
end
require("core.options")
local options = require("custom.view_opts")
local tmp = vim.fn.tempname()
vim.fn.mkdir(tmp, "p")
local function git(...)
  local args = { "git", "-C", tmp }
  vim.list_extend(args, { ... })
  local output = vim.fn.system(args)
  assert(vim.v.shell_error == 0, output)
end
local function edit(name, ft)
  vim.cmd.edit(vim.fn.fnameescape(tmp .. "/" .. name))
  vim.bo.filetype = ft
end
local ok, err = xpcall(function()
  git("init", "-q")
  for _, name in ipairs({ "first.lua", "second.lua" }) do
    vim.fn.writefile({ "local value = 1", "print(value)", "return value" }, tmp .. "/" .. name)
  end
  git("add", "first.lua", "second.lua")
  git("-c", "user.name=Test User", "-c", "user.email=test@example.invalid",
    "-c", "commit.gpgsign=false", "commit", "-qm", "fixture")
  for _, name in ipairs({ "first.lua", "second.lua" }) do
    vim.fn.writefile({ "local value = 2", "print(value)", "return value" }, tmp .. "/" .. name)
  end
  edit("readme.md", "markdown")
  assert(vim.wo.wrap, "未操作時のMarkdown既定が変わった")
  options.toggle_wrap()
  edit("next.md", "markdown")
  assert(not vim.wo.wrap, "折返しOFFが次のMarkdownへ引き継がれない")
  options.toggle_wrap()
  vim.cmd("tabnew")
  edit("first.lua", "lua")
  assert(vim.wo.wrap, "折返しONが別タブのコードへ引き継がれない")
  vim.cmd.cd(tmp)
  require("diffview").setup(require("plugins.diffview")[1].opts())
  require("diffview").open({})
  local view = require("diffview.lib").get_current_view()
  assert(vim.wait(5000, function() return view.ready and #view.files.working == 2 end))
  local function select_file(index, wrapped)
    local entry = view.files.working[index]
    view.panel:focus()
    view.panel:highlight_file(entry)
    local mapping = vim.fn.maparg("<CR>", "n", false, true)
    assert(type(mapping.callback) == "function", "Enterの割当がない")
    mapping.callback()
    assert(vim.wait(4000, function()
      return view.cur_entry == entry and entry.opened and vim.wo.diff
    end), "Enter後に差分本文へフォーカスが移らない")
    for _, win in ipairs(vim.api.nvim_tabpage_list_wins(view.tabpage)) do
      if vim.wo[win].diff then assert(vim.wo[win].wrap == wrapped, "差分を選択すると折返し設定が変わった") end
    end
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    vim.cmd("normal j")
    assert(vim.api.nvim_win_get_cursor(0)[1] == 2, "Enter直後のjで本文を移動できない")
    local back = vim.fn.maparg("<leader>h", "n", false, true)
    assert(type(back.callback) == "function", "一覧へ直接戻る割当がない")
    back.callback()
    assert(view.panel:is_focused(), "Space hの1操作で差分一覧へ戻れない")
  end
  select_file(1, true)
  select_file(2, true)
  view.panel:focus()
  local panel_wrap = vim.wo.wrap
  options.toggle_wrap()
  assert(vim.wo.wrap == panel_wrap, "本文の設定で一覧の折返しまで変更した")
  select_file(1, false)
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(view.tabpage)) do
    if vim.wo[win].diff then assert(not vim.wo[win].wrap) end
  end
  require("diffview").close()
  edit("last.md", "markdown")
  assert(not vim.wo.wrap, "差分で選んだ折返しOFFが通常表示へ引き継がれない")
end, debug.traceback)
pcall(function() require("diffview").close() end)
vim.cmd.cd(repo)
vim.fn.delete(tmp, "rf")
assert(ok, err)
print("view_navigation_spec: OK")
