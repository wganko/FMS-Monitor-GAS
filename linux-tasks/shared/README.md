# 共有スクリプト・テンプレート

複数のサーバで使用可能な共通スクリプトとテンプレート。

## ddns/
- `cf-ddns.sh` - Cloudflare DDNS 更新スクリプト
- 設定ファイル: `env.sh`（各サーバで作成、git管理外）
  - ZONE_ID, RECORD_ID, API_TOKEN, RECORD_NAME

## acme/
- `README.md` - 証明書管理のドキュメント（参考）

## cron/
Cron テンプレート（`/etc/cron.d` に配置）

- `cf-ddns` - 10分ごとに DDNS 更新
- `monitor-ssl` - 毎日08:15に SSL 監視実行

パス設定: `/opt/servei/...`（各サーバで設定ファイルを編集）

## systemd/
Systemd service/timer テンプレート（`/etc/systemd/system` に配置）

- `cf-ddns.service` / `cf-ddns.timer` - 10分周期 DDNS
- `monitor-ssl.service` / `monitor-ssl.timer` - 毎日08:15 SSL監視

## サーバ別配置例

```bash
# 各サーバで共有スクリプトを配置
cp shared/ddns/cf-ddns.sh /opt/servei/ddns/
cp shared/ddns/cf-ddns.sh /opt/servei/ddns/
cp shared/cron/* /etc/cron.d/
```

