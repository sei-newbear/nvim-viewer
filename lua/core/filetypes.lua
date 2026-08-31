-- ===================================================================
-- lua/core/filetypes.lua
-- 標準では判別されないファイルタイプを補う
--
-- Helm のテンプレートは拡張子が .yaml だが、中身は Go テンプレートを
-- 含むため **YAML としては構文エラーになる**。
--   {{- if .Values.image }}
--   image: "{{ .Values.image.repo }}"
--   {{- end }}
-- Neovim は既定でこれを yaml と判定するので、
--   - treesitter が ERROR 節点を作る（色が壊れる）
--   - helm_ls は filetype=helm を要求するので接続しない
-- という二重の不都合が起きる。ここで helm と判定させる。
-- ===================================================================

--- Gauge のプロジェクトルートを探す
--- manifest.json は他の用途（PWA・ブラウザ拡張）でも使われる名前なので、
--- 中身に Gauge の鍵があるかまで見る
local function gauge_root(path)
  local root = vim.fs.root(path, "manifest.json")
  if not root then return nil end
  local ok, txt = pcall(vim.fn.readfile, root .. "/manifest.json")
  if not ok then return nil end
  local body = table.concat(txt, "\n")
  if body:find('"Language"') or body:find('"Plugins"') then return root end
  return nil
end

vim.filetype.add({
  pattern = {
    -- Gauge の仕様ファイル。中身は Markdown（見出し＋`* 手順`）。
    -- .cpt は既定で html と誤判定される。
    [".*%.cpt"] = "gauge",
    -- .spec は RPM のパッケージ定義と紛らわしいので、
    -- Gauge プロジェクトの中にあるときだけ gauge とみなす。
    [".*%.spec"] = function(path)
      return gauge_root(path) and "gauge" or "spec"
    end,

    -- チャートの templates/ 配下は Go テンプレートを含む
    [".*/templates/.*%.ya?ml"] = "helm",
    [".*/templates/.*%.tpl"] = "helm",
    [".*/templates/.*%.txt"] = "helm",
    ["helmfile.*%.ya?ml"] = "helm",

    -- values.yaml は素の YAML だが、helm_ls に見せると
    -- テンプレート側との対応を解決できる。
    -- 同じ階層に Chart.yaml がある場合だけ（無関係な values.yaml を巻き込まない）
    [".*/values%.ya?ml"] = function(path)
      local dir = vim.fn.fnamemodify(path, ":h")
      if vim.uv.fs_stat(dir .. "/Chart.yaml") then
        return "yaml.helm-values"
      end
      return "yaml"
    end,
  },
})

-- Gauge の仕様は Markdown なので、その構文で色を付ける。
-- 専用のファイルタイプにしておくことで、言語サーバは
-- 通常のマークダウンには接続せず、Gauge のファイルにだけ繋がる。
vim.treesitter.language.register("markdown", "gauge")
