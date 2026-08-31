-- ===================================================================
-- lua/custom/frontmatter.lua
-- マークダウン先頭の frontmatter を「メタデータ」として明示する
--
-- エージェントのスキルファイル(SKILL.md)では frontmatter の name /
-- description が本体と同じくらい重要な情報になる。しかし通常の描画では
-- 罫線に挟まれたただの本文にしか見えず、本文との区別がつかない。
-- ここでは見出しを付け、キーと値を色分けして、metadata だと分かるようにする。
-- ===================================================================

local M = {}

local NS = vim.api.nvim_create_namespace("viewer_frontmatter")
local MAX_SCAN = 200 -- frontmatter を探す最大行数（md-preview-template.html と揃えること）

--- 表示中かどうかをバッファごとに覚える（Space m の切替と連動させる）
local enabled = {}

--- ハイライト定義（配色テーマに追従するよう既存グループから派生させる）
local function define_highlights()
  vim.api.nvim_set_hl(0, "ViewerFrontmatter",      { link = "NormalFloat", default = true })
  vim.api.nvim_set_hl(0, "ViewerFrontmatterKey",   { link = "Identifier",  default = true })
  vim.api.nvim_set_hl(0, "ViewerFrontmatterValue", { link = "String",      default = true })
  vim.api.nvim_set_hl(0, "ViewerFrontmatterLabel", { link = "Title",       default = true })
end

--- frontmatter の範囲を返す
---@return integer? close_line 閉じ `---` の行番号(1始まり)
local function find_range(buf)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, MAX_SCAN, false)
  if #lines == 0 then return nil end
  -- 開始は1行目の `---` または `+++` のみ（本文中の区切り線と区別するため）
  local first = lines[1]
  if first ~= "---" and first ~= "+++" then return nil end
  for i = 2, #lines do
    if lines[i] == first then return i, lines end
  end
  return nil
end

function M.clear(buf)
  if vim.api.nvim_buf_is_valid(buf) then
    vim.api.nvim_buf_clear_namespace(buf, NS, 0, -1)
  end
end

function M.decorate(buf)
  buf = buf or vim.api.nvim_get_current_buf()
  if not vim.api.nvim_buf_is_valid(buf) then return end
  if vim.bo[buf].filetype ~= "markdown" then return end

  M.clear(buf)
  if enabled[buf] == false then return end

  local close, lines = find_range(buf)
  if not close then return end

  -- 見出しは開始行の行末に出す。
  -- 1行目より上に仮想行を置く方式は環境によって表示されないことがあるため。
  vim.api.nvim_buf_set_extmark(buf, NS, 0, 0, {
    virt_text = { { "  ▌ メタデータ (frontmatter)", "ViewerFrontmatterLabel" } },
    virt_text_pos = "eol",
  })

  for i = 1, close do
    local line = lines[i]
    -- 範囲全体に背景色を敷いて、本文と視覚的に分ける
    vim.api.nvim_buf_set_extmark(buf, NS, i - 1, 0, {
      line_hl_group = "ViewerFrontmatter",
    })
    -- `key: value` のキーと値を色分けする
    local key, rest = line:match("^([%w_%-%.]+):(.*)$")
    if key then
      vim.api.nvim_buf_set_extmark(buf, NS, i - 1, 0, {
        end_col = #key + 1,
        hl_group = "ViewerFrontmatterKey",
        hl_mode = "combine",
      })
      if rest and rest:match("%S") then
        vim.api.nvim_buf_set_extmark(buf, NS, i - 1, #key + 1, {
          end_col = #line,
          hl_group = "ViewerFrontmatterValue",
          hl_mode = "combine",
        })
      end
    end
  end
end

--- 表示のオン/オフ（生のファイルを見たいとき用）
function M.toggle(buf)
  buf = buf or vim.api.nvim_get_current_buf()
  enabled[buf] = (enabled[buf] == false)
  M.decorate(buf)
  return enabled[buf] ~= false
end

--- 状態を明示的に設定する（Space m から呼ばれる）
function M.set(buf, on)
  buf = buf or vim.api.nvim_get_current_buf()
  enabled[buf] = on
  M.decorate(buf)
end

-- ---- 自動適用 ----
local group = vim.api.nvim_create_augroup("ViewerFrontmatter", { clear = true })

vim.api.nvim_create_autocmd("ColorScheme", {
  group = group,
  callback = define_highlights,
})

vim.api.nvim_create_autocmd({ "FileType", "BufWinEnter", "TextChanged" }, {
  group = group,
  pattern = { "markdown", "*.md" },
  callback = function(ev)
    if vim.bo[ev.buf].filetype ~= "markdown" then return end
    vim.schedule(function() M.decorate(ev.buf) end)
  end,
})

vim.api.nvim_create_autocmd("BufDelete", {
  group = group,
  callback = function(ev) enabled[ev.buf] = nil end,
})

define_highlights()

return M
