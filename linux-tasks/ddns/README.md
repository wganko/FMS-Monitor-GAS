# ddns (Cloudflare DDNS - Linux)

- 目的: Cloudflare Aレコードを現在のWAN IPv4に更新
- 配置: `linux-tasks/ddns/cf-ddns.sh`
- 実行環境: bash / cron（例: */5分）
- 依存: curl, (任意) jq
- 秘密情報: `env.sh` に記載し、Gitには含めない

## 設定ファイル: env.sh（Git管理外）
```bash
# Cloudflare secrets
ZONE_ID="<your_zone_id>"
RECORD_ID="<your_record_id>"
API_TOKEN="<your_token>"
RECORD_NAME="mic.kwgi.org"
```

## cron 例（root）
```
*/5 * * * * /usr/local/bin/cf-ddns.sh > /dev/null 2>&1
```

## デプロイ手順
- サーバー上に `/usr/local/bin/cf-ddns.sh` として配置（実行権付与）
- 同ディレクトリに `env.sh` を設置（600推奨）
- `sudo crontab -e` で実行スケジュールを登録
