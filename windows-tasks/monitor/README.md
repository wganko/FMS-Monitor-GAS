# monitor (FMS監視タスク)

- 目的: FMS稼働監視・SSL期限チェックを実行し、GASにレポート送信する。
- 配置: `windows-tasks/monitor/monitor_fms.ps1`（このREADMEと同階層）
- 実行環境: PowerShell 5+ / Windows Task Scheduler
- 推奨エンコーディング: UTF-8 (BOM付き)。送信・出力もUTF-8に統一。
- タスクスケジューラ設定: 手動で登録（引数・実行間隔は運用に合わせて指定）。
- ログ/秘密情報はコミットしない（.gitignoreで除外）。

## 置きたいファイル
- monitor_fms.ps1
- (任意) install_task.ps1  # タスク登録用スクリプトを作る場合

## メモ
- Invoke-RestMethod実行時は `-ContentType "application/json; charset=utf-8"` を指定。
- `Console` と `$OutputEncoding` を UTF-8 に設定して文字化けを防止。
