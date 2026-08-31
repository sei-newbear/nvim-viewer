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
--- 同じバッファを複数の窓で開いている場合は**いちばん狭い窓**に合わせる。
--- extmark はバッファに付くので窓ごとに変えられない。広い方に合わせると
--- 狭い窓ではみ出して読めなくなるため、収まる側を採る。
local function text_width(buf)
  local best = nil
  for _, w in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_buf(w) == buf then
      local info = vim.fn.getwininfo(w)[1]
      if info then
        local usable = info.width - (info.textoff or 0)
        if not best or usable < best then best = usable end
      end
    end
  end
  return best or vim.o.columns
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
      -- NUL を含む行は Vim 側で Blob 扱いになり strdisplaywidth が E976 で落ちる。
      -- 描画全体が止まると set_keymaps まで届かず「表示だけモード中」になるので、
      -- ここで受け止めてバイト数で代用する。
      local okw, code_w = pcall(vim.fn.strdisplaywidth, line)
      if not okw then code_w = #line end
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

-- ---- コミットの差分を開く / 前後のコミットへ移動 ----

--- 差分を開いている間の文脈。
--- 「開いた状態のまま前のコミットへ」を実現するために、
--- そのファイルを触ったコミットの並びと現在位置を覚えておく。
local nav = nil       -- { file, rel, dir, root, commits, paths, idx, tabpage }
local switching = false -- 自分で開き直している最中か

--- git ルートからの相対パスを求める
--- ルート自体も返す。DiffviewOpen にどのリポジトリの話かを明示するのに要る。
---@return string rel, string dir, string? root
local function rel_path(file)
  local dir = vim.fn.fnamemodify(file, ":h")
  local r = vim.system({ "git", "-C", dir, "rev-parse", "--show-toplevel" },
    { text = true }):wait()
  if r.code == 0 and r.stdout then
    local top = vim.trim(r.stdout)
    if top ~= "" and file:sub(1, #top + 1) == top .. "/" then
      return file:sub(#top + 2), dir, top
    end
  end
  return file, dir, nil
end

--- そのファイルを触ったコミットを新しい順に取る
---
--- `--follow` でリネームを追う。追わないとリネーム前のコミットが一覧から
--- 落ち、「何番目か」の探索が外れて位置表示まで狂う。
--- 追うとコミットごとにパスが変わるので、その時点のパスも一緒に返す
--- （昔のコミットを今の名前で開こうとしても空になるため）。
---
--- 注意: パスは**絶対パス**で渡すこと。
--- -C にファイルのディレクトリを、パスに git ルートからの相対を渡すと
--- 基準がずれて一致せず、結果が空になる。
---@return string[] shas, table<string,string> paths
local function file_commits(dir, abs_file)
  local r = vim.system({ "git", "-C", dir, "log", "--follow",
    "--format=%H", "--name-only", "--", abs_file }, { text = true }):wait()
  if r.code ~= 0 then return {}, {} end
  local shas, paths, cur = {}, {}, nil
  for _, l in ipairs(vim.split(r.stdout or "", "\n")) do
    if #l == 40 and l:match("^%x+$") then
      cur = l
      table.insert(shas, l)
    elseif cur and l ~= "" and not paths[cur] then
      paths[cur] = l -- そのコミット時点でのパス
    end
  end
  return shas, paths
end

--- 指定のコミットの差分を、そのファイルだけ開く
local function show(sha, summary, pos)
  vim.notify(("%s%s • %s\n（[h 前の変更 / ]h 次の変更 / q 戻る）"):format(
    pos and (pos .. "  ") or "", sha:sub(1, 7), summary or ""), vim.log.levels.INFO)
  -- 既に差分を開いていれば一度閉じる（タブが積み上がらないように）。
  -- ただし閉じると DiffviewViewClosed が飛んで nav が捨てられてしまうので、
  -- 切り替え中であることを立てておく。
  switching = true
  local ok, lib = pcall(require, "diffview.lib")
  if ok and lib.views and #lib.views > 0 then pcall(vim.cmd, "DiffviewClose") end
  -- リポジトリを -C で明示する。DiffviewOpen の相対パスは **nvim の cwd**
  -- 基準で解決されるので、リポジトリの下位ディレクトリから nvim を起動して
  -- いるだけで一致せず、エラーも出ないまま空の差分が開く。
  -- パスはそのコミット時点のもの（リネーム前は昔の名前）を使う。
  local path = nav.paths[sha] or nav.rel
  local cmd = "DiffviewOpen "
  if nav.root then cmd = cmd .. "-C" .. vim.fn.fnameescape(nav.root) .. " " end
  vim.cmd(cmd .. ("%s^! -- %s"):format(sha, vim.fn.fnameescape(path)))

  -- どのタブで開いたかを覚える。無関係な差分を「ブレイムの差分」と
  -- 取り違えないための目印にする。
  nav.tabpage = vim.api.nvim_get_current_tabpage()

  -- 1ファイルしか見ていないので、左のファイル一覧は場所の無駄。
  -- 隠すと差分が全幅に広がって読みやすくなる。
  vim.defer_fn(function()
    local ok2, lib2 = pcall(require, "diffview.lib")
    local v = ok2 and lib2.views and lib2.views[1]
    if v and v.panel and v.panel.is_open and v.panel:is_open() then
      pcall(function() v.panel:close() end)
    end
  end, 120)

  vim.schedule(function() switching = false end)
end

--- 履歴移動が有効か、いま何番目かを返す（フッターが参照する）
--- DiffviewViewClosed のイベントだけに頼ると閉じ方によって取りこぼすので、
--- 「差分が実際に開いているか」を毎回見て自己修復する。
function M.nav_state()
  if not nav then return nil end
  if switching then return { idx = nav.idx, total = #nav.commits } end
  local ok, lib = pcall(require, "diffview.lib")
  if not (ok and lib.views and #lib.views > 0) then
    nav = nil
    return nil
  end
  -- 開いていた差分タブが無くなったなら、この文脈はもう死んでいる。
  if not (nav.tabpage and vim.api.nvim_tabpage_is_valid(nav.tabpage)) then
    nav = nil
    return nil
  end
  -- 別のタブに居る間は出さない。
  -- `Space dd` の作業ツリー差分や、`gf` で戻った通常ファイルの上でまで
  -- 「◀ 前の変更」が出ると、押した瞬間に無関係な差分が入れ替わる。
  -- nav は捨てない（差分タブへ戻れば続きから使える）。
  if vim.api.nvim_get_current_tabpage() ~= nav.tabpage then return nil end
  return { idx = nav.idx, total = #nav.commits }
end

--- 前後のコミットへ移動する（差分を開いたまま）
--- delta > 0 で古い方へ、< 0 で新しい方へ
function M.nav_commit(delta)
  if not nav then
    vim.notify("ブレイムから差分を開いているときに使えます", vim.log.levels.WARN)
    return
  end
  local i = nav.idx + delta
  if i < 1 then
    vim.notify("これ以上新しい変更はありません", vim.log.levels.INFO)
    return
  end
  if i > #nav.commits then
    vim.notify("これ以上古い変更はありません", vim.log.levels.INFO)
    return
  end
  nav.idx = i
  local sha = nav.commits[i]
  local r = vim.system({ "git", "-C", nav.dir, "log", "-1", "--format=%s", sha },
    { text = true }):wait()
  show(sha, vim.trim(r.stdout or ""), ("%d/%d"):format(i, #nav.commits))
end

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
  local rel, dir, root = rel_path(file)
  local commits, paths = file_commits(dir, file)

  -- 何番目のコミットかを覚えておき、[h / ]h で前後に動けるようにする
  local idx = nil
  for i, h in ipairs(commits) do if h == sha then idx = i break end end
  if not idx then
    -- 履歴に見つからないコミット。黙って 1 番目として扱うと、
    -- 位置表示も [h / ]h の行き先も全部ずれる。
    vim.notify(("%s はこのファイルの履歴に見つかりません（前後移動は使えません）")
      :format(sha:sub(1, 7)), vim.log.levels.WARN)
    idx = 1
    commits, paths = { sha }, { [sha] = rel }
  end
  nav = { file = file, rel = rel, dir = dir, root = root,
    commits = commits, paths = paths, idx = idx }

  show(sha, c and c.summary or "", ("%d/%d"):format(idx, #commits))
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
  state[buf] = nil
  -- 既に消えたバッファに対しても呼ばれる（BufUnload 経由）
  if vim.api.nvim_buf_is_valid(buf) then
    vim.api.nvim_buf_clear_namespace(buf, NS, 0, -1)
    set_keymaps(buf, false)
  end
  return true
end

---@param opts? { quiet?: boolean } quiet: 取り直しなので通知しない
function M.on(buf, opts)
  buf = buf or vim.api.nvim_get_current_buf()
  local quiet = opts and opts.quiet
  local function say(msg, lvl)
    if not quiet then vim.notify(msg, lvl) end
  end

  local file = vim.api.nvim_buf_get_name(buf)
  if file == "" or vim.bo[buf].buftype ~= "" then
    say("通常のファイルで使ってください", vim.log.levels.WARN)
    return
  end

  -- バイナリは blame しても読めない。加えて NUL を含む行が描画に回ると
  -- 途中で落ちて「注釈もキーマップも無いのにモード中」という状態になる。
  for _, l in ipairs(vim.api.nvim_buf_get_lines(buf, 0, 200, false)) do
    if l:find("\0", 1, true) then
      say("バイナリファイルでは使えません", vim.log.levels.WARN)
      return
    end
  end

  local dir = vim.fn.fnamemodify(file, ":h")
  vim.system({ "git", "-C", dir, "blame", "--porcelain", "--", file }, { text = true },
    vim.schedule_wrap(function(res)
      if res.code ~= 0 then
        say("blame を取得できません（git 管理下のファイルですか）", vim.log.levels.WARN)
        return
      end
      if not res.stdout or res.stdout == "" then
        -- 追跡済みの空ファイルは exit 0 かつ出力 0 バイトになる。
        -- git 管理外と同じ文言を出すと原因を誤らせる。
        say("このファイルは空です", vim.log.levels.INFO)
        return
      end
      if not vim.api.nvim_buf_is_valid(buf) then return end
      local commits, lines = parse(res.stdout)
      state[buf] = { commits = commits, lines = lines }
      render(buf)
      set_keymaps(buf, true)
      local n = 0
      for _ in pairs(commits) do n = n + 1 end
      say(("ブレイムモード: %d コミット / Enter でそのコミットの差分"):format(n),
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

--- 指定行を入れたコミットの短いハッシュを返す（herdr_link が参照する）
--- ブレイムモードでないとき、未コミット行のときは nil
function M.commit_at(lnum, buf)
  buf = buf or vim.api.nvim_get_current_buf()
  local st = state[buf]
  if not st then return nil end
  local sha = st.lines[lnum]
  if not sha then return nil end
  local c = st.commits[sha]
  if c and c.uncommitted then return nil end
  return sha:sub(1, 10)
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

-- バッファを閉じたら片付ける（注釈とキーマップも含めて）
vim.api.nvim_create_autocmd({ "BufDelete", "BufWipeout" }, {
  group = group,
  callback = function(ev) M.off(ev.buf) end,
})

-- BufUnload は「閉じた」とは限らない。
-- 差分からの `gf` や `:edit!` でも飛ぶ。ここで状態だけ捨てると、
-- 注釈は画面に残ったまま Enter だけが「モードではありません」と言う
-- 辻褄の合わない状態になる。
-- 実際に消えたのかを次のループで見て、残っているなら取り直す
-- （読み込み直しで中身が変わっている可能性があるため）。
vim.api.nvim_create_autocmd("BufUnload", {
  group = group,
  callback = function(ev)
    local buf = ev.buf
    if not state[buf] then return end
    vim.schedule(function()
      if vim.api.nvim_buf_is_valid(buf) and vim.api.nvim_buf_is_loaded(buf) then
        M.on(buf, { quiet = true })
      else
        M.off(buf)
      end
    end)
  end,
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

vim.keymap.set("n", "[h", function() M.nav_commit(1) end,
  { silent = true, desc = "前（古い）の変更へ" })
vim.keymap.set("n", "]h", function() M.nav_commit(-1) end,
  { silent = true, desc = "次（新しい）の変更へ" })

-- 差分を閉じたら履歴移動の文脈も捨てる
vim.api.nvim_create_autocmd("User", {
  group = group,
  pattern = "DiffviewViewClosed",
  callback = function()
    if not switching then nav = nil end
  end,
})

vim.keymap.set("n", "<leader>g", M.toggle,
  { silent = true, desc = "ブレイムモードの切替（行ごとの由来）" })

vim.api.nvim_create_user_command("Blame", M.toggle, { desc = "ブレイムモードの切替" })
vim.api.nvim_create_user_command("BlameDensity", M.toggle_density,
  { desc = "ブレイム表示の密度を切替（変わり目だけ ⇄ 全行）" })

return M
