# monitor (FMS監視タスク - Ubuntu/mic)

- 目的: FileMaker Server (mic.kwgi.org) の稼働状態、SSL証明書期限を監視し、GASにレポート送信。
- 配置: `linux-tasks/monitor/monitor_fms_mic.sh`
- 実行環境: bash / cron (毎日 08:10 実行)
- エンコーディング: UTF-8
- 依存: `notify_gas.sh` (GAS送信ヘルパー)
- 通知: 異常時のみLINE通知（ERROR/WARN）

## ファイル
- monitor_fms_mic.sh - FMS監視スクリプト
- notify_gas.sh - GAS送信共通ヘルパー（別途配置）
