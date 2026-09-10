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
vim.cmd("enew!")
vim.api.nvim_buf_set_lines(0, 0, -1, false, { "print('example')" })
vim.bo.filetype = "lua"
assert(not lib.buffers[vim.api.nvim_get_current_buf()], "対象外言語にも有効化した")
print("rainbow_spec: OK")
