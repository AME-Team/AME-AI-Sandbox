# Claude Code ルール — AME-AI-Sandbox

このリポジトリは、Claude Code / OpenCode / Antigravity CLI を Docker コンテナ内で動かすための開発用サンドボックスです。
中核は `Dockerfile` / `entrypoint.sh` の定義です。
加えて、AI コードレビューシステム（[AME-Team/AME-AI-Review-System](https://github.com/AME-Team/AME-AI-Review-System)）を
**方式A（wheel + `ame-ai-reviewer init`）** で導入している。パッケージ本体は vendored せず、GitHub Release の wheel を
`.pre-commit-config.yaml`（`language: python` + `#sha256=` 固定）で参照する。CI のラッパは hub の
**移動メジャータグ `v0`** を参照し、リリースごとに自動追随する（配布先での更新作業は不要）。
プロジェクト設定は `.ame-review/config.json` に置く。

- CI（ラッパの `uses:@<ref>` / `system_ref`）は移動メジャータグ `v0` を参照する。不変性が必要な場合は
  `ame-ai-reviewer init --ref v0.2.16` のようにリリースタグへ固定する（その場合は手作業の更新が必要）。
- Gate 1 の wheel は `.pre-commit-config.yaml` の 3 フックに `#sha256=` 付きで固定する（現在 v0.2.16）。
  追随は `ame-ai-reviewer sync`、差分の確認だけなら `sync --check`（差分あり exit 1 / 判定不能 exit 2）。
  リリース直後は CI とローカルの版がずれ得るため、追随は `sync` の実行時点で揃う。
- ラッパの `checks: read` は Gate 2 が PR の check runs を読むための権限（hub の Issue #140）。
  欠けると外部 CI ゲートが無言で無効化されるため、テンプレートどおりに維持する。
- `review_reply.yml` に前置 `if` は置かない。bot 自己除外・コマンド除外・`@ame-ai-reviewer` 宛て判定は
  upstream が `comment_user` / `comment_body` 入力に対して行う（重複させると上流の条件と乖離する）。
  `review_command.yml` のジョブ `if`（PR 判定と `/request-review` のコマンド判定）は**維持**する。

## ブランチ・PR ポリシー

現状、このリポジトリのブランチは `main` のみを運用している。作業ブランチ（`feature/*` / `bug/*` /
`chore/*`）から直接 `main` へ PR を作成してよい。

```text
feature/* | bug/* | chore/*  ──►  main
```

将来 `dev` ブランチを導入する場合は、移植元と同様に `feature/* → dev → main`
の三層フローへ拡張すること。
その際、AI Agent が PR を作成する際のデフォルト base を `dev`
にする運用へ切り替える（`--base` を必ず明示する）。

## サンドボックス固有ルール

- **SSH鍵はイメージに焼き込まない。** 実行時に `-v ~/.ssh:/etc/ssh-host:ro`
  で bind-mount する。`entrypoint.sh` が書き込み可能な `~/.ssh`
  へコピーする方式に統一する。`Dockerfile` に `COPY` で秘密鍵を追加することは禁止。
- **GitHubトークンをディスクに平文保存しない。** `GH_TOKEN` 環境変数のみで認証し、
  `entrypoint.sh` が `gh auth setup-git` で credential helper を設定して env から
  動的解決する方式を維持する（`gh auth login --with-token` による hosts.yml への
  保存は行わない。GH_TOKEN 設定時は gh が rc=1 を返すため login 自体も不要）。
  `gh auth setup-git` が失敗してもコンテナは起動を継続し、stderr に警告を出力する
  （認証エラーは git 使用時に顕在化する。サンドボックスとしてグレースフルに劣化させる判断）。
  `~/.git-credentials` への直接書き込みは禁止。
- Claude Code / OpenCode / Antigravity CLI いずれかに固有の実装を追加する場合、他の2つのCLIの動作を壊さないこと。
  `entrypoint.sh` は特定CLIの分岐を持たず、各CLIが自身の環境変数を直接読む設計を維持する。
- **コンテナ内 Web サービスの公開設定はハードコードしない。** `compose.yaml` の `network_mode` /
  `ports` は `.env` の `DOCKER_NETWORK_MODE`（`bridge` | `host`）と `DEV_PORT_*`
  で切り替える（Issue #11）。`ports` は必ず `127.0.0.1`
  にバインドし、LAN へ誤公開しないこと。

## PR レビュー対応フロー（必須）

PR をマージする前に、以下のフローをすべて完了すること。

### 1. インラインレビューコメントへの対応と返信

PR に AI レビュアーからインラインレビューコメントが付いたら、次の手順を実施する。対象レビュアー:
`ame-ai-reviewer` (GitHub App のため、コメント作成者は `ame-ai-reviewer[bot]` になる)。

1. **コードを修正する** — CRITICAL / HIGH / MIDDLE /
   LOW レベルの各指摘事項に対応した修正を加え、pre-commit を通過させてコミット・プッシュする。
2. **各スレッドに返信する** — 対応内容を説明したメッセージを、必ず `@<レビュアー名>[bot]`
   メンション付きで投稿する。
   - API: `POST /repos/{owner}/{repo}/pulls/{pr}/comments/{id}/replies`
   - トークン: `~/.config/ame-ai-review-system/github.token`（ユーザーアカウント）
3. **レビュアーが LGTM 返信してくれる** — レビュアーが対応済みを確認し、返信を投稿してくれる。
   - CI 上のレビュアーは GitHub App (`AME_AI_REVIEWER_APP_ID` /
     `AME_AI_REVIEWER_APP_PRIVATE_KEY`) から発行されたインストールトークンを使用
   - 本文例: `「対応確認しました。LGTM ✅ Resolve してください。」`
4. **スレッドを Resolve する** — LGTM 返信が来たら Resolve する。
   - GitHub REST には対応エンドポイントが無い。GraphQL mutation `resolveReviewThread`
     経由で Resolve する。実装は `reply.py` → `github_client.resolve_review_thread` で行う。

### 2. 返信・Resolve の API まとめ

```text
GitHub API : https://api.github.com
GraphQL   : https://api.github.com/graphql
リポジトリ : AME-Team/AME-AI-Sandbox
通常トークン : ~/.config/ame-ai-review-system/github.token（なければ環境変数 $GITHUB_PAT_TOKEN を使用）

CI 上のレビュアートークン（GitHub App インストールトークンを actions/create-github-app-token で取得）:
  AME_AI_REVIEWER_APP_ID          : GitHub App の App ID（数値）
  AME_AI_REVIEWER_APP_PRIVATE_KEY : Private Key (.pem)

ローカル環境のレビュアートークン:
  ame-ai-reviewer : ~/.config/ame-ai-review-system/ame-ai-reviewer.token

スレッド返信 : POST /repos/{repo}/pulls/{pr}/comments/{id}/replies
Resolve     : GraphQL mutation resolveReviewThread(input: {threadId: ID!})
```

> **トークン取得の優先順位（ファイルが存在しない場合は次を試す）**
>
> 1. `~/.config/ame-ai-review-system/github.token`（またはレビュアー固有の `<name>.token`）
> 2. 環境変数 `$GITHUB_PAT_TOKEN`（または `<NAME>_TOKEN`）
>
> GitHub Actions 上では `actions/create-github-app-token@v2` がインストールトークンを発行し、それを
> `GITHUB_PAT_TOKEN` / `AME_AI_REVIEWER_TOKEN` に設定して Python コードに渡す。`GITHUB_REPOSITORY` /
> `GITHUB_API_URL`
> が自動設定されるため、ワークフロー側での環境変数明示は不要（`github_client.resolve_env`
> が解決する）。

### 3. 各レビュアーの仕様（重要）

各レビュアーは以下の 2 つのタイミングで動作する。

1. **レビュー実行**: PR コメントで `/request-review`
   が入力されたときにインラインコメントを投稿する（`review_command.yml`）。`/review`
   も同じコマンドのエイリアス。
2. **返信判断**: インライン返信（`pull_request_review_comment: created`
    イベント）で `@<レビュアー名>` 宛ての返信を検知する。**実際の diff を読んで LGTM
    か追加指摘かを判断**して返信する（`review_reply.yml`）。ただし
    `/` で始まるコメント（コマンド）は返信判定の対象外。

返信判断は `reply.py` (`python3 -m ame_ai_review_system.reply run`) →
設定エンジンのフローで実行される。エンジン既定は `opencode`
（`inputs.review_engine || secrets.review-engine || 'opencode'`。`vars.REVIEW_ENGINE` 等で上書き可能）。
ローカル pre-commit レビューは `precommit_engine: auto`（`.ame-review/config.json`）で実装ツールを自動検出する。
Gate 2（CI）で `claude` エンジンを使う場合は、Claude 認証情報（`CLAUDE_CONFIG_B64` /
`CLAUDE_CREDENTIALS_B64` 等）を Actions secrets に追加する必要がある（現行のラッパ既定にも Claude 用の
secrets は含まれないため、本リポジトリでは `opencode` を既定とする）。
エンジンはレビュアーとして「元の指摘内容」「開発者の返信」「PR の diff」を照合し、修正が十分かを判断する。

### 4. PR 作成後の自動レビュー対応フロー

> **【絶対ルール】未解決スレッドがゼロになるまで絶対に作業を止めない。**
> ユーザーから「止めていい」と明示的に言われない限り、何があっても以下のループを継続する。途中で止めることは厳禁。

PR を作成・プッシュしたら、以下のループを完遂すること。

0. PR コメントで `/request-review` を投稿してレビューを依頼する（`github.token`）。 `/review`
   も同じ意味。
1. `ame-ai-reviewer[bot]` のインラインコメント一覧を取得する。API:
   `GET /repos/{repo}/pulls/{pr}/comments`。
2. 未対応の CRITICAL / HIGH / MIDDLE / LOW コメントがあればコードを修正してコミット・プッシュする
3. 各スレッドに `@ame-ai-reviewer[bot]` メンション付きで対応内容を返信する（`github.token`）
4. `ame-ai-reviewer[bot]` が LGTM 返信を投稿してくれる（`ame-ai-reviewer.token`
   または CI 上の App インストールトークン）
5. LGTM が届いたスレッドを Resolve する
6. **未解決スレッドが残っていれば 1 に戻る**
7. 全スレッドが Resolve されたら、**再度 `/request-review`
   を投稿して再レビュー**する。新たな指摘がなければ完了。指摘があれば 1 に戻り、指摘がゼロになるまでループする。

### 5. CI/CD 品質ゲートの例外ルール

`main.py review` は指摘があっても `exit 0` で終了させる（ワークフローを success にする）。

- **理由**:
  AI レビューの指摘によるエラーと、スクリプト自体のエラーを区別できるようにするため。指摘は GitHub の PR インラインコメントで通知されるため、CI ステータスでゲートする必要はない。
- **適用範囲**: `main.py review`
  の末尾 exit ステータスのみ。スクリプト内のエラー（エンジン呼び出し失敗など）は引き続き `exit 1`
  を返す。

### 6. レビュアー追加方法

レビュー処理は `main review` サブコマンドが担う。`REVIEWER_NAME` / `REVIEWER_PROMPT_FILE`
環境変数でパラメータ化されているため、コード追加なしで新レビュアーを追加できる。

> 本リポジトリは方式A（wheel + `ame-ai-reviewer init`）のため、`review_command.yml` /
> `review_reply.yml` は reusable workflow を呼ぶ薄いラッパであり、実処理・判定ロジックは
> upstream の `AME-Team/AME-AI-Review-System` 側にある。多レビュアー対応は upstream の
> reusable workflow が担う（`REVIEWER_NAME` / `REVIEWER_PROMPT_FILE`）。本リポジトリ側では
> ラッパの `secrets:` に `<REVIEWER_NAME_UPPER>_APP_ID` / `<REVIEWER_NAME_UPPER>_APP_PRIVATE_KEY` を
> 追加するか、`ame-ai-reviewer init --force` でラッパを再生成する。プロンプトは
> `.ame-review/review_prompt.txt`（upstream の wheel 既定を初期値とする）を編集する。

1. GitHub App を作成し、対象リポジトリにインストール。必要権限: `Contents: Read` /
   `Pull requests: Read & Write` / `Issues: Read & Write`
2. GitHub Actions Secrets に `<REVIEWER_NAME_UPPER>_APP_ID` と
   `<REVIEWER_NAME_UPPER>_APP_PRIVATE_KEY` を登録（例: `SECURITY_REVIEWER_APP_ID` /
   `SECURITY_REVIEWER_APP_PRIVATE_KEY`）
3. `.github/workflows/review_command.yml` / `review_reply.yml`（reusable workflow のラッパ）の
   `secrets:` ブロックに新レビュアーの Secrets を追加する。bot 自己除外はラッパで扱いが異なる。
   - `review_command.yml` のジョブ `if`（PR 判定とコマンド判定）は**維持**し、新レビュアーの
     `github.event.comment.user.login != '<新レビュアーslug>[bot]'` を追加する。
   - `review_reply.yml` には前置 `if` を**置かない**。bot 自己除外・コマンド除外・`@ame-ai-reviewer`
     宛て判定は upstream が `comment_user` / `comment_body` 入力に対して行う（新レビュアーの slug は
     upstream 側の条件へ追加する）。
4. プロンプトは `.ame-review/review_prompt.txt`（全レビュアー共通の既定）を編集する。
   レビュアー固有のプロンプトが必要な場合は `REVIEWER_PROMPT_FILE` を利用する

### 7. コーディング規約（レビューでよく指摘される点）

- コメントは **WHY のみ**。WHAT を説明するコメント・docstring は不要
- `except Exception:` は禁止。発生しうる具体的な例外型に限定する
- `kill -15 $pids` は禁止。`echo "$pids" | xargs -r kill -15` を使う
- 一時ファイルは必ず `cleanup()` + `trap cleanup EXIT` で管理する
- シェルで外部入力を扱う場合は `printf '%s\n'`
  または stdin 渡しを使い、引数展開によるインジェクションを避ける

> 上記規約は、導入済みパッケージ（wheel）内の Semgrep カスタムルール
> （`ame_ai_review_system/.semgrep/rules.yml`）と AI レビュー（Gate 1 / Gate 2）で機械的に検出・ブロックする。
> 新しい規約を追加する場合は、upstream の `ame_ai_review_system/.semgrep/rules.yml` にルールを追加し、
> 次のリリースで取り込む（本リポジトリは vendored していないため）。

### 8. トークン削減施策

以下の施策により AI レビューのラウンド数・トークン消費量・処理時間を削減する。

- **Circuit Breaker**:
  PR レビュー前に ruff/mypy/hadolint/trivy config/semgrep 等を実行する。エラーがあれば AI レビューをスキップする。`pr_review_require_static_checks`
  で ON/OFF。
- **プロンプトキャッシュ最適化**: 返信判定プロンプトは固定セクションを先頭に配置する。
- **Reasoning Effort 制御**: 返信判定は `reply_model`/`reply_thinking`
  で軽量モデルに切り替え、推論トークンを削減する。
- **Stale-Loop 検出**: レビュアーの直近2返信の Jaccard 類似度 ≥80% で強制 LGTM。
- **Diff 圧縮**: `diff_utils.py` が git diff のメタデータ・バイナリ差分・連続空行を除去。
- **最大ラウンド制限**: PR ごとに最大 10 ラウンド。ラウンド3到達時に収束シグナルを挿入。
