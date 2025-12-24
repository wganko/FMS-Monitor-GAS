# wireguard (WireGuard VPN監視)

- 目的: wg0インターフェースのUP状態、対向ノード(ant)への疎通確認。
- 配置: `linux-tasks/wireguard/check_wg.sh`
- 実行環境: bash / cron (毎日 08:00 実行)
- 通知: 異常時のみGAS/LINE通知
- ログ: `~/wg_logs/` (30日保存)

## ファイル
- check_wg.sh - WireGuard監視スクリプト
