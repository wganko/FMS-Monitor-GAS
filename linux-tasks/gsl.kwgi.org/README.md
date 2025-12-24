# gsl.kwgi.org (AlmaLinux / GroupSession)

AlmaLinux 上で実行する DDNS 更新と SSL 監視スクリプト群。

## スクリプト一覧

### monitor/
- `monitor_ssl_gsl.sh` - SSL 証明書期限監視（自動更新 cron）

### acme/
- 証明書自動更新設定の構成。DNS-01（Cloudflare）で運用中。

## 共有リソース

- DDNS 更新: `../shared/ddns/cf-ddns.sh`
- Cron テンプレート: `../shared/cron/`
- Systemd テンプレート: `../shared/systemd/`

## 配置と運用

詳細は [DEPLOY.md](DEPLOY.md) を参照してください。

