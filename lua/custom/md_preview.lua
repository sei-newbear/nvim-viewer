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

local LIB_DIR  = vim.fn.expand("~/.local/share/nvim-md-preview")
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

--- 現在のバッファをHTMLにしてブラウザで開く
function M.open()
  if vim.bo.filetype ~= "markdown" then
    vim.notify("マークダウンファイルではありません（filetype=" .. vim.bo.filetype .. "）",
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
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local md = table.concat(lines, "\n")

  local abs = vim.api.nvim_buf_get_name(0)
  local dir = abs ~= "" and vim.fn.fnamemodify(abs, ":h") or vim.fn.getcwd()
  local name = abs ~= "" and vim.fn.fnamemodify(abs, ":t") or "[無題]"

  local template = table.concat(vim.fn.readfile(TEMPLATE), "\n")

  -- 相対パスの画像リンクが解決できるよう base を元ファイルの場所にする
  local html = template
    :gsub("__TITLE__", vim.fn.escape(name, "%"))
    :gsub("__BASE__", vim.fn.escape("file://" .. dir .. "/", "%"))
    :gsub("__LIB__", vim.fn.escape("file://" .. LIB_DIR, "%"))
    :gsub("__FOOTER__", vim.fn.escape(abs ~= "" and abs or "（保存されていないバッファ）", "%"))
    :gsub("__MD_B64__", vim.base64.encode(md))

  -- 同じファイルは同じ出力先に書く（タブが無限に増えないように）
  local key = vim.fn.sha256(abs ~= "" and abs or tostring(vim.api.nvim_get_current_buf())):sub(1, 12)
  local out = ("%s/nvim-md-preview-%s.html"):format(vim.fn.stdpath("cache"), key)
  vim.fn.writefile(vim.split(html, "\n"), out)

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

vim.api.nvim_create_user_command("MarkdownBrowser", M.open,
  { desc = "マークダウンをブラウザで開く" })

return M
