#!/usr/bin/env bash
# ===================================================================
# 新しいマシンでこの設定を動かすための初期化スクリプト
#
#   git clone <repo> ~/.config/nvim
#   ~/.config/nvim/scripts/bootstrap.sh
#
# 方針:
#   - sudo を使わない（mise / npm / go install で完結させる）
#   - 何度実行しても壊れない（入っているものは飛ばす）
#   - 勝手に消さない・上書きしない
#   - 何をしたか最後にまとめて出す
# ===================================================================
set -uo pipefail

NVIM_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIB_DIR="$HOME/.local/share/nvim-md-preview"
PUPPETEER_JSON="$NVIM_DIR/mermaid-puppeteer.json"

DONE=(); SKIP=(); WARN=()
ok()   { DONE+=("$1"); printf '  \033[32m✓\033[0m %s\n' "$1"; }
skip() { SKIP+=("$1"); printf '  \033[90m-\033[0m %s（導入済み）\n' "$1"; }
warn() { WARN+=("$1"); printf '  \033[33m!\033[0m %s\n' "$1"; }
head_() { printf '\n\033[1m%s\033[0m\n' "$1"; }

has() { command -v "$1" >/dev/null 2>&1; }

# -------------------------------------------------------------------
head_ "0. 置き場所の確認"
# -------------------------------------------------------------------
# nvim は $XDG_CONFIG_HOME/nvim（既定は ~/.config/nvim）しか見ない。
# 別の場所に clone した状態で実行すると、プラグインやパーサーの導入だけが
# 「本物の設定」に対して行われ、意図しない結果になる。
EXPECTED="${XDG_CONFIG_HOME:-$HOME/.config}/nvim"
if [ "$NVIM_DIR" != "$(cd "$EXPECTED" 2>/dev/null && pwd || echo "")" ]; then
  printf '  \033[33m!\033[0m このリポジトリは %s にあります\n' "$NVIM_DIR"
  printf '    nvim が読むのは %s です。\n' "$EXPECTED"
  printf '    そこへ clone し直すか、symlink を張ってから実行してください。\n\n'
  printf '    中断しました。\n'
  exit 1
fi
ok "配置は正しい（$NVIM_DIR）"

# -------------------------------------------------------------------
head_ "1. 前提ツールの確認"
# -------------------------------------------------------------------
for c in git curl; do
  has "$c" && skip "$c" || warn "$c が無い。先に入れてください"
done

if ! has mise; then
  warn "mise が無い。https://mise.jdx.dev/ を見て入れるか、neovim を自分で用意してください"
fi

# -------------------------------------------------------------------
head_ "2. Neovim（0.11 以上が必要）"
# -------------------------------------------------------------------
need_nvim=1
if has nvim; then
  ver=$(nvim --version | head -1 | grep -oE '[0-9]+\.[0-9]+' | head -1)
  major=${ver%%.*}; minor=${ver##*.}
  if [ "$major" -gt 0 ] || [ "$minor" -ge 11 ]; then
    skip "neovim $ver"; need_nvim=0
  else
    warn "neovim $ver は古い（0.11 以上が必要）。入れ直します"
  fi
fi
if [ "$need_nvim" = 1 ] && has mise; then
  mise use -g neovim@latest >/dev/null 2>&1 && ok "neovim を導入" || warn "neovim の導入に失敗"
fi

# -------------------------------------------------------------------
head_ "3. tree-sitter CLI（パーサーのビルドに必須）"
# -------------------------------------------------------------------
if has tree-sitter; then
  skip "tree-sitter"
elif has npm; then
  npm install -g tree-sitter-cli >/dev/null 2>&1 \
    && { has mise && mise reshim >/dev/null 2>&1; ok "tree-sitter-cli を導入"; } \
    || warn "tree-sitter-cli の導入に失敗"
else
  warn "npm が無いため tree-sitter-cli を入れられない（パーサーがビルドできません）"
fi

# -------------------------------------------------------------------
head_ "4. 言語サーバ（プロジェクトの言語に応じて）"
# -------------------------------------------------------------------
if has npm; then
  if has vtsls; then skip "vtsls (TypeScript)"
  else
    npm install -g @vtsls/language-server typescript >/dev/null 2>&1 \
      && ok "vtsls / typescript を導入" || warn "vtsls の導入に失敗"
  fi
  if has vscode-json-language-server; then skip "vscode-langservers-extracted"
  else
    npm install -g vscode-langservers-extracted >/dev/null 2>&1 \
      && ok "vscode-langservers-extracted を導入" || warn "同上の導入に失敗"
  fi
  has mise && mise reshim >/dev/null 2>&1
fi

if has go; then
  if has gopls; then skip "gopls (Go)"
  else
    go install golang.org/x/tools/gopls@latest >/dev/null 2>&1 \
      && { has mise && mise reshim >/dev/null 2>&1; ok "gopls を導入"; } || warn "gopls の導入に失敗"
  fi
else
  skip "gopls（go が無いので飛ばす）"
fi

# Kotlin は Java が要り重いので、既に java がある場合だけ案内する
if has java && ! has kotlin-language-server; then
  warn "Kotlin を使うなら kotlin-language-server の導入が別途必要（docs/ の手順書を参照）"
fi

# -------------------------------------------------------------------
head_ "5. マークダウンのブラウザ表示用"
# -------------------------------------------------------------------
if has npm; then
  if has mmdc && has marked; then
    skip "mermaid-cli / marked"
  else
    PUPPETEER_SKIP_DOWNLOAD=1 npm install -g @mermaid-js/mermaid-cli marked >/dev/null 2>&1 \
      && { has mise && mise reshim >/dev/null 2>&1; ok "mermaid-cli / marked を導入"; } \
      || warn "mermaid-cli / marked の導入に失敗"
  fi

  # ブラウザ描画用のライブラリを、node のバージョンに依存しない場所へ複製する
  mkdir -p "$LIB_DIR"
  NM="$(npm root -g 2>/dev/null)"
  copied=0
  for pair in "mermaid/dist/mermaid.min.js:mermaid.min.js" "marked/lib/marked.umd.js:marked.umd.js"; do
    src="$NM/${pair%%:*}"; dst="$LIB_DIR/${pair##*:}"
    if [ -f "$src" ]; then cp "$src" "$dst"; copied=$((copied+1)); fi
  done
  [ "$copied" = 2 ] && ok "描画ライブラリを $LIB_DIR に複製" \
                    || warn "描画ライブラリの複製に失敗（$copied/2）。Space o が動きません"
fi

# -------------------------------------------------------------------
head_ "6. Chrome のパス設定（mermaid を図にするため）"
# -------------------------------------------------------------------
CHROME=""
for c in google-chrome google-chrome-stable chromium chromium-browser microsoft-edge brave-browser; do
  if has "$c"; then CHROME="$(command -v "$c")"; break; fi
done
if [ -n "$CHROME" ]; then
  cat > "$PUPPETEER_JSON" <<JSON
{
  "executablePath": "$CHROME",
  "args": ["--no-sandbox", "--disable-dev-shm-usage"]
}
JSON
  ok "mermaid-puppeteer.json を生成（$CHROME）"
else
  warn "ブラウザが見つからない。mermaid の画像変換は使えません（HTMLプレビューは動きます）"
fi

# -------------------------------------------------------------------
head_ "7. プラグインとパーサーの導入"
# -------------------------------------------------------------------
if has nvim; then
  # ★ sync ではなく restore を使う。
  #   sync  = 最新に更新する（lazy-lock.json の固定を無視して書き換えてしまう）
  #   restore = lazy-lock.json のコミット通りに入れる
  # 「どのマシンでも同じ版が入る」「勝手に更新されない」という利点は
  # restore を使って初めて成立する。
  nvim --headless "+Lazy! install" +qa >/dev/null 2>&1
  nvim --headless "+Lazy! restore" +qa >/dev/null 2>&1 \
    && ok "プラグインをロック通りに導入" || warn "プラグインの導入に失敗"

  echo "  パーサーを導入中（数分かかります）..."
  nvim --headless -c 'lua
local ok, ts = pcall(require, "nvim-treesitter")
if not ok then vim.cmd("qa!") end
local want = {"bash","c","css","diff","go","html","javascript","json",
  "lua","luadoc","markdown","markdown_inline","python","query","regex",
  "ruby","rust","sql","toml","tsx","typescript","vim","vimdoc","yaml"}
local h = ts.install(want)
if h and h.wait then h:wait(560000) end
vim.cmd("qa!")' >/dev/null 2>&1
  n=$(nvim --headless -c 'lua
local ok, ts = pcall(require, "nvim-treesitter")
io.stderr:write(ok and tostring(#ts.get_installed()) or "0")
vim.cmd("qa!")' 2>&1 | tail -1)
  [ "${n:-0}" -ge 20 ] && ok "パーサー $n 件を導入" || warn "パーサーが $n 件しか入っていない"
fi

# -------------------------------------------------------------------
head_ "8. 動作確認"
# -------------------------------------------------------------------
if has nvim; then
  # LSP の確認は実際のソースファイルで行う（空バッファでは起動しない）
  probe=$(git -C "$NVIM_DIR" ls-files '*.lua' 2>/dev/null | head -1)
  probe="${probe:+$NVIM_DIR/$probe}"
  result=$(nvim --headless ${probe:+"$probe"} -c 'lua vim.wait(2500)' -c 'lua
local n = 0
for l in vim.fn.execute("messages"):gmatch("[^\n]+") do
  if l:match("^E%d+:") then n = n + 1 end
end
io.stderr:write("errors=" .. n .. " lsp=" .. table.concat(vim.g.viewer_lsp_enabled or {}, ","))
vim.cmd("qa!")' 2>&1 | tail -1)
  case "$result" in
    errors=0*) ok "起動エラーなし（${result#errors=0 }）" ;;
    *) warn "起動時にエラーがあります: $result" ;;
  esac
fi

# -------------------------------------------------------------------
head_ "結果"
# -------------------------------------------------------------------
printf '  導入 %d件 / 既存 %d件 / 要確認 %d件\n' "${#DONE[@]}" "${#SKIP[@]}" "${#WARN[@]}"
if [ "${#WARN[@]}" -gt 0 ]; then
  printf '\n  \033[33m要確認:\033[0m\n'
  for w in "${WARN[@]}"; do printf '    - %s\n' "$w"; done
fi
printf '\n  nvim を起動して、上部のメニューバーが出れば完了です。\n'
printf '  使い方は README.md、キー一覧は nvim 内で ? を押してください。\n\n'
