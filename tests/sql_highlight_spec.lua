local repo = vim.fn.getcwd()
package.path = repo .. "/lua/?.lua;" .. package.path

-- 既存の Tree-sitter 配色が変更されないことを先に記録する。
vim.api.nvim_set_hl(0, "@type.builtin.sql", { fg = 0x123456 })
local before = vim.api.nvim_get_hl(0, { name = "@type.builtin.sql", link = false })

local sql_highlight = require("custom.sql_highlight")

local keyword = vim.api.nvim_get_hl(0, { name = "@keyword.sql", link = false })
assert(keyword.fg == 0x569cd6, "SQL 予約語に青色が設定されていない")
assert(not keyword.bold, "SQL 予約語が太字になっている")
local table_name = vim.api.nvim_get_hl(0, { name = "@type.sql", link = false })
assert(table_name.fg == 0xce9178, "SQL のテーブル名に赤系の色が設定されていない")
local column_name = vim.api.nvim_get_hl(0, { name = "@variable.member.sql", link = false })
assert(column_name.fg == 0xce9178, "SQL の列名に赤系の色が設定されていない")

-- colorscheme 変更で消されても予約語の色を復元する。
vim.api.nvim_set_hl(0, "@keyword.sql", {})
sql_highlight.define_highlights()
keyword = vim.api.nvim_get_hl(0, { name = "@keyword.sql", link = false })
assert(keyword.fg == 0x569cd6, "SQL 予約語の色を復元できない")

local buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
  "SELECT customer_id FROM sample_orders WHERE total > 100",
})
vim.bo[buf].filetype = "sql"
vim.api.nvim_exec_autocmds("FileType", { buffer = buf })

vim.api.nvim_set_current_buf(buf)
assert(vim.bo.syntax == "sql", "SQL syntax が有効になっていない")
local syntax_group = vim.fn.synIDattr(vim.fn.synID(1, 1, true), "name")
assert(syntax_group ~= "", "標準 SQL syntax が読み込まれていない")

local after = vim.api.nvim_get_hl(0, { name = "@type.builtin.sql", link = false })
assert(vim.deep_equal(after, before), "既存の Tree-sitter 配色を変更している")

vim.o.background = "light"
sql_highlight.define_highlights()
keyword = vim.api.nvim_get_hl(0, { name = "@keyword.sql", link = false })
assert(keyword.fg == 0x0000ff, "明るい背景で SQL 予約語が青色になっていない")
table_name = vim.api.nvim_get_hl(0, { name = "@type.sql", link = false })
assert(table_name.fg == 0xa31515, "明るい背景でテーブル名が赤系になっていない")

vim.api.nvim_buf_delete(buf, { force = true })
print("sql_highlight_spec: OK")
