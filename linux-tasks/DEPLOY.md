# AlmaLinux 配置とスケジュール手順

本手順は AlmaLinux 上に DDNS（10分ごと）と SSL 監視（1日1回）を配置・実行するための標準パスと設定例です。

## 標準配置パス（推奨）
- スクリプト: `/opt/servei/`
  - DDNS: `/opt/servei/ddns/cf-ddns.sh`（隣に `env.sh` を配置）
  - 監視: `/opt/servei/monitor/monitor_ssl_gsl.sh`
- 機微設定: `/opt/servei/ddns/env.sh`（git管理外、権限600）
- ログ: `/var/log/servei/`（`ddns.log`, `ssl-monitor.log`）

> 備考: `/usr/local/bin` 直下に置いても構いませんが、関連ファイルをまとめやすい `/opt/servei` を推奨します。

## ディレクトリ作成と配置
```bash
sudo mkdir -p /opt/servei/ddns /opt/servei/monitor /var/log/servei
sudo chown root:root /opt/servei -R
sudo chmod 755 /opt/servei /opt/servei/ddns /opt/servei/monitor
sudo chmod 755 /var/log/servei

# リポジトリからサーバへ転送（例）
# scp linux-tasks/ddns/cf-ddns.sh root@almalinux:/opt/servei/ddns/
# scp linux-tasks/monitor/monitor_ssl_gsl.sh root@almalinux:/opt/servei/monitor/

# 機微情報ファイル（env.sh）を作成（ZONE_ID/RECORD_ID/API_TOKEN/RECORD_NAME を設定）
sudo bash -c 'cat > /opt/servei/ddns/env.sh <<"EOF" 
ZONE_ID=""
RECORD_ID=""
API_TOKEN=""
RECORD_NAME="gsl.kwgi.org"
EOF'
sudo chown root:root /opt/servei/ddns/env.sh
sudo chmod 600 /opt/servei/ddns/env.sh

# 実行権限
sudo chmod 750 /opt/servei/ddns/cf-ddns.sh /opt/servei/monitor/monitor_ssl_gsl.sh
```

## 動作テスト
```bash
sudo /opt/servei/ddns/cf-ddns.sh
sudo /opt/servei/monitor/monitor_ssl_gsl.sh
```

## スケジュール設定（cron 方式）
最もシンプルな方法です。`/etc/cron.d` にテンプレートを配置します。

```bash
# DDNS: 10分ごと
sudo install -m 644 linux-tasks/cron/cf-ddns /etc/cron.d/cf-ddns

# SSL監視: 1日1回（08:15）
sudo install -m 644 linux-tasks/cron/monitor-ssl /etc/cron.d/monitor-ssl

sudo systemctl restart crond
```

テンプレート内のパス（`/opt/servei/...`）を環境に合わせて変更してください。

## スケジュール設定（systemd timer 方式）
より厳密な制御が必要な場合。

```bash
# DDNS（10分おき）
sudo install -m 644 linux-tasks/systemd/cf-ddns.service /etc/systemd/system/cf-ddns.service
sudo install -m 644 linux-tasks/systemd/cf-ddns.timer   /etc/systemd/system/cf-ddns.timer
sudo systemctl daemon-reload
sudo systemctl enable --now cf-ddns.timer
sudo systemctl status cf-ddns.timer

# SSL監視（毎日 08:15）
sudo install -m 644 linux-tasks/systemd/monitor-ssl.service /etc/systemd/system/monitor-ssl.service
sudo install -m 644 linux-tasks/systemd/monitor-ssl.timer   /etc/systemd/system/monitor-ssl.timer
sudo systemctl daemon-reload
sudo systemctl enable --now monitor-ssl.timer
sudo systemctl status monitor-ssl.timer
```

## GAS 送信について
- `monitor_ssl_gsl.sh` は `$HOME/notify_gas.sh` があればそれを使い、無ければ `GAS_URL` へ直接POSTします。
- 直接POSTする場合はスクリプト冒頭の `GAS_URL` を設定してください。

## トラブルシュート
- `cf-ddns.sh` が `env.sh` を見つけられない: `/opt/servei/ddns/env.sh` のパスと権限（600）を再確認。
- SSL監視が送信失敗: `GAS_URL` 設定、あるいは `notify_gas.sh` の `send_report` 関数の存在を確認。
- cronが動かない: `/etc/cron.d` ファイルの権限（644）、末尾改行、`crond` 再起動を確認。
- systemd timerが動かない: `systemctl list-timers` でスケジュール確認、`journalctl -u <service>` でログ確認。
