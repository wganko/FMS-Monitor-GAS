#!/usr/bin/env bash
# monitor_ssl_gsl.sh - gsl.kwgi.org の証明書期限監視 → GAS送信
# 依存: openssl, date, curl
# 通知: send_report() があれば使用。無ければ GAS_URL に直接POST。

set -u
set -o pipefail

HOST="gsl.kwgi.org"
SERVER_NAME="gsl.kwgi.org"

# GAS_URL を最初に指定。未設定なら GAS 設定取得エンドポイントから自動取得を試みる
GAS_BASE_URL=""  # GAS Web App base URL。デプロイ時に設定される
GAS_URL=""

NOTIFY_HELPER="$HOME/notify_gas.sh"

log() { echo "[monitor_ssl_gsl] $*" >&2; }

# GAS 設定を取得するか、手動設定を使用
get_gas_url() {
  if [[ -n "$GAS_URL" ]]; then
    return 0  # 既に設定済み
  fi
  
  if [[ -z "$GAS_BASE_URL" ]]; then
    log "GAS_BASE_URL が未設定です"
    return 1
  fi
  
  # GAS から設定を取得
  local config_response
  config_response=$(curl -fsS "${GAS_BASE_URL}?action=getConfig" 2>/dev/null) || {
    log "GAS 設定取得失敗"
    return 1
  }
  
  GAS_URL=$(echo "$config_response" | jq -r '.gasWebAppUrl // empty' 2>/dev/null)
  
  if [[ -z "$GAS_URL" ]]; then
    log "GAS_URL を設定から取得できませんでした"
    return 1
  fi
  
  log "GAS_URL を自動取得: ${GAS_URL:0:50}..."
  return 0
}

get_notafter(){
  echo | openssl s_client -connect "${HOST}:443" -servername "${HOST}" 2>/dev/null \
   | openssl x509 -noout -enddate | cut -d= -f2-
}

calc_days(){
  local raw="$1"
  local expiry_epoch
  expiry_epoch="$(date -d "$raw" +%s)" || return 1
  local now_epoch
  now_epoch="$(date +%s)"
  echo $(((expiry_epoch - now_epoch) / 86400))
}

post_gas(){
  local status="$1"; shift
  local message="$1"; shift
  local expiry="$1"; shift

  if [[ -f "$NOTIFY_HELPER" ]]; then
    # shellcheck source=/dev/null
    source "$NOTIFY_HELPER"
    if declare -F send_report >/dev/null 2>&1; then
      send_report "$status" "$message" "$SERVER_NAME" "$expiry"
      return 0
    fi
  fi

  if [[ -z "$GAS_URL" ]]; then
    log "GAS_URL が未設定で notify_gas.sh も見つかりません。送信をスキップします。"
    return 1
  fi

  # 直接POST: server/status/message/ip/expiryDateString を送る
  # メッセージの改行を\nから実改行に変換（シェル展開）
  local msg_escaped
  msg_escaped=$(printf '%s\n' "$message" | jq -Rs .)
  
  local payload="{\"server\":\"$SERVER_NAME\",\"status\":\"$status\",\"message\":$msg_escaped,\"ip\":\"-\",\"expiryDateString\":\"$expiry\"}"
  log "Sending to GAS: $payload"
  
  curl -L -X POST "$GAS_URL" \
    -H 'Content-Type: application/json; charset=utf-8' \
    --data "$payload"
}

main(){
  local notafter days expiry_date_only status msg
  
  # GAS_URL を取得（未設定なら GAS から自動取得）
  if ! get_gas_url; then
    log "GAS_URL 取得失敗、スキップ"
    return 1
  fi
  
  notafter="$(get_notafter)" || { log "証明書期限取得に失敗"; post_gas "ERROR" "SSL期限の取得に失敗" ""; exit 1; }
  days="$(calc_days "$notafter")" || { log "期限解析に失敗: $notafter"; post_gas "ERROR" "SSL期限の解析に失敗: $notafter" ""; exit 1; }
  expiry_date_only="$(date -d "$notafter" +"%Y-%m-%d 00:00:00")"

  status="INFO"
  msg="◆判定ステップ: すべて正常\n【SSL】残り ${days} 日 (OK) [$(date -d "$notafter" +"%Y/%m/%d")]"

  if (( days < 0 )); then
    status="ERROR"
    msg="◆判定ステップ: SSL期限\n【SSL】期限切れ: ${days} 日 (期限: $(date -d "$notafter" +"%Y/%m/%d"))"
  elif (( days < 7 )); then
    status="ERROR"
    msg="◆判定ステップ: SSL期限\n【SSL】非常に近い: 残り ${days} 日 (期限: $(date -d "$notafter" +"%Y/%m/%d"))"
  elif (( days < 30 )); then
    status="ERROR"
    msg="◆判定ステップ: SSL期限\n【SSL】近い: 残り ${days} 日 (期限: $(date -d "$notafter" +"%Y/%m/%d"))"
  fi

  post_gas "$status" "$msg" "$expiry_date_only" || true
}

[[ "${BASH_SOURCE[0]}" == "$0" ]] && main "$@"
