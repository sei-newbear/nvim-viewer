-- ===================================================================
-- lua/core/parsers.lua
-- treesitter パーサーの一覧（ハイライト対象の言語）
--
-- ここが唯一の定義。plugins/treesitter.lua と scripts/bootstrap.sh の
-- 両方がこれを読む。以前は両方に同じ配列を書いていたため、
-- 片方だけ増やしてズレていた。
--
-- 方針: lua/plugins/lsp.lua の候補表にある言語は、ここにも入れる。
-- 定義ジャンプはできるのに色が付かない、という状態を作らないため。
-- ===================================================================

return {
  -- 設定・文書
  "bash", "diff", "dockerfile", "helm", "json", "markdown", "markdown_inline",
  "query", "regex", "sql", "terraform", "toml", "vim", "vimdoc", "yaml",

  -- Web
  "css", "html", "javascript", "svelte", "tsx", "typescript",

  -- コンパイル言語
  "c", "cpp", "fsharp", "go", "haskell", "java", "kotlin", "ocaml",
  "rust", "scala", "zig",

  -- 動的言語・その他
  "clojure", "dart", "lua", "luadoc", "php", "python", "ruby",
}
