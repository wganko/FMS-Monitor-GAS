# acme (gsl.kwgi.org / AlmaLinux)

- 運用状況: certbot + systemd timer による自動更新（`certbot-renew.timer` 有効）
- 確認結果: 証明書は Let's Encrypt (E7) 発行、`notAfter=2026-03-17`（openssl 取得）。
- 認証方式: DNS-01（Cloudflare）で確定。`authenticator = dns-cloudflare`（本番サーバ）。

## 認証方式の確認（root）
```bash
sudo grep -E 'authenticator|server|webroot_path' /etc/letsencrypt/renewal/gsl.kwgi.org.conf
# 追加で Cloudflare 資格情報パスなど
sudo grep -E 'dns_cloudflare' /etc/letsencrypt/renewal/gsl.kwgi.org.conf || true
```
- `authenticator = webroot` なら HTTP-01
- `authenticator = dns-cloudflare` なら DNS-01（Cloudflare）

### Cloudflare 資格情報ファイルの確認と権限
`/etc/letsencrypt/renewal/gsl.kwgi.org.conf` に、以下のような行があるはずです。

```
dns_cloudflare_credentials = /root/.secrets/certbot/cloudflare.ini
```

確認手順（root）:
```bash
# パスの特定（上記grepで表示されたパスを使用）
cred="/root/.secrets/certbot/cloudflare.ini"  # 例。実際はgrep結果のパスに置き換え
sudo ls -l "$cred"
sudo head -n 2 "$cred"    # 中身の露出に注意。必要最小限の確認だけ行う

# 推奨パーミッション（機微情報のため600, root所有）
sudo chown root:root "$cred"
sudo chmod 600 "$cred"
```

## よく使う確認コマンド
```bash
# 期限と発行者の確認
echo | openssl s_client -connect gsl.kwgi.org:443 -servername gsl.kwgi.org 2>/dev/null \
  | openssl x509 -noout -enddate -issuer -subject

# timer/サービス状況
systemctl status certbot-renew.timer
systemctl list-timers --all | grep certbot
journalctl -u certbot-renew.service --since "-7 days"

# 利用可能プラグイン（dns-cloudflare が出ればOK）
certbot plugins -v
```

## 手動更新テスト（ドライラン）
```bash
sudo certbot renew --dry-run
```

## 本番更新（必要なときのみ）
通常はtimerで自動更新されます。手動実行する場合はメンテナンス時間に実施してください。
```bash
sudo certbot renew
```

## 注意
- Cloudflare の DDNS 更新（Aレコード書き換え）と、DNS-01 での証明書発行は別物です。
  - DDNS: Aレコードを現在のWAN IPに更新（例: `cf-ddns.sh`）
  - DNS-01: TXTレコードを使ってドメイン所持を証明（certbot dns プラグイン等）
