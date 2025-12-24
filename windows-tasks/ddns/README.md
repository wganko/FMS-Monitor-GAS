# ddns (DDNS更新タスク)

- 目的: DDNS更新スクリプトを定期実行。
- 配置: `windows-tasks/ddns/` 配下にPSスクリプトを置く。
- 実行環境: PowerShell 5+ / Windows Task Scheduler。
- エンコーディング: UTF-8 (BOM付き) 推奨。
- ログ/秘密情報(APIキー等)はコミットしない。

## 置きたいファイル
- ddns_update.ps1
- (任意) install_task.ps1
