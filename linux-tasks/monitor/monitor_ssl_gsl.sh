#!/usr/bin/env bash
# monitor_ssl_gsl.sh - gsl.kwgi.org の証明書期限監視 → GAS送信
# 依存: openssl, date, curl
# 通知: send_report() があれば使用。無ければ GAS_URL に直接POST。

set -u
set -o pipefail

HOST="gsl.kwgi.org"
SERVER_NAME="gsl.kwgi.org"
GAS_URL=""  # 直接送る場合に設定（任意）。notify_gas.sh があれば不要。

NOTIFY_HELPER="$HOME/notify_gas.sh"

log() { echo "[monitor_ssl_gsl] $*" >&2; }

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
  curl -fsS -X POST "$GAS_URL" \
    -H 'Content-Type: application/json; charset=utf-8' \
    --data "{\"server\":\"$SERVER_NAME\",\"status\":\"$status\",\"message\":$(jq -Rs . <<<"$message" 2>/dev/null || printf '"%s"' "$message" ),\"ip\":\"-\",\"expiryDateString\":\"$expiry\"}"
}

main(){
  local notafter days expiry_date_only status msg
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
