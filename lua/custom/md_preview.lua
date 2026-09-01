-- ===================================================================
-- lua/custom/md_preview.lua
-- マークダウンを整形HTMLにしてブラウザで開く（mermaid も図として描画）
--
-- herdr のペインはピクセル寸法を報告しないため、ターミナル内への
-- 画像インライン表示は成立しない。図を見たいときはブラウザに出す。
-- 文章・表・コードはターミナル内で render-markdown が描画するので、
-- ブラウザに出すのは「図を見たいとき」だけでよい。
--
-- ライブラリはローカルに複製済みのものを file:// で読むので、
-- ネットワークに繋がっていなくても動く。
-- ===================================================================

local M = {}

-- 描画ライブラリの置き場所。bootstrap.sh がここへ複製する。
-- 設定ごとに分けず共有する（中身は marked / mermaid で、どの設定でも同じ）。
-- XDG_DATA_HOME を尊重する（bootstrap.sh と同じ場所を指すこと）。
local LIB_DIR  = (vim.env.XDG_DATA_HOME or vim.fn.expand("~/.local/share"))
  .. "/nvim-md-preview"
local TEMPLATE = vim.fn.stdpath("config") .. "/md-preview-template.html"

--- 依存が揃っているか確認する
---@return boolean ok, string? reason
local function check()
  if vim.fn.filereadable(TEMPLATE) ~= 1 then
    return false, "テンプレートが見つかりません: " .. TEMPLATE
  end
  for _, lib in ipairs({ "marked.umd.js", "mermaid.min.js" }) do
    if vim.fn.filereadable(LIB_DIR .. "/" .. lib) ~= 1 then
      return false, ("ライブラリが見つかりません: %s/%s\n"):format(LIB_DIR, lib)
        .. "npm i -g marked @mermaid-js/mermaid-cli で入れ直してください"
    end
  end
  return true
end

--- .desktop ファイルから実行コマンドを取り出す
local function exec_from_desktop(desktop)
  if not desktop or desktop == "" then return nil end
  local dirs = {
    vim.fn.expand("~/.local/share/applications"),
    "/usr/share/applications",
    "/usr/local/share/applications",
    "/var/lib/snapd/desktop/applications",
    "/var/lib/flatpak/exports/share/applications",
  }
  for _, d in ipairs(dirs) do
    local path = d .. "/" .. desktop
    if vim.fn.filereadable(path) == 1 then
      for _, line in ipairs(vim.fn.readfile(path)) do
        local exec = line:match("^Exec%s*=%s*(.+)$")
        if exec then
          -- "google-chrome %U" のような形から実行ファイル名だけを取る
          local bin = exec:gsub("%%%a", ""):match("^%s*(%S+)")
          if bin and vim.fn.executable(bin) == 1 then return bin end
        end
      end
    end
  end
  return nil
end

--- ブラウザを開くコマンドを決める
---
--- 注意: `xdg-open` は使わない。
--- xdg-open は text/html の関連付け（`xdg-mime query default text/html`）に従うが、
--- ここが Slack など**ブラウザ以外**になっている環境が実際にある。
--- ローカルの .html を確実にブラウザで開くため、ブラウザを直接選ぶ。
local function opener()
  -- 1) 明示指定を最優先
  if vim.env.BROWSER and vim.env.BROWSER ~= "" then
    local bin = vim.env.BROWSER:match("^%s*(%S+)")
    if bin and vim.fn.executable(bin) == 1 then return bin end
  end

  -- 2) 既定のウェブブラウザ（xdg-settings が返す .desktop を解決する）
  if vim.fn.executable("xdg-settings") == 1 then
    local r = vim.system({ "xdg-settings", "get", "default-web-browser" },
      { text = true }):wait()
    if r.code == 0 and r.stdout then
      local bin = exec_from_desktop(vim.trim(r.stdout))
      if bin then return bin end
    end
  end

  -- 3) よく使われるブラウザを順に探す
  for _, cmd in ipairs({
    "google-chrome", "google-chrome-stable", "chromium", "chromium-browser",
    "microsoft-edge", "brave-browser", "firefox", "librewolf",
  }) do
    if vim.fn.executable(cmd) == 1 then return cmd end
  end

  -- 4) 最後の手段（macOS / WSL、および関連付けが正しい環境向け）
  for _, cmd in ipairs({ "open", "wslview", "xdg-open" }) do
    if vim.fn.executable(cmd) == 1 then return cmd end
  end
  return nil
end

--- ファイルパスを file:// の URL にする
--- HTML エスケープだけでは足りない。`#` や `?` はそのままだとフラグメント・
--- クエリとして扱われ、相対パスの解決先が**別のディレクトリ**になる。
--- `%41` のような並びも実際に別のファイルを読みに行ってしまう。
local function path_to_url(p)
  return "file://" .. (p:gsub("[^%w%-%._~/]", function(c)
    return ("%%%02X"):format(c:byte())
  end))
end

--- HTML に流し込む値を安全にする
--- テンプレートは属性値の中にも埋めるので、引用符まで潰しておく
local function esc_html(t)
  return (tostring(t)
    :gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;")
    :gsub('"', "&quot;"):gsub("'", "&#39;"))
end

--- 読み出しを許すのは本人だけにする（中身がそのまま埋まっているため）
local function protect(path)
  pcall(vim.uv.fs_chmod, path, tonumber("600", 8))
end

--- 古いプレビューを片付ける
--- ファイル名は絶対パスのハッシュで決まるので放っておくと溜まり続け、
--- しかも中身（マークダウン全文）が base64 で埋まったまま残る。
local function sweep()
  local dir = vim.fn.stdpath("cache")
  local cutoff = os.time() - 7 * 86400
  local ok, iter = pcall(vim.fs.dir, dir)
  if not ok then return end
  for name, t in iter do
    if t == "file" and name:match("^nvim%-md%-preview%-%x+%.html$") then
      local path = dir .. "/" .. name
      local st = vim.uv.fs_stat(path)
      if st and st.mtime and st.mtime.sec < cutoff then
        pcall(vim.uv.fs_unlink, path)
      end
    end
  end
end

--- バッファをHTMLにしてブラウザで開く
--- 対象は引数で受ける。フッターのボタンは「裏のマークダウン」を
--- 指しながら押されるので、現在バッファを見ると必ず外れる。
function M.open(buf)
  buf = buf or vim.api.nvim_get_current_buf()
  if vim.bo[buf].filetype ~= "markdown" then
    vim.notify("マークダウンファイルではありません（filetype=" .. vim.bo[buf].filetype .. "）",
      vim.log.levels.WARN)
    return
  end

  local ok, reason = check()
  if not ok then
    vim.notify(reason, vim.log.levels.ERROR)
    return
  end

  local open_cmd = opener()
  if not open_cmd then
    vim.notify("ブラウザが見つかりません（$BROWSER に実行ファイルを指定してください）", vim.log.levels.ERROR)
    return
  end

  -- 保存されていない変更も含めて、今バッファに見えている内容を出す
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local md = table.concat(lines, "\n")

  local abs = vim.api.nvim_buf_get_name(buf)
  local dir = abs ~= "" and vim.fn.fnamemodify(abs, ":h") or vim.fn.getcwd()
  local name = abs ~= "" and vim.fn.fnamemodify(abs, ":t") or "[無題]"

  local template = table.concat(vim.fn.readfile(TEMPLATE), "\n")

  -- 穴埋めは**関数**で行う。
  -- `gsub` の置換文字列では `%` がエスケープ文字として解釈されるため、
  -- `100%done.md` のような名前で中身が壊れ、`pct%1abc.md` に至っては
  -- プレースホルダ文字列がそのまま出力に漏れていた。
  -- 関数の戻り値はパターン解釈されないので、この問題ごと消える。
  -- 併せて HTML としての意味も潰しておく（ファイル名は属性値にも入る）。
  local nonce = vim.fn.sha256(("%s|%s|%s"):format(abs, vim.uv.hrtime(), vim.uv.os_getpid())):sub(1, 32)
  local vals = {
    TITLE  = esc_html(name),
    -- 相対パスの画像リンクが解決できるよう base を元ファイルの場所にする
    BASE   = esc_html(path_to_url(dir) .. "/"),
    LIB    = esc_html(path_to_url(LIB_DIR)),
    FOOTER = esc_html(abs ~= "" and abs or "（保存されていないバッファ）"),
    MD_B64 = vim.base64.encode(md),
    NONCE  = nonce,
  }
  local html = template:gsub("__(%u[%u%d_]*)__", function(k) return vals[k] end)

  -- 同じファイルは同じ出力先に書く（タブが無限に増えないように）
  local key = vim.fn.sha256(abs ~= "" and abs or tostring(buf)):sub(1, 12)
  local out = ("%s/nvim-md-preview-%s.html"):format(vim.fn.stdpath("cache"), key)
  -- 先に空ファイルを 0600 で作ってから書く。
  -- writefile は umask に従うので、そのまま書くと一瞬 0664 になる窓ができる。
  -- 中身はマークダウン全文なので、その窓を作らない。
  if not vim.uv.fs_stat(out) then
    local fd = vim.uv.fs_open(out, "w", tonumber("600", 8))
    if fd then vim.uv.fs_close(fd) end
  end
  protect(out)
  vim.fn.writefile(vim.split(html, "\n"), out)
  protect(out)
  sweep()

  vim.system({ open_cmd, out }, { detach = true })
  vim.notify(("%s で開きました: %s"):format(vim.fn.fnamemodify(open_cmd, ":t"), name),
    vim.log.levels.INFO)
end

-- ---- キーマップ / コマンド ----
vim.api.nvim_create_autocmd("FileType", {
  group = vim.api.nvim_create_augroup("ViewerMdPreview", { clear = true }),
  pattern = "markdown",
  callback = function(ev)
    -- `p`(preview) ではなく `o`(open) にしている。
    -- このビューアーは最初から整形表示なので「プレビュー」という語は
    -- 「整形表示に切り替える」と誤解されやすい。ここは純粋に
    -- 「ブラウザで開く」操作であることを名前で示す。
    vim.keymap.set("n", "<leader>o", M.open,
      { buffer = ev.buf, silent = true, desc = "ブラウザで開く（mermaid を図で描画）" })
  end,
})

-- 注意: コマンドのコールバックには引数テーブルが渡される。
-- buf を取る関数をそのまま登録すると、buf にテーブルが入って落ちる。
vim.api.nvim_create_user_command("MarkdownBrowser", function() M.open() end,
  { desc = "マークダウンをブラウザで開く" })

return M
