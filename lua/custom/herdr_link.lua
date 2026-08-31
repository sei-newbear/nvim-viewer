-- ===================================================================
-- lua/custom/herdr_link.lua
-- ビューアーで選択したコードを Ctrl+L で左ペインのエージェントへ送信する
--
-- 仕組み:
--   herdr は各ペインに HERDR_PANE_ID を環境変数として注入している。
--   そこから `herdr pane neighbor --direction left` で左隣（エージェント）を特定し、
--   `herdr agent send` で文脈を直接流し込む。
--   Enter は送られないので、貼り付いた後に自分で質問を書き足せる。
-- ===================================================================

local M = {}

-- ---- herdr バイナリの解決 ----
local function herdr_bin()
  if vim.fn.executable("herdr") == 1 then
    return "herdr"
  end
  local fallback = vim.fn.expand("~/.local/bin/herdr")
  if vim.fn.executable(fallback) == 1 then
    return fallback
  end
  return nil
end

-- ---- herdr コマンド実行（リスト形式なのでシェルのクォート問題が起きない）----
local function herdr_json(args)
  local bin = herdr_bin()
  if not bin then return nil end
  local cmd = { bin }
  vim.list_extend(cmd, args)
  local res = vim.system(cmd, { text = true }):wait()
  if res.code ~= 0 or not res.stdout or res.stdout == "" then
    return nil
  end
  local ok, decoded = pcall(vim.json.decode, res.stdout)
  if not ok or type(decoded) ~= "table" or decoded.error then
    return nil
  end
  return decoded.result
end

local function self_pane()
  local id = vim.env.HERDR_PANE_ID
  if id and id ~= "" then return id end
  return nil
end

-- ---- 送信先の決定 ----
-- 戻り値: pane_id, has_agent, 理由の文字列
function M.resolve_target()
  -- 1) 明示的な指定を最優先（環境変数 or vim.g）
  local forced = vim.g.herdr_agent_target or vim.env.HERDR_AGENT_TARGET
  if forced and forced ~= "" then
    return forced, true, "明示指定"
  end

  local me = self_pane()
  if not me then
    return nil, false, "HERDR_PANE_ID が無い（herdr の外で起動している）"
  end

  -- ペイン一覧を取得して pane_id -> info のマップを作る
  local list = herdr_json({ "pane", "list" })
  local panes, my_tab = {}, nil
  if list and list.panes then
    for _, p in ipairs(list.panes) do
      panes[p.pane_id] = p
      if p.pane_id == me then my_tab = p.tab_id end
    end
  end

  -- 2) 左隣のペインを見る
  -- 注意: 戻り値の `pane_id` は問い合わせたペイン自身。
  -- 実際の隣は `neighbor_pane_id`（隣が無い場合はこのキーが存在しない）。
  local nb = herdr_json({ "pane", "neighbor", "--direction", "left", "--pane", me })
  local left = nb and nb.neighbor and nb.neighbor.neighbor_pane_id
  if left and left ~= vim.NIL and left ~= "" and left ~= me then
    local info = panes[left]
    local has_agent = info ~= nil and info.agent ~= nil and info.agent ~= vim.NIL
    return left, has_agent, "左隣のペイン"
  end

  -- 3) 左隣が無ければ、同じタブ内のエージェントを探す
  if my_tab then
    for _, p in pairs(panes) do
      if p.tab_id == my_tab and p.pane_id ~= me
        and p.agent ~= nil and p.agent ~= vim.NIL then
        return p.pane_id, true, "同じタブ内のエージェント"
      end
    end
  end

  return nil, false, "送信先のエージェントが見つからない"
end

-- ---- 実際の送信 ----
-- エージェントが居れば `agent send`、居なければ `pane send-text` を使う
local function send_to_pane(target, has_agent, text)
  local bin = herdr_bin()
  if not bin then return false, "herdr が見つからない" end

  local subcmd = has_agent and { "agent", "send" } or { "pane", "send-text" }
  local cmd = { bin }
  vim.list_extend(cmd, subcmd)
  table.insert(cmd, target)
  table.insert(cmd, text)

  local res = vim.system(cmd, { text = true }):wait()
  if res.code ~= 0 then
    return false, (res.stderr or res.stdout or "不明なエラー")
  end
  -- herdr は成功時もJSONで error を返すことがある
  if res.stdout and res.stdout:find('"error"') then
    return false, res.stdout
  end
  return true, nil
end

-- ---- 表示用のファイルパス（gitルートからの相対パスにする）----
local function display_path()
  local abs = vim.fn.expand("%:p")
  if abs == "" then return "[無名バッファ]" end
  local dir = vim.fn.fnamemodify(abs, ":h")
  local res = vim.system({ "git", "-C", dir, "rev-parse", "--show-toplevel" }, { text = true }):wait()
  if res.code == 0 and res.stdout then
    local root = vim.trim(res.stdout)
    if root ~= "" and abs:sub(1, #root + 1) == root .. "/" then
      return abs:sub(#root + 2)
    end
  end
  return abs
end

-- ---- 文脈テキストの組み立て ----
local function build_context(srow, erow, lines)
  local ft = vim.bo.filetype
  if ft == nil or ft == "" then ft = "" end
  local range = (srow == erow) and tostring(srow) or string.format("%d-%d", srow, erow)
  return table.concat({
    "【参照コード】",
    "File: " .. display_path(),
    "Lines: " .. range,
    "",
    "```" .. ft,
    table.concat(lines, "\n"),
    "```",
    "",
  }, "\n")
end

-- ---- 共通の送信処理 ----
local function deliver(context, label)
  local target, has_agent, reason = M.resolve_target()

  if target then
    local ok, err = send_to_pane(target, has_agent, context)
    if ok then
      vim.notify(string.format("%s を送信しました → %s (%s)", label, target, reason),
        vim.log.levels.INFO)
      return
    end
    vim.notify("herdr への送信に失敗: " .. tostring(err) .. "\nクリップボードへコピーします",
      vim.log.levels.WARN)
  end

  -- フォールバック: クリップボードへ
  vim.fn.setreg("+", context)
  vim.fn.setreg('"', context)
  local msg = target and "クリップボードへコピーしました"
    or string.format("クリップボードへコピーしました（%s）", reason)
  vim.notify(msg, vim.log.levels.INFO)
end

-- ---- ビジュアルモード: 選択範囲を送信 ----
-- 注意: ビジュアルモード中のマッピングでは '< '> はまだ更新されておらず
-- 「1つ前の選択範囲」を指してしまう。そのため getpos("v") と getpos(".") を使う。
--- ビジュアルモードで選択したテキストを取得し、文脈としてエージェントへ送信する関数
---
--- 選択モードをそのまま尊重する:
---   v      文字単位 → 選んだ文字だけ（識別子ひとつを聞きたいとき）
---   V      行単位   → 行まるごと
---   Ctrl-V 矩形     → 矩形の範囲
--- 行単位で決め打ちにすると、`v` で語を選んでも行全体が送られて
--- 「選んだものと違う」ことになる。getregion() がモードを見て取り分ける。
function M.send_selection()
  local mode = vim.fn.mode()
  if not mode:match("^[vV\22]") then mode = "v" end

  local vpos = vim.fn.getpos("v")
  local cpos = vim.fn.getpos(".")
  local srow = math.min(vpos[2], cpos[2])
  local erow = math.max(vpos[2], cpos[2])

  local ok, lines = pcall(vim.fn.getregion, vpos, cpos, { type = mode })
  if not ok or type(lines) ~= "table" or #lines == 0 then
    -- getregion が使えない環境向けの保険（行単位で取る）
    lines = vim.fn.getline(srow, erow)
    if type(lines) ~= "table" then lines = { tostring(lines) } end
  end
  if #lines == 0 then
    vim.notify("選択範囲が空です", vim.log.levels.WARN)
    return
  end

  -- ビジュアルモードを抜ける
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "n", false)

  -- 1行の一部だけを選んだ場合に「1行のコード」と出ると紛らわしいので、
  -- 短い選択はその中身をそのまま見せる
  local label
  local joined = table.concat(lines, " ")
  if #lines == 1 and vim.fn.strdisplaywidth(joined) <= 30 then
    label = ("「%s」"):format(vim.trim(joined))
  else
    label = ("%d行のコード"):format(#lines)
  end
  deliver(build_context(srow, erow, lines), label)
end

-- ---- ノーマルモード: 現在行の位置情報を送信 ----
function M.send_location()
  local row = vim.fn.line(".")
  local lines = vim.fn.getline(row, row)
  if type(lines) ~= "table" then lines = { tostring(lines) } end
  deliver(build_context(row, row, lines), "現在行")
end

-- ---- キーマップ ----
vim.keymap.set("v", "<C-l>", M.send_selection,
  { noremap = true, silent = true, desc = "選択コードをエージェントへ送信" })
vim.keymap.set("n", "<C-l>", M.send_location,
  { noremap = true, silent = true, desc = "現在行をエージェントへ送信" })

-- ---- 動作確認用コマンド ----
vim.api.nvim_create_user_command("HerdrTarget", function()
  local target, has_agent, reason = M.resolve_target()
  if target then
    vim.notify(string.format(
      "送信先: %s\n判定理由: %s\n送信方法: %s\n自ペイン: %s",
      target, reason, has_agent and "agent send" or "pane send-text",
      self_pane() or "(不明)"), vim.log.levels.INFO)
  else
    vim.notify("送信先が見つかりません: " .. reason .. "\n（Ctrl+L はクリップボードへコピーします）",
      vim.log.levels.WARN)
  end
end, { desc = "Ctrl+L の送信先を確認する" })

return M
