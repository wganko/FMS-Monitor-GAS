# mic.kwgi.org (Ubuntu / FileMaker Server)

Ubuntu 上で実行する監視・保守スクリプト群。

## スクリプト一覧

### monitor/
- `monitor_fms_mic.sh` - FileMaker Server 監視（FMS Admin Console、バックアップ成功判定）

### wireguard/
- `check_wg.sh` - WireGuard VPN 接続確認

### backup/
- `rclone_backup_latest.sh` - rclone バックアップ実行（最新データ同期）

### cleanup/
- `delete_old_folders.sh` - 古いバックアップフォルダ削除

## 共有リソース

- DDNS 更新: `../shared/ddns/cf-ddns.sh`
- Cron テンプレート: `../shared/cron/`
- Systemd テンプレート: `../shared/systemd/`

## 設定と実行

各スクリプトは `notify_gas.sh` で GAS に報告します。GAS URL は `notify_gas.sh` で設定してください。

