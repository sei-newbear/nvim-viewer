# ターミナル専用 高度コードビューアー (Read-Only Neovim)

herdr の左ペインにエージェント、右ペインにこのビューアーを置いて使う構成。

## 新しいマシンで使う

```bash
# SSH 鍵を GitHub に登録している場合
git clone git@github.com:sei-newbear/nvim-viewer.git ~/.config/nvim-viewer
# していない場合
git clone https://github.com/sei-newbear/nvim-viewer.git ~/.config/nvim-viewer

NVIM_APPNAME=nvim-viewer ~/.config/nvim-viewer/scripts/bootstrap.sh
nvim-viewer
```

**既に nvim を使っているかどうかに関係なく、この手順ひとつでよい。**
`~/.config/nvim` には触れないので、既存の設定があっても壊れないし、
無い場合もそこを空けたままにする（後から普通の nvim を使いたくなったときのため）。

| | 設定 | プラグイン | 起動 |
|---|---|---|---|
| このビューアー | `~/.config/nvim-viewer` | `~/.local/share/nvim-viewer` | `nvim-viewer` |
| 普通の nvim | `~/.config/nvim` | `~/.local/share/nvim` | `nvim` |

### なぜ ~/.config/nvim に入れないのか

**この設定は閲覧専用ビューアーで、そのままでは編集ができない。**

| すること | 影響 |
|---|---|
| 通常バッファを `modifiable = false` にする | 編集できなくなる |
| `:w` を握り潰す | 保存できなくなる |
| `q` を `<Nop>` にする | マクロ記録が使えなくなる |
| `grn` / `gra` / `grx` / `gcc` を削除する | リネーム・コードアクションが消える |
| `lazy` が `lua/plugins/` を丸ごと import する | 同居する他のプラグイン定義まで読み込んで競合する |

`~/.config/nvim` に入れると、そのマシンの nvim が編集に使えなくなる。
**編集は左ペインのエージェントに任せる**のがこの道具の前提だが、
それを nvim 全体に強制する必要はない。

起動は `bootstrap.sh` が用意する `~/.local/bin/nvim-viewer` から行う
（中身は `exec env NVIM_APPNAME="nvim-viewer" nvim "$@"` の1行）。
`~/.local/bin` が PATH に無ければ警告が出る。

---

`bootstrap.sh` は **sudo を使わず**依存を導入し、パーサーを入れ、最後に動作確認まで走らせる。
何度実行しても壊れず、既に入っているものは飛ばす。
`~/.config/nvim` を symlink にして実体を別の場所に置く構成にも対応している。

### bootstrap.sh が変更するもの

**このスクリプトはグローバルな環境に手を入れる。** 実行前に把握しておくこと。

| 対象 | 何をするか | 条件 |
|---|---|---|
| **mise のグローバル設定** | `mise use -g neovim@latest`。**そのマシン全体の Neovim が変わる** | Neovim が無い、または 0.11 未満のときだけ |
| npm グローバル | `tree-sitter-cli` / `@vtsls/language-server` / `typescript` / `vscode-langservers-extracted` / `@mermaid-js/mermaid-cli` / `marked` を導入 | それぞれ未導入のときだけ |
| `$GOBIN` | `go install gopls@latest` | go があり gopls が無いときだけ |
| `~/.local/share/nvim-md-preview/` | `marked.umd.js` と `mermaid.min.js` を複製 | 常に |
| `~/.local/bin/nvim-<名前>` | 起動用ラッパーを作成 | `NVIM_APPNAME` を使ったときだけ。**既存の別ファイルは上書きしない** |
| リポジトリ直下 | `mermaid-puppeteer.json` を生成（git 管理外） | ブラウザが見つかったとき |

**0.9 系など古い Neovim で安定させているマシンでは、`mise use -g` に注意。**
本業の Neovim まで変わる。避けたい場合は先に 0.11 以上を用意しておけば、この処理は走らない。

### このリポジトリについて

- `lua/` — 設定と自作モジュール
- `scripts/bootstrap.sh` — 新しいマシンの初期化
- `docs/design-notes.md` — **なぜそう作ったか / 触ると何が壊れるか。**
  設定を変える前に読む。設定ファイルの中身は載せていない（このリポジトリが正）
- `docs/todo.md` — 残っている作業
- `LICENSE` — MIT
- `lazy-lock.json` — **コミットに含める。** プラグインの版を固定し、
  どのマシンでも同じ状態になる。勝手な更新も起きない
- `mermaid-puppeteer.json` — **管理しない。** Chrome の場所が環境で違うため
  `bootstrap.sh` が生成する

設定を変えたらコミットする。他のマシンには `git pull` で反映できる。

## 起動

```bash
nvim-viewer <ファイル or ディレクトリ>
```

## キー操作

| キー | 動作 |
|---|---|
| **上部バーをクリック** | **メニューバーの項目を実行（ショートカット不要）** |
| **下部バーをクリック** | **ジャンプ系を実行（LSPが使えるときだけ表示）** |
| **`F1`** / `Space c` | **コマンドパレット（全操作を日本語で検索）** |
| **`?`** | **キー操作早見表を開く（herdr のキーも載っている）** |
| `Space` を押して待つ | 続けて押せるキーの候補が出る（which-key） |
| `Space ?` | 全キーマップを検索する |
| `Ctrl+L` (ビジュアル) | **選択したコードを左ペインのエージェントへ送信** |
| `Ctrl+L` (ノーマル) | 現在行を左ペインのエージェントへ送信 |
| `gd` | 定義へジャンプ |
| `gr` | **参照一覧**（どこから使われているか） |
| `gi` | **実装へジャンプ**（インターフェースの実装先） |
| `gy` / `gD` | 型定義 / 宣言へジャンプ |
| `K` | ホバー（型・ドキュメント表示） |
| `Ctrl+o` | ジャンプ元へ戻る |
| `Space s` | このファイルの関数・型を一覧 |
| `Space S` | プロジェクト全体から名前で探す |
| `Space t` | **ファイルツリーの表示切替** |
| `Space dd` | 差分を開く（作業ツリー） |
| `Space dm` | 差分を開く（vs origin/main） |
| `Space dh` | このファイルの変更履歴 |
| `Space dc` | 差分を閉じる |
| `Tab` / `Shift+Tab` | 差分内で次/前のファイル |
| `gf` | 差分から実ファイルを開く（同じ行に着地） |
| `]c` / `[c` | 次/前の差分ハンク |
| `Ctrl+p` | **ファイル名で探す（VSCode の Ctrl+P 相当）** |
| `Space r` | **最近開いたファイル** |
| `Space b` | 開いているバッファ |
| `Space /` | ファイルの中身を全文検索 |
| `Space *` | カーソル下の語をプロジェクト全体から検索 |
| **`gf`** | **差分から実ファイルを開く（同じ行に着地）** |
| **`Space w`** | **折り返しの切替（差分では左右同時）** |
| **`Space g`** | **ブレイムモード（行ごとの由来）** |
| **`Space 0`** | **全部閉じて最初の状態に戻す** |
| `Space o` | **マークダウンをブラウザで開く（mermaid を図で描画）** |
| `Space m` | **整形表示 ⇄ 生ファイル** を切り替え |
| `Space y` | 現在位置 `path:line` をコピー |
| `Space q` / `Space Q` | ウィンドウを閉じる / Neovim終了 |

## 散らかったら `Space 0`

差分タブ・ツリー・ポップアップ・分割が積み重なって何がどこにあるか分からなくなったら、
`Space 0`（またはコマンドパレットで `reset`）で**起動直後の状態に戻る**。

閉じるもの: 差分ビュー / ピッカー・ツリー / 浮動ウィンドウ / 余分なタブ / 分割 / 他のバッファ

何を片付けたかは通知に出る（黙って消えると不安なため）。

```
片付けました（差分1 / 一覧1 / 分割2 / ファイル4）→ index.ts
```

**開いたファイルは残したい**場合は `:Reset!`（`!` 付き）。画面だけ片付けてバッファは保つ。

## よく使う流れ：差分 → ファイル全体 → 定義へ

```
Space dd  差分を開く
  → Tab   ファイルを選ぶ
  → gf    ★ファイル全体を開く（同じ行に着地）
  → gd    定義へ飛ぶ
  → Ctrl+o 戻る
```

差分表示は変更箇所しか見えないので、前後の文脈を読むには `gf` で実ファイルを開く。
**差分を見ている間はメニューバーに「ファイルを開く」ボタンが出る**ので、キーを忘れても押せる。

横長で読みにくいときは `Space w` で折り返しを切り替える。差分では左右の窓に同時に効く。

## 行の由来を追う（ブレイム）

`Space g` でブレイムモードに入ると、**行ごとに「なぜ変わったか」**が出る。

```
import type { Language } from "./types";        newbear 3日前 • 初期実装: 型・あいさつ
  en: (name) => `Hello, ${name}!`,              newbear 11時間前 • fix: 英語のあいさつに感嘆符
  ko: (name) => `안녕하세요, ${name}님`,        newbear 11時間前 • feat: 韓国語に対応する
```

その行で **`Enter`（またはダブルクリック）**を押すと、**そのコミットの差分**が開く。
「なぜこうなっているか」をコミットメッセージと変更内容で追える。

**差分は「今見ているファイルだけ」に絞られる。** そのコミットが他のファイルも
触っていても出さない。知りたいのは「この行がなぜこうなったか」だから。

**`q` で戻る。** 元のファイルの元の行に戻り、ブレイムモードも継続する。
違う内容だったときにすぐ抜けられるようにしてある（`Space dc` でも同じ）。

```
Space g → 行を選ぶ → Enter → 差分を見る → q → 元の位置に戻る
                              ↕
                        [h / ]h で前後の変更へ
```

**`[h` / `]h` で、差分を開いたまま前後のコミットへ移動できる。**
「これじゃない」となったときに、いちいち戻らずそのまま遡れる。
対象はそのファイルを触ったコミットだけで、端まで来ると止まる。

**フッターにクリックできるナビが出る**ので、キーを知らなくても操作できる。

```
◀ 前の変更 [h │ 4/5 │ 次の変更 ▶ ]h │ 閉じる q │ ファイルを開く gf │ 定義 gd
```

`4/5` は「5件のうち4番目のコミット」。差分を閉じるとこの行は通常表示に戻る。

**左のファイル一覧は出さない。** 1ファイルしか見ていないので場所の無駄で、
隠すと差分が全幅に広がって読みやすくなる。

### 表示の考え方

**同じコミットが続く行は省略し、切り替わった行だけ**に注釈を出す。
全行に出すと同じ文字列が延々と並び、狭いペインでは**変わり目が埋もれる**。
blame で知りたいのは「どこで変わったか」なので、切り替わりだけを見せる方が実用的。
全行に出したいときは `:BlameDensity`。

**幅が足りないときは「誰が・いつ」を捨ててコミットメッセージを残す。**
知りたいのは「なぜ」なので、そこを最後まで守る。

```
幅がある  newbear 3日前 • 初期実装: 型・あいさつ・利用…
幅が狭い  fix: 英語のあいさつ…
```

注釈が出ない行は、コードが長くて余白が10桁未満のとき。`Ctrl+b z` で全画面にすると出る。

## 変更履歴をたどる

`Space dh` でそのファイルの履歴、`Space dH` でリポジトリ全体の履歴。
左に並んだコミットを `j`/`k` で選び `Enter` を押すと、そのコミットの差分が右に出る。

## エージェントへコードを送る

### 送るのは「参照」であってコードではない

エージェントはファイルを読めるので、`File` と `Lines` があれば足りる。
コードまで貼ると入力欄が埋まり、**質問を書く場所が無くなる**。

```
V で 19-20行を選択:
  【参照コード】
  File: nvim-viewer-demo/src/types.ts
  Lines: 19-20

v で Message を選択:
  【参照コード】
  File: nvim-viewer-demo/src/types.ts
  Lines: 19
  選択: Message          ← 行参照では「行のどの部分か」を表現できないため
```

**選択モードで送る内容が変わる。** `V`（行）は参照だけ、`v`（文字）と
`Ctrl+V`（矩形）は選んだ文字を添える。意味と一致している。

**Enter は押さない**ので、質問を書き足してから送れる。

### パスは「相手の作業ディレクトリ」基準

git ルート相対にすると、エージェントが別のディレクトリに居るときに
**そのままでは開けないパス**を渡してしまう。herdr から送信先の `cwd` を取り、
その配下なら相対、外なら絶対パスにする。

### 状況で情報が増える

| 見ているもの | 追加される行 |
|---|---|
| コミットの差分 | `Commit: 7ef7777` ＋ `Side: 変更前` |
| 作業ツリーの差分 | `Side: 変更後（作業ツリー）` |
| ブレイムモード中 | `Commit: 7ef7777`（その行を入れたコミット） |

差分では**左右どちら側を見ているか**が重要。変更前側の行番号は現在の
ファイルとずれるので、`Side` が無いとエージェントが違う場所を読む。

コミットメッセージは送らない。ハッシュがあれば `git show` で辿れる。

### 送信先は4段階で探す

`:HerdrTarget` で確認できる。

1. 環境変数 `HERDR_AGENT_TARGET`
2. 左隣のペイン
3. 同じタブ内のエージェント
4. **クリップボード**（herdr の外でも壊れない）

## ショートカットを覚えたくない場合

キーを一切覚えなくても操作できるようにしてある。

### 3本の帯の役割

```
 コマンド F1 │ ツリー ␣t │ 差分 ␣dd │ ファイル ⌃p │ 最近 ␣r │ 検索 ␣/ │ ヘルプ ?   ← どこを見るか
 …/application/use-cases/register-user-with-email-verification.ts                ← 今どこにいるか
   1 import type { User } from "../../../../types";
   …
 定義 gd │ 戻る ⌃o │ 参照 gr │ 実装 gi │ 型 gy │ 一覧 ␣s │ 折り返し ␣w      12:5  ← 何ができるか
```

| | 役割 | 中身 |
|---|---|---|
| ヘッダー | どこを見るか（移動・グローバル） | コマンド / ツリー / 差分 / ファイル / 最近 / 検索 / ヘルプ |
| パンくず | 今どこにいるか | git ルートからの相対パス |
| フッター | 今のファイルに何ができるか | 定義・参照・実装・型・一覧・戻る / 生ファイル⇄整形・ブラウザ / ファイルを開く / 折り返し / 行:桁 |

**パス専用の行を設けたことで、フッターからファイル名を外せた。**
幅の奪い合いが無くなり、狭いペインでもジャンプ項目が削られない。

| 幅84での項目数 | ファイル名あり | パンくずに分離 |
|---|---|---|
| フッターのジャンプ | 4個 | **7個** |

全8項目（定義・戻る・参照・実装・型・一覧・blame・折り返し）が並ぶのは幅88以上。
幅84では優先度のいちばん低い「折り返し」だけが落ちる。

パスは長いと**先頭から** `…/` で省略される。末尾＝今いる場所が最も重要で、
`…/` があれば上位階層の存在も分かるため。

### 差分は別ファイルで壊れない

差分を開いた状態でツリーやファイル検索からファイルを選ぶと、**差分の片側が
そのファイルに置き換わって壊れる**（snacks は差分ウィンドウも開き先の候補にするため）。

そうならないよう、`lua/custom/open_guard.lua` が
`Snacks.picker.actions.jump` を包んで開き先を差し替える。

```
ツリーから greeter.ts を選ぶと…
  タブ1: greeter.ts  ← ここに開いて切り替わる
  タブ2: [差分]index.ts │ [差分]index.ts   ← 差分はそのまま残る
```

差分に戻るときは `Space dd`。ツリー・ファイル検索・LSPジャンプはすべて
同じ経路を通るので、この1か所で全部に効く。

差分表示中は **Diffview 自身の winbar（`INDEX` / `WORKING TREE`）が優先**される。
どちら側を見ているかの方が重要なので、上書きしない作りにしてある。

不要なら `:WinbarToggle` / `:ToolbarToggle` / `:StatuslineToggle` で個別に消せる
（コマンドパレットからも切り替えられる）。

**フッターは開いているファイルで中身が変わる。**

```
TypeScript    定義 gd │ 戻る ⌃o │ 参照 gr │ 実装 gi │ 型 gy │ 一覧 ␣s │ 折り返し ␣w
マークダウン  生ファイル ␣m │ ブラウザ ␣o │ blame ␣g │ 折り返し ␣w
差分表示中    ファイルを開く gf │ 定義 gd │ 戻る ⌃o │ 参照 gr │ 実装 gi │ 型 gy │ 一覧 ␣s
```

LSP のジャンプ系とマークダウンの表示切替は、**同じファイルで同時に出ない**
（マークダウンには LSP が繋がらない）ので混雑しない。

「閲覧のみ」の表示はしない — ビューアーである以上、常時出す情報ではない。

**上部のメニューバー** — 常に表示されていて、左クリックで実行できる。

```
 コマンド F1 │ ツリー ␣t │ 差分 ␣dd │ ファイル ⌃p │ 最近 ␣r │ 検索 ␣/ │ ヘルプ ?
```

ペインが狭いと優先度の低い項目から自動で消えるが、**「コマンド」は必ず残る**ので
操作の入口を失わない。`:ToolbarToggle` で表示を消せる。

**ボタンは「行き先」であってトグルではない。** 「差分」を押すと、
既に開いていればその**タブへ移動する**（閉じない）。
トグルにすると、差分を見たくて押したのに閉じてしまい「効かない」と見える。
閉じるのは `Space dc` / `Space 0` の役目。
（サイドバーである「ツリー」だけは慣例どおり開閉のトグル）

**幅に余裕があるとキーも併記される。**

```
幅82以上  コマンド F1 │ ツリー ␣t │ 差分 ␣dd │ ファイル ⌃p │ 最近 ␣r │ 検索 ␣/ │ ヘルプ ?
幅61      コマンド │ ツリー │ 差分 │ ファイル │ 最近 │ 検索 │ ヘルプ
```

ボタン7個が全部並ぶのは幅61以上、キーも併記されるのは幅82以上。
**ボタンを削ってまでキーは出さない**（優先順位は「ボタン ＞ キー」）。
`Ctrl+b z` で全画面にすればキーが出る。`␣` は Space、`⌃` は Ctrl。

**下部のジャンプメニュー** — LSP が繋がっているファイルでは、フッターにこう出る。

```
 定義 gd │ 戻る ⌃o │ 参照 gr │ 実装 gi │ 型 gy │ 一覧 ␣s │ blame ␣g │ 折り返し ␣w   12:5
```

クリックで実行できて、**キーも横に出るので使ううちに覚えられる**。
コードを辿る操作はこのビューアーの中心機能なのに、キーを知らないと存在に気づけないため、
常に見えるフッターに置いてある。LSP が無いファイル（マークダウン等）では出ない。
`:StatuslineToggle` で消せる。

**コマンドパレット** — `F1` または「コマンド」ボタン。全操作が日本語で並び、
絞り込み入力で探せる。右端にショートカットも出るので、使ううちに自然に覚えられる。

**日本語・英語のどちらでも検索できる。** 表示は日本語のまま、照合用の文字列に英語キーワードを
混ぜてあるので、`diff` `definition` `history` `wrap` などでも引ける。
日本語入力に切り替える手間を省くため。

項目を足したいときは `lua/custom/palette.lua` の `actions()` に1行加える。
メニューバーの項目は `lua/custom/toolbar.lua` の `BUTTONS`。

### マウスでできること・できないこと

| 操作 | 可否 |
|---|---|
| 左クリック（カーソル移動、ツリーやメニューの選択） | できる |
| ホイールでスクロール | できる |
| ウィンドウ境界のドラッグでサイズ変更 | できる |
| **ドラッグでのテキスト選択** | **herdr が横取りする**（下記） |
| **右クリックメニュー** | **herdr のペインメニューが出る**（下記） |

herdr は既定で、ドラッグ選択（`copy_on_select`）と右クリック（ペインメニュー）を
自分で処理する。nvim 側に渡したい場合は `~/.config/herdr/config.toml` に:

```toml
[ui]
copy_on_select = false                    # ドラッグ選択を nvim に渡す
right_click_passthrough_modifier = "ctrl" # Ctrl+右クリックを nvim に渡す
```

変更後は `herdr server reload-config` と、**クライアント側の再読込（`Ctrl+b` → `Shift+R`）**が必要。
ただし herdr 側の選択コピーも便利なので、無理に変える必要はない。
コードをエージェントに送るだけなら、クリックで位置を決めて `V` と `j` で範囲を広げ、
`Ctrl+L` を押す方が速い。

## キーが思い出せないとき

3つの調べ方がある。

1. **`?`** — 早見表を開く。**herdr のキー（`Ctrl+b` 系）も載っている**ので、まずこれ。
   `j`/`k` でスクロール、`q` で閉じる。`:Cheatsheet` でも開く
2. **`Space` を押して少し待つ** — 続けて押せるキーの候補が出る（which-key）。`g` でも出る
3. **`Space ?`** — 全キーマップを絞り込み検索する

`?` は本来「後方検索」だが、ビューアーではヘルプの方が有用なので置き換えてある。
後方に検索したいときは `/単語` を打ってから `N` で遡る。

早見表の内容は `lua/custom/cheatsheet.lua` の `SECTIONS` を編集すれば変えられる。

## 確認用コマンド

- `:HerdrTarget` … Ctrl+L の送信先がどこに解決されるか表示
- `:LspEnabled` … 有効になっている言語サーバを表示
- `:checkhealth` … 全体の健全性チェック

## Ctrl+L の送信先の決まり方

1. 環境変数 `HERDR_AGENT_TARGET`（または `vim.g.herdr_agent_target`）があればそれ
2. `HERDR_PANE_ID` から見た **左隣のペイン**
3. 左隣が無ければ、同じタブ内のエージェント
4. どれも無ければ**クリップボードにコピー**（herdr の外で使っても壊れない）

送信先にエージェントが居れば `herdr agent send`、居なければ `herdr pane send-text` を使う。
どちらも **Enter は押さない**ので、貼り付いた後に質問を書き足してから送信できる。

## ファイルツリーと差分パネルの使い分け

`Space t` で左側にファイルツリー（snacks explorer）が出る。開いているファイルの位置まで
自動で展開され、git の変更やエラーのあるファイルには印が付く。もう一度 `Space t` で閉じる。

差分表示（`Space dd`）は**別のタブページ**で開くので、ツリーとは共存する。
差分側の左パネルは `Space e` で開閉、差分自体は `Space dc` で閉じてツリー側に戻る。

ツリー内のキー:

| キー | 動作 |
|---|---|
| `l` / `Enter` | 開く（ディレクトリなら展開） |
| `h` | ディレクトリを閉じる |
| `H` / `I` | 隠しファイル / gitignore対象の表示切替 |
| `]g` / `[g` | 次 / 前の変更ファイルへ |
| `q` | ツリーを閉じる |

**注意**: ツリーからのファイル作成・削除・リネーム・移動・コピー（`a` `d` `r` `m` `c` `p`）は
閲覧専用の方針に合わせて**無効化してある**。これらの操作は左ペインのエージェントに依頼する。
戻したい場合は `lua/plugins/snacks.lua` の該当行を消す。

## コードジャンプについて

`gd` `gr` `gi` などは snacks のピッカー経由。**候補が1つなら即ジャンプ、複数あるときだけ一覧**が出る。
一覧では絞り込み入力ができ、`Enter` で決定、`Esc` で取り消し。
どのジャンプも `Ctrl+o` で元の位置に戻れる。

## マークダウンと mermaid

**文章・見出し・表・コードブロックは、ターミナル内でそのまま整形描画される**（render-markdown.nvim）。
表は罫線で組まれ、桁も揃う。生のテキストを見たいときは `Space m` で切り替える。

**mermaid の図だけはブラウザに出す。** `Space o` を押すと、開いているバッファを
整形HTMLにしてブラウザで開く。図・表・本文がまとめて見られる。

- 未保存の変更も含めて、**今バッファに見えている内容**が出る
- 同じファイルは同じ出力先に書くので、タブが無限に増えない
- ライブラリ（marked / mermaid）は `~/.local/share/nvim-md-preview/` に複製済みなので
  **ネットワークに繋がっていなくても動く**
- ページのテーマ（明暗）は OS 設定に追従し、図の配色もそれに合わせる

### 「プレビュー」という言葉を使わない理由

VSCode は「.md を生で開く → プレビューを開く」なので、プレビュー＝わざわざ入るモード。
一方このビューアーは**最初から整形表示**なので、概念が逆になる。

| | 既定の状態 | 操作で行く先 |
|---|---|---|
| VSCode | 生ファイル | プレビュー |
| このビューアー | **整形表示（すでにプレビュー状態）** | 生ファイル |

そのため「プレビュー」というボタン名は、押す前に何が起きるか分からない。代わりに:

- **切り替えボタンは「押すと何になるか」を表示する** — 整形表示中は `生ファイル`、
  生表示中は `整形表示` とラベルが入れ替わる（`lua/custom/md_view.lua` が状態を持つ）
- **ブラウザで開く操作は `ブラウザ` と呼ぶ** — ブラウザに行く理由は実質 mermaid の図を
  見るためだけなので、目的をそのまま名前にする。キーも `Space p`(preview) ではなく
  `Space o`(open) にしてある

### スキルファイル(SKILL.md)を読む

エージェントのスキルファイルは frontmatter の `name` / `description` が本体と同じくらい重要だが、
普通の描画では罫線に挟まれたただの本文にしか見えない。そこで:

- **ターミナル内** — frontmatter に背景色を敷き、開始行の行末に `▌ メタデータ (frontmatter)` と表示。
  キーと値も色分けする（`lua/custom/frontmatter.lua`）
- **ブラウザ** — frontmatter を本文から切り離し、`name` / `description` を並べた
  **メタデータのカード**として先頭に置く。HTMLコメントも枠で囲って可視化する
- **`Space m`** で整形表示と生のテキストを行き来できる。装飾も同時に外れる

`description` は非常に長い1行になることが多いため、マークダウンでは**折り返しを有効**にしてある
（`wrap` / `linebreak` / `breakindent`）。折り返し行は `↪` で示される。

### なぜターミナル内に図を出さないのか

herdr のペインは端末のピクセル寸法を `0 x 0` で報告する。
Kitty graphics は画像の配置とサイズ計算にこれを必要とするため、
**herdr の中では原理的にインライン画像が成立しない**（`kitty_graphics = true` にしても変わらない）。
（他のツール、例えば yazi の画像プレビューが粗いブロックになるのも同じ理由。
chafa による近似表示に落ちている）

確認方法:

```bash
python3 -c "import fcntl,termios,struct
t=open('/dev/tty'); b=fcntl.ioctl(t.fileno(),termios.TIOCGWINSZ,struct.pack('HHHH',0,0,0,0))
print(struct.unpack('HHHH',b))"   # (rows, cols, xpixel, ypixel)
```

## 閲覧専用について

実ファイルのバッファは `modifiable=false` / `readonly=true` になる。
Diffview・lazy.nvim などの UI バッファは対象外（除外しないと壊れるため）。
編集は左ペインのエージェントに依頼する運用。

## 対応している言語

**ハイライトと LSP は別々**で、必要なものが違う。

| | 何が要るか | 対象 |
|---|---|---|
| ハイライト・構造認識 | **何も要らない**（パーサーは `bootstrap.sh` が入れる） | 39言語 |
| 定義ジャンプ・参照検索 | **その言語サーバを自分で入れる** | 39サーバ |

### ハイライト（追加インストール不要）

一覧は `lua/core/parsers.lua`。`:TSInstalled` で導入済みを確認できる。

```
bash c clojure cpp css dart diff dockerfile fsharp go haskell helm html
java javascript json kotlin lua luadoc markdown markdown_inline ocaml php
python query regex ruby rust scala sql svelte terraform toml tsx
typescript vim vimdoc yaml zig
```

### 定義ジャンプ（言語サーバの導入が必要）

一覧は `lua/plugins/lsp.lua` の `candidates`。
**実行ファイルが存在するものだけ**が自動で有効になる。入っていないものは無視されるだけで、
起動が重くなることはない（起動時の存在確認が 1 件あたり 0.1ms 程度）。

| 分類 | 言語 | サーバ（実行ファイル名） |
|---|---|---|
| 設定・文書 | Lua / Bash | `lua-language-server` / `bash-language-server` |
| | JSON / YAML / TOML | `vscode-json-language-server` / `yaml-language-server` / `taplo` |
| | Markdown | `marksman` |
| | SQL | `sqls`（または `sql-language-server` / `postgres-language-server`） |
| | Dockerfile / Terraform | `docker-langserver` / `terraform-ls` |
| | Helm | `helm_ls` |
| Web | TypeScript / JavaScript | `vtsls`（または `typescript-language-server`） |
| | Deno | `deno` |
| | HTML / CSS / ESLint | `vscode-{html,css,eslint}-language-server` |
| | Tailwind / Svelte | `tailwindcss-language-server` / `svelteserver` |
| コンパイル言語 | Go / Rust | `gopls` / `rust-analyzer` |
| | C / C++ | `clangd` |
| | Java / Kotlin | `jdtls` / `kotlin-language-server` |
| | Scala / F# | `metals` / `fsautocomplete` |
| | Zig / Haskell / OCaml | `zls` / `haskell-language-server-wrapper` / `ocamllsp` |
| | Dart | `dart`（SDK 本体。`dart language-server` を使う） |
| 動的言語 | Python | `pyright-langserver` ＋ `ruff`（役割が違うので併用する） |
| | Ruby | `ruby-lsp`（または `solargraph`） |
| | PHP | `intelephense`（または `phpactor`） |
| | Clojure | `clojure-lsp` |
| テスト | Gauge の仕様（`.spec` / `.cpt`） | `gauge`（`gauge daemon --lsp`） |

同じ言語に複数入っている場合の優先順位は `skip_if` で決める
（`vtsls` > `ts_ls`、`ruby-lsp` > `solargraph`、`intelephense` > `phpactor`、
`sqls` > その他の SQL）。両方有効にすると診断が二重に出るため。

**ここに無い言語は、入れても有効にならない。** 足すには `candidates` に1行書く。
名前は `nvim-lspconfig` の `lsp/<名前>.lua` に実在していないと、
エラーにならず静かに無視される。

```bash
ls ~/.local/share/nvim/lazy/nvim-lspconfig/lsp/ | grep '^<名前>\.lua$'
```

### いま自分の環境で何が効いているか

```
:LspEnabled     有効になっている言語サーバを表示
:TSInstalled    導入済みのパーサーを表示
```

`bootstrap.sh` が自動で入れるのは **TypeScript / JSON・HTML・CSS・ESLint / Go** だけ。
残りは「既に入っていれば使う」という扱いなので、必要なものは自分で入れる。

| 言語 | 導入方法 |
|---|---|
| TypeScript / JavaScript | `npm i -g @vtsls/language-server typescript` |
| JSON / HTML / CSS / ESLint | `npm i -g vscode-langservers-extracted` |
| Go | `go install golang.org/x/tools/gopls@latest` |
| Kotlin | `~/.local/share/kotlin-lsp/` に fwcd 版を展開し、`~/.local/bin/kotlin-language-server` にラッパーを置く（手順書の第4.3節） |

注意: npm 製のサーバは mise の Node インストール先に入るため、
mise で Node のメジャーバージョンを上げた場合は入れ直しが必要。

---

## ライセンス

このリポジトリは **MIT**（`LICENSE`）。

導入されるプラグインは**同梱しておらず**、`lazy.nvim` が利用者のマシンで
各配布元から取得する。それぞれのライセンスは以下のとおり。

| ライセンス | プラグイン |
|---|---|
| **GPL-3.0-or-later** | `diffview.nvim` |
| Apache-2.0 | `lazy.nvim` / `nvim-lspconfig` / `nvim-treesitter` / `snacks.nvim` / `which-key.nvim` |
| MIT | `nvim-web-devicons` / `plenary.nvim` / `render-markdown.nvim` |

`bootstrap.sh` が npm から入れる `marked` / `mermaid` / `@mermaid-js/mermaid-cli` は
いずれも MIT。これらも同梱しておらず、利用者のマシンで取得する。

**`diffview.nvim` が GPL である点に注意。** この設定はそのコードを一行も含まず、
利用者が自分で取得するため、この設定自体のライセンスには影響しない。
ただし導入すると自分の環境に GPL のコードが入ることは認識しておくこと。
