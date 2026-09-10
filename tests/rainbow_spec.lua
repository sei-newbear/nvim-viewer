vim.opt.rtp:prepend(vim.fn.getcwd())
local data = vim.fn.stdpath("data")
local plugins = vim.env.VIEWER_TEST_PLUGIN_DIR or (data .. "/lazy")
vim.opt.rtp:append(data .. "/site")
vim.opt.rtp:append(plugins .. "/rainbow-delimiters.nvim")
require("plugins.rainbow")[1].init()
vim.cmd("runtime plugin/rainbow-delimiters.lua")
vim.api.nvim_buf_set_lines(0, 0, -1, false, { '(let [x {:a 1}] (str "(text)" x))' })
vim.bo.filetype = "clojure"
vim.treesitter.get_parser(0, "clojure"):parse()
local lib = require("rainbow-delimiters.lib")
assert(vim.wait(2000, function()
  return #vim.api.nvim_buf_get_extmarks(0, lib.nsids.clojure, 0, -1, {}) >= 8
end, 20), "Clojureの括弧に色が付かない")
local at = {}
for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(0, lib.nsids.clojure, 0, -1, { details = true })) do
  at[mark[3]] = mark[4].hl_group
end
assert(at[0] == at[32], "対応する丸括弧が同じ色にならない")
assert(at[5] == at[14] and at[5] ~= at[0], "入れ子の角括弧が別色にならない")
assert(at[8] == at[13] and at[8] ~= at[5], "対応する波括弧が同じ色にならない")
assert(at[22] == nil and at[27] == nil, "文字列内の括弧を色分けした")
for lang, source in pairs({
  lua = "print(math.abs(1))",
  kotlin = "fun example() { println(listOf(1)) }",
  java = "class Example { void run() { consume(value()); } }",
  python = "print(abs(1))",
  typescript = "console.log(Math.abs(1));",
}) do
  vim.cmd("enew!")
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { source })
  vim.bo.filetype = lang
  vim.treesitter.get_parser(0, lang):parse()
  assert(vim.wait(2000, function()
    local ns = lib.nsids[lang]
    return ns and #vim.api.nvim_buf_get_extmarks(0, ns, 0, -1, {}) >= 4
  end, 20), lang .. "の括弧に色が付かない")
  local marks = {}
  for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(0, lib.nsids[lang], 0, -1, { details = true })) do
    marks[mark[3] + 1] = mark[4].hl_group
  end
  local first = assert(source:find("(1)", 1, true) or source:find("value()", 1, true))
  if lang == "java" then first = first + #"value" end
  local last = assert(source:find(")", first, true))
  assert(marks[first] and marks[first] == marks[last], lang .. "の対応する括弧が同じ色にならない")
  local stack = {}
  for column = 1, first - 1 do
    local char = source:sub(column, column)
    if char == "(" then stack[#stack + 1] = column end
    if char == ")" then table.remove(stack) end
  end
  local outer = stack[#stack]
  assert(outer and marks[outer] and marks[outer] ~= marks[first],
    lang .. "の入れ子の括弧が別色にならない")
end
vim.cmd("enew!")
vim.api.nvim_buf_set_lines(0, 0, -1, false, { "(plain text)" })
vim.bo.filetype = "text"
assert(not lib.buffers[vim.api.nvim_get_current_buf()], "未対応のプレーンテキストでも有効化した")
print("rainbow_spec: OK")
