-- ===================================================================
-- lua/custom/blame.lua
-- 行ごとの由来を表示する（GitLens の File Blame に近いもの）
--
--   Space g   ブレイムモードの切替
--   Enter     その行を変えたコミットの差分を開く（モード中のみ）
--   ダブルクリック  同上
--
-- 表示の方針:
--   既定では「コミットが切り替わった行」にだけ注釈を出す。
--   全行に出すと同じコミットが延々と並び、狭いペインでは
--   **変わり目が埋もれてノイズになる**。blame で知りたいのは
--   「どこで変わったか」なので、切り替わりだけを見せる方が実用的。
--   全行に出したい場合は M.opts.only_changes = false にする。
--
-- 注意: git blame は「ディスク上のファイル」を見る。
-- このビューアーは閲覧専用なので未保存の差異は生じない。
-- ===================================================================

local M = {}

M.opts = {
  only_changes = true, -- true: 変わり目だけ / false: 全行
  max_width = 46,      -- 注釈の最大表示幅
}

local NS = vim.api.nvim_create_namespace("viewer_blame")
local state = {} -- buf -> { lines = {lnum -> sha}, commits = {sha -> info} }

-- ---- 表示用の整形 ----

local function relative(t)
  local d = os.time() - (t or 0)
  if d < 60 then return "たった今" end
  if d < 3600 then return math.floor(d / 60) .. "分前" end
  if d < 86400 then return math.floor(d / 3600) .. "時間前" end
  if d < 2592000 then return math.floor(d / 86400) .. "日前" end
  if d < 31536000 then return math.floor(d / 2592000) .. "か月前" end
  return os.date("%Y-%m-%d", t)
end

--- 表示幅で切り詰める（バイト単位で切ると多バイト文字が壊れる）
local function shorten(s, w)
  if vim.fn.strdisplaywidth(s) <= w then return s end
  local out, acc = "", 0
  for i = 0, vim.fn.strchars(s) - 1 do
    local c = vim.fn.strcharpart(s, i, 1)
    local cw = vim.fn.strdisplaywidth(c)
    if acc + cw > w - 1 then break end
    out, acc = out .. c, acc + cw
  end
  return out .. "…"
end

--- 使える幅に応じて表示を変える
--- 幅が無いときは「誰が・いつ」を捨てて**コミットメッセージを残す**。
--- blame で知りたいのは「なぜ変わったか」なので、そこを最後まで守る。
local function label(commit, room)
  if not commit then return nil end
  if commit.uncommitted then return "未コミット" end

  local who = ("%s %s"):format(commit.author or "?", relative(commit.time))
  local msg = commit.summary or ""
  local budget = math.min(M.opts.max_width, room)

  local full = ("%s • %s"):format(who, msg)
  if vim.fn.strdisplaywidth(full) <= budget then return full end

  -- 「誰が・いつ」を入れてもメッセージが十分残るなら、その形で切る
  local if_full = budget - vim.fn.strdisplaywidth(who) - 3
  if if_full >= 16 then return who .. " • " .. shorten(msg, if_full) end

  -- 残らないならメッセージだけにする
  return shorten(msg, budget)
end

-- ---- git blame の解析 ----

--- `git blame --porcelain` の出力を読む
--- 同じコミットの2行目以降はヘッダが省略されるため、sha をキーに覚えておく
local function parse(stdout)
  local commits, lines, cur = {}, {}, nil
  for _, l in ipairs(vim.split(stdout, "\n")) do
    local sha, _, final = l:match("^(%x+) (%d+) (%d+)")
    if sha then
      cur = sha
      commits[sha] = commits[sha] or { uncommitted = sha:match("^0+$") ~= nil }
      lines[tonumber(final)] = sha
    elseif cur then
      local k, v = l:match("^([%w%-]+) (.*)$")
      if k == "author" then commits[cur].author = v
      elseif k == "author-time" then commits[cur].time = tonumber(v)
      elseif k == "summary" then commits[cur].summary = v end
    end
  end
  return commits, lines
end

-- ---- 描画 ----

--- そのバッファを表示している窓の、本文に使える幅を返す
--- 行番号やサイン列の分（textoff）を差し引く
local function text_width(buf)
  for _, w in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_buf(w) == buf then
      local info = vim.fn.getwininfo(w)[1]
      if info then return info.width - (info.textoff or 0) end
    end
  end
  return vim.o.columns
end

local function render(buf)
  local st = state[buf]
  if not st then return end
  vim.api.nvim_buf_clear_namespace(buf, NS, 0, -1)

  -- right_align は幅が足りないと**コードに被さる**。
  -- 行ごとに「その行のコードを書いた残り」を計算して、そこへ収める。
  local avail_total = text_width(buf)
  local total = vim.api.nvim_buf_line_count(buf)
  local prev = nil
  for i = 1, total do
    local sha = st.lines[i]
    local show = sha ~= nil
    if show and M.opts.only_changes then
      show = sha ~= prev -- コミットが切り替わった行だけ
    end
    if show then
      local line = vim.api.nvim_buf_get_lines(buf, i - 1, i, false)[1] or ""
      local code_w = vim.fn.strdisplaywidth(line)
      -- コードの幅 + 2桁の余白 を空けた残りに収める
      local room = avail_total - code_w - 2
      local txt = room >= 10 and label(st.commits[sha], room) or nil
      if txt then
        do
          local body = txt
          -- 右揃えは virt_text_pos="right_align" に任せず、自分で余白を詰める。
          -- right_align は幅が足りないと描画自体を落とすことがあり、
          -- 行によって出たり出なかったりして安定しない。
          local pad = avail_total - code_w - vim.fn.strdisplaywidth(body)
          vim.api.nvim_buf_set_extmark(buf, NS, i - 1, 0, {
            virt_text = { { string.rep(" ", math.max(1, pad)) .. body, "Comment" } },
            virt_text_pos = "eol",
          })
        end
      end
    end
    prev = sha
  end
end

-- ---- コミットの差分を開く ----

function M.open_commit()
  local buf = vim.api.nvim_get_current_buf()
  local st = state[buf]
  if not st then
    vim.notify("ブレイムモードではありません（Space g で開始）", vim.log.levels.WARN)
    return
  end
  local lnum = vim.fn.line(".")
  local sha = st.lines[lnum]
  if not sha then
    vim.notify("この行の由来が取れませんでした", vim.log.levels.WARN)
    return
  end
  local c = st.commits[sha]
  if c and c.uncommitted then
    vim.notify("この行はまだコミットされていません", vim.log.levels.INFO)
    return
  end
  -- そのコミットが触った全ファイルではなく、**今見ているファイルだけ**に絞る。
  -- 知りたいのは「この行がなぜこうなったか」であって、
  -- 同じコミットの他ファイルまでは要らない。
  local file = vim.api.nvim_buf_get_name(buf)
  local dir = vim.fn.fnamemodify(file, ":h")
  local rel = file
  local root = vim.system({ "git", "-C", dir, "rev-parse", "--show-toplevel" },
    { text = true }):wait()
  if root.code == 0 and root.stdout then
    local top = vim.trim(root.stdout)
    if top ~= "" and file:sub(1, #top + 1) == top .. "/" then rel = file:sub(#top + 2) end
  end

  vim.notify(("%s • %s\n（q または Space dc で戻る）"):format(
    sha:sub(1, 7), c and c.summary or ""), vim.log.levels.INFO)
  vim.cmd(("DiffviewOpen %s^! -- %s"):format(sha, vim.fn.fnameescape(rel)))
end

-- ---- モードの切替 ----

local function set_keymaps(buf, on)
  if on then
    vim.keymap.set("n", "<CR>", M.open_commit,
      { buffer = buf, silent = true, desc = "この行を変えたコミットの差分を開く" })
    vim.keymap.set("n", "<2-LeftMouse>", function()
      -- ダブルクリック: 1回目でカーソルが動くので、そのまま開く
      M.open_commit()
    end, { buffer = buf, silent = true, desc = "同上（ダブルクリック）" })
  else
    pcall(vim.keymap.del, "n", "<CR>", { buffer = buf })
    pcall(vim.keymap.del, "n", "<2-LeftMouse>", { buffer = buf })
  end
end

function M.off(buf)
  buf = buf or vim.api.nvim_get_current_buf()
  if not state[buf] then return false end
  vim.api.nvim_buf_clear_namespace(buf, NS, 0, -1)
  set_keymaps(buf, false)
  state[buf] = nil
  return true
end

function M.on(buf)
  buf = buf or vim.api.nvim_get_current_buf()
  local file = vim.api.nvim_buf_get_name(buf)
  if file == "" or vim.bo[buf].buftype ~= "" then
    vim.notify("通常のファイルで使ってください", vim.log.levels.WARN)
    return
  end

  local dir = vim.fn.fnamemodify(file, ":h")
  vim.system({ "git", "-C", dir, "blame", "--porcelain", "--", file }, { text = true },
    vim.schedule_wrap(function(res)
      if res.code ~= 0 or not res.stdout or res.stdout == "" then
        vim.notify("blame を取得できません（git 管理下のファイルですか）", vim.log.levels.WARN)
        return
      end
      if not vim.api.nvim_buf_is_valid(buf) then return end
      local commits, lines = parse(res.stdout)
      state[buf] = { commits = commits, lines = lines }
      render(buf)
      set_keymaps(buf, true)
      local n = 0
      for _ in pairs(commits) do n = n + 1 end
      vim.notify(("ブレイムモード: %d コミット / Enter でそのコミットの差分"):format(n),
        vim.log.levels.INFO)
    end))
end

function M.toggle(buf)
  buf = buf or vim.api.nvim_get_current_buf()
  if state[buf] then
    M.off(buf)
    vim.notify("ブレイムモードを終了しました", vim.log.levels.INFO)
  else
    M.on(buf)
  end
end

--- 現在ブレイムモードか（ツールバー等から参照する）
function M.is_on(buf)
  return state[buf or vim.api.nvim_get_current_buf()] ~= nil
end

--- 全行表示 ⇄ 変わり目だけ を切り替える
function M.toggle_density()
  M.opts.only_changes = not M.opts.only_changes
  for buf in pairs(state) do
    if vim.api.nvim_buf_is_valid(buf) then render(buf) end
  end
  vim.notify(M.opts.only_changes and "変わり目だけ表示" or "全行に表示", vim.log.levels.INFO)
end

local group = vim.api.nvim_create_augroup("ViewerBlame", { clear = true })

-- バッファを閉じたら状態を捨てる
vim.api.nvim_create_autocmd({ "BufDelete", "BufUnload" }, {
  group = group,
  callback = function(ev) state[ev.buf] = nil end,
})

-- 幅が変わると収まり方が変わるので描き直す
vim.api.nvim_create_autocmd({ "VimResized", "WinResized" }, {
  group = group,
  callback = function()
    for buf in pairs(state) do
      if vim.api.nvim_buf_is_valid(buf) then render(buf) end
    end
  end,
})

vim.keymap.set("n", "<leader>g", M.toggle,
  { silent = true, desc = "ブレイムモードの切替（行ごとの由来）" })

vim.api.nvim_create_user_command("Blame", M.toggle, { desc = "ブレイムモードの切替" })
vim.api.nvim_create_user_command("BlameDensity", M.toggle_density,
  { desc = "ブレイム表示の密度を切替（変わり目だけ ⇄ 全行）" })

return M
