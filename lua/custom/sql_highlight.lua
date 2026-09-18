-- Tree-sitter の SQL 配色を保ったまま、方言などの認識漏れだけを
-- Neovim 標準の SQL syntax で補う。
local M = {}

local keyword_groups = {
  "@keyword.sql",
  "@keyword.conditional.sql",
  "@keyword.modifier.sql",
  "@keyword.operator.sql",
  "@keyword.repeat.sql",
}

local name_groups = {
  "@type.sql",            -- テーブル名・CTE名
  "@variable.sql",        -- テーブルの別名
  "@variable.member.sql", -- 列名
  "@string.sql",
}

function M.define_highlights()
  -- Visual Studio 系の見慣れた配色に寄せる。予約語は青、SQL 内の名前と
  -- 文字列は赤茶系。データ型 (@type.builtin.sql) などは上書きしない。
  local light = vim.o.background == "light"
  local keyword = light and 0x0000ff or 0x569cd6
  local identifier = light and 0xa31515 or 0xce9178
  local keyword_cterm = light and 21 or 75
  local name_cterm = light and 124 or 173

  for _, name in ipairs(keyword_groups) do
    vim.api.nvim_set_hl(0, name, {
      fg = keyword,
      ctermfg = keyword_cterm,
      bold = false,
    })
  end
  for _, group_name in ipairs(name_groups) do
    vim.api.nvim_set_hl(0, group_name, {
      fg = identifier,
      ctermfg = name_cterm,
      bold = false,
    })
  end

  -- Tree-sitter が拾わず、下の標準 SQL syntax が補った予約語にも同じ色を使う。
  vim.api.nvim_set_hl(0, "sqlSpecial", { fg = keyword, ctermfg = keyword_cterm })
  vim.api.nvim_set_hl(0, "sqlStatement", { fg = keyword, ctermfg = keyword_cterm })
  vim.api.nvim_set_hl(0, "sqlString", { fg = identifier, ctermfg = name_cterm })
end

local group = vim.api.nvim_create_augroup("ViewerSqlHighlight", { clear = true })

vim.api.nvim_create_autocmd("ColorScheme", {
  group = group,
  callback = M.define_highlights,
})

vim.api.nvim_create_autocmd("FileType", {
  group = group,
  pattern = "sql",
  callback = function(ev)
    vim.api.nvim_buf_call(ev.buf, function()
      -- vim.treesitter.start() は従来 syntax を無効にするため、その後で
      -- SQL syntax だけを読み込む。Tree-sitter の装飾のほうが優先される。
      vim.bo.syntax = "sql"
      vim.cmd("runtime! syntax/sql.vim")
    end)
  end,
})

M.define_highlights()

return M
