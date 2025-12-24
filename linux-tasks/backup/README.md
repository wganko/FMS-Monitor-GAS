# backup (Google Drive → FileMaker復元)

- 目的: Google Driveの最新Daily_フォルダからFileMaker Databasesを復元。
- 配置: `linux-tasks/backup/rclone_backup_latest.sh`
- 実行環境: bash / cron (毎日 09:00 実行)
- 依存: rclone, fmsadmin, `~/fms_env.sh` (FMS認証情報)
- 通知: 成功/失敗をGAS経由でLINE通知
- ログ: `~/rclone_logs/` (30日保存)

## ファイル
- rclone_backup_latest.sh - バックアップ復元スクリプト
- (環境設定) `~/fms_env.sh` - FMS認証情報 (Gitに含めない)

## 注意
- FMS_USERNAME / FMS_PASSWORD を `~/fms_env.sh` に記載（Gitから除外）
