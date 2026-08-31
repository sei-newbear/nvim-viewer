-- ===================================================================
-- lua/custom/winbar.lua
-- コード領域の上端に、いま見ているファイルのパスを出す（パンくず）
--
-- 3本の帯の役割:
--   ヘッダー(tabline)    = どこを見るか（移動・グローバル）
--   パンくず(ここ)       = 今どこにいるか（ファイルの位置）
--   フッター(statusline) = 今のファイルに何ができるか（操作）
--
-- パス専用の行を設けたので、フッターからファイル名を外せる。
-- 結果、フッターの幅をジャンプ項目に丸ごと使える。
--
-- 省略は先頭側で行う（`…/application/use-cases/register-user.ts`）。
-- 末尾＝今いる場所が最も重要で、`…/` があれば上位階層の存在も分かるため。
-- ===================================================================

local M = {}

local WINBAR = "%!v:lua.require'custom.winbar'.render()"

--- git ルートからの相対パスを求める（バッファごとに覚えておく）
local function rel_path(buf)
  local cached = vim.b[buf].viewer_relpath
  if cached then return cached end

  local abs = vim.api.nvim_buf_get_name(buf)
  if abs == "" then return nil end

  local dir = vim.fn.fnamemodify(abs, ":h")
  local res = vim.system({ "git", "-C", dir, "rev-parse", "--show-toplevel" },
    { text = true }):wait()
  local path
  if res.code == 0 and res.stdout then
    local root = vim.trim(res.stdout)
    if root ~= "" and abs:sub(1, #root + 1) == root .. "/" then
      path = abs:sub(#root + 2)
    end
  end
  path = path or vim.fn.fnamemodify(abs, ":~:.")
  vim.b[buf].viewer_relpath = path
  return path
end

-- 幅の計測に strdisplaywidth を使ってはいけない。
-- あれは**現在窓**の折り返し設定（wrap / showbreak / breakindent）を
-- 勘定に入れるため、狭い窓やマークダウンを開いているときに
-- 素の文字幅と大きく食い違う。UI の文字は窓に依存しない strwidth で測る。

--- 幅に収まるよう、パスの先頭側を省略する
local function shorten(path, budget)
  if vim.fn.strwidth(path) <= budget then return path end

  -- ディレクトリ単位で先頭から削り、末尾をできるだけ残す
  local parts = vim.split(path, "/", { plain = true })
  for i = 2, #parts do
    local tail = "…/" .. table.concat(parts, "/", i)
    if vim.fn.strwidth(tail) <= budget then return tail end
  end

  -- ファイル名だけでも入らない場合は、文字単位で頭を削る
  local name = parts[#parts]
  local keep, w = "", 0
  for i = vim.fn.strchars(name) - 1, 0, -1 do
    local c = vim.fn.strcharpart(name, i, 1)
    local cw = vim.fn.strwidth(c)
    if w + cw > budget - 1 then break end
    keep, w = c .. keep, w + cw
  end
  return "…" .. keep
end

function M.render()
  -- winbar は各ウィンドウごとに評価される。
  -- 対象ウィンドウは g:statusline_winid で分かる。
  local winid = vim.g.statusline_winid
  local win = (winid and winid ~= 0 and vim.api.nvim_win_is_valid(winid))
    and winid or vim.api.nvim_get_current_win()
  local buf = vim.api.nvim_win_get_buf(win)

  if vim.bo[buf].buftype ~= "" then return "" end
  local path = rel_path(buf)
  if not path then return "" end

  local width = vim.api.nvim_win_get_width(win) - 2
  return "%#Comment# " .. shorten(path, math.max(8, width)) .. " "
end

--- ウィンドウにパンくずを付ける（他が使っている場合は触らない）
local function apply(win)
  if not vim.api.nvim_win_is_valid(win) then return end
  local cfg = vim.api.nvim_win_get_config(win)
  if cfg.relative and cfg.relative ~= "" then return end -- 浮動ウィンドウは対象外

  local cur = vim.wo[win].winbar
  -- Diffview は自分の winbar（INDEX / WORKING TREE）を出す。
  -- 差分ではそちらの方が有用なので、他が設定済みなら上書きしない。
  if cur ~= "" and cur ~= WINBAR then return end

  local buf = vim.api.nvim_win_get_buf(win)
  local show = vim.bo[buf].buftype == "" and vim.api.nvim_buf_get_name(buf) ~= ""
  vim.wo[win].winbar = show and WINBAR or ""
end

local group = vim.api.nvim_create_augroup("ViewerWinbar", { clear = true })

vim.api.nvim_create_autocmd({ "BufWinEnter", "WinEnter", "WinNew", "BufEnter" }, {
  group = group,
  callback = function()
    if not M.enabled then return end
    for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do apply(w) end
  end,
})

-- ファイルを開き直したときにパスの記憶を捨てる
vim.api.nvim_create_autocmd("BufFilePost", {
  group = group,
  callback = function(ev) vim.b[ev.buf].viewer_relpath = nil end,
})

M.enabled = true

function M.enable()
  M.enabled = true
  for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do apply(w) end
end

function M.disable()
  M.enabled = false
  for _, w in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_is_valid(w) and vim.wo[w].winbar == WINBAR then
      vim.wo[w].winbar = ""
    end
  end
end

function M.toggle()
  if M.enabled then
    M.disable()
    vim.notify("パンくずを隠しました", vim.log.levels.INFO)
  else
    M.enable()
    vim.notify("パンくずを表示しました", vim.log.levels.INFO)
  end
end

vim.api.nvim_create_user_command("WinbarToggle", M.toggle,
  { desc = "パンくず（ファイルパス）の表示切替" })

return M
