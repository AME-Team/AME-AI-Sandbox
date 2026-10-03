# AME-AI-Sandbox

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="landing-page/public/header-dark.svg">
  <source media="(prefers-color-scheme: light)" srcset="landing-page/public/header-light.svg">
  <img alt="AME-AI-Sandbox" src="landing-page/public/header-light.svg">
</picture>

Claude Code / OpenCode / Antigravity CLI をコンテナ内で動かすための開発用 Docker サンドボックスです。
Ubuntu 24.04 LTS をベースに、Python 3.14 (uv 管理) ・ Node.js v24 ・ Go ・ GitHub CLI (`gh`) を含みます。

設定値はすべてファイルから読み込むため、コマンドの引数で都度渡す必要はありません（Issue #3）。

- 環境変数（`GH_TOKEN`, `GIT_AUTHOR_NAME`, `SSH_HOST_DIR` 等） → `.env`
- sudo パスワード（BuildKit secret） → `secrets/user_password.txt`
- SSH 鍵 → `.env` の `SSH_HOST_DIR` で指定したホストディレクトリ

## 初回セットアップ

### 1. 環境変数ファイルの作成

```bash
cp .env.example .env
# .env を編集して以下を埋める:
#   - GH_TOKEN            : GitHub PAT（gh / git HTTPS 認証）
#   - GIT_AUTHOR_NAME     : git commit の著者名
#   - GIT_AUTHOR_EMAIL    : git commit のメールアドレス
#   - SSH_HOST_DIR        : ホスト側の SSH 鍵ディレクトリ（絶対パス必須）
```

> `SSH_HOST_DIR` は必須です。未設定の場合、`docker compose` が起動時にエラーで停止します。
> `~` を指定すると Compose 変数展開で解釈されない場合があるため、`/home/<user>/.ssh` のような絶対パスを推奨します。

### 2. sudo パスワードファイルの作成

```bash
mkdir -p secrets
cp secrets/user_password.txt.example secrets/user_password.txt
# secrets/user_password.txt を編集し、コンテナ内 ai-developer ユーザーの sudo パスワードを記載
```

> `secrets/user_password.txt` と `.env` は `.gitignore` で除外されています。
> sudo パスワードは BuildKit secret mount 経由で渡され、`docker history` 等のイメージメタデータに残りません。

### 3. （任意）ホスト UID/GID の調整

既定では `ai-developer` ユーザーの UID/GID は `1000:1000` です。
ホストと合わせたい場合は `.env` に追記してください。

```bash
USER_UID=1000
USER_GID=1000
```

## 使い方

```bash
# Docker イメージをビルド
docker compose build

# コンテナをバックグラウンド起動
docker compose up -d

# コンテナに入る（対話シェル）
# 初期ディレクトリは HOME (/home/ai-developer)。リポジトリ本体は /workspace にマウントされている。
docker compose exec sandbox bash

# 終了時: コンテナを停止
docker compose down
```

## コンテナ内 Web サービスへのホスト側からのアクセス

コンテナ内で `npm run dev` 等により Web サービスを起動した場合、ホスト側のブラウザから
アクセスできるようにする方法は 2 通りあり、`.env` の設定だけで切り替えられます。

### 既定（bridge モード・特定ポートのみ公開）

`.env` の `DOCKER_NETWORK_MODE=bridge`（既定値）のとき、`DEV_PORT_1`〜`DEV_PORT_5`
で指定したポートのみ `127.0.0.1` に公開されます。既定のポート番号は以下のとおりです。

- `DEV_PORT_1=5173`（Vite）
- `DEV_PORT_2=3000`（Next.js・React・Node）
- `DEV_PORT_3=8000`（Django・FastAPI）
- `DEV_PORT_4=8080`（汎用）
- `DEV_PORT_5=5000`（Flask）

別のポートを使いたい場合は該当する `DEV_PORT_*` を書き換えてから、以下を実行してください。

```bash
docker compose up -d
```

### host モード（任意ポートに即アクセス）

`.env` の `DOCKER_NETWORK_MODE=host` に変更して `docker compose up -d`
すると、コンテナがホストのネットワークを直接共有します。`DEV_PORT_*`
の設定に関わらず、コンテナ内で起動した任意の Web サーバーに `http://localhost:<port>/` で到達できます。

> host モードは Docker Desktop（Mac/Windows）のバックエンドによっては未対応・要設定の場合があります。
> その場合は bridge モードのまま `DEV_PORT_*` に必要なポートを追加してください。
> また host モードでは起動ログに
> `WARNING: Published ports are discarded when using host network mode` と表示されますが、
> `ports` 設定が無視されているだけで想定内の警告です。

## 各CLIの使い方

| CLI | 起動コマンド | 認証方法 |
| --- | --- | --- |
| Claude Code | `claude` | 対話ログイン、または `ANTHROPIC_API_KEY` 環境変数 |
| OpenCode | `opencode` | `opencode auth login`（対話）、またはプロバイダごとの API キー環境変数（例: `ANTHROPIC_API_KEY`） |
| Antigravity CLI | `agy` | ヘッドレス環境では URL + ワンタイムコードによる対話認証、または `ANTIGRAVITY_API_KEY` 環境変数（Google AI Studio で取得） |
| GitHub CLI | `gh` | `GH_TOKEN` 環境変数で entrypoint 起動時に自動ログイン済み |

API キーは `.env` に記載すれば、コンテナ起動直後から非対話的に利用できます。

## セキュリティに関する注記

- **SSH 鍵はビルド時にイメージへ焼き込まない。** 代わりに、実行時はホストの鍵を読み取り専用で bind-mount する。
  マウント元は `.env` の `SSH_HOST_DIR` で指定し、`entrypoint.sh` がコンテナ起動時に書き込み可能な `~/.ssh` へコピーする。
  イメージレイヤーやコミット履歴に鍵 material は残らない。
- GitHub のホスト鍵は `ssh-keyscan` で `known_hosts` に登録しており、
  `StrictHostKeyChecking no` のような検証無効化は行っていません。
- `GH_TOKEN` は環境変数として渡され、`gh` の credential helper が動的に解決するため、
  `~/.git-credentials` のような平文ファイルには保存されません。
- sudo パスワードは BuildKit の secret mount 機構でビルド時にのみ渡され、
  イメージの `ARG` / `ENV` や `docker history` には一切残りません。

## 開発・レビュー（AME-AI-Review-System）

二段ゲート方式の AI コードレビュー基盤（[AME-Team/AME-AI-Review-System](https://github.com/AME-Team/AME-AI-Review-System)）を
**方式A（wheel + `ame-ai-reviewer init`）** で導入しています。

- パッケージは vendored せず、GitHub Release の wheel を参照します（`.pre-commit-config.yaml` の
  `language: python` フックが pre-commit 環境へ自動導入。供給チェーン対策のため `#sha256=` で内容固定）。
- プロジェクト設定は `.ame-review/config.json`（Git 追跡対象）に配置されます。
  - `ai_review_enforce_no_skip`: `true`（既定）で `SKIP=ai-precommit-review` を `ai-skip-guard` フックがブロック
  - `review_include_package_dir`: `false`（既定）で vendored パッケージをレビュー対象外に
  - `show_engine_info_gate1` / `show_engine_info_gate2`: エンジン・モデル・思考量バナー表示の ON/OFF
  - `precommit_engine`: `auto`（既定）で実装ツール（claude/opencode/antigravity）を自動検出
  - これらは導入済み wheel v0.2.16 が解釈するキー（`review_config` / `skip_guard` / `engine` が参照）。
- CI は `ame-ai-reviewer init` が生成する薄いラッパ（`.github/workflows/review_command.yml` /
  `review_reply.yml`）が reusable workflow を呼び出します。
- **バージョンの追随**は移動メジャータグ `v0` により自動で行われます。CI 側（ラッパの `uses:@<ref>` /
  `system_ref`）は `v0` を参照するため、配布先での更新作業は不要です。
- Gate 1 の wheel は `.pre-commit-config.yaml` の 3 フックに `#sha256=` 付きで固定します（現在 v0.2.16）。
  追随は `ame-ai-reviewer sync` が行い、URL と `#sha256=` を hub の最新リリースへ書き換えます。
  差分の確認だけなら `ame-ai-reviewer sync --check`（差分があれば exit 1、判定できなければ exit 2）を使います。
- リリース直後は「CI（移動タグ）」と「ローカル wheel（固定）」の版がずれ得ます。判断の目安は
  `sync --check` です。CI 側は常に最新を参照し、ローカルは `sync` を実行した時点で揃います。
  不変性が必要な場合は `ame-ai-reviewer init --ref v0.2.16` のようにリリースタグへ固定します
  （その場合は手作業の更新が必要になります）。
- ラッパの `checks: read` は Gate 2 が PR の check runs を読むための権限です（hub の Issue #140）。
  欠けると外部 CI ゲートが無言で無効化されるため、テンプレートどおりに維持してください。
- `review_reply.yml` には前置 `if` フィルタを置きません。bot 自己除外とコマンド除外は upstream の
  reusable workflow が `comment_user` / `comment_body` 入力に対して実施します（`@ame-ai-reviewer`
  宛てかどうかの判定も含みます）。重複して持つと上流の条件と乖離します。
- ローカルレビュー（Gate 1）と PR レビュー（Gate 2）の運用は、本リポジトリの
  `.agents/skills/review-round/SKILL.md`（配布先では `.claude/skills/review-round/SKILL.md`）
  および [セットアップガイド](https://github.com/AME-Team/AME-AI-Review-System/blob/main/ame_ai_review_system/docs/setup.md) を参照してください。
- レビュアー用 GitHub App の Secrets（`AME_AI_REVIEWER_APP_ID` / `AME_AI_REVIEWER_APP_PRIVATE_KEY`）は
  リポジトリの Actions secrets に登録済みです。

## 紹介用ランディングページ（landing-page/）

本リポジトリを紹介する React + TypeScript + Tailwind CSS 製のランディングページです。
`main` への push で GitHub Pages（<https://tarminjapan.github.io/AME-AI-Sandbox/>）へ自動デプロイされます。

```bash
cd landing-page
npm install
npm run dev      # 開発サーバー
npm run build    # 本番ビルド (dist/)
```
