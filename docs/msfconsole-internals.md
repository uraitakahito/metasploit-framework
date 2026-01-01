# msfconsole 内部動作

msfconsoleの起動からメインループ（REPL）までの処理フローを示すシーケンス図です。

## 起動シーケンス図

```mermaid
sequenceDiagram
    autonumber
    participant msfconsole as msfconsole
    participant Base as Command::Base
    participant Console as Command::Console
    participant Driver as Console::Driver
    participant DispatcherShell as Rex::Ui::Text::DispatcherShell
    participant Shell as Rex::Ui::Text::Shell
    participant SimpleFramework as Simple::Framework
    participant Framework as Msf::Framework
    participant EventDispatcher as EventDispatcher

    Note over msfconsole,Console: エントリーポイント
    msfconsole->>+Base: Console.start
    activate Base
    Base->>Base: require_environment!
    Base->>+Console: new
    Console-->>-Base: instance
    Base->>+Console: start

    Note over Console,Driver: Console#start
    Console->>Console: Tip表示、スピナー
    Console->>+Driver: Driver.new

    Note over Driver,Shell: Driver#initialize（継承チェーン）
    Driver->>+DispatcherShell: super
    DispatcherShell->>+Shell: super
    Shell-->>-DispatcherShell: initialized
    DispatcherShell-->>-Driver: initialized

    Note over Driver,EventDispatcher: Phase 1: Framework初期化
    Driver->>+SimpleFramework: create
    SimpleFramework->>+Framework: Framework.new
    Framework->>+EventDispatcher: EventDispatcher.new
    EventDispatcher-->>-Framework: dispatcher
    Framework->>EventDispatcher: add_exploit_subscriber
    Framework->>EventDispatcher: add_session_subscriber
    Framework->>EventDispatcher: add_general_subscriber
    Framework->>EventDispatcher: add_db_subscriber
    Framework->>EventDispatcher: add_ui_subscriber
    Framework-->>-SimpleFramework: framework
    SimpleFramework-->>-Driver: framework

    Note over Driver,Core: Phase 2: UI/Dispatcher初期化
    Driver->>+Core: enstack_dispatcher(Core)
    Core-->>-Driver: registered
    Note over Driver: Modules, Jobs, Resource,<br/>Db, Creds, Developer, DNS<br/>も同様に登録
    Driver-->>-Console: driver ready

    Console->>+Driver: run

    Note over Driver,DispatcherShell: Phase 3: on_startup
    Driver->>Driver: on_startup
    Driver->>EventDispatcher: on_ui_start(revision)
    Driver->>+DispatcherShell: run_single("banner")
    DispatcherShell->>+DispatcherShell: run_command(dispatcher, method, arguments)
    Note over DispatcherShell: bannerを表示する
    deactivate DispatcherShell
    DispatcherShell-->>-Driver: completed

    Note over Driver,Shell: Phase 4: REPLへ移行
    Driver->>+DispatcherShell: run
    DispatcherShell->>+Shell: run (継承)
    Note over Shell: メインループ開始
```

## コマンド実行例: workspace -a msftest

`workspace -a msftest` コマンドを入力した時の具体的な処理フローを示すシーケンス図です。

```mermaid
sequenceDiagram
    autonumber
    participant User as User
    participant Shell as Rex::Ui::Text::Shell
    participant DispatcherShell as Rex::Ui::Text::DispatcherShell
    participant DbDispatcher as CommandDispatcher::Db
    participant DataProxy as DataProxy
    participant WorkspaceProxy as WorkspaceDataProxy
    participant DBManager as DBManager::Workspace
    participant Mdm as Mdm::Workspace
    participant PG as PostgreSQL
    participant EventDispatcher as EventDispatcher

    activate Shell
    Shell->>Shell: with_history_manager_context

    Shell->>Shell: init_tab_complete
    Shell->>Shell: update_prompt
    Shell-->>User: msf >

    User->>+Shell: workspace -a msftest
    Shell->>Shell: get_input_line

    Note over Shell,DispatcherShell: コマンド解析・ディスパッチ
    Shell->>+DispatcherShell: run_single("workspace -a msftest")
    DispatcherShell->>Shell: parse_line("workspace -a msftest")
    Note right of Shell: Rex::Parser::Arguments.from_s<br/>でパースし配列を返す
    Shell-->>DispatcherShell: ["workspace", "-a", "msftest"]
    DispatcherShell->>DispatcherShell: method = arguments.shift
    Note right of DispatcherShell: method = "workspace"<br/>arguments = ["-a", "msftest"]
    DispatcherShell->>+DispatcherShell: run_command(Db, "workspace", ["-a", "msftest"])

    Note over DispatcherShell,DbDispatcher: Dbディスパッチャーで処理
    DispatcherShell->>+DbDispatcher: cmd_workspace("-a", "msftest")
    DbDispatcher->>DbDispatcher: @@workspace_opts.parse(args)
    Note right of DbDispatcher: state = :adding<br/>names = ["msftest"]

    Note over DbDispatcher,PG: 既存ワークスペースの確認
    DbDispatcher->>+DataProxy: framework.db.workspaces(name: "msftest")
    DataProxy->>+WorkspaceProxy: workspaces(name: "msftest")
    WorkspaceProxy->>WorkspaceProxy: data_service_operation
    WorkspaceProxy->>+DBManager: workspaces(name: "msftest")
    DBManager->>+Mdm: where(name: "msftest")
    Mdm->>+PG: SELECT * FROM workspaces WHERE name = 'msftest'
    PG-->>-Mdm: [] (空)
    Mdm-->>-DBManager: nil
    DBManager-->>-WorkspaceProxy: nil
    WorkspaceProxy-->>-DataProxy: nil
    DataProxy-->>-DbDispatcher: nil

    Note over DbDispatcher,PG: 新規ワークスペース作成
    DbDispatcher->>+DataProxy: framework.db.add_workspace("msftest")
    DataProxy->>+WorkspaceProxy: add_workspace("msftest")
    WorkspaceProxy->>WorkspaceProxy: data_service_operation
    WorkspaceProxy->>+DBManager: add_workspace(name: "msftest")
    DBManager->>+Mdm: where(name: "msftest").first_or_create
    Mdm->>+PG: INSERT INTO workspaces (name) VALUES ('msftest')
    PG-->>-Mdm: OK
    Mdm-->>-DBManager: Mdm::Workspace instance
    DBManager-->>-WorkspaceProxy: wspace
    WorkspaceProxy-->>-DataProxy: wspace
    DataProxy-->>-DbDispatcher: wspace

    Note over DbDispatcher,WorkspaceProxy: 現在のワークスペースに設定
    DbDispatcher->>+DataProxy: framework.db.workspace = wspace
    DataProxy->>+WorkspaceProxy: workspace=(wspace)
    WorkspaceProxy->>WorkspaceProxy: @current_workspace = wspace
    WorkspaceProxy-->>-DataProxy: set
    DataProxy-->>-DbDispatcher: set

    DbDispatcher->>DbDispatcher: print_status("Added workspace: msftest")
    DbDispatcher->>DbDispatcher: print_status("Workspace: msftest")
    DbDispatcher-->>-DispatcherShell: completed
    deactivate DispatcherShell

    Note over DispatcherShell,EventDispatcher: イベント記録
    DispatcherShell->>+EventDispatcher: on_ui_command("workspace -a msftest")
    EventDispatcher->>EventDispatcher: notify subscribers
    EventDispatcher-->>-DispatcherShell: notified

    DispatcherShell-->>-Shell: completed
    deactivate Shell
```

### 処理の流れ

1. **コマンド解析**: `DispatcherShell` が入力を解析し、`Db` ディスパッチャーの `cmd_workspace` を呼び出す
2. **オプション解析**: `@@workspace_opts.parse` で `-a` オプションを検出し `state = :adding` に設定
3. **既存確認**: `framework.db.workspaces(name: "msftest")` で既存ワークスペースを検索
4. **Proxyチェーン**: `DataProxy` → `WorkspaceDataProxy` → `DBManager::Workspace` → `Mdm::Workspace`
5. **DB操作**: `Mdm::Workspace.where(name: opts[:name]).first_or_create` で新規作成
6. **状態更新**: `WorkspaceDataProxy` の `@current_workspace` に新しいワークスペースを設定
7. **イベント記録**: `EventDispatcher` 経由でコマンド実行をDBに記録

### 関連ソース

- [cmd_workspace](../lib/msf/ui/console/command_dispatcher/db.rb#L113) - workspaceコマンドの実装
- [WorkspaceDataProxy](../lib/metasploit/framework/data_service/proxy/workspace_data_proxy.rb) - Proxyレイヤー
- [DBManager::Workspace#add_workspace](../lib/msf/core/db_manager/workspace.rb#L7) - ワークスペース追加

## コマンド実行例: db_nmap -F 192.168.10.109

`db_nmap -F 192.168.10.109` コマンドを入力した時の処理フローを示すシーケンス図です。`db_nmap` はnmapを実行し、結果をデータベースにインポートします。

```mermaid
sequenceDiagram
    autonumber
    participant User as User
    participant Shell as Rex::Ui::Text::Shell
    participant DispatcherShell as Rex::Ui::Text::DispatcherShell
    participant DbDispatcher as CommandDispatcher::Db
    participant FileUtils as Rex::FileUtils
    participant Quickfile as Rex::Quickfile
    participant Open3 as Open3
    participant Nmap as nmap (OS)
    participant DataProxy as DataProxy
    participant NmapProxy as NmapDataProxy
    participant DBManager as DBManager::Import::Nmap
    participant Mdm as Mdm::Host/Service
    participant PG as PostgreSQL
    participant EventDispatcher as EventDispatcher

    activate Shell
    Shell->>Shell: with_history_manager_context

    Shell->>Shell: init_tab_complete
    Shell->>Shell: update_prompt
    Shell-->>User: msf >

    User->>+Shell: db_nmap -F 192.168.10.109
    Shell->>Shell: get_input_line

    Note over Shell,DispatcherShell: コマンド解析・ディスパッチ
    Shell->>+DispatcherShell: run_single("db_nmap -F 192.168.10.109")
    DispatcherShell->>Shell: parse_line("db_nmap -F 192.168.10.109")
    Shell-->>DispatcherShell: ["db_nmap", "-F", "192.168.10.109"]
    DispatcherShell->>DispatcherShell: method = arguments.shift
    Note right of DispatcherShell: method = "db_nmap"<br/>arguments = ["-F", "192.168.10.109"]
    DispatcherShell->>+DispatcherShell: run_command(Db, "db_nmap", ["-F", "192.168.10.109"])

    Note over DispatcherShell,DbDispatcher: Dbディスパッチャーで処理
    DispatcherShell->>+DbDispatcher: cmd_db_nmap("-F", "192.168.10.109")

    Note over DbDispatcher,FileUtils: Phase 1: 前処理
    DbDispatcher->>DbDispatcher: active?
    Note right of DbDispatcher: DB接続を確認
    DbDispatcher->>+FileUtils: find_full_path("nmap")
    FileUtils-->>-DbDispatcher: "/usr/bin/nmap"

    Note over DbDispatcher,Quickfile: Phase 2: 一時ファイル作成
    DbDispatcher->>+Quickfile: new(['msf-db-nmap-', '.xml'])
    Quickfile-->>-DbDispatcher: fd (一時ファイル)
    DbDispatcher->>DbDispatcher: arguments.push('-oX', fd.path)
    Note right of DbDispatcher: arguments = ["-F", "192.168.10.109", "-oX", "/tmp/msf-db-nmap-xxx.xml"]

    Note over DbDispatcher,Nmap: Phase 3: nmap実行
    DbDispatcher->>DbDispatcher: run_nmap(nmap, arguments)
    DbDispatcher->>+Open3: popen3("nmap", "-F", "192.168.10.109", "-oX", path)
    Open3->>+Nmap: 実行
    Note right of Nmap: 高速スキャン(-F)を実行<br/>結果をXMLファイルに出力

    DbDispatcher->>DbDispatcher: framework.threads.spawn("db_nmap-Stdout")
    DbDispatcher->>DbDispatcher: framework.threads.spawn("db_nmap-Stderr")
    Note right of DbDispatcher: 標準出力/エラー出力を<br/>別スレッドで監視

    loop 各行の出力
        Nmap-->>DbDispatcher: stdout/stderr
        DbDispatcher->>DbDispatcher: print_status("Nmap: ...")
    end

    Nmap-->>-Open3: 終了 (exit 0)
    Open3-->>-DbDispatcher: 完了

    Note over DbDispatcher,PG: Phase 4: 結果をDBにインポート
    DbDispatcher->>+DataProxy: framework.db.import_nmap_xml_file(filename: fd.path)
    DataProxy->>+NmapProxy: import_nmap_xml_file(args)
    NmapProxy->>NmapProxy: data_service_operation
    NmapProxy->>NmapProxy: add_opts_workspace(args)
    NmapProxy->>+DBManager: import_nmap_xml_file(args)

    DBManager->>DBManager: File.open(filename, 'rb')
    DBManager->>DBManager: import_nmap_xml(data)
    Note right of DBManager: Nokogiri/StreamParserで<br/>XMLをパース

    loop 発見したホストごと
        DBManager->>DBManager: parser.on_found_host
        DBManager->>+Mdm: msf_import_host(data)
        Mdm->>+PG: INSERT INTO hosts (address, state, ...)
        PG-->>-Mdm: OK
        Mdm-->>-DBManager: hobj

        loop ホストの各ポート
            DBManager->>+Mdm: msf_import_service(data)
            Mdm->>+PG: INSERT INTO services (host_id, port, proto, state, name, ...)
            PG-->>-Mdm: OK
            Mdm-->>-DBManager: service
        end

        opt OS情報がある場合
            DBManager->>Mdm: msf_import_note(type: 'host.os.nmap_fingerprint')
        end
    end

    DBManager-->>-NmapProxy: インポート完了
    NmapProxy-->>-DataProxy: 完了
    DataProxy-->>-DbDispatcher: 完了

    Note over DbDispatcher,Quickfile: Phase 5: クリーンアップ
    DbDispatcher->>Quickfile: fd.close
    DbDispatcher->>Quickfile: fd.unlink
    Note right of Quickfile: 一時ファイルを削除<br/>(--save指定時は保持)

    DbDispatcher-->>-DispatcherShell: completed
    deactivate DispatcherShell

    Note over DispatcherShell,EventDispatcher: イベント記録
    DispatcherShell->>+EventDispatcher: on_ui_command("db_nmap -F 192.168.10.109")
    EventDispatcher->>EventDispatcher: notify subscribers
    EventDispatcher-->>-DispatcherShell: notified

    DispatcherShell-->>-Shell: completed
    deactivate Shell
```

### 処理の流れ

1. **コマンド解析**: `DispatcherShell` が入力を解析し、`Db` ディスパッチャーの `cmd_db_nmap` を呼び出す
2. **DB接続確認**: `active?` でデータベース接続を確認
3. **nmapパス検索**: `Rex::FileUtils.find_full_path("nmap")` でnmap実行ファイルを検索
4. **一時ファイル作成**: `Rex::Quickfile.new` でXML出力用の一時ファイルを作成
5. **引数構築**: `-oX /tmp/msf-db-nmap-xxx.xml` を引数に追加
6. **nmap実行**: `Open3.popen3` でnmapを子プロセスとして実行、stdout/stderrを別スレッドで監視
7. **XMLインポート**: `framework.db.import_nmap_xml_file` でスキャン結果をDBにインポート
8. **Proxyチェーン**: `DataProxy` → `NmapDataProxy` → `DBManager::Import::Nmap`
9. **XMLパース**: Nokogiri/StreamParserでXMLをパースし、ホスト・サービス情報を抽出
10. **ホスト登録**: `msf_import_host` で発見したホストを `hosts` テーブルに登録
11. **サービス登録**: `msf_import_service` で各ポートを `services` テーブルに登録
12. **クリーンアップ**: 一時ファイルを削除（`--save` 指定時は保持）
13. **イベント記録**: `EventDispatcher` 経由でコマンド実行をDBに記録

### -F オプション（高速スキャン）

`-F` は nmap の「Fast scan」オプションで、スキャン対象のポート数を削減して高速化します。

| モード | スキャン対象ポート数 | 説明 |
|--------|---------------------|------|
| デフォルト | 上位 1,000 ポート | `nmap 192.168.10.109` |
| `-F` | 上位 100 ポート | `nmap -F 192.168.10.109` |

### nmap実行時の特殊処理

- **root権限エスカレーション**: stderrに "requires root privileges" が含まれる場合、自動的に `sudo` 付きで再実行
- **Cygwin対応**: Cygwin環境ではパスをWin32形式に変換

## コマンド実行例: use auxiliary/scanner/ssh/ssh_version

`use auxiliary/scanner/ssh/ssh_version` コマンドを入力した時の処理フローを示すシーケンス図です。`use` コマンドはモジュールをロードし、モジュール専用のコマンドディスパッチャーをスタックに追加します。

```mermaid
sequenceDiagram
    autonumber
    participant User as User
    participant Shell as Rex::Ui::Text::Shell
    participant DispatcherShell as Rex::Ui::Text::DispatcherShell
    participant ModulesDispatcher as CommandDispatcher::Modules
    participant ModuleManager as Msf::ModuleManager
    participant ModuleSet as Msf::ModuleSet (auxiliary)
    participant Module as MetasploitModule
    participant Driver as Console::Driver
    participant AuxDispatcher as CommandDispatcher::Auxiliary
    participant EventDispatcher as EventDispatcher

    activate Shell
    Shell->>Shell: with_history_manager_context

    Shell->>Shell: init_tab_complete
    Shell->>Shell: update_prompt
    Shell-->>User: msf >

    User->>+Shell: use auxiliary/scanner/ssh/ssh_version
    Shell->>Shell: get_input_line

    Note over Shell,DispatcherShell: コマンド解析・ディスパッチ
    Shell->>+DispatcherShell: run_single("use auxiliary/scanner/ssh/ssh_version")
    DispatcherShell->>Shell: parse_line(...)
    Shell-->>DispatcherShell: ["use", "auxiliary/scanner/ssh/ssh_version"]
    DispatcherShell->>DispatcherShell: method = arguments.shift
    Note right of DispatcherShell: method = "use"<br/>arguments = ["auxiliary/scanner/ssh/ssh_version"]
    DispatcherShell->>+DispatcherShell: run_command(Modules, "use", [...])

    Note over DispatcherShell,ModulesDispatcher: Modulesディスパッチャーで処理
    DispatcherShell->>+ModulesDispatcher: cmd_use("auxiliary/scanner/ssh/ssh_version")

    Note over ModulesDispatcher,Module: Phase 1: モジュール名の解決とインスタンス生成
    ModulesDispatcher->>+ModuleManager: framework.modules.create("auxiliary/scanner/ssh/ssh_version")

    ModuleManager->>ModuleManager: エイリアスチェック
    ModuleManager->>ModuleManager: タイプ判定 ("auxiliary" → MODULE_AUX)
    Note right of ModuleManager: names = ["auxiliary", "scanner", "ssh", "ssh_version"]<br/>type = "auxiliary"

    ModuleManager->>+ModuleSet: module_set_by_type["auxiliary"]
    ModuleSet->>ModuleSet: create("scanner/ssh/ssh_version")
    ModuleSet->>+Module: MetasploitModule.new
    Note right of Module: initialize() 実行<br/>- Name, Description設定<br/>- register_options([RPORT, TIMEOUT, ...])
    Module-->>-ModuleSet: mod instance
    ModuleSet-->>-ModuleManager: mod
    ModuleManager-->>-ModulesDispatcher: mod

    Note over ModulesDispatcher,AuxDispatcher: Phase 2: ディスパッチャーの選択
    ModulesDispatcher->>ModulesDispatcher: mod.type を判定
    Note right of ModulesDispatcher: MODULE_AUX → Auxiliary ディスパッチャー

    Note over ModulesDispatcher,Driver: Phase 3: 既存モジュールの退避（あれば）
    alt active_module が存在する場合
        ModulesDispatcher->>ModulesDispatcher: @previous_module = active_module
        ModulesDispatcher->>ModulesDispatcher: cmd_back()
        Note right of ModulesDispatcher: DataStoreをキャッシュ<br/>@dscache[fullname] = datastore.dup
    end

    Note over ModulesDispatcher,AuxDispatcher: Phase 4: 新ディスパッチャーをスタック
    ModulesDispatcher->>+Driver: driver.enstack_dispatcher(Auxiliary)
    Driver->>Driver: dispatcher_stack.push(Auxiliary)
    Driver-->>-ModulesDispatcher: registered
    Note right of Driver: Auxiliaryディスパッチャー追加<br/>run, reload, rerun等が使用可能に

    Note over ModulesDispatcher,Module: Phase 5: アクティブモジュールの設定
    ModulesDispatcher->>ModulesDispatcher: self.active_module = mod

    Note over ModulesDispatcher,Module: Phase 6: DataStoreキャッシュの復元
    alt @dscache[fullname] が存在する場合
        ModulesDispatcher->>Module: active_module.datastore.update(@dscache[...])
        Note right of Module: 以前設定したRHOSTS等を復元
    end

    Note over ModulesDispatcher,Module: Phase 7: UIの初期化
    ModulesDispatcher->>Module: mod.init_ui(driver.input, driver.output)

    ModulesDispatcher-->>-DispatcherShell: completed
    deactivate DispatcherShell

    Note over DispatcherShell,EventDispatcher: イベント記録
    DispatcherShell->>+EventDispatcher: on_ui_command("use auxiliary/scanner/ssh/ssh_version")
    EventDispatcher->>EventDispatcher: notify subscribers
    EventDispatcher-->>-DispatcherShell: notified

    DispatcherShell-->>-Shell: completed

    Note over Shell,User: プロンプト変更
    Shell->>Shell: update_prompt
    Shell-->>User: msf auxiliary(scanner/ssh/ssh_version) >
    deactivate Shell
```

### 処理の流れ

1. **コマンド解析**: `DispatcherShell` が入力を解析し、`Modules` ディスパッチャーの `cmd_use` を呼び出す
2. **モジュールインスタンス生成**: [`ModuleManager#create`](../lib/msf/core/module_manager.rb#L51) が以下を実行:
   - エイリアステーブルをチェック
   - タイプを判定（"auxiliary" → `MODULE_AUX`）
   - 該当する `ModuleSet` から `create` を呼び出し
   - `MetasploitModule` クラスをインスタンス化
3. **ディスパッチャー選択**: モジュールタイプに応じて `Auxiliary` ディスパッチャーを選択
4. **既存モジュールの退避**: アクティブモジュールがあれば `@previous_module` に保存し、DataStoreをキャッシュ
5. **ディスパッチャーのスタック**: `driver.enstack_dispatcher(Auxiliary)` で専用コマンドを追加
6. **アクティブモジュール設定**: `self.active_module = mod`
7. **DataStore復元**: 以前使用時のオプション設定を復元
8. **UI初期化**: モジュールに入出力を接続
9. **プロンプト更新**: `msf auxiliary(scanner/ssh/ssh_version) >` に変更

### ディスパッチャースタックの変化

```
use 実行前:                      use 実行後:
┌─────────────────┐             ┌─────────────────┐
│ Modules         │             │ Auxiliary       │ ← 新規追加
├─────────────────┤             ├─────────────────┤
│ Core            │             │ Modules         │
├─────────────────┤             ├─────────────────┤
│ Db, Creds, etc. │             │ Core            │
└─────────────────┘             ├─────────────────┤
                                │ Db, Creds, etc. │
                                └─────────────────┘
```

### Auxiliaryディスパッチャーで追加されるコマンド

| コマンド | 説明 |
|---------|------|
| `run` | モジュールを実行 |
| `exploit` | `run` のエイリアス |
| `reload` | モジュールをリロード |
| `rerun` | リロードして実行 |
| `rexploit` | `rerun` のエイリアス |
| `rcheck` | リロードしてチェック |

### DataStoreキャッシュの仕組み

```ruby
# back時: オプションをキャッシュ
@dscache[active_module.fullname] = active_module.datastore.dup

# use時: キャッシュからオプションを復元
if @dscache[active_module.fullname]
  active_module.datastore.update(@dscache[active_module.fullname])
end
```

→ 一度設定した `RHOSTS`, `RPORT` 等は `back` → `use` しても保持される

### 関連ソース

- [cmd_use](../lib/msf/ui/console/command_dispatcher/modules.rb#L786) - useコマンドの実装
- [cmd_back](../lib/msf/ui/console/command_dispatcher/modules.rb#L1122) - backコマンドの実装
- [cmd_previous](../lib/msf/ui/console/command_dispatcher/modules.rb#L921) - previousコマンドの実装
- [ModuleManager#create](../lib/msf/core/module_manager.rb#L51) - モジュールインスタンス生成
- [Auxiliary dispatcher](../lib/msf/ui/console/command_dispatcher/auxiliary.rb) - Auxiliary専用コマンド
- [ssh_version.rb](../modules/auxiliary/scanner/ssh/ssh_version.rb) - モジュール本体

## コマンド実行例: services -u -p 22 -R（use auxiliary/scanner/ssh/ssh_version の後）

前節の `use auxiliary/scanner/ssh/ssh_version` を実行した後に `services -u -p 22 -R` コマンドを入力した時の処理フローを示すシーケンス図です。このコマンドは、データベースからポート22でUP状態のサービスを検索し、結果をアクティブモジュールの `RHOSTS` オプションに設定します。

```mermaid
sequenceDiagram
    autonumber
    participant User as User
    participant Shell as Rex::Ui::Text::Shell
    participant DispatcherShell as Rex::Ui::Text::DispatcherShell
    participant DbDispatcher as CommandDispatcher::Db
    participant DataProxy as DataProxy
    participant ServiceProxy as ServiceDataProxy
    participant DBManager as DBManager::Service
    participant Mdm as Mdm::Service
    participant PG as PostgreSQL
    participant Common as CommandDispatcher::Common
    participant Module as active_module
    participant EventDispatcher as EventDispatcher

    activate Shell
    Shell->>Shell: with_history_manager_context

    Shell->>Shell: init_tab_complete
    Shell->>Shell: update_prompt
    Shell-->>User: msf auxiliary(scanner/ssh/ssh_version) >

    User->>+Shell: services -u -p 22 -R
    Shell->>Shell: get_input_line

    Note over Shell,DispatcherShell: コマンド解析・ディスパッチ
    Shell->>+DispatcherShell: run_single("services -u -p 22 -R")
    DispatcherShell->>Shell: parse_line("services -u -p 22 -R")
    Shell-->>DispatcherShell: ["services", "-u", "-p", "22", "-R"]
    DispatcherShell->>DispatcherShell: method = arguments.shift
    Note right of DispatcherShell: method = "services"<br/>arguments = ["-u", "-p", "22", "-R"]
    DispatcherShell->>+DispatcherShell: run_command(Db, "services", [...])

    Note over DispatcherShell,DbDispatcher: Dbディスパッチャーで処理
    DispatcherShell->>+DbDispatcher: cmd_services("-u", "-p", "22", "-R")

    Note over DbDispatcher: Phase 1: オプション解析
    DbDispatcher->>DbDispatcher: @@services_opts.parse(args)
    Note right of DbDispatcher: onlyup = true (-u)<br/>port_ranges = [22] (-p 22)<br/>set_rhosts = true (-R)

    Note over DbDispatcher,PG: Phase 2: サービス検索
    DbDispatcher->>+DataProxy: framework.db.services(opts)
    DataProxy->>+ServiceProxy: services(opts)
    ServiceProxy->>ServiceProxy: data_service_operation
    ServiceProxy->>+DBManager: services(opts)
    DBManager->>+Mdm: where(port: 22).joins(:host)
    Mdm->>+PG: SELECT services.*, hosts.address<br/>FROM services<br/>JOIN hosts ON services.host_id = hosts.id<br/>WHERE port = 22
    PG-->>-Mdm: [service1, service2, ...]
    Mdm-->>-DBManager: services
    DBManager-->>-ServiceProxy: services
    ServiceProxy-->>-DataProxy: services
    DataProxy-->>-DbDispatcher: services

    Note over DbDispatcher: Phase 3: 結果のフィルタリング
    loop 各サービス
        DbDispatcher->>DbDispatcher: service.state == 'open' ?
        alt state == 'open'
            DbDispatcher->>DbDispatcher: rhosts << host.address
            DbDispatcher->>DbDispatcher: tbl << columns
        else onlyup == true && state != 'open'
            Note right of DbDispatcher: スキップ
        end
    end

    Note over DbDispatcher: Phase 4: テーブル表示
    DbDispatcher->>DbDispatcher: print_line(tbl.to_s)

    Note over DbDispatcher,Module: Phase 5: RHOSTS設定
    DbDispatcher->>+Common: set_rhosts_from_addrs(rhosts.uniq)
    Common->>Common: active_module ?
    Note right of Common: active_module が存在するので<br/>モジュールの datastore を使用

    alt rhosts.length > 5
        Common->>Common: Rex::Quickfile.new("msf-db-rhosts-")
        Common->>Module: datastore['RHOSTS'] = 'file:' + path
        Note right of Common: ホストが多い場合は<br/>一時ファイルに保存
    else rhosts.length <= 5
        Common->>Module: datastore['RHOSTS'] = rhosts.join(" ")
        Note right of Common: 少ない場合は<br/>直接スペース区切りで設定
    end

    Common->>Common: print_line("RHOSTS => #{rhosts}")
    Common-->>-DbDispatcher: completed

    DbDispatcher-->>-DispatcherShell: completed
    deactivate DispatcherShell

    Note over DispatcherShell,EventDispatcher: イベント記録
    DispatcherShell->>+EventDispatcher: on_ui_command("services -u -p 22 -R")
    EventDispatcher->>EventDispatcher: notify subscribers
    EventDispatcher-->>-DispatcherShell: notified

    DispatcherShell-->>-Shell: completed

    Shell->>Shell: update_prompt
    Shell-->>User: msf auxiliary(scanner/ssh/ssh_version) >
    deactivate Shell
```

### 処理の流れ

1. **コマンド解析**: [`DispatcherShell`](../lib/rex/ui/text/dispatcher_shell.rb#L513) が入力を解析し、`Db` ディスパッチャーの [`cmd_services`](../lib/msf/ui/console/command_dispatcher/db.rb#L842) を呼び出す
2. **オプション解析**: `@@services_opts.parse` でオプションを解析:
   - `-u`: `onlyup = true`（UP状態のみ）
   - `-p 22`: `port_ranges = [22]`（ポート22）
   - `-R`: `set_rhosts = true`（RHOSTSに設定）
3. **Proxyチェーン**: `DataProxy` → `ServiceDataProxy` → `DBManager::Service` → `Mdm::Service`
4. **DB検索**: `services` テーブルからポート22のサービスを検索
5. **フィルタリング**: `onlyup = true` なので `state == 'open'` のサービスのみ抽出
6. **テーブル表示**: 検索結果をテーブル形式で表示
7. **RHOSTS設定**: [`set_rhosts_from_addrs`](../lib/msf/ui/console/command_dispatcher/common.rb#L72) でアクティブモジュールの `datastore['RHOSTS']` に設定
8. **イベント記録**: `EventDispatcher` 経由でコマンド実行をDBに記録

### オプションの説明

| オプション | 説明 |
|-----------|------|
| `-u` | UP状態（`state == 'open'`）のサービスのみ表示 |
| `-p 22` | ポート22のサービスのみ表示 |
| `-R` | 検索結果のホストアドレスをRHOSTSに設定 |

### RHOSTS設定の分岐

```ruby
# lib/msf/ui/console/command_dispatcher/common.rb:72-99
def set_rhosts_from_addrs(rhosts)
  if active_module
    mydatastore = active_module.datastore  # モジュールのDataStore
  else
    mydatastore = self.framework.datastore  # グローバルDataStore
  end

  if rhosts.length > 5
    # ホストが多い場合はファイルに保存
    rhosts_file = Rex::Quickfile.new("msf-db-rhosts-")
    mydatastore['RHOSTS'] = 'file:' + rhosts_file.path
    rhosts_file.write(rhosts.join("\n") + "\n")
  else
    # 少ない場合は直接設定
    mydatastore['RHOSTS'] = rhosts.join(" ")
  end
end
```

### 実行例

```bash
msf auxiliary(scanner/ssh/ssh_version) > services -u -p 22 -R

Services
========

host            port  proto  name  state  info
----            ----  -----  ----  -----  ----
192.168.10.101  22    tcp    ssh   open   OpenSSH 8.2
192.168.10.102  22    tcp    ssh   open   OpenSSH 7.9
192.168.10.109  22    tcp    ssh   open   OpenSSH 8.4

RHOSTS => 192.168.10.101 192.168.10.102 192.168.10.109

msf auxiliary(scanner/ssh/ssh_version) > run
[*] 192.168.10.101:22 - SSH server version: SSH-2.0-OpenSSH_8.2 ...
```

### 関連ソース

- [cmd_services](../lib/msf/ui/console/command_dispatcher/db.rb#L842) - servicesコマンドの実装
- [set_rhosts_from_addrs](../lib/msf/ui/console/command_dispatcher/common.rb#L72) - RHOSTS設定
- [ServiceDataProxy](../lib/metasploit/framework/data_service/proxy/service_data_proxy.rb) - Proxyレイヤー
- [DBManager::Service#services](../lib/msf/core/db_manager/service.rb#L129) - サービス検索

## コマンド実行例: back（use auxiliary/scanner/ssh/ssh_version の後）

前節の `use auxiliary/scanner/ssh/ssh_version` を実行した後に `back` コマンドを入力した時の処理フローを示すシーケンス図です。`back` コマンドはモジュールコンテキストを抜けて、グローバルコンテキストに戻ります。

```mermaid
sequenceDiagram
    autonumber
    participant User as User
    participant Shell as Rex::Ui::Text::Shell
    participant DispatcherShell as Rex::Ui::Text::DispatcherShell
    participant ModulesDispatcher as CommandDispatcher::Modules
    participant Module as active_module
    participant Driver as Console::Driver
    participant EventDispatcher as EventDispatcher

    activate Shell
    Shell->>Shell: with_history_manager_context

    Shell->>Shell: init_tab_complete
    Shell->>Shell: update_prompt
    Shell-->>User: msf auxiliary(scanner/ssh/ssh_version) >

    User->>+Shell: back
    Shell->>Shell: get_input_line

    Note over Shell,DispatcherShell: コマンド解析・ディスパッチ
    Shell->>+DispatcherShell: run_single("back")
    DispatcherShell->>Shell: parse_line("back")
    Shell-->>DispatcherShell: ["back"]
    DispatcherShell->>DispatcherShell: method = arguments.shift
    Note right of DispatcherShell: method = "back"<br/>arguments = []
    DispatcherShell->>+DispatcherShell: run_command(Modules, "back", [])

    Note over DispatcherShell,ModulesDispatcher: Modulesディスパッチャーで処理
    DispatcherShell->>+ModulesDispatcher: cmd_back()

    Note over ModulesDispatcher,Driver: 前提条件チェック
    ModulesDispatcher->>ModulesDispatcher: dispatcher_stack.size > 1 ?
    ModulesDispatcher->>ModulesDispatcher: current_dispatcher.name != 'Core' ?
    ModulesDispatcher->>ModulesDispatcher: current_dispatcher.name != 'Database Backend' ?
    Note right of ModulesDispatcher: すべてtrue → 処理続行

    Note over ModulesDispatcher,Module: Phase 1: DataStoreのキャッシュ
    ModulesDispatcher->>+Module: active_module.fullname
    Module-->>-ModulesDispatcher: "auxiliary/scanner/ssh/ssh_version"
    ModulesDispatcher->>+Module: active_module.datastore.dup
    Module-->>-ModulesDispatcher: datastore copy
    ModulesDispatcher->>ModulesDispatcher: @dscache[fullname] = datastore
    Note right of ModulesDispatcher: RHOSTS, RPORT等の設定を保存<br/>次回use時に復元される

    Note over ModulesDispatcher,Module: Phase 2: アクティブモジュールの解除
    ModulesDispatcher->>ModulesDispatcher: self.active_module = nil

    Note over ModulesDispatcher,Driver: Phase 3: ディスパッチャーのデスタック
    ModulesDispatcher->>+Driver: driver.destack_dispatcher
    Driver->>Driver: dispatcher_stack.pop
    Note right of Driver: Auxiliaryディスパッチャーを除去<br/>run, reload等のコマンドが無効に
    Driver-->>-ModulesDispatcher: destacked

    ModulesDispatcher-->>-DispatcherShell: completed
    deactivate DispatcherShell

    Note over DispatcherShell,EventDispatcher: イベント記録
    DispatcherShell->>+EventDispatcher: on_ui_command("back")
    EventDispatcher->>EventDispatcher: notify subscribers
    EventDispatcher-->>-DispatcherShell: notified

    DispatcherShell-->>-Shell: completed

    Note over Shell,User: プロンプト変更
    Shell->>Shell: update_prompt
    Shell-->>User: msf >
    deactivate Shell
```

### 処理の流れ

1. **コマンド解析**: [`DispatcherShell`](../lib/rex/ui/text/dispatcher_shell.rb#L513) が入力を解析し、`Modules` ディスパッチャーの [`cmd_back`](../lib/msf/ui/console/command_dispatcher/modules.rb#L1122) を呼び出す
2. **前提条件チェック**: 以下をすべて確認:
   - `dispatcher_stack.size > 1` （スタックに複数のディスパッチャーがある）
   - `current_dispatcher.name != 'Core'` （Coreディスパッチャーではない）
   - `current_dispatcher.name != 'Database Backend'` （DBバックエンドではない）
3. **DataStoreのキャッシュ**: `@dscache[fullname]` にオプション設定を保存
4. **アクティブモジュールの解除**: `self.active_module = nil`
5. **ディスパッチャーのデスタック**: `driver.destack_dispatcher` でモジュール専用ディスパッチャーを除去
6. **イベント記録**: `EventDispatcher` 経由でコマンド実行をDBに記録
7. **プロンプト更新**: `msf >` に戻る

### ディスパッチャースタックの変化

```
back 実行前:               back 実行後:
┌─────────────────┐       ┌─────────────────┐
│ Auxiliary       │ ─────→│ Modules         │  ※ Auxiliary を除去
├─────────────────┤       ├─────────────────┤
│ Modules         │       │ Core            │
├─────────────────┤       ├─────────────────┤
│ Core            │       │ Db, Creds, etc. │
├─────────────────┤       └─────────────────┘
│ Db, Creds, etc. │
└─────────────────┘
```

### DataStoreキャッシュの効果

```bash
msf > use auxiliary/scanner/ssh/ssh_version
msf auxiliary(scanner/ssh/ssh_version) > set RHOSTS 192.168.10.109
msf auxiliary(scanner/ssh/ssh_version) > set THREADS 10
msf auxiliary(scanner/ssh/ssh_version) > back
msf >
# ... 他の作業 ...
msf > use auxiliary/scanner/ssh/ssh_version
msf auxiliary(scanner/ssh/ssh_version) > show options
# → RHOSTS=192.168.10.109, THREADS=10 が復元されている
```

### backできない場合

以下の場合は `back` コマンドは何もしません:

- `dispatcher_stack.size == 1` （グローバルコンテキストにいる）
- `current_dispatcher.name == 'Core'` （Coreディスパッチャー）
- `current_dispatcher.name == 'Database Backend'` （DBバックエンド）

### 関連ソース

- [cmd_back](../lib/msf/ui/console/command_dispatcher/modules.rb#L1122) - backコマンドの実装
- [destack_dispatcher](../lib/rex/ui/text/dispatcher_shell.rb) - ディスパッチャー除去

## コマンド実行例: clear

`clear` コマンドを入力した時の処理フローを示すシーケンス図です。`clear` はMetasploit内部のコマンドではなく、システムコマンドとして実行されます。

```mermaid
sequenceDiagram
    autonumber
    participant User as User
    participant Shell as Rex::Ui::Text::Shell
    participant DispatcherShell as Rex::Ui::Text::DispatcherShell
    participant Driver as Console::Driver
    participant FileUtils as Rex::FileUtils
    participant OS as OS (system)
    participant EventDispatcher as EventDispatcher

    activate Shell
    Shell->>Shell: with_history_manager_context

    Shell->>Shell: init_tab_complete
    Shell->>Shell: update_prompt
    Shell-->>User: msf >

    User->>+Shell: clear
    Shell->>Shell: get_input_line

    Note over Shell,DispatcherShell: コマンド解析・ディスパッチ
    Shell->>+DispatcherShell: run_single("clear")
    DispatcherShell->>Shell: parse_line("clear")
    Shell-->>DispatcherShell: ["clear"]
    DispatcherShell->>DispatcherShell: method = arguments.shift
    Note right of DispatcherShell: method = "clear"<br/>arguments = []

    Note over DispatcherShell,Driver: 各ディスパッチャーを検索
    loop dispatcher_stack.each
        DispatcherShell->>DispatcherShell: dispatcher.commands.has_key?("clear")
        Note right of DispatcherShell: Core, Modules, Jobs,<br/>Resource, Db, Creds,<br/>Developer, DNS<br/>すべて該当なし
    end

    Note over DispatcherShell,Driver: unknown_command へフォールバック
    DispatcherShell->>+Driver: unknown_command("clear", "clear")

    Note over Driver,OS: システムコマンドの検索と実行
    Driver->>+FileUtils: find_full_path("clear")
    FileUtils-->>-Driver: "/usr/bin/clear"
    Note right of Driver: command_passthru == true<br/>かつパスが見つかった

    Driver->>+Driver: run_unknown_command("clear")
    Driver->>Driver: print_status("exec: clear")
    Driver->>+OS: system("clear")
    Note right of OS: 画面をクリア
    OS-->>-Driver: 0 (success)
    deactivate Driver
    Driver-->>-DispatcherShell: completed

    Note over DispatcherShell,EventDispatcher: イベント記録
    DispatcherShell->>+EventDispatcher: on_ui_command("clear")
    EventDispatcher->>EventDispatcher: notify subscribers
    EventDispatcher-->>-DispatcherShell: notified

    DispatcherShell-->>-Shell: completed
    deactivate Shell
```

### 処理の流れ

1. **コマンド解析**: `parse_line("clear")` で `["clear"]` に分解
2. **ディスパッチャー検索**: 全ディスパッチャー（Core, Modules, Jobs, Resource, Db, Creds, Developer, DNS）の `commands` をチェック → 該当なし
3. **unknown_command**: `Driver#unknown_command` が呼ばれる
4. **パス検索**: `Rex::FileUtils.find_full_path("clear")` でシステム上の `clear` コマンドを検索
5. **システムコマンド実行**: `system("clear")` で OS の clear コマンドを実行
6. **イベント記録**: `EventDispatcher` 経由でコマンド実行をDBに記録

### 関連ソース

- [Driver#unknown_command](../lib/msf/ui/console/driver.rb#L523) - 未知コマンドの処理
- [Driver#run_unknown_command](../lib/msf/ui/console/driver.rb#L555) - システムコマンド実行
- [Rex::FileUtils.find_full_path](../lib/rex/file_utils.rb) - コマンドパス検索

## 各フェーズの説明

### Phase 1: Framework初期化

- [EventDispatcher](../lib/msf/core/event_dispatcher.rb#L17)、[ModuleManager](../lib/msf/core/module_manager.rb#L17)、[DataStore](../lib/msf/core/data_store.rb#L10)等のコンポーネントを初期化

### Phase 2: UI/Dispatcher初期化

- シェル（入出力、プロンプト、タブ補完）を初期化
- コマンドディスパッチャーを登録（[driver.rb#L26](../lib/msf/ui/console/driver.rb#L26)）:
  1. [**Core**](../lib/msf/ui/console/command_dispatcher/core.rb) - 基本コマンド（`use`, `set`, `show`, `info`, `banner`等）
  2. [**Modules**](../lib/msf/ui/console/command_dispatcher/modules.rb) - モジュール管理（`search`, `reload`, `loadpath`等）
  3. [**Jobs**](../lib/msf/ui/console/command_dispatcher/jobs.rb) - ジョブ管理（`jobs`, `kill`等）
  4. [**Resource**](../lib/msf/ui/console/command_dispatcher/resource.rb) - リソーススクリプト（`resource`, `makerc`等）
  5. [**Db**](../lib/msf/ui/console/command_dispatcher/db.rb) - データベース操作（`workspace`, `db_status`, `hosts`, `services`, `vulns`等）
  6. [**Creds**](../lib/msf/ui/console/command_dispatcher/creds.rb) - 認証情報管理（`creds`等）
  7. [**Developer**](../lib/msf/ui/console/command_dispatcher/developer.rb) - 開発者向け（`edit`, `reload_lib`, `log`等）
  8. [**DNS**](../lib/msf/ui/console/command_dispatcher/dns.rb) - DNS設定（`dns`等）
- `framework.db`（[DataProxy](../lib/metasploit/framework/data_service/proxy/core.rb#L11)）に初回アクセスしDB接続をチェック

### Phase 3: Module/Configロード

- モジュールパスを初期化（`framework.init_module_paths`）
- 別スレッドでモジュールキャッシュを更新（`ModuleCacheRebuild`）
- コンソール設定をロード
- [`on_startup`](../lib/msf/ui/console/driver.rb#L364)処理:
  - モジュールロードエラー/警告の確認
  - ワークスペース設定
  - バナー表示（`run_single("banner")`）

**Banner表示**:

[`cmd_banner`](../lib/msf/ui/console/command_dispatcher/core.rb#L272):
- `run_single("banner")`により`Core`ディスパッチャーの`cmd_banner`が呼び出される
- [`Banner.to_s`](../lib/msf/ui/banner.rb#L39)でASCIIアートを取得
- `print_line(banner)`で出力

**起動後処理**:
- デフォルトリソーススクリプト（`~/.msf4/msfconsole.rc`）を実行
- 永続ハンドラーを復元
- 起動時コマンド（`-x`オプション）を実行

### Phase 4: メインループ (REPL)

[`Rex::Ui::Text::Shell#run`](../lib/rex/ui/text/shell.rb#L124)がRead-Eval-Print Loopを開始:

1. 履歴マネージャーコンテキストを設定
2. 無限ループ開始:
   - タブ補完を初期化
   - プロンプトを更新
   - ユーザー入力を待機（[`get_input_line`](../lib/rex/ui/text/shell.rb#L324)）
   - コマンドを実行（`run_single`）
3. `Ctrl+C`で中断した場合は継続
4. `quit`/`exit`またはEOFで終了

## イベント記録

msfconsoleの操作はデータベースの`events`テーブルに記録される。

### 記録されるイベント

| イベント名 | 発生タイミング |
|-----------|---------------|
| `ui_start` | msfconsole起動時 |
| `ui_stop` | msfconsole終了時 |
| `ui_command` | コマンド実行時 |
| `module_run` | モジュール実行開始 |
| `module_complete` | モジュール実行完了 |
| `module_error` | モジュールエラー |
| `session_open` | セッション確立時 |

### 処理の流れ

```mermaid
sequenceDiagram
    autonumber
    participant ED as EventDispatcher
    participant FES as FrameworkEventSubscriber
    participant DB as DBManager
    participant Mdm as Mdm::Event
    participant PG as PostgreSQL

    ED->>+FES: on_ui_command(command)
    FES->>FES: report_event(...)
    FES->>+DB: report_event(data)
    DB->>+Mdm: create(...)
    Mdm->>+PG: INSERT INTO events
    PG-->>-Mdm: OK
    Mdm-->>-DB: event record
    DB-->>-FES: reported
    FES-->>-ED: handled
```

### 関連ソース

- [FrameworkEventSubscriber](../lib/msf/core/framework.rb#L320) - イベント購読・記録
- [report_event](../lib/msf/core/db_manager/event.rb#L52) - DB書き込み
