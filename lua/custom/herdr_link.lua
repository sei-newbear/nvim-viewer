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
-- herdr が応答しないと Neovim ごと止まるので、必ず上限を切る
local TIMEOUT_MS = 2000

local function herdr_json(args)
  local bin = herdr_bin()
  if not bin then return nil end
  local cmd = { bin }
  vim.list_extend(cmd, args)
  local ok, res = pcall(function() return vim.system(cmd, { text = true }):wait(TIMEOUT_MS) end)
  if not ok or not res then return nil end
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
local function has_agent_at(info)
  return info ~= nil and info.agent ~= nil and info.agent ~= vim.NIL
end

--- 同じタブに居るエージェントを列挙する
---
--- 送信先を選ぶ画面と自動選択の両方がこれを使う。
--- **必ず pane_id で並べること。** `pairs` は順序が不定なので、
--- 並べないと同じタブに複数居るときに毎回違う相手へ送りうる
--- （エラーも出ないので気づけない）。
---@return table[] agents, string? me, table panes, boolean ok herdr から取得できたか
local function tab_agents()
  local list = herdr_json({ "pane", "list" })
  local panes = {}
  if list and list.panes then
    for _, p in ipairs(list.panes) do panes[p.pane_id] = p end
  end
  local me = self_pane()
  local my_tab = me and panes[me] and panes[me].tab_id or nil

  local out = {}
  if my_tab then
    for _, p in pairs(panes) do
      if p.tab_id == my_tab and p.pane_id ~= me and has_agent_at(p) then
        table.insert(out, p)
      end
    end
    table.sort(out, function(a, b) return a.pane_id < b.pane_id end)
  end
  return out, me, panes, list ~= nil
end

--- 選ばれている送信先を返す（無ければ nil）
local function pinned()
  local v = vim.g.herdr_agent_target or vim.env.HERDR_AGENT_TARGET
  if v == nil or v == "" then return nil end
  return v
end

function M.resolve_target()
  local agents, me, panes, ok = tab_agents()

  local forced = pinned()
  if forced then
    if not ok then
      -- herdr の応答が無い。指定を消してしまうと復旧できないので、そのまま使う。
      return forced, true, "指定した送信先（確認できず）", nil
    end
    local info = panes[forced]
    if info then
      return forced, has_agent_at(info), "指定した送信先", info.cwd
    end
    -- 指定先が消えている。黙って失敗させず、自動選択に戻す。
    vim.notify(("送信先 %s が見つかりません（閉じられた？）。自動選択に戻します"):format(forced),
      vim.log.levels.WARN)
    vim.g.herdr_agent_target = nil
  end

  if not me then
    return nil, false, "HERDR_PANE_ID が無い（herdr の外で起動している）", nil
  end

  -- 左隣のペイン。
  -- 注意: 戻り値の `pane_id` は問い合わせたペイン自身で、
  -- 実際の隣は `neighbor_pane_id`（隣が無い場合はこのキーごと存在しない）。
  local nb = herdr_json({ "pane", "neighbor", "--direction", "left", "--pane", me })
  local left = nb and nb.neighbor and nb.neighbor.neighbor_pane_id
  if left == vim.NIL or left == "" or left == me then left = nil end

  -- 左隣にエージェントが居るなら、それが本命
  if left and has_agent_at(panes[left]) then
    return left, true, "左隣のエージェント", panes[left].cwd
  end

  -- 左隣がシェルなどの場合、同じタブのエージェントの方が意図に近い。
  -- 左隣を無条件に優先すると、シェルへ文面が打ち込まれてしまう。
  -- 複数居るときは pane_id の若い方に固定する（tab_agents が並べてある）。
  if agents[1] then
    local a = agents[1]
    local why = #agents > 1
      and ("同じタブ内のエージェント（%d件中の先頭）"):format(#agents)
      or "同じタブ内のエージェント"
    return a.pane_id, true, why, a.cwd
  end

  -- エージェントがどこにも居なければ、左隣へ素の文字列として送る
  if left then
    return left, false, "左隣のペイン（エージェント無し）",
      panes[left] and panes[left].cwd or nil
  end

  return nil, false, "送信先のエージェントが見つからない", nil
end

-- ---- 送信 ----

local function send_to_pane(target, has_agent, text)
  local bin = herdr_bin()
  if not bin then return false, "herdr が見つからない" end

  -- エージェントが居るペインなら agent send、そうでなければ pane send-text
  local subcmd = has_agent and { "agent", "send" } or { "pane", "send-text" }

  -- 末尾の改行は送り先で意味が変わる。
  --   agent send    : 入力欄に改行が入るだけ。送信はされない。
  --                   **付けないと、続けて送ったときに前の文面と行が繋がる**
  --                     Lines: 23【参照コード】
  --                   付けておけば次が新しい行から始まり、そのまま質問も書ける。
  --   pane send-text: 相手はシェルなので、改行はそのまま実行になる。付けない。
  local payload = has_agent and (text .. "\n") or text

  local cmd = { bin }
  vim.list_extend(cmd, subcmd)
  table.insert(cmd, target)
  table.insert(cmd, payload)

  local ok, res = pcall(function() return vim.system(cmd, { text = true }):wait(TIMEOUT_MS) end)
  if not ok or not res then return false, "herdr が応答しません" end
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

  -- ここでは末尾に改行を付けない。付けるかどうかは送り先で決める
  -- （送信経路によって改行の意味が変わるため。send_to_pane を見ること）。
  return table.concat(out, "\n")
end

-- ---- 送信の入口 ----

--- 送る意味があるバッファか
--- 無名バッファや特殊バッファは File も選択文字も無く、
--- 受け取った側に打つ手が無い
local function sendable()
  local buf = vim.api.nvim_get_current_buf()
  if vim.api.nvim_buf_get_name(buf) == "" then
    vim.notify("保存されていないバッファは送れません", vim.log.levels.WARN)
    return false
  end
  if vim.bo[buf].buftype ~= "" and not vim.wo[vim.api.nvim_get_current_win()].diff then
    vim.notify("このバッファは送れません（通常のファイルか差分で使ってください）",
      vim.log.levels.WARN)
    return false
  end
  return true
end

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

  -- フォールバック: クリップボードへ（貼り付けたときに行が繋がらないよう改行を付ける）
  vim.fn.setreg("+", text .. "\n")
  vim.fn.setreg('"', text .. "\n")
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
-- 選択に付ける上限。
-- これは「入力欄を守るため」ではなく、事故を防ぐための最後の砦。
-- agent send は Enter を押さないので、長すぎたら入力欄で消せばよく、
-- 送るかどうかを決めるのは受け取る側。
-- 一方 minified なファイルは1行が数万文字あり、そこで v$ を押すと
-- それが丸ごと流し込まれる。手書きのコードならまず届かない値にする。
local MAX_SELECTION = 2000

--- 表示幅で切り詰める（バイトで切ると多バイト文字が壊れる）
--- 必要な幅に達した時点で止まるので、極端に長い行でも走査は一定量で済む
---@return string text, boolean cut
local function clip(s, w)
  if vim.fn.strwidth(s) <= w then return s, false end
  local out, acc = "", 0
  for i = 0, vim.fn.strchars(s) - 1 do
    local c = vim.fn.strcharpart(s, i, 1)
    local cw = vim.fn.strwidth(c)
    if acc + cw > w - 1 then break end
    out, acc = out .. c, acc + cw
  end
  return out .. "…", true
end

--- 選んだ文字を1行に収める
---
--- 複数行をただ空白でつなぐと、原文のどこにも無い文字列になる
--- （インデントが連続空白として混ざり、行の境界も消える）。
--- 区切りが分かる形にして、境界を保つ。
--- タブは生のまま送らない。TUI の入力欄では補完キーとして解釈されうるうえ、
--- 幅の計算でも8桁分を食って80桁の枠を無駄に使い切る。
local function format_selection(lines)
  if not lines or #lines == 0 then return nil end

  local joined
  if #lines == 1 then
    joined = vim.trim((lines[1]:gsub("\t", " ")))
  else
    local parts = {}
    for _, l in ipairs(lines) do
      local t = vim.trim((l:gsub("\t", " ")))
      if t ~= "" then table.insert(parts, t) end
    end
    joined = table.concat(parts, " / ")
  end

  if joined == "" then return nil end

  -- 長いからといって黙って捨てない。
  -- 以前は80桁を超えると `選択:` ごと落としていたため、
  -- 長い行では v（文字選択）と V（行選択）の文面が完全に同じになり、
  -- 「行のどこを指しているか」を伝える手段が消えていた。
  local text, cut = clip(joined, MAX_SELECTION)
  if cut then
    vim.notify(("選択が長いので %d 桁で切りました"):format(MAX_SELECTION),
      vim.log.levels.WARN)
  end
  return text
end

function M.send_selection()
  if not sendable() then
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "n", false)
    return
  end

  local mode = vim.fn.mode()
  if not mode:match("^[vV\22]") then mode = "v" end

  local vpos = vim.fn.getpos("v")
  local cpos = vim.fn.getpos(".")
  local srow = math.min(vpos[2], cpos[2])
  local erow = math.max(vpos[2], cpos[2])

  -- `$` で行末まで伸ばした矩形選択かどうか。
  -- このとき curswant は v:maxcol になるが、getpos は curswant を運ばない
  -- （getcurpos に替えても getregion の結果は変わらない）。
  -- そのため getregion はカーソル桁で切ってしまい、
  -- **ファイルのどこにも無い文字列**が出来上がる。自分で行末まで採る。
  local to_eol = (mode == "\22")
    and vim.fn.winsaveview().curswant == vim.v.maxcol

  local selection = nil
  if mode ~= "V" then
    local lines
    if to_eol then
      lines = {}
      local from = math.min(vpos[3], cpos[3])
      for l = srow, erow do
        table.insert(lines, vim.fn.getline(l):sub(from))
      end
    else
      local ok, got = pcall(vim.fn.getregion, vpos, cpos, { type = mode })
      if ok and type(got) == "table" then lines = got end
    end
    selection = format_selection(lines)
  end

  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "n", false)

  -- 通知に選択文字をそのまま出すと、長い選択で画面が埋まる。
  -- 「何を送ったか」が分かれば十分なので、通知用は短く切る。
  local label = selection and ("「%s」"):format((clip(selection, 40)))
    or ((srow == erow) and ("%d行目"):format(srow) or ("%d-%d行目"):format(srow, erow))
  deliver(srow, erow, selection, label)
end

--- ノーマルモード: 現在行を送る
function M.send_location()
  if not sendable() then return end
  local row = vim.fn.line(".")
  deliver(row, row, nil, ("%d行目"):format(row))
end

-- ---- 送信先を選ぶ ----

--- 同じタブのエージェントから送信先を選ぶ
---
--- 範囲を同じタブに限っているのは、この道具の前提が
--- 「いま隣で話している相手に、見ているコードを渡す」だから。
--- 別タブのエージェントは視界に入っておらず、cwd も違うので
--- 渡しても噛み合わない。
---
--- 選んだ結果は vim.g.herdr_agent_target に入れるだけ。
--- 既存の上書き経路をそのまま使うので、新しい仕組みは足していない。
--- nvim を閉じれば自動選択に戻る。
function M.pick()
  local agents, me, _, ok = tab_agents()
  if not ok then
    vim.notify("herdr から情報を取得できません", vim.log.levels.WARN)
    return
  end
  if not me then
    vim.notify("herdr の外で起動しています（Ctrl+L はクリップボードへコピーします）",
      vim.log.levels.WARN)
    return
  end
  if #agents == 0 then
    vim.notify("このタブにエージェントが居ません", vim.log.levels.WARN)
    return
  end

  local cur = pinned()
  local items = { { auto = true } }
  for _, a in ipairs(agents) do table.insert(items, a) end

  vim.ui.select(items, {
    prompt = "Ctrl+L の送信先",
    format_item = function(it)
      if it.auto then
        return ("%s自動（左隣を優先／%d件から選ぶ）"):format(cur and "  " or "● ", #agents)
      end
      local title = it.terminal_title_stripped or it.terminal_title or ""
      return ("%s%-7s %-8s %s"):format(
        cur == it.pane_id and "● " or "  ",
        it.pane_id, it.agent_status or "", clip(vim.trim(title), 40))
    end,
  }, function(choice)
    if not choice then return end
    if choice.auto then
      vim.g.herdr_agent_target = nil
      vim.notify("送信先: 自動（左隣を優先）", vim.log.levels.INFO)
    else
      vim.g.herdr_agent_target = choice.pane_id
      vim.notify(("送信先: %s  %s"):format(choice.pane_id,
        clip(vim.trim(choice.terminal_title_stripped or ""), 40)), vim.log.levels.INFO)
    end
  end)
end

-- ---- キーマップ / コマンド ----
vim.keymap.set("v", "<C-l>", M.send_selection,
  { noremap = true, silent = true, desc = "選択箇所をエージェントへ送る" })
vim.keymap.set("n", "<C-l>", M.send_location,
  { noremap = true, silent = true, desc = "現在行をエージェントへ送る" })

vim.api.nvim_create_user_command("HerdrPick", function() M.pick() end,
  { desc = "Ctrl+L の送信先を同じタブのエージェントから選ぶ" })

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
