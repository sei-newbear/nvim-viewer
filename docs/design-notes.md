# 設計ノート（なぜそうなっているか）

> **導入手順は README を見てください**（`git clone` → `scripts/bootstrap.sh`）。
> この文書は「なぜそう作ったか」「触ると何が壊れるか」を残すためのものです。
>
> 設定ファイルの中身は**このリポジトリそのもの**なので、ここには載せていません。
> 以前は全文を転記していましたが、リポジトリと二重管理になって食い違い、
> 古い危険な指示（`Lazy! sync`）が残る事故が起きたため、やめました。
>
> 検証環境: Linux / bash / Neovim 0.12.5 / herdr 0.7.4 / mise 管理
> 更新: 2026-08-31

---

## 1. これは何か

herdr（ターミナルマルチプレクサ）の **左ペインにコーディングエージェント、右ペインに閲覧専用 Neovim**
を置き、人間は「差分を読む・コードを追う・文脈をエージェントに渡す」ことに専念する環境。

**Neovim はコードを書くエディタではなく、閲覧専用ビューアーとして設定する。**

### なぜターミナルなのか

エージェント（codex 等）を VSCode の統合ターミナルで動かすと、環境によっては
うまく動かないことがあった。
そこでエージェントはターミナルに置いたまま、**その隣でコードを読める環境**を作る。
つまり目的は「ショートカットを覚えること」ではなく「エージェントの隣にいること」。
そのため**マウスだけでも操作できる**ように作る。

### 完成形の画面

```
 コマンド F1 │ ツリー ␣t │ 差分 ␣dd │ ファイル ⌃p │ 最近 ␣r │ 検索 ␣/ │ ヘルプ ?   ← どこを見るか
 src/features/user-management/application/use-cases/register-user.ts             ← 今どこにいるか
   1 import type { User } from "../../../../types";
   …
 定義 gd │ 戻る ⌃o │ 参照 gr │ 実装 gi │ 型 gy │ 一覧 ␣s │ blame ␣g │ 折り返し ␣w  12:5  ← 何ができるか
```

3本の帯すべてクリックできる。ショートカットを知らなくても操作でき、
ラベルの横にキーが出るので使ううちに覚えられる。

### できること

| 機能 | キー | 概要 |
|---|---|---|
| 差分表示 | `Space dd` | 左右分割。未コミット/ブランチ間/ファイル履歴 |
| 差分から実ファイルへ | `gf` | 同じ行に着地する。最も使う導線 |
| 定義・参照・実装へジャンプ | `gd` `gr` `gi` | 候補1つなら即ジャンプ、複数なら一覧 |
| エージェントへ送信 | `Ctrl+L` | 選択したコードを左ペインへ。Enterは押さない |
| コマンドパレット | `F1` | 全操作を日本語・英語どちらでも検索 |
| ファイル名検索 | `Ctrl+p` | VSCode の Ctrl+P 相当 |
| マークダウン描画 | 自動 | 見出し・表・コードをバッファ内で整形 |
| 整形 ⇄ 生ファイル | `Space m` | スキルファイルの生の中身を見たいとき |
| ブラウザで開く | `Space o` | mermaid を図として描画 |
| 画面の片付け | `Space 0` | 開きすぎた画面を起動直後に戻す |
| 操作早見表 | `?` | herdr のキーも含めた一覧 |

---

## 2. エージェントへの基本制約

- **sudo を使わない。** 必要ならコマンドをユーザーに提示して手動実行を依頼する。
  実績として本構成は**全て sudo なしで導入できた**（mise / npm / go install）。
- **既存環境を壊さない。** `~/.config/nvim` があれば
  `~/.config/nvim.bak.$(date +%s)` にバックアップしてから作業する。
- **herdr 上で作業する場合、閉じる操作は慎重に。** 作成は自由だが、閉じるときは
  作業開始時のスナップショットと突き合わせ、**自分が作ったものだけ**を ID 指定で閉じる。
  ユーザーは並行して別の作業をしている可能性が高い。
- **`pkill -f` を使わない。** パターンが自分自身のコマンドラインにもマッチして自滅する。PID を指定する。

---

## 3. 事前確認

```bash
for c in nvim git rg fd fdfind yazi herdr node go java mise npm; do
  printf '%-8s: ' "$c"; command -v "$c" || echo "NOT FOUND"
done
ls -la ~/.config/nvim 2>/dev/null
mise ls 2>/dev/null
```

| ツール | 用途 | 備考 |
|---|---|---|
| `neovim` **0.11+** | 本体 | 0.11 未満は不可（treesitter の API が違う） |
| `git` | 差分表示の前提 | |
| `ripgrep` / `fd` | 検索バックエンド | |
| `node` / `npm` | 言語サーバ・各種ツール | |
| `herdr` | ペイン管理 | 無い場合 `Ctrl+L` はクリップボードにフォールバック |

**`yazi` は不要**（旧版では入れていたが、ツリーとファイル検索で役割が重複するため外した）。

### 3.1 既に nvim を使っているマシンでは、上書きしないこと

上の `ls -la ~/.config/nvim` に**中身がある場合は、絶対にその上へ入れないこと。**

この設定は閲覧専用ビューアーなので、次のことをする。

| すること | 相手の環境への影響 |
|---|---|
| 通常バッファを `modifiable = false` にする | **編集できなくなる** |
| `BufWriteCmd` で `:w` を握り潰す | **保存できなくなる** |
| `q` を `<Nop>` にする | マクロ記録が使えなくなる |
| `grn` / `gra` / `grx` / `gcc` を削除する | リネーム・コードアクションが消える |
| `lazy` の spec が `lua/plugins/` を**丸ごと** import する | 相手が置いていたプラグイン定義まで読み込み、競合する |

`init.lua` も同名なので上書きされ、相手の設定は失われる。

**`NVIM_APPNAME` を使って並べて入れる。** 設定もプラグインも完全に分かれる。

```sh
git clone <repo> ~/.config/viewer
NVIM_APPNAME=viewer ~/.config/viewer/scripts/bootstrap.sh
```

| | 設定 | プラグイン |
|---|---|---|
| `nvim`（従来どおり） | `~/.config/nvim` | `~/.local/share/nvim` |
| `nvim-viewer`（このビューアー） | `~/.config/viewer` | `~/.local/share/viewer` |

`bootstrap.sh` が `~/.local/bin/nvim-viewer` という起動用ラッパーを作る
（既に同名のファイルがあり、それが自分の作ったものでなければ上書きしない）。
herdr の右ペインではこれを起動する。

**何も入っていないマシンなら**、`~/.config/nvim` にそのまま入れてよい。

---

## 4. 依存のインストール

> **リポジトリの `scripts/bootstrap.sh` が、この節と第8節・第9節を自動化する。**
> 設定ファイルを先に配置してから `~/.config/nvim/scripts/bootstrap.sh` を実行すれば、
> 依存の導入・パーサーの導入・起動確認までを一度に済ませられる。
> 何度実行しても壊れず、入っているものは飛ばし、最後に何をしたかをまとめて出す。
> 以下は**その中身を理解するため**と、手動でやりたい場合のための説明。

### 4.1 Neovim

```bash
mise use -g neovim@latest      # sudo 不要
```

ディストリの apt/dnf 版は古いことが多く、**0.11 未満だと動かない**ので避ける。

### 4.2 tree-sitter CLI（必須）

nvim-treesitter は **`main` ブランチを使う**（理由は第5.1節）。
main ブランチは**パーサーのビルドに `tree-sitter` CLI を要求する**。

```bash
npm install -g tree-sitter-cli
mise reshim 2>/dev/null || true
tree-sitter --version
```

### 4.3 言語サーバ

対象プロジェクトの言語を先に調べる。

```bash
fd -t f -E node_modules -E .git | sed 's/.*\.//' | sort | uniq -c | sort -rn | head
```

| 言語 | インストール | 実行ファイル |
|---|---|---|
| TypeScript / JS | `npm i -g @vtsls/language-server typescript` | `vtsls` |
| JSON/HTML/CSS/ESLint | `npm i -g vscode-langservers-extracted` | `vscode-json-language-server` 他 |
| Go | `go install golang.org/x/tools/gopls@latest` | `gopls` |
| Kotlin | 下記 | `kotlin-language-server` |
| Python | `uv tool install pyright` | `pyright-langserver` |

**npm グローバルの注意**: mise 管理の Node を使っている場合、
グローバルパッケージは mise の Node 配下に入る。
**Node のメジャーバージョンを上げると消える**のでユーザーに伝える。

#### 有効になるのは「候補表に載っているもの」だけ

`lua/plugins/lsp.lua` は**固定の候補表**を持ち、実行ファイルが存在するものだけを
有効にする（38個 ＋ 自前定義の gauge）。**表に無い言語サーバは、そのマシンに入っていても有効にならない。**

```
lua_ls bashls jsonls yamlls taplo marksman dockerls terraformls
vtsls ts_ls denols eslint html cssls tailwindcss svelte helm_ls
gopls rust_analyzer clangd zls jdtls kotlin_language_server hls ocamllsp
metals dartls fsautocomplete sqls sqlls postgres_lsp
gauge（lspconfig に定義が無いので自前定義）
pyright ruff ruby_lsp solargraph intelephense phpactor clojure_lsp
```

足したい場合は候補表に1行足す。**名前は `nvim-lspconfig` の `lsp/<名前>.lua` に
実在していなければならない**（存在しない名前を書いても、エラーにならず静かに無視される）。
確認方法:

```bash
ls ~/.local/share/nvim/lazy/nvim-lspconfig/lsp/ | grep '^<名前>\.lua$'
```

同じ言語に複数のサーバが入っている場合は `skip_if` で優先順位を付ける
（両方有効にすると診断が二重に出る）。現在は
`vtsls` > `ts_ls`、`ruby_lsp` > `solargraph`、`intelephense` > `phpactor`。

起動後に `:LspEnabled` で、実際に有効になったものを確認できる。

#### Kotlin（Java が必要）

```bash
mise use -g java@temurin-21.0.12+101.0.LTS   # mise ls-remote java で選ぶ
mkdir -p ~/.local/share/kotlin-lsp ~/.local/bin
curl -sL -o /tmp/kls.zip \
  https://github.com/fwcd/kotlin-language-server/releases/download/1.3.13/server.zip
unzip -q -o /tmp/kls.zip -d ~/.local/share/kotlin-lsp/
chmod +x ~/.local/share/kotlin-lsp/server/bin/kotlin-language-server

cat > ~/.local/bin/kotlin-language-server <<'SH'
#!/usr/bin/env bash
if [ -z "$JAVA_HOME" ] || [ ! -x "$JAVA_HOME/bin/java" ]; then
  if command -v mise >/dev/null 2>&1; then
    _jh="$(mise where java 2>/dev/null)"
    [ -n "$_jh" ] && [ -x "$_jh/bin/java" ] && export JAVA_HOME="$_jh"
  fi
fi
exec "$HOME/.local/share/kotlin-lsp/server/bin/kotlin-language-server" "$@"
SH
chmod +x ~/.local/bin/kotlin-language-server
```

**JDK のパスを直書きしない**（mise で上げると壊れる）。
Kotlin のファイルタイプ検出は Neovim 0.12 に標準搭載なので追加プラグインは不要。

### 4.4 マークダウンのブラウザ表示用

```bash
PUPPETEER_SKIP_DOWNLOAD=1 npm install -g @mermaid-js/mermaid-cli marked
mise reshim 2>/dev/null || true

# node のバージョンが上がっても壊れない場所へ複製する
NM=$(npm root -g)
mkdir -p ~/.local/share/nvim-md-preview
cp "$NM/mermaid/dist/mermaid.min.js" ~/.local/share/nvim-md-preview/
cp "$NM/marked/lib/marked.umd.js"    ~/.local/share/nvim-md-preview/

# mmdc に既存の Chrome を使わせる（パスは環境に合わせる）
cat > ~/.config/nvim/mermaid-puppeteer.json <<'EOF'
{
  "executablePath": "/usr/bin/google-chrome",
  "args": ["--no-sandbox", "--disable-dev-shm-usage"]
}
EOF
```

複製した2つを `file://` で読むので、**ネットワークに繋がっていなくても動く**。

---

## 5. 落とし穴（設定を書く前に必読）

**ここが本文書の核心。** 実際に踏んだものだけを書いてある。

### 5.1 【最重要】nvim-treesitter は `main` ブランチを使う

Neovim 0.11+ で旧 `master` ブランチを使うと、**マークダウンを開いた瞬間に実行時エラー**になる。

```
treesitter.lua: attempt to call method 'range' (a nil value)
  ...nvim-treesitter/lua/nvim-treesitter/query_predicates.lua:141
```

`main` ブランチで変わること:

- **ハイライトが自動で有効にならない** → FileType で `vim.treesitter.start()` を自分で呼ぶ
- **`tree-sitter` CLI が必要**（第4.2節）
- `jsonc` パーサーが存在しない（`json` が兼ねる）。指定すると警告が出る

### 5.2 【最重要】herdr の中ではターミナル内画像表示が成立しない

**最初にこれを確認すれば、無駄な調査を丸ごと省ける。**

```bash
python3 -c "import fcntl,termios,struct
t=open('/dev/tty'); b=fcntl.ioctl(t.fileno(),termios.TIOCGWINSZ,struct.pack('HHHH',0,0,0,0))
print(struct.unpack('HHHH',b))"   # (rows, cols, xpixel, ypixel)
```

herdr のペインは **`xpixel=0 ypixel=0`** を返す。Kitty graphics は画像の配置と
サイズ計算にピクセル寸法を要するため、**ペイン内のアプリからインライン画像は出せない**。

- `[experimental] kitty_graphics = true` にしても変わらない。この設定は herdr 自身が
  `pane.graphics.set` などの独自API経由で描画するためのもので、透過パススルーではない
- `snacks.image` の `env()` は環境変数から `placeholders = true` を返すが**当てにならない**
  （`TERM_PROGRAM` を見ているだけ）。`:checkhealth snacks` の方が実地の判定を出す
- yazi の画像プレビューが粗く見えるのも同じ理由（chafa にフォールバックしている）

**結論**: 図はブラウザに出す。文章・表・コードはターミナル内で完結させる。

### 5.3 【重要】`xdg-open` でブラウザを開いてはいけない

`xdg-open file.html` は **text/html の関連付け**に従う。
ここがブラウザ以外になっている環境が実在する（検証環境では **Slack** だった）。

```bash
xdg-mime query default text/html        # → slack.desktop だった
xdg-settings get default-web-browser    # → google-chrome.desktop（こちらは正しい）
```

この2つは**別物**。後者は `http://` 用で**ローカルの .html には効かない**。
ブラウザを直接選ぶこと（`$BROWSER` → `.desktop` の `Exec=` を解決 → 既知のブラウザ → 最後に `xdg-open`）。
**どのブラウザで開いたかを通知に出す**と切り分けが早い。

### 5.4 【重要】Diffview の `<leader>c` 系を無効化する

Diffview は差分バッファに**マージ競合の解決キーを8個**割り当てる
（`<leader>co`/`ct`/`cb`/`ca`/`cO`/`cT`/`cB`/`cA`、他に `dx`/`dX`）。

1. **ファイルを書き換える操作**なので閲覧専用の方針に反する
2. `<leader>c`（コマンドパレット）を**プレフィックスとして潰す**

2は気づきにくい。**差分を開いているときだけ**パレットが開かず、
`A ➜ Choose all the versions…` のような競合メニューが出る。

### 5.5 【重要】差分ウィンドウが別ファイルに乗っ取られる

差分を開いた状態でツリーやファイル検索からファイルを選ぶと、
**差分の片側が置き換わって壊れる**。

```
開く前:  diff=true index.ts │ diff=true  index.ts
開いた後: diff=true index.ts │ diff=false greeter.ts   ← 壊れる
```

snacks の `picker/core/main.lua` の `find()` が
「現在タブの、浮動でない、buftype が空のウィンドウ」を候補にするが、
**差分ウィンドウもこの条件を満たす**（`winfixbuf` も見ていない）。

ツリー・ファイル検索・LSPジャンプは**すべて `Snacks.picker.actions.jump` を通る**ので、
そこを1か所包んで開き先を差し替える。`nvim_set_current_win` は他タブの窓を渡せば
タブごと切り替わるので、タブ移動を自前で書く必要はない。

### 5.6 閲覧専用フックを `pattern = "*"` で無条件に適用しない

全バッファを `modifiable=false` にすると **Diffview のパネル、lazy.nvim、
snacks のピッカーなど、プラグインの UI バッファまで壊れる**。
`buftype == ""` に限定し、さらに UI 系 filetype を除外する。

### 5.7 ビジュアルモードで `'<` `'>` は使えない

ビジュアルモード中のマッピングから呼ばれた関数では `'<` `'>` は**まだ更新されておらず、
1つ前の選択範囲**を指す。`getpos("v")`（選択開始）と `getpos(".")`（カーソル）を使う。

### 5.8 herdr の隣接ペイン取得は `neighbor_pane_id`

```json
{"neighbor":{"pane_id":"w3:pC","neighbor_pane_id":"w3:p3"}}
```

`pane_id` は**問い合わせたペイン自身**。実際の隣は `neighbor_pane_id`
（隣が無い場合はこのキーごと存在しない）。

### 5.9 `herdr agent send` はエージェントが居るペインにしか送れない

無い場合は `agent_not_found`。`herdr pane send-text` は任意のペインに送れる。
どちらも **Enter は押さずリテラルのテキストだけ**を置く。
これは仕様上正しく、**ユーザーがコードに質問を書き足してから送信できる**ようにするため。
送信は必ず**リスト形式のコマンド**（`vim.system({...})`）で行う（シェル経由だとクォート地獄になる）。

### 5.10 Diffview は `nvim-web-devicons` が無いと起動時に止まる

`nvim-web-devicons is required to use file icons!` と出て
**「Press ENTER」で停止する**。依存に必ず含める。

### 5.11 treesitter の `auto_install` は切る

ファイルを開くたびにパーサーのダウンロードとコンパイルが走り画面が埋まる。
中断すると `*-tmp` ディレクトリが残り、以後インストールが失敗し続ける。

```bash
find ~/.local/share/nvim -maxdepth 4 -name '*-tmp' -type d -exec rm -rf {} +
```

### 5.12 マークダウンでは折り返しを有効にする

`wrap = false` は差分向けの設定で、マークダウンには不向き。
特にスキルファイル(SKILL.md)の frontmatter は `description` が非常に長い1行になるため、
**折り返さないと画面端で切れて読めない**。

### 5.13 frontmatter は「見えているが目立たない」／ブラウザでは消える

Neovim は装飾を重ねる方式なので frontmatter は消えないが、
render-markdown が `minus_metadata` を区切り線として扱うため**ただの本文に見える**。
一方**ブラウザでは本当に消える**（marked が `---` を `<hr>` にする）。
HTMLを生成する前に frontmatter を切り出して別枠で描くこと。
HTMLコメントも不可視になるので `TreeWalker(NodeFilter.SHOW_COMMENT)` で拾う。

`virt_lines_above` を1行目より上に置く方式は環境によって表示されない。
ラベルは開始行の**行末**（`virt_text_pos = "eol"`）に出す方が確実。

### 5.14 which-key の group は「本当にプレフィックスのキー」にだけ付ける

単独で機能するキーに `group` を宣言すると、**そのキー本来の説明が上書きされる**。

### 5.15 LSP キーマップの二重定義でピッカーが効かなくなる

`LspAttach` でバッファローカルに `gd`/`gr`/`gi` を定義すると、
グローバルに定義したピッカー版より**優先されてしまう**。

### 5.16 動作確認用スクリプトの注意

- `nvim --headless` は `-c` の処理後も**終了しない**。必ず `+qa` か `vim.cmd("qa!")` で終わらせる。
  終了し忘れたプロセスがペインを占有し、以後の操作が全て無反応になる
- Vim の heredoc（`lua << EOF`）は `-c` 引数の中では使えない。Lua は別ファイルにして `-c 'luafile ...'`
- `vtsls` を手で起動する場合 `--stdio` が必須
- `textDocument/references` は `params.context = { includeDeclaration = true }` が無いとエラー
- `pane read --lines N` は**画面の末尾N行**を返す。先頭を見たいときは大きめの N を渡して `head` する

---

## 6. 設計判断（安易に変えないこと）

別マシンで再現する際、以下は**意図的な選択**。

### 6.1 全体方針

1. **`Ctrl+L` で Enter を送らない** — コードと指示がセットで届く方が有用
2. **補完・フォーマット・コード修正を入れない** — 書くのはエージェント側の責務
3. **ツリーからのファイル作成・削除・リネームを無効化** — 閲覧専用の方針と矛盾する
4. **LSP は「実行ファイルが存在するものだけ」自動で有効化** — 未導入サーバでエラーを出さない
5. **ピッカーは候補1件なら即ジャンプ** — `gd` のたびに一覧が挟まる煩わしさを避ける

### 6.2 画面の作り（3本の帯）

分類の軸を決めずにボタンを足すと、「別のものを開く」「今のファイルの見方を変える」
「全体操作」が混ざって、どこに何があるか分からなくなる。**スコープで分ける**。

- **ヘッダー(tabline) = どこを見るか**（移動・グローバル）
- **パンくず(winbar) = 今どこにいるか**（git ルートからの相対パス）
- **フッター(statusline) = 今のファイルに何ができるか**（文脈）

補足:

- ステータスラインは**1行しか持てない**。行を分けたいときは winbar を使う
- **ファイル名は片方だけに出す。** 上下に重複させると15桁ほど無駄になり、
  分割時にボタン2個分を失う。「閲覧のみ」のような常時同じ表示もしない
- フッターは状況で入れ替わるが、**LSPのジャンプ系とマークダウンの表示切替は同時に出ない**
  （マークダウンには LSP が繋がらない）ので混雑しない
- **移動のボタンをトグルにしない。** 「差分」をトグルにすると、差分を見たくて押したのに
  閉じてしまい**「効かない」と映る**（実際にそう報告された）。行き先を表すボタンは
  押したら必ずそこへ行く。閉じるのは別のキーの役目
- **他人の winbar を奪わない。** Diffview は差分に `INDEX`/`WORKING TREE` を出す。
  差分ではそちらが有用なので、設定済みなら上書きしない
- winbar は各ウィンドウごとに評価される。対象ウィンドウは **`g:statusline_winid`** から取る

### 6.3 幅への対応

- ボタンは**優先度をつけて間引く**。「コマンド」は入口なので必ず残す
- **キー併記は幅に余裕があるときだけ。** 併記すると必要な幅が3割増える。
  ボタンを削ってまで出すのは本末転倒
- 表記は `Space t` ではなく **`␣t`**、`Ctrl+p` ではなく **`⌃p`** と1桁に縮める
- **優先度は状況で変える。** 「プレビュー」を固定の最低優先度にすると、
  マークダウンを開いているときに真っ先に消えるという逆の挙動になる
- 幅の見積もりは**実際の描画と一致させる**（区切りを3桁で計算して1桁で描くと、必要以上に落とす）
- **長いパスは先頭側を省略する**（`…/use-cases/register-user.ts`）。
  末尾＝今いる場所が最も重要。バイト単位で切ると多バイト文字が壊れるので
  `strcharpart` と `strdisplaywidth` で1文字ずつ積む

### 6.4 マウスとパレット

- **「プレビュー」という語を使わない。** VSCode は生で開いてプレビューに入るが、
  このビューアーは最初から整形表示なので概念が逆。切り替えボタンは**行き先**
  （`生ファイル` / `整形表示`）をラベルにし、ブラウザで開く操作は `ブラウザ` と呼ぶ
- **パレットは日本語・英語の両方で引けるようにする。** 表示は日本語のまま、
  snacks picker が照合に使う `item.text` に英語キーワードを混ぜる。
  日本語入力への切り替えを強いるとパレットの速さが失われる。
  静的な items では `preview = "none"` と `layout = { preset = "select" }` を指定しないと
  項目の内部データがプレビューに出る
- **ツールバーの判定は「最後に見ていた実ファイル」を基準にする。** ピッカーを開いている間、
  現在バッファは特殊バッファになる。そのまま判定するとボタンが入れ替わり、
  **位置までずれて誤爆する**
- **状態は一箇所で持つ。** 整形/生の状態はキーマップ・ツールバー・パレットの3箇所から
  参照されるので、別々に持つとラベルと実際がずれる
- **「全部閉じる」を用意する。** 片付ける順序が重要で、**差分ビューを最初に閉じる**
  （自前のタブページを持つため）、次にピッカー、浮動ウィンドウ、`tabonly`、`only`。
  **何を閉じたかを通知する**こと。黙って消えると事故なのか分からない

---

## 7. ディレクトリ構成

```text
~/.config/nvim/
├── init.lua
├── README.md                    # ユーザー向けの使い方（強く推奨）
├── md-preview-template.html     # ブラウザプレビューのひな形
├── mermaid-puppeteer.json       # mmdc に既存Chromeを使わせる設定
├── scripts/
│   └── bootstrap.sh             # 依存の導入をまとめて行う
└── lua/
    ├── core/
    │   ├── options.lua          # 閲覧専用設定・折り返し
    │   ├── keymaps.lua          # 基本キーバインド
    │   ├── filetypes.lua        # Helm など標準では判別されないもの
    │   └── parsers.lua          # ハイライト対象の言語一覧（唯一の定義）
    ├── plugins/
    │   ├── diffview.lua         # 差分表示
    │   ├── lsp.lua              # 定義ジャンプ
    │   ├── markdown.lua         # マークダウン描画
    │   ├── snacks.lua           # ツリー・ピッカー・画像
    │   ├── treesitter.lua       # ハイライト（main ブランチ）
    │   └── which-key.lua        # キー候補の表示
    └── custom/
        ├── blame.lua            # Space g の行ごとの由来
        ├── cheatsheet.lua       # `?` の早見表
        ├── frontmatter.lua      # frontmatter を明示
        ├── herdr_link.lua       # Ctrl+L 連携
        ├── md_preview.lua       # ブラウザで開く
        ├── md_view.lua          # 整形 ⇄ 生 の状態管理
        ├── open_guard.lua       # 差分の乗っ取り防止
        ├── palette.lua          # コマンドパレット
        ├── reset.lua            # Space 0 の片付け
        ├── statusline.lua       # フッター
        ├── toolbar.lua          # ヘッダー
        ├── view_opts.lua        # 折り返し・行番号
        └── winbar.lua           # パンくず
```

導入するプラグインは9つ。

| プラグイン | 用途 |
|---|---|
| `folke/lazy.nvim` | パッケージマネージャ |
| `sindrets/diffview.nvim` | 左右分割の差分 |
| `nvim-tree/nvim-web-devicons` | **Diffview に必須**（第5.10節） |
| `nvim-lua/plenary.nvim` | Diffview の依存 |
| `neovim/nvim-lspconfig` | LSP 設定 |
| `folke/snacks.nvim` | ツリー・ピッカー・通知 |
| `nvim-treesitter/nvim-treesitter` | ハイライト（**main ブランチ**） |
| `MeanderingProgrammer/render-markdown.nvim` | マークダウン描画 |
| `folke/which-key.nvim` | キー候補の表示 |

**これらの安全性・出所・監査方法は第11節にまとめてある。**
ユーザーから「情報を抜かれないか」と聞かれたら、そこの実測結果で答える。

## 8. パーサーの導入

設定を書いたら、プラグインとパーサーを入れる。`install()` は非同期なので待つこと。

> **`Lazy! sync` を使ってはいけない。**
> `sync` は `lazy-lock.json` の固定を無視して**最新版に更新し、ロックを書き換える**。
> 「どのマシンでも同じ版が入る」という利点はロック通りに入れて初めて成立する。
> `install`（未導入のものを入れる）→ `restore`（ロックの版に合わせる）の順で行う。

```bash
nvim --headless "+Lazy! install" +qa
nvim --headless "+Lazy! restore" +qa

# 一覧は lua/core/parsers.lua が持つ（ここに書き写すとズレる）
nvim --headless -c 'lua
local ts = require("nvim-treesitter")
local h = ts.install(require("core.parsers"))
if h and h.wait then h:wait(900000) end
print("導入済み " .. #ts.get_installed() .. " 件")
' +qa
```

---

## 9. 検証手順

**ユーザーに渡す前に、エージェント自身がここまで確認する。**

```bash
# 1) 起動エラーが無いこと
nvim --headless <任意のソースファイル> -c 'lua
  local n=0
  for l in vim.fn.execute("messages"):gmatch("[^\n]+") do
    if l:match("^E%d+:") then n=n+1; print(l) end
  end
  print("errors=" .. n)
  print("modifiable=" .. tostring(vim.bo.modifiable))   -- false であること
  print("lsp=" .. table.concat(vim.g.viewer_lsp_enabled or {}, ","))' +qa

# 2) マークダウンでエラーが出ず、折り返しが効くこと
nvim --headless <任意の.md> -c 'lua vim.wait(3000)' -c 'lua
  print("wrap=" .. tostring(vim.wo.wrap))
  print("ts=" .. tostring(vim.treesitter.highlighter.active[0] ~= nil))' +qa

# 3) キーが割り当たっていること
nvim --headless <任意の.md> -c 'lua vim.wait(1500)' -c 'lua
  for _, k in ipairs({"?", "<F1>", "<C-p>", " c", " r", " m", " o", " /", " w", " 0"}) do
    local m = vim.fn.maparg(k, "n", false, true)
    print(string.format("%-6s -> %s", k, (m and m.desc) or "未設定"))
  end' +qa

# 4) 3本の帯が出ること
nvim --headless <任意のソースファイル> -c 'lua vim.wait(4000)' -c 'lua
  local tb, sl = require("custom.toolbar"), require("custom.statusline")
  local function c(s) return (s:gsub("%%#%w+#",""):gsub("%%%d+@[^@]+@",""):gsub("%%X","")) end
  print("上: " .. c(tb.render()))
  print("下: " .. c(sl.render()))' +qa

# 5) 差分が別ファイルで壊れないこと（第5.5節）
#    差分を開いた状態でツリーからファイルを選び、差分タブが残ることを確認する

# 6) ブラウザプレビューが描画されること
google-chrome --headless --disable-gpu --no-sandbox --virtual-time-budget=8000 \
  --dump-dom "file://$(ls -t ~/.cache/nvim/nvim-md-preview-*.html | head -1)" \
  | grep -c '<svg'   # mermaid が図になっていれば 1 以上
```

**`:checkhealth snacks`** も有効。`your terminal does not support the kitty graphics protocol`
と出るのは herdr 環境では**正常**（第5.2節）。

### Ctrl+L の検証（herdr がある場合）

**実エージェントのペインを汚さないこと。** 検証用タブを新規作成し、
「左＝`cat > /tmp/out.txt` を実行中のシェル / 右＝nvim」を作って試す。

```bash
herdr tab create --workspace <ws> --label "verify" --no-focus
herdr pane split <root_pane> --direction right --no-focus
herdr pane run <left>  'cat > /tmp/out.txt'
herdr pane run <right> 'nvim <file> -c "luafile /tmp/probe.lua"'
```

`probe.lua` 側で `vim.notify` を差し替えてログを取り、
`nvim_feedkeys` で `5GVjj<C-l>` を送ると、キーマップ経由の本物の経路を検証できる。
確認したら**自分が作ったタブだけ**を `herdr tab close <tab_id>` で閉じる。

---

## 10. ユーザーに伝えること

### 11.1 キーは2層ある（最重要）

初見のユーザーが最も混乱する点。**最初にこれを説明する。**

- **herdr の層**: 必ず `Ctrl+b` を押して離してから次のキー。`h`=左 / `l`=右 / `z`=全画面
- **Neovim の層**: 合図なしでそのまま効く

herdr が単独で奪うのは `Ctrl+b` と `Ctrl+v` だけで、それ以外は全て Neovim に届く。
差分は幅が要るので、**読むときは `Ctrl+b z` で全画面**にするよう伝える。

### 11.2 覚えなくても使える手段を伝える

| 手段 | 内容 |
|---|---|
| **上下のバーをクリック** | ショートカット不要で操作できる |
| **`F1`** | コマンドパレット。日本語・英語どちらでも検索 |
| **`?`** | 早見表（**herdr のキーも載っている**） |
| `Space` を押して待つ | 続けて押せるキーの候補（which-key） |

### 11.3 よく使う流れ

```
Space dd  差分を開く
  → Tab   ファイルを選ぶ
  → gf    ★ファイル全体を開く（同じ行に着地）
  → gd    定義へ飛ぶ
  → Ctrl+o 戻る
  → V j j Ctrl+L  気になった箇所をエージェントに送る
```

### 11.4 動作確認してもらう項目

1. **閲覧モード** — `i` を押して `modifiable is off` が出ること
2. **差分表示** — `Space dd` で左右に差分。`Tab` でファイル切り替え
3. **コードジャンプ** — `gd` `gr` `gi`。`Ctrl+o` で戻れること
4. **ファイルツリー** — `Space t`
5. **Ctrl+L 送信** — `V` で数行選択して `Ctrl+L`。左ペインに届き、
   **Enter は押されていない**ので質問を書き足せること
6. **マークダウン** — `Space m` で生⇄整形、`Space o` でブラウザ（mermaid が図になる）
7. **片付け** — 散らかしてから `Space 0`

### 11.5 必ず伝えるべきこと

**設定を変えた後は nvim の再起動が必要。**
動いているインスタンスは古い設定のままなので、「キーが効かない」の原因の大半がこれ。

### 11.6 困ったときの案内

| 症状 | 説明 |
|---|---|
| キーが分からない | `?` で早見表。`F1` でパレット |
| `modifiable is off` | 正常。閲覧専用なので書き換えられない |
| `recording @x` | `q` の誤爆。`q` をもう一度押せば止まる（無効化済み） |
| 画面が散らかった | `Space 0` |
| 送信先が分からない | `:HerdrTarget` |
| `gd` が効かない | `:LspEnabled` で言語サーバを確認 |
| 図が出ない | `Space o` でブラウザへ（ターミナル内には原理的に出せない。第5.2節） |

### 11.7 デモ用リポジトリを作ると理解が早い

以下を含む小さな git リポジトリを作って渡すと、一通り試せる。

- 差分の4種類（新規・変更・削除・ステージ済み）
- インターフェース＋複数の実装クラス（`gi` の練習）
- 複数コミットを持つファイル（`Space dh` の練習）
- mermaid を含むマークダウン（`Space o` の練習）
- 深い階層と長いファイル名（表示の確認）

**注意**: ステージ済みの変更を作った後に `git commit` を打つと巻き込んで消える。
`git commit --only <path>` を使う。

---

## 11. プラグインの安全性について

**この節はユーザーに聞かれたときに答えられるようにしておくためのもの。**
「情報を抜かれないか」は正当な懸念であり、曖昧に安心させるのではなく事実で答える。

### 12.1 仕組みの前提

Neovim のプラグインは **Lua のコードがユーザー権限でそのまま動く**だけで、
**サンドボックスも権限システムも無い**。`~/.ssh` も `.env` も読めるし、シェルも叩ける。

| | VSCode | Neovim |
|---|---|---|
| サンドボックス | **なし** | **なし** |
| 権限システム | なし | なし |
| 配布元の審査 | マーケットプレイスの審査がある | 無い（GitHub から直接取得） |
| 中身の可読性 | VSIX にまとめて配布 | **平文の Lua** |
| 更新 | 自動更新が既定 | **コミット固定・手動のみ** |

**「抜かれる可能性」自体は VSCode と同じくある。** 悪意あるコードを止める仕組みは
どちらにも無い。違いは、Neovim には審査が無い代わりに
**中身が読めて、更新が勝手に起きない**点。

### 12.2 この構成のプラグインの出所

| プラグイン | 出所 | 位置づけ |
|---|---|---|
| `nvim-lspconfig` | **`neovim/`** | **Neovim 公式組織** |
| `nvim-treesitter` | `nvim-treesitter/` | Neovim コアと連動する準公式 |
| `plenary.nvim` | `nvim-lua/` | コミュニティ公式組織の基盤ライブラリ |
| `nvim-web-devicons` | `nvim-tree/` | 事実上の標準 |
| `lazy.nvim` / `snacks.nvim` / `which-key.nvim` | folke | 広く使われている |
| `diffview.nvim` | sindrets | 差分表示の定番 |
| `render-markdown.nvim` | MeanderingProgrammer | マークダウンの整形表示 |

ライセンスは全て MIT または Apache 2.0。素性不明のものは無い。

**注意点**:

- **`snacks.nvim` はこの構成で最も機能的に依存している**。ピッカー・ツリー・
  通知・画像と守備範囲が広い。監査するなら見る量が多い、という意味で挙げておく

### 12.3 実測（この構成で測った結果）

ネットワークに出る処理を持つのは **9個中2個だけ**だった。

| プラグイン | 該当箇所 | 用途 |
|---|---|---|
| `lazy.nvim` | `lua/lazy/build.lua` | プラグインの取得（git）。本来の仕事 |
| `snacks.nvim` | `lua/snacks/picker/source/icons.lua` | アイコン一覧の取得。**そのピッカーを開いたときだけ** |

`nvim-lspconfig` に URL が861件見つかるが、**ほぼ全部が説明文**
（各言語サーバの GitHub リンク）。実際に通信するコードは `lsp/gitlab_duo.lua` の1箇所のみで、
これは有効化していない言語サーバの設定なので動かない。

`nvim-treesitter` の URL も同様で、実際の取得は `install()` を明示的に呼んだときだけ。

`snacks` が呼ぶ外部コマンドの内訳も妥当だった。

```
git 42 / lazygit 7 / gh 6 / fd 6 / rg 5 / magick 3 / curl 3 / mmdc 2
```

### 12.4 同じ監査を再実行する手順

**別マシンでも必ずこれを回して、結果を自分の目で確認すること。**
以下は静的な走査なので、ネットワークに繋がなくても実行できる。

```bash
cd ~/.local/share/nvim/lazy

# 1) 出所・ライセンス・更新の鮮度
for d in */; do d=${d%/}
  url=$(git -C "$d" remote get-url origin 2>/dev/null | sed 's|https://github.com/||; s|\.git$||')
  last=$(git -C "$d" log -1 --format=%cr 2>/dev/null)
  printf '%-24s %-40s 最終: %s\n' "$d" "$url" "$last"
done

# 2) 外部コマンド実行・通信の件数
printf '%-24s %8s %8s %8s\n' "プラグイン" "shell実行" "URL出現" "ファイル書込"
for d in */; do d=${d%/}
  sh=$(grep -rhoE 'vim\.fn\.system|vim\.system|io\.popen|os\.execute|jobstart' "$d/lua" 2>/dev/null | wc -l)
  http=$(grep -rhoE 'https?://[a-z]' "$d/lua" 2>/dev/null | wc -l)
  wr=$(grep -rhoE 'io\.open\([^)]*"w|writefile|uv\.fs_write' "$d/lua" 2>/dev/null | wc -l)
  printf '%-24s %8s %8s %8s\n' "$d" "$sh" "$http" "$wr"
done

# 3) 「本当に通信する」ファイルだけを抽出（説明文のURLを除外できる）
for d in */; do d=${d%/}
  f=$(grep -rlE 'vim\.fn\.system\(\{?\s*["'"'"']?(curl|wget|git)|jobstart\(\{?\s*["'"'"']?(curl|wget|git)' "$d/lua" 2>/dev/null)
  [ -n "$f" ] && { echo "$d:"; echo "$f" | sed 's/^/  /'; }
done

# 4) コミット固定の確認（勝手に更新されないこと）
python3 -c "
import json; d = json.load(open('$HOME/.config/nvim/lazy-lock.json'))
for k, v in sorted(d.items()): print(f'{k:26} {v.get(\"commit\",\"\")[:12]}')"
```

**件数の多さで判断しないこと。** URL の大半は説明文なので、
3番目の「本当に通信するファイル」まで見ないと意味がない。

### 12.5 現実的なリスクと守り方

| リスク | 内容 | 対処 |
|---|---|---|
| **更新時** | 今のコードは読めるが、`:Lazy update` で別のコードになる。上流が乗っ取られればそれが入る | 惰性で更新しない。`:Lazy log` で変更を見る習慣 |
| **treesitter のパーサー** | C のソースを GitHub から取得し、ローカルでビルドしている。Lua より監査しにくい | 必要な言語だけ入れる |
| **`snacks.nvim` の依存度** | 機能が多く、外部コマンド呼び出しの箇所も多い | 監査するときは見る量が多いことを踏まえる |
| **npm/go で入れたツール** | `mermaid-cli` は Chrome を起動し、`vtsls` はプロジェクトの全ファイルを読む | プラグインだけ気にしても片手落ち、と理解しておく |
| **秘密情報** | LSP はプロジェクト内の全ファイルを読む | 認証情報をリポジトリに置かない（ツール以前の話） |

**この構成で自動更新は有効にしていない**（`checker = { enabled = false }`）。
`lazy-lock.json` でコミットが固定されているので、明示的に更新するまで中身は変わらない。

### 12.6 ユーザーに伝えるときの要点

- 「安全です」と言い切らない。**サンドボックスは無く、原理的には抜ける**のが事実
- そのうえで「**素性の分かるものだけを入れ、勝手な更新は起きない状態にしてある**」と伝える
- **12.4 の監査は自分でも回せる**ことを伝える。信じてもらうのではなく確認してもらう
- なお `lua/custom/` に置いた自作コード（約2000行）は外部と通信しない。
  日本語コメント付きで全文が手順書にあるので、そこは読んで確認できる
