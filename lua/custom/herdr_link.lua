-- ===================================================================
-- lua/custom/herdr_link.lua
-- 見ている場所を Ctrl+L で左ペインのエージェントへ渡す
--
-- 仕組み:
--   herdr は各ペインに HERDR_PANE_ID を環境変数として注入している。
--   そこから `herdr pane neighbor --direction left` で左隣（エージェント）を
--   特定し、`herdr agent send` で文脈を流し込む。
--   Enter は送られないので、貼り付いた後に自分で質問を書き足せる。
--
-- 送るのは「参照」であってコードそのものではない:
--   エージェントはファイルを読めるので File と Lines があれば足りる。
--   コードまで貼ると入力欄が埋まり、質問を書く場所が無くなる。
--   例外は文字単位の選択で、行参照では「行のどの部分か」を表現できないため
--   選んだ文字列だけを添える。
--
-- パスは「送信先エージェントの作業ディレクトリ」基準にする:
--   git ルート相対にすると、エージェントが別のディレクトリに居るときに
--   そのままでは開けないパスを渡してしまう。
-- ===================================================================

local M = {}

-- ---- herdr の呼び出し ----

local function herdr_bin()
  if vim.fn.executable("herdr") == 1 then return "herdr" end
  local fallback = vim.fn.expand("~/.local/bin/herdr")
  if vim.fn.executable(fallback) == 1 then return fallback end
  return nil
end

--- herdr コマンドを実行する
--- リスト形式で渡すので、コード中のクォートやバックティックで壊れない
local function herdr_json(args)
  local bin = herdr_bin()
  if not bin then return nil end
  local cmd = { bin }
  vim.list_extend(cmd, args)
  local res = vim.system(cmd, { text = true }):wait()
  if res.code ~= 0 or not res.stdout or res.stdout == "" then return nil end
  local ok, decoded = pcall(vim.json.decode, res.stdout)
  if not ok or type(decoded) ~= "table" or decoded.error then return nil end
  return decoded.result
end

local function self_pane()
  local id = vim.env.HERDR_PANE_ID
  if id and id ~= "" then return id end
  return nil
end

-- ---- 送信先の決定 ----

--- 送信先を決める
---@return string? pane_id, boolean has_agent, string reason, string? cwd
function M.resolve_target()
  local forced = vim.g.herdr_agent_target or vim.env.HERDR_AGENT_TARGET
  if forced and forced ~= "" then
    return forced, true, "明示指定", nil
  end

  local me = self_pane()
  if not me then
    return nil, false, "HERDR_PANE_ID が無い（herdr の外で起動している）", nil
  end

  local list = herdr_json({ "pane", "list" })
  local panes, my_tab = {}, nil
  if list and list.panes then
    for _, p in ipairs(list.panes) do
      panes[p.pane_id] = p
      if p.pane_id == me then my_tab = p.tab_id end
    end
  end

  -- 左隣のペイン。
  -- 注意: 戻り値の `pane_id` は問い合わせたペイン自身で、
  -- 実際の隣は `neighbor_pane_id`（隣が無い場合はこのキーごと存在しない）。
  local nb = herdr_json({ "pane", "neighbor", "--direction", "left", "--pane", me })
  local left = nb and nb.neighbor and nb.neighbor.neighbor_pane_id
  if left and left ~= vim.NIL and left ~= "" and left ~= me then
    local info = panes[left]
    local has_agent = info ~= nil and info.agent ~= nil and info.agent ~= vim.NIL
    return left, has_agent, "左隣のペイン", info and info.cwd or nil
  end

  -- 左隣が無ければ、同じタブ内のエージェント
  if my_tab then
    for _, p in pairs(panes) do
      if p.tab_id == my_tab and p.pane_id ~= me
        and p.agent ~= nil and p.agent ~= vim.NIL then
        return p.pane_id, true, "同じタブ内のエージェント", p.cwd
      end
    end
  end

  return nil, false, "送信先のエージェントが見つからない", nil
end

-- ---- 送信 ----

local function send_to_pane(target, has_agent, text)
  local bin = herdr_bin()
  if not bin then return false, "herdr が見つからない" end

  -- エージェントが居るペインなら agent send、そうでなければ pane send-text
  local subcmd = has_agent and { "agent", "send" } or { "pane", "send-text" }
  local cmd = { bin }
  vim.list_extend(cmd, subcmd)
  table.insert(cmd, target)
  table.insert(cmd, text)

  local res = vim.system(cmd, { text = true }):wait()
  if res.code ~= 0 then
    return false, (res.stderr or res.stdout or "不明なエラー")
  end
  if res.stdout and res.stdout:find('"error"') then
    return false, res.stdout
  end
  return true, nil
end

-- ---- 見ている場所の情報 ----

--- 送信先の作業ディレクトリを基準にしたパスを返す
--- 配下でなければ絶対パスにする（曖昧さを残さないため）
local function path_for(abs, cwd)
  if abs == "" then return "[無名バッファ]" end
  if cwd and cwd ~= "" then
    local base = cwd:gsub("/$", "")
    if abs:sub(1, #base + 1) == base .. "/" then
      return abs:sub(#base + 2)
    end
  end
  return abs
end

--- 差分を見ているなら、その情報を返す
---
--- バッファ名から判別してはいけない。差分側のバッファ名は
--- `diffview:///<repo>/.git/:0:/<path>` のような内部表現で、
--- そのまま File に出すとエージェントが開けないうえ、
--- 左右の判別も付かない（コミット差分では両側が同じ形になる）。
--- Diffview が持つモデル（cur_layout の a/b と cur_entry）を使う。
---@return table? { rev = string?, side = string, path = string? }
local function diff_context()
  local win = vim.api.nvim_get_current_win()
  if not vim.wo[win].diff then return nil end

  local ok, lib = pcall(require, "diffview.lib")
  local v = ok and lib.views and lib.views[1]
  if not (v and v.cur_layout) then return { side = "差分" } end

  -- a = 左（変更前） / b = 右（変更後）
  local side_key
  if v.cur_layout.a and v.cur_layout.a.id == win then side_key = "a"
  elseif v.cur_layout.b and v.cur_layout.b.id == win then side_key = "b" end
  if not side_key then return { side = "差分" } end

  local label = side_key == "a" and "変更前" or "変更後"
  local file = v.cur_layout[side_key].file
  local rev = file and file.rev

  -- RevType: 1=作業ツリー 2=コミット 3=INDEX
  local rev_sha, what
  if rev then
    if rev.commit then
      rev_sha = tostring(rev.commit):sub(1, 10)
      what = rev_sha
    elseif rev.type == 1 then what = "作業ツリー"
    elseif rev.type == 3 then what = "INDEX"
    end
  end

  -- 実ファイルの相対パス（リポジトリルート基準）
  local path = v.cur_entry and v.cur_entry.path or (file and file.path)

  -- Commit 行にハッシュを出すので、Side には重ねない。
  -- ハッシュが無いとき（作業ツリー/INDEX）だけ、どこの中身かを補う。
  return {
    rev = rev_sha,
    side = (not rev_sha and what) and ("%s（%s）"):format(label, what) or label,
    path = path,
  }
end

--- リポジトリのルートを返す
local function repo_root(from)
  local r = vim.system({ "git", "-C", from, "rev-parse", "--show-toplevel" },
    { text = true }):wait()
  if r.code == 0 and r.stdout then
    local top = vim.trim(r.stdout)
    if top ~= "" then return top end
  end
  return nil
end

--- ブレイムモード中なら、その行を入れたコミットを返す
local function blame_commit(lnum)
  local ok, B = pcall(require, "custom.blame")
  if not ok or type(B.commit_at) ~= "function" then return nil end
  local okc, sha = pcall(B.commit_at, lnum)
  return okc and sha or nil
end

--- 送る文面を組み立てる
--- コードは入れない。参照だけで足りる。
--- 文字単位の選択のときだけ、選んだ文字を添える。
local function build(srow, erow, cwd, selection)
  local abs = vim.api.nvim_buf_get_name(0)
  local range = (srow == erow) and tostring(srow) or ("%d-%d"):format(srow, erow)
  local dc = diff_context()

  -- 差分側のバッファ名は内部表現なので、Diffview が持つ実パスに置き換える
  if dc and dc.path then
    local root = repo_root(vim.fn.getcwd())
    if root then abs = root .. "/" .. dc.path end
  end

  local out = {
    "【参照コード】",
    "File: " .. path_for(abs, cwd),
    "Lines: " .. range,
  }

  if dc then
    if dc.rev then table.insert(out, "Commit: " .. dc.rev) end
    table.insert(out, "Side: " .. dc.side)
  else
    -- 通常のファイルでも、ブレイム中ならその行の由来を添える
    local c = blame_commit(srow)
    if c then table.insert(out, "Commit: " .. c) end
  end

  if selection and selection ~= "" then
    table.insert(out, "選択: " .. selection)
  end

  table.insert(out, "")
  return table.concat(out, "\n")
end

-- ---- 送信の入口 ----

local function deliver(srow, erow, selection, label)
  local target, has_agent, reason, cwd = M.resolve_target()
  local text = build(srow, erow, cwd, selection)

  if target then
    local ok, err = send_to_pane(target, has_agent, text)
    if ok then
      vim.notify(("%s を送信 → %s（%s）"):format(label, target, reason), vim.log.levels.INFO)
      return
    end
    vim.notify("herdr への送信に失敗: " .. tostring(err) .. "\nクリップボードへコピーします",
      vim.log.levels.WARN)
  end

  -- フォールバック: クリップボードへ
  vim.fn.setreg("+", text)
  vim.fn.setreg('"', text)
  vim.notify(target and "クリップボードへコピーしました"
    or ("クリップボードへコピーしました（%s）"):format(reason), vim.log.levels.INFO)
end

-- ---- ビジュアルモード ----
-- 注意: ビジュアルモード中のマッピングでは '< '> はまだ更新されておらず
-- 「1つ前の選択範囲」を指してしまう。そのため getpos("v") と getpos(".") を使う。

--- 選択箇所を送る
---
--- 選択モードで送る内容が変わる:
---   V      行単位   → 参照だけ（エージェントが読めるので十分）
---   v      文字単位 → 参照＋選んだ文字（行参照では表現できないため）
---   Ctrl-V 矩形     → 同上
function M.send_selection()
  local mode = vim.fn.mode()
  if not mode:match("^[vV\22]") then mode = "v" end

  local vpos = vim.fn.getpos("v")
  local cpos = vim.fn.getpos(".")
  local srow = math.min(vpos[2], cpos[2])
  local erow = math.max(vpos[2], cpos[2])

  local selection = nil
  if mode ~= "V" then
    local ok, lines = pcall(vim.fn.getregion, vpos, cpos, { type = mode })
    if ok and type(lines) == "table" and #lines > 0 then
      local joined = vim.trim(table.concat(lines, " "))
      -- 長すぎるものは行参照で足りるので添えない
      if joined ~= "" and vim.fn.strdisplaywidth(joined) <= 80 then
        selection = joined
      end
    end
  end

  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "n", false)

  local label = selection and ("「%s」"):format(selection)
    or ((srow == erow) and ("%d行目"):format(srow) or ("%d-%d行目"):format(srow, erow))
  deliver(srow, erow, selection, label)
end

--- ノーマルモード: 現在行を送る
function M.send_location()
  local row = vim.fn.line(".")
  deliver(row, row, nil, ("%d行目"):format(row))
end

-- ---- キーマップ / コマンド ----
vim.keymap.set("v", "<C-l>", M.send_selection,
  { noremap = true, silent = true, desc = "選択箇所をエージェントへ送る" })
vim.keymap.set("n", "<C-l>", M.send_location,
  { noremap = true, silent = true, desc = "現在行をエージェントへ送る" })

vim.api.nvim_create_user_command("HerdrTarget", function()
  local target, has_agent, reason, cwd = M.resolve_target()
  if target then
    vim.notify(("送信先: %s\n判定理由: %s\n送信方法: %s\n相手の作業ディレクトリ: %s\n自ペイン: %s")
      :format(target, reason, has_agent and "agent send" or "pane send-text",
        cwd or "(不明。絶対パスで送ります)", self_pane() or "(不明)"),
      vim.log.levels.INFO)
  else
    vim.notify("送信先が見つかりません: " .. reason ..
      "\n（Ctrl+L はクリップボードへコピーします）", vim.log.levels.WARN)
  end
end, { desc = "Ctrl+L の送信先を確認する" })

return M
