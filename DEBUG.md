# Metasploit Framework デバッグ環境構築ガイド

VS Code + Docker を使用して msfconsole をステップ実行デバッグする手順です。

## 前提条件

- Docker Desktop がインストールされていること
- VS Code がインストールされていること
- VS Code 拡張機能 `KoichiSasada.vscode-rdbg` がインストールされていること

## セットアップ手順

### 1. 開発用Dockerイメージをビルド

初回のみ実行します（10〜15分程度かかります）:

```bash
UID=$(id -u) GID=$(id -g) docker-compose -f docker-compose.dev.yml build
```

> **Note**: `UID`と`GID`を渡すことで、コンテナ内のユーザーIDがホストと一致し、ファイル権限の問題を回避できます。

### 2. コンテナを起動

```bash
docker-compose -f docker-compose.dev.yml up -d
```

起動確認:

```bash
docker-compose -f docker-compose.dev.yml ps
```

rdbgサーバーが起動しているか確認:

```bash
docker-compose -f docker-compose.dev.yml logs msf-dev
```

以下のメッセージが表示されれば成功です:

```
DEBUGGER: Debugger can attach via TCP/IP (0.0.0.0:38697)
DEBUGGER: wait for debugger connection...
```

### 3. VS Code でデバッグ開始

1. VS Code でプロジェクトを開く
2. 左サイドバーの「実行とデバッグ」アイコンをクリック（または `Cmd+Shift+D`）
3. ドロップダウンから「**Attach: msfconsole (Docker)**」を選択
4. 緑色の再生ボタンをクリック（または `F5`）

デバッガーがアタッチされると、msfconsole の実行が開始されます。

## ブレークポイントの設定

### VS Code でブレークポイントを設定

1. デバッグしたいRubyファイルを開く
2. 行番号の左側をクリックして赤い点を表示

### 推奨するブレークポイント設置場所

| ファイル | 説明 |
|---------|------|
| `msfconsole` | エントリポイント |
| `lib/metasploit/framework/command/console.rb` | コンソール起動処理 |
| `lib/msf/ui/console/driver.rb` | コンソールドライバー |
| `lib/msf/core/module_manager.rb` | モジュールロード処理 |

### コード内でブレークポイントを追加

```ruby
require 'debug'
binding.break  # ここで実行が停止します
```

## デバッグ構成一覧

| 構成名 | 説明 |
|-------|------|
| `Attach: msfconsole (Docker)` | Dockerコンテナにアタッチしてデバッグ |
| `Launch: msfconsole (Local)` | ローカル環境で直接起動してデバッグ |
| `Debug: Current Ruby File` | 現在開いているファイルをデバッグ |
| `Debug: RSpec Current File` | RSpecテストをデバッグ |
| `Docker + Attach` | コンテナ起動とアタッチを連続実行 |

## よく使うコマンド

### コンテナの操作

```bash
# コンテナを起動
docker-compose -f docker-compose.dev.yml up -d

# コンテナを停止
docker-compose -f docker-compose.dev.yml down

# ログを確認
docker-compose -f docker-compose.dev.yml logs -f msf-dev

# コンテナに入る
docker-compose -f docker-compose.dev.yml exec msf-dev bash

# イメージを再ビルド（Gemfile変更時など）
UID=$(id -u) GID=$(id -g) docker-compose -f docker-compose.dev.yml build --no-cache
```

> **Tip**: 毎回`UID`/`GID`を指定するのが面倒な場合は、`.env`ファイルを作成してください:
> ```bash
> echo "UID=$(id -u)" >> .env
> echo "GID=$(id -g)" >> .env
> ```

### VS Code タスク

`Cmd+Shift+P` → `Tasks: Run Task` から以下のタスクを実行できます:

- `docker-compose-up-dev` - コンテナ起動
- `docker-compose-down-dev` - コンテナ停止
- `docker-compose-build-dev` - イメージ再ビルド
- `docker-compose-logs` - ログ表示
- `docker-exec-bash` - コンテナにシェル接続

## トラブルシューティング

### ポート競合エラー

```
Bind for 0.0.0.0:4444 failed: port is already allocated
```

他のプロセスがポート4444を使用しています:

```bash
# 使用中のプロセスを確認
lsof -i :4444

# コンテナを停止して再起動
docker-compose -f docker-compose.dev.yml down
docker-compose -f docker-compose.dev.yml up -d
```

### デバッガーに接続できない

1. コンテナが起動しているか確認:
   ```bash
   docker-compose -f docker-compose.dev.yml ps
   ```

2. rdbgサーバーが起動しているか確認:
   ```bash
   docker-compose -f docker-compose.dev.yml logs msf-dev | grep DEBUGGER
   ```

3. ポート38697が開いているか確認:
   ```bash
   lsof -i :38697
   ```

### bundle install が必要な場合

```bash
docker-compose -f docker-compose.dev.yml exec msf-dev bundle install
```

## ファイル構成

```
metasploit-framework/
├── Dockerfile.dev              # 開発用Dockerfile
├── docker-compose.dev.yml      # 開発用compose設定
├── docker/
│   └── entrypoint.dev.sh       # 開発用エントリポイント
├── .vscode/
│   ├── launch.json             # デバッグ設定
│   └── tasks.json              # タスク定義
└── .devcontainer/
    └── devcontainer.json       # Dev Container設定
```

## 公開ポート

| ポート | 用途 |
|-------|------|
| 4444 | リバースシェル用リスナー |
| 38697 | rdbg デバッガー接続用 |
