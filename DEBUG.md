# デバッグ環境

VS Code + Docker で Metasploit Framework を開発・デバッグする手順。

## 前提条件

- Docker Desktop
- VS Code + 拡張機能:
  - `ms-vscode-remote.remote-containers` - Dev Containers
  - `KoichiSasada.vscode-rdbg` - Ruby デバッガー
  - `castwide.solargraph` - Ruby Language Server

## セットアップ

### 1. 開発用イメージをビルド（初回のみ）

```bash
UID=$(id -u) GID=$(id -g) docker-compose -f docker-compose.dev.yml build
```

> **Note**: `UID`/`GID` を指定することで、コンテナ内のユーザー ID がホストと一致し、マウントされたソースコードの権限問題を回避できます。

### 2. コンテナを起動

```bash
docker-compose -f docker-compose.dev.yml up -d
```

### 3. VS Code でコンテナにアタッチ

1. `Cmd+Shift+P` → `Dev Containers: Attach to Running Container...`
2. `/msf-dev` を選択
3. 新しい VS Code ウィンドウが開く
4. `File` → `Open Folder` → `/usr/src/metasploit-framework`

### 4. デバッグ開始

1. デバッグしたいファイルにブレークポイントを設定
2. `Cmd+Shift+P` → `Tasks: Run Task` → `msfconsole (debug)` を実行
3. ターミナルに `DEBUGGER: Debugger can attach via TCP/IP (127.0.0.1:38697)` が表示されたら準備完了
4. `F5` → `Attach: msfconsole` を選択

| 場所 | 操作 |
|------|------|
| Terminal | msfconsole コマンド入力 |
| Debug Console | デバッガー操作（変数確認等） |

## タスク

`Cmd+Shift+P` → `Tasks: Run Task` から実行:

| タスク | 説明 |
|-------|------|
| `msfconsole` | msfconsole を起動 |
| `msfconsole (debug)` | デバッガー付きで起動（その後 `F5` でアタッチ） |
| `msfconsole (with resource)` | リソースファイル指定で起動 |
| `rspec` | 現在のファイルのテストを実行 |

## コマンド

```bash
# コンテナ起動
docker-compose -f docker-compose.dev.yml up -d

# コンテナ停止
docker-compose -f docker-compose.dev.yml down

# ログ確認
docker-compose -f docker-compose.dev.yml logs -f

# イメージ再ビルド
UID=$(id -u) GID=$(id -g) docker-compose -f docker-compose.dev.yml build --no-cache
```

### stop / down / down -v の違い

| コマンド | コンテナ | Volume（データ） | 用途 |
|----------|----------|------------------|------|
| `stop` | 停止のみ | 残る | 一時的な停止、すぐ再開する場合 |
| `down` | 削除 | **残る** | 通常の停止（推奨） |
| `down -v` | 削除 | **削除** | クリーンな状態に戻したい場合 |

## トラブルシューティング

### データベース接続エラー

通常、コンテナ起動時に `config/database.yml` とデータベースが自動で作成されます。

手動で作成する場合:

```bash
rails db:create
```

