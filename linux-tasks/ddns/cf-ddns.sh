#!/usr/bin/env bash
set -u
set -o pipefail

# Cloudflare DDNS updater (Linux)
# Secrets are loaded from env.sh (not committed)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/env.sh"

if [[ -f "$ENV_FILE" ]]; then
  # shellcheck source=/dev/null
  source "$ENV_FILE"
else
  echo "[ERROR] env.sh が見つかりません: $ENV_FILE" >&2
  echo "[ERROR] ZONE_ID, RECORD_ID, API_TOKEN, RECORD_NAME を定義してください" >&2
  exit 1
fi

: "${ZONE_ID:?ZONE_ID is required}"
: "${RECORD_ID:?RECORD_ID is required}"
: "${API_TOKEN:?API_TOKEN is required}"
: "${RECORD_NAME:?RECORD_NAME is required}"

# Get current WAN IPv4 with fallback
WAN_IP=""
for url in \
  "https://api.ipify.org" \
  "https://ifconfig.me/ip" \
  "http://checkip.dyndns.org"; do
  if resp=$(curl -fsS "$url" 2>/dev/null); then
    if [[ "$resp" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
      WAN_IP="$resp"
      break
    elif [[ "$resp" =~ ([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+) ]]; then
      WAN_IP="${BASH_REMATCH[1]}"
      break
    fi
  fi
done

if [[ -z "$WAN_IP" ]]; then
  echo "[ERROR] WAN IP を取得できませんでした" >&2
  exit 1
fi

API_URL="https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/dns_records/${RECORD_ID}"
BODY=$(jq -nc --arg name "$RECORD_NAME" --arg ip "$WAN_IP" '{type:"A", name:$name, content:$ip, ttl:60, proxied:false}')

if ! command -v jq >/dev/null 2>&1; then
  # Fallback without jq
  BODY="{\"type\":\"A\",\"name\":\"${RECORD_NAME}\",\"content\":\"${WAN_IP}\",\"ttl\":60,\"proxied\":false}"
fi

HTTP_CODE=$(curl -sS -o /tmp/cf-ddns.res.$$ -w "%{http_code}" \
  -X PUT "$API_URL" \
  -H "Authorization: Bearer ${API_TOKEN}" \
  -H "Content-Type: application/json" \
  --data "$BODY")

if [[ "$HTTP_CODE" != "200" ]]; then
  echo "[ERROR] Cloudflare API 更新失敗 (HTTP $HTTP_CODE)" >&2
  cat /tmp/cf-ddns.res.$$ >&2 || true
  rm -f /tmp/cf-ddns.res.$$ 2>/dev/null || true
  exit 1
fi

echo "[OK] ${RECORD_NAME} を ${WAN_IP} に更新しました"
rm -f /tmp/cf-ddns.res.$$ 2>/dev/null || true
