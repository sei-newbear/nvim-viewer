# Repository instructions

## コミット前の必須確認

### コミットの著者情報

- コミットを作る前に `git log -20 --format='%an <%ae> | %cn <%ce>'` で、直近20件の author と committer の名前・メールアドレスを確認する。端末のグローバルな Git 設定を根拠にしない。
- 直近20件の author と committer がすべて同じ組み合わせなら、新しいコミットの author と committer の両方をその名前・メールアドレスに合わせる。
- author と committer を確実に指定するため、コミット時だけ `GIT_AUTHOR_NAME`、`GIT_AUTHOR_EMAIL`、`GIT_COMMITTER_NAME`、`GIT_COMMITTER_EMAIL` を確認済みの値に設定して `git commit` を実行する。リポジトリやグローバルの Git 設定は変更しない。
- 直近20件に複数の組み合わせがある場合、または初回コミットで履歴がない場合は、コミットせず依頼者に使う名前・メールアドレスを確認する。

### 公開可能性

- 最初に `git status --short` で staged、unstaged、untracked の全ファイルを把握する。コミット対象のパスだけを明示してステージし、`git status --short` を再実行して対象を確定する。`git add .` や `git add -A` で一括追加しない。
- コミット直前に `git diff --cached --stat` と `git diff --cached` を実行し、ステージ済みの全差分を確認する。unstaged と untracked はコミットに入らないが、意図した変更の入れ忘れがないか `git status --short` と照合する。
- untracked のテキストファイルをコミット候補にするときは、ステージ前に `file -- <path>` で種類を確認し、ファイルの全内容を読む。バイナリまたは全内容を現実的に確認できない大容量ファイルは、由来と公開可能性を確認できるまでコミットしない。
- secrets、認証情報、個人情報、端末固有のパスやホスト名、社内限定情報、実在する顧客・企業・案件のデータを含めない。
- テスト、fixture、サンプル、ドキュメントの例示には、実データを加工・匿名化した値ではなく、最初から架空として作った汎用的なダミーデータだけを使う。
- 公開してよいか判断できない情報が一つでもある場合は、コミットせず依頼者に確認する。
