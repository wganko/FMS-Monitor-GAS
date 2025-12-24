# cleanup (古いDaily_フォルダ削除)

- 目的: Google Drive上の古いDaily_フォルダを削除し、最新7個のみ保持。
- 配置: `linux-tasks/cleanup/delete_old_folders.sh`
- 実行環境: bash / cron (毎日 10:00 実行)
- 依存: rclone
- ログ: `~/rclone_logs/` (30日保存)

## ファイル
- delete_old_folders.sh - 古いフォルダ削除スクリプト
