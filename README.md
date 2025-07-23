# dAIdalus - AI Engineering Agent Server

dAIdalus（ダイダロス）は、開発者の隣で作業する思考の見えるAIペアプログラマーです。本プロジェクトは「脳」（gemini-cli）と「神経系」（dAIdalus）を分離した設計思想に基づき、GitHubやLINEからのトリガーを受けてAIエージェントを実行するサーバーサイドコンポーネントです。

## 🏗️ アーキテクチャ

```
トリガー層 (外部サービス)
├── GitHub (Issue/PR/Comment)
└── LINE (Botへのメンション)
    ↓
オーケストレーション層 (神経系)
├── Cloud Functions (Webhook/API受付)
├── Cloud Run (管理画面)
└── Firestore (タスクキュー/状態管理)
    ↓
実行層 (脳と手足)
├── AIエージェント (脳): gemini-cli as MCPホスト
└── ローカル実行環境 (手足): Self-hosted Runner as MCPサーバー
```

## 🚀 クイックスタート

### 環境構築の方針

- **🔧 開発環境**: DevContainer を使用（推奨）
- **🚀 本番実行**: Dockerfile を使用

### 開発環境のセットアップ（DevContainer）

**推奨方法**: VS Code + DevContainer を使用した開発環境

1. **前提条件**
   - Docker Desktop
   - VS Code
   - Dev Containers 拡張機能

2. **セットアップ手順**
```bash
# リポジトリのクローン
git clone https://github.com/koduki/daidalus.git
cd daidalus
```

3. **VS Code で開発環境を起動**
   - VS Code でプロジェクトフォルダーを開く
   - 「Reopen in Container」を選択
   - 自動的に開発環境がセットアップされます
   - Ruby 3.2、Node.js 18、gemini-cli が自動インストールされます

4. **環境変数の設定**
```bash
cp .env.example .env
# .envファイルを編集して必要な環境変数を設定
```

5. **サーバーの起動**
```bash
# DevContainer内で実行
bundle exec ruby app.rb
```

サーバーは `http://localhost:4567` で起動します。

### 手動セットアップ（DevContainer未使用の場合）

DevContainerを使用しない場合の手動セットアップ：

1. **前提条件**
   - Ruby 3.2以上
   - Node.js 18以上
   - Google Cloud SDK

2. **依存関係のインストール**
```bash
# Ruby依存関係
bundle install

# gemini-cliのインストール
npm install -g @google/gemini-cli
```

## 📡 API リファレンス

### ヘルスチェック

```http
GET /health
```

**レスポンス:**
```json
{
  "status": "ok",
  "timestamp": "2025-07-23T08:39:07+00:00"
}
```

### Gemini CLI セッション管理

#### セッション作成

```http
POST /gemini/sessions
Content-Type: application/json

{
  "session_id": "unique-session-id",
  "options": {
    "interactive": true,
    "model": "gemini-pro",
    "temperature": 0.7,
    "max_tokens": 1000,
    "mcp_servers": ["server1", "server2"]
  }
}
```

**レスポンス:**
```json
{
  "success": true,
  "session_id": "unique-session-id",
  "message": "Session created successfully"
}
```

#### コマンド送信

```http
POST /gemini/sessions/{session_id}/command
Content-Type: application/json

{
  "command": "Hello, can you help me?",
  "timeout": 30
}
```

**レスポンス:**
```json
{
  "success": true,
  "response": "AI response here...",
  "timestamp": "2025-07-23T08:39:07+00:00"
}
```

#### 構造化プロンプト送信

```http
POST /gemini/sessions/{session_id}/prompt
Content-Type: application/json

{
  "prompt": "What is the capital of Japan?",
  "context": "This is a geography question",
  "timeout": 30
}
```

#### セッション状態確認

```http
GET /gemini/sessions/{session_id}/status
```

**レスポンス:**
```json
{
  "exists": true,
  "alive": true,
  "created_at": "2025-07-23T08:30:00+00:00",
  "pid": 12345
}
```

#### アクティブセッション一覧

```http
GET /gemini/sessions
```

**レスポンス:**
```json
{
  "sessions": [
    {
      "session_id": "session-1",
      "alive": true,
      "created_at": "2025-07-23T08:30:00+00:00",
      "pid": 12345
    }
  ]
}
```

#### セッション停止

```http
DELETE /gemini/sessions/{session_id}
```

### GitHub Webhook エンドポイント

```http
POST /webhooks/github
Content-Type: application/json
X-GitHub-Event: issues

{
  "action": "opened",
  "issue": { ... },
  "repository": { ... }
}
```

### LINE Webhook エンドポイント

```http
POST /webhooks/line
Content-Type: application/json

{
  "events": [
    {
      "type": "message",
      "message": {
        "type": "text",
        "text": "@dAIdalus help me with this issue"
      }
    }
  ]
}
```

## 🐳 Docker デプロイ

### ローカルでのDockerビルド・実行

```bash
# イメージのビルド
docker build -t daidalus-server .

# コンテナの実行
docker run -p 4567:4567 \
  -e GOOGLE_CLOUD_PROJECT=your-project \
  -e GEMINI_API_KEY=your-api-key \
  daidalus-server
```

### Google Cloud Run へのデプロイ

1. **Google Cloud プロジェクトの設定**
```bash
gcloud config set project YOUR_PROJECT_ID
gcloud auth configure-docker
```

2. **イメージのビルドとプッシュ**
```bash
# Cloud Build を使用
gcloud builds submit --tag gcr.io/YOUR_PROJECT_ID/daidalus-server

# または手動でビルド・プッシュ
docker build -t gcr.io/YOUR_PROJECT_ID/daidalus-server .
docker push gcr.io/YOUR_PROJECT_ID/daidalus-server
```

3. **Cloud Run へのデプロイ**
```bash
gcloud run deploy daidalus-server \
  --image gcr.io/YOUR_PROJECT_ID/daidalus-server \
  --platform managed \
  --region asia-northeast1 \
  --allow-unauthenticated \
  --port 4567 \
  --set-env-vars GOOGLE_CLOUD_PROJECT=YOUR_PROJECT_ID
```

### Google Compute Engine へのデプロイ

1. **VMインスタンスの作成**
```bash
gcloud compute instances create daidalus-server \
  --zone=asia-northeast1-a \
  --machine-type=e2-medium \
  --image-family=cos-stable \
  --image-project=cos-cloud \
  --tags=http-server,https-server
```

2. **ファイアウォールルールの設定**
```bash
gcloud compute firewall-rules create allow-daidalus \
  --allow tcp:4567 \
  --source-ranges 0.0.0.0/0 \
  --target-tags http-server
```

3. **VMでのコンテナ実行**
```bash
# VMにSSH接続
gcloud compute ssh daidalus-server --zone=asia-northeast1-a

# Docker実行
docker run -d -p 4567:4567 \
  --name daidalus-server \
  --restart unless-stopped \
  gcr.io/YOUR_PROJECT_ID/daidalus-server
```

## ⚙️ 環境変数

| 変数名 | 説明 | 必須 | デフォルト値 |
|--------|------|------|-------------|
| `GOOGLE_CLOUD_PROJECT` | Google Cloud プロジェクトID | ○ | - |
| `GEMINI_API_KEY` | Gemini API キー | ○ | - |
| `GITHUB_WEBHOOK_SECRET` | GitHub Webhook シークレット | △ | - |
| `LINE_CHANNEL_SECRET` | LINE チャンネルシークレット | △ | - |
| `LINE_CHANNEL_ACCESS_TOKEN` | LINE チャンネルアクセストークン | △ | - |
| `FIRESTORE_COLLECTION` | Firestore コレクション名 | △ | `tasks` |
| `PORT` | サーバーポート | △ | `4567` |
| `RACK_ENV` | 実行環境 | △ | `development` |

## 🧪 テスト

### 単体テスト実行

```bash
# RSpecテストの実行
bundle exec rspec

# 特定のテストファイルの実行
bundle exec rspec spec/gemini_cli_service_spec.rb
```

### API テスト

```bash
# テストスクリプトの実行
ruby test_gemini_interface.rb
```

### 手動テスト

```bash
# ヘルスチェック
curl http://localhost:4567/health

# セッション作成
curl -X POST http://localhost:4567/gemini/sessions \
  -H "Content-Type: application/json" \
  -d '{"session_id": "test-session", "options": {"interactive": true}}'

# コマンド送信
curl -X POST http://localhost:4567/gemini/sessions/test-session/command \
  -H "Content-Type: application/json" \
  -d '{"command": "Hello, world!", "timeout": 10}'
```

## 🔧 開発ガイド

### プロジェクト構造

```
daidalus/
├── app.rb                    # メインアプリケーション
├── lib/
│   └── gemini_cli_service.rb # Gemini CLI サービス
├── .devcontainer/
│   └── devcontainer.json     # VS Code DevContainer設定
├── Dockerfile                # Docker設定
├── Gemfile                   # Ruby依存関係
├── config.ru                 # Rack設定
├── test_gemini_interface.rb  # APIテストスクリプト
└── README.md                 # このファイル
```

### コーディング規約

- Ruby Style Guide に従う
- RuboCop を使用してコード品質を維持
- テストファーストで開発
- コミットメッセージは英語で記述

### 新機能の追加

1. 機能ブランチを作成: `git checkout -b feature/new-feature`
2. 実装とテストを追加
3. RuboCop チェック: `bundle exec rubocop`
4. テスト実行: `bundle exec rspec`
5. プルリクエストを作成

## 🔗 関連リンク

- [Gemini CLI Documentation](https://github.com/google/gemini-cli)
- [Model Context Protocol (MCP)](https://modelcontextprotocol.io/)
- [Google Cloud Run Documentation](https://cloud.google.com/run/docs)
- [Sinatra Documentation](http://sinatrarb.com/)

## 📄 ライセンス

MIT License

## 🤝 コントリビューション

1. このリポジトリをフォーク
2. 機能ブランチを作成 (`git checkout -b feature/amazing-feature`)
3. 変更をコミット (`git commit -m 'Add amazing feature'`)
4. ブランチにプッシュ (`git push origin feature/amazing-feature`)
5. プルリクエストを作成

## 📞 サポート

問題や質問がある場合は、GitHub Issues でお知らせください。

---

**dAIdalus** - AI Engineering Agent System
