local M = {}

local compile_log = "logs/nvim-viewer-compile.log"

--- Gauge LSPを起動するコマンドを返す。
--- Kotlinの手順実装はコンパイル済みclassから読み取られるため、
--- 成果物がない初回だけMavenの差分コンパイルを先に実行する。
function M.daemon_command(root)
  local compiler = vim.uv.fs_stat(root .. "/mvnw") and "./mvnw" or "mvn"
  local script = ([[
root=$2
cd "$root" || exit 1
if [ ! -d target/test-classes ]; then
  mkdir -p logs
  "$1" test-compile > %s 2>&1
  status=$?
  if [ "$status" -ne 0 ]; then
    cat %s >&2
    exit "$status"
  fi
fi
exec env gauge_custom_build_path=target/test-classes \
  gauge daemon --lsp --dir "$root"
]]):format(compile_log, compile_log)

  return { "sh", "-c", script, "nvim-viewer-gauge", compiler, root }
end

return M
