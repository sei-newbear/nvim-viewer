-- ===================================================================
-- lua/custom/gauge_highlight.lua
-- Gauge Spec の構造を Markdown より一段はっきり表示する
-- ===================================================================

local M = {}

local NS = vim.api.nvim_create_namespace("viewer_gauge_highlight")
M.namespace = NS

local heading_groups = {
  "ViewerGaugeHeading1",
  "ViewerGaugeHeading2",
  "ViewerGaugeHeading3",
  "ViewerGaugeHeading4",
  "ViewerGaugeHeading5",
  "ViewerGaugeHeading6",
}

local function define_highlights()
  -- Gauge で中心となる仕様名とシナリオ名は、配色テーマに追従しながら
  -- 暖色と寒色に分ける。Markdown の見出しグループはテーマによって
  -- 全階層が同色になるため、そのままは使わない。
  vim.api.nvim_set_hl(0, "ViewerGaugeHeading1", { link = "DiagnosticWarn", default = true })
  vim.api.nvim_set_hl(0, "ViewerGaugeHeading2", { link = "DiagnosticInfo", default = true })
  vim.api.nvim_set_hl(0, "ViewerGaugeHeading3", { link = "DiagnosticHint", default = true })
  vim.api.nvim_set_hl(0, "ViewerGaugeHeading4", { link = "Type", default = true })
  vim.api.nvim_set_hl(0, "ViewerGaugeHeading5", { link = "Special", default = true })
  vim.api.nvim_set_hl(0, "ViewerGaugeHeading6", { link = "Comment", default = true })
  vim.api.nvim_set_hl(0, "ViewerGaugeString", { link = "String", default = true })
  vim.api.nvim_set_hl(0, "ViewerGaugeParameter", { link = "Special", default = true })
  vim.api.nvim_set_hl(0, "ViewerGaugeTagLabel", { link = "Keyword", default = true })
  vim.api.nvim_set_hl(0, "ViewerGaugeTag", { link = "Type", default = true })
end

local function highlight(buf, row, start_col, end_col, group, priority)
  if end_col <= start_col then return end
  vim.api.nvim_buf_set_extmark(buf, NS, row, start_col, {
    end_col = end_col,
    hl_group = group,
    hl_mode = "replace",
    priority = priority or 120,
  })
end

local function decorate_inline(buf, row, line)
  local offset = 1
  while true do
    local first, last = line:find('"[^"\n]*"', offset)
    if not first then break end
    highlight(buf, row, first - 1, last, "ViewerGaugeString", 130)
    offset = last + 1
  end

  offset = 1
  while true do
    local first, last = line:find("<[^<>\n]+>", offset)
    if not first then break end
    highlight(buf, row, first - 1, last, "ViewerGaugeParameter", 140)
    offset = last + 1
  end
end

function M.clear(buf)
  if vim.api.nvim_buf_is_valid(buf) then
    vim.api.nvim_buf_clear_namespace(buf, NS, 0, -1)
  end
end

function M.decorate(buf)
  buf = buf or vim.api.nvim_get_current_buf()
  if not vim.api.nvim_buf_is_valid(buf) or vim.bo[buf].filetype ~= "gauge" then return end

  M.clear(buf)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local fence_char
  local fence_length
  for row, line in ipairs(lines) do
    local fence_indent, fence_marker, fence_rest = line:match("^( *)([`~]+)(.*)$")
    local valid_marker = fence_marker
      and #fence_indent <= 3
      and #fence_marker >= 3
      and fence_marker == fence_marker:sub(1, 1):rep(#fence_marker)
    local valid_opening = valid_marker
      and not (fence_marker:sub(1, 1) == "`" and fence_rest:find("`", 1, true))
    local is_fence_line = false

    if valid_opening and not fence_char then
      fence_char = fence_marker:sub(1, 1)
      fence_length = #fence_marker
      is_fence_line = true
    elseif valid_marker and fence_marker:sub(1, 1) == fence_char
        and #fence_marker >= fence_length and fence_rest:match("^%s*$") then
      fence_char = nil
      fence_length = nil
      is_fence_line = true
    end

    if not fence_char and not is_fence_line then
      local markers = line:match("^(#+)%s")
      if markers then
        local level = math.min(#markers, #heading_groups)
        highlight(buf, row - 1, 0, #line, heading_groups[level], 120)
      end

      local tag_start, tag_end = line:find("^%s*Tags%s*:")
      if tag_start then
        highlight(buf, row - 1, tag_start - 1, tag_end, "ViewerGaugeTagLabel", 130)
        highlight(buf, row - 1, tag_end, #line, "ViewerGaugeTag", 130)
      end

      decorate_inline(buf, row - 1, line)
    end
  end
end

--- Gauge LSP の診断は残し、本文を覆う波線だけを消す。
---@param client_id integer
---@param deps? table テスト用の依存差し替え
function M.disable_diagnostic_underline(client_id, deps)
  deps = deps or {
    get_namespace = vim.lsp.diagnostic.get_namespace,
    config = vim.diagnostic.config,
  }
  local namespace = deps.get_namespace(client_id)
  deps.config({ underline = false }, namespace)
end

local group = vim.api.nvim_create_augroup("ViewerGaugeHighlight", { clear = true })

vim.api.nvim_create_autocmd("ColorScheme", {
  group = group,
  callback = define_highlights,
})

vim.api.nvim_create_autocmd({ "FileType", "BufWinEnter", "TextChanged" }, {
  group = group,
  pattern = { "gauge", "*.spec", "*.cpt" },
  callback = function(ev)
    if vim.bo[ev.buf].filetype ~= "gauge" then return end
    vim.schedule(function() M.decorate(ev.buf) end)
  end,
})

vim.api.nvim_create_autocmd("LspAttach", {
  group = group,
  callback = function(ev)
    local client = vim.lsp.get_client_by_id(ev.data.client_id)
    if client and client.name == "gauge" then
      M.disable_diagnostic_underline(client.id)
    end
  end,
})

define_highlights()

return M
