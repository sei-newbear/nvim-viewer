local repo = vim.fn.getcwd()
package.path = repo .. "/lua/?.lua;" .. package.path

local gauge_highlight = require("custom.gauge_highlight")

local buf = vim.api.nvim_create_buf(false, true)
vim.bo[buf].filetype = "gauge"
local step = '* 入力欄に "架空企業の概要" と入力し <dummy-account> を選ぶ'
vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
  "# 仕様の見出し",
  "## シナリオの見出し",
  step,
  "Tags: smoke, regression",
  "```text",
  "## コード例の見出し",
  '* "コード例" と <sample>',
  "```",
  "## コードブロック後の見出し",
  "    ```text",
  "# 4スペース字下げ後の見出し",
  "```foo`bar",
  "# 無効なfence後の見出し",
})

gauge_highlight.decorate(buf)

local marks = vim.api.nvim_buf_get_extmarks(
  buf, gauge_highlight.namespace, 0, -1, { details = true }
)

local found = {}
for _, mark in ipairs(marks) do
  local row, col, details = mark[2], mark[3], mark[4]
  local key = table.concat({
    row,
    col,
    details.end_col or -1,
    details.hl_group or "",
  }, ":")
  found[key] = true
end

local function has(row, col, end_col, group)
  local key = table.concat({ row, col, end_col, group }, ":")
  assert(found[key], "ハイライトがない: " .. key)
end

has(0, 0, #"# 仕様の見出し", "ViewerGaugeHeading1")
has(1, 0, #"## シナリオの見出し", "ViewerGaugeHeading2")
local string_start, string_end = step:find('"架空企業の概要"', 1, true)
local parameter_start, parameter_end = step:find("<dummy-account>", 1, true)
has(2, string_start - 1, string_end, "ViewerGaugeString")
has(2, parameter_start - 1, parameter_end, "ViewerGaugeParameter")
has(3, 0, 5, "ViewerGaugeTagLabel")
has(3, 5, #"Tags: smoke, regression", "ViewerGaugeTag")
has(8, 0, #"## コードブロック後の見出し", "ViewerGaugeHeading2")
has(10, 0, #"# 4スペース字下げ後の見出し", "ViewerGaugeHeading1")
has(12, 0, #"# 無効なfence後の見出し", "ViewerGaugeHeading1")

for key in pairs(found) do
  local row = tonumber(key:match("^(%d+):"))
  assert(row < 4 or row > 7, "コードブロック内が Gauge 構文として着色された: " .. key)
end

local configured
local namespace_for
gauge_highlight.disable_diagnostic_underline(42, {
  get_namespace = function(client_id)
    namespace_for = client_id
    return 84
  end,
  config = function(opts, namespace)
    configured = { opts = opts, namespace = namespace }
  end,
})

assert(namespace_for == 42, "Gauge LSP の診断名前空間を使っていない")
assert(configured.namespace == 84, "診断設定の対象名前空間が違う")
assert(configured.opts.underline == false, "Gauge の診断波線が無効になっていない")

vim.api.nvim_buf_delete(buf, { force = true })
print("gauge_highlight_spec: OK")
