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

vim.filetype.add({
  pattern = {
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
