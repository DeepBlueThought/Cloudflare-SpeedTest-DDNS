#!/usr/bin/env bash

# Business-level health checks for a Cloudflare edge IP.
# The caller may define log_msg(level, message) before sourcing this file.

BUSINESS_PROBE_REASON=""
BUSINESS_PROBE_HTTP_CODE=""
BUSINESS_PROBE_TCP_MS="0.00"
BUSINESS_PROBE_TLS_MS="0.00"
BUSINESS_PROBE_WS_MS="0.00"
BUSINESS_PROBE_SCORE="999999.00"

_business_probe_log() {
  local level="$1"
  local message="$2"

  if declare -F log_msg >/dev/null 2>&1; then
    log_msg "$level" "$message"
  else
    printf '[%s] %s\n' "$level" "$message"
  fi
}

_business_probe_true() {
  case "${1:-}" in
    1|true|TRUE|yes|YES|on|ON) return 0 ;;
    *) return 1 ;;
  esac
}

business_probe_enabled() {
  case "${ws_probe_enabled:-auto}" in
    1|true|TRUE|yes|YES|on|ON) return 0 ;;
    0|false|FALSE|no|NO|off|OFF) return 1 ;;
    auto|AUTO|"") [[ -n "${ws_probe_host:-}" ]] ;;
    *)
      BUSINESS_PROBE_REASON="invalid ws_probe_enabled value: ${ws_probe_enabled}"
      return 2
      ;;
  esac
}

business_probe_validate_config() {
  local enabled_status=0
  business_probe_enabled || enabled_status=$?

  if [[ $enabled_status -eq 2 ]]; then
    return 1
  fi
  if [[ $enabled_status -eq 1 ]]; then
    return 0
  fi
  if [[ -z "${ws_probe_host:-}" ]]; then
    BUSINESS_PROBE_REASON="ws_probe_host is required when WebSocket probing is enabled"
    return 1
  fi
  if [[ "$ws_probe_host" == *"://"* || "$ws_probe_host" == */* || "$ws_probe_host" =~ [[:space:]] ]]; then
    BUSINESS_PROBE_REASON="ws_probe_host must be a hostname without scheme, port, or path"
    return 1
  fi

  ws_probe_path=${ws_probe_path:-/}
  [[ "$ws_probe_path" == /* ]] || ws_probe_path="/$ws_probe_path"

  case "${ws_probe_tls_verify:-true}" in
    1|true|TRUE|yes|YES|on|ON|0|false|FALSE|no|NO|off|OFF) ;;
    *)
      BUSINESS_PROBE_REASON="invalid ws_probe_tls_verify value: ${ws_probe_tls_verify}"
      return 1
      ;;
  esac

  return 0
}

_business_probe_valid_ipv4() {
  local ip="$1"
  local octet
  local IFS=.
  local -a octets

  [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || return 1
  read -r -a octets <<< "$ip"
  [[ ${#octets[@]} -eq 4 ]] || return 1
  for octet in "${octets[@]}"; do
    [[ "$octet" =~ ^[0-9]+$ ]] || return 1
    (( 10#$octet >= 0 && 10#$octet <= 255 )) || return 1
  done
}

_business_probe_tcp() {
  local ip="$1"
  local timeout_seconds=${ws_probe_tcp_timeout:-3}

  if ! timeout "$timeout_seconds" bash -c 'exec 3<>/dev/tcp/$1/443' _ "$ip" >/dev/null 2>&1; then
    BUSINESS_PROBE_REASON="TCP 443 connection failed or timed out after ${timeout_seconds}s"
    return 1
  fi
}

_business_probe_tls() {
  local ip="$1"
  local host="$2"
  local timeout_seconds=${ws_probe_tls_timeout:-5}
  local -a verify_args=()
  local output
  local status=0

  if _business_probe_true "${ws_probe_tls_verify:-true}"; then
    verify_args=(-verify_return_error -verify_hostname "$host")
  fi

  output=$(timeout "$timeout_seconds" openssl s_client \
    -connect "${ip}:443" \
    -servername "$host" \
    "${verify_args[@]}" \
    </dev/null 2>&1) || status=$?

  if [[ $status -ne 0 ]]; then
    BUSINESS_PROBE_REASON=$(printf '%s\n' "$output" \
      | grep -Eim1 'verify error|verification error|handshake failure|alert|timed out|connect:' \
      | tr '\r\n' ' ' \
      | sed -E 's/[[:space:]]+/ /g; s/^ //; s/ $//' \
      | cut -c1-180)
    [[ -n "$BUSINESS_PROBE_REASON" ]] || BUSINESS_PROBE_REASON="TLS SNI handshake failed or timed out after ${timeout_seconds}s"
    return 1
  fi

  if ! grep -qE 'Protocol *:|Protocol version:|Cipher is |Ciphersuite:' <<< "$output"; then
    BUSINESS_PROBE_REASON="TLS SNI handshake did not negotiate a protocol"
    return 1
  fi
}

_business_probe_body_reason() {
  local body_file="$1"
  local reason=""

  if [[ -s "$body_file" ]]; then
    reason=$(grep -Eio 'error code:?[[:space:]]*[0-9]+' "$body_file" | head -n1 || true)
    if [[ -z "$reason" ]]; then
      reason=$(tr '\r\n\t' '   ' < "$body_file" \
        | sed -E 's/<[^>]+>/ /g; s/[[:space:]]+/ /g; s/^ //; s/ $//' \
        | cut -c1-180)
    fi
  fi
  printf '%s' "$reason"
}

_business_probe_websocket() {
  local ip="$1"
  local host="$2"
  local path="$3"
  local timeout_seconds=${ws_probe_http_timeout:-8}
  local probe_tmp
  local headers_file
  local body_file
  local ws_key
  local metrics=""
  local curl_status=0
  local http_code="000"
  local time_connect="0"
  local time_appconnect="0"
  local time_starttransfer="0"
  local body_reason=""
  local -a tls_args=()

  probe_tmp=$(mktemp -d "${TMPDIR:-/tmp}/cfst-ws-probe.XXXXXX") || {
    BUSINESS_PROBE_REASON="could not create WebSocket probe temporary directory"
    return 1
  }
  headers_file="$probe_tmp/headers"
  body_file="$probe_tmp/body"

  ws_key=$(openssl rand -base64 16 2>/dev/null | tr -d '\r\n')
  [[ -n "$ws_key" ]] || ws_key="dGhlIHNhbXBsZSBub25jZQ=="

  if ! _business_probe_true "${ws_probe_tls_verify:-true}"; then
    tls_args=(-k)
  fi

  metrics=$(curl -sS \
    --noproxy '*' \
    --http1.1 \
    --connect-timeout "${ws_probe_connect_timeout:-5}" \
    --max-time "$timeout_seconds" \
    --resolve "${host}:443:${ip}" \
    "${tls_args[@]}" \
    -H 'Connection: Upgrade' \
    -H 'Upgrade: websocket' \
    -H 'Sec-WebSocket-Version: 13' \
    -H "Sec-WebSocket-Key: $ws_key" \
    -D "$headers_file" \
    -o "$body_file" \
    -w $'%{http_code}\t%{time_connect}\t%{time_appconnect}\t%{time_starttransfer}' \
    "https://${host}${path}" 2>"$probe_tmp/curl-error") || curl_status=$?

  IFS=$'\t' read -r http_code time_connect time_appconnect time_starttransfer <<< "$metrics"
  BUSINESS_PROBE_HTTP_CODE=${http_code:-000}
  BUSINESS_PROBE_TCP_MS=$(awk -v value="${time_connect:-0}" 'BEGIN { printf "%.2f", value * 1000 }')
  BUSINESS_PROBE_TLS_MS=$(awk -v start="${time_connect:-0}" -v finish="${time_appconnect:-0}" \
    'BEGIN { value=(finish-start)*1000; if (value < 0) value=0; printf "%.2f", value }')
  BUSINESS_PROBE_WS_MS=$(awk -v start="${time_appconnect:-0}" -v finish="${time_starttransfer:-0}" \
    'BEGIN { value=(finish-start)*1000; if (value < 0) value=0; printf "%.2f", value }')
  BUSINESS_PROBE_SCORE=$(awk \
    -v tcp="$BUSINESS_PROBE_TCP_MS" \
    -v tls="$BUSINESS_PROBE_TLS_MS" \
    -v ws="$BUSINESS_PROBE_WS_MS" \
    'BEGIN { printf "%.2f", tcp * 0.3 + tls * 0.2 + ws * 0.5 }')

  if [[ "$BUSINESS_PROBE_HTTP_CODE" == "101" ]]; then
    rm -rf "$probe_tmp"
    return 0
  fi

  body_reason=$(_business_probe_body_reason "$body_file")
  if [[ -n "$body_reason" ]]; then
    BUSINESS_PROBE_REASON="HTTP ${BUSINESS_PROBE_HTTP_CODE}: ${body_reason}"
  elif [[ $curl_status -ne 0 ]]; then
    BUSINESS_PROBE_REASON=$(tr '\r\n' ' ' < "$probe_tmp/curl-error" \
      | sed -E 's/[[:space:]]+/ /g; s/^ //; s/ $//' \
      | cut -c1-180)
    [[ -n "$BUSINESS_PROBE_REASON" ]] || BUSINESS_PROBE_REASON="curl failed with exit code $curl_status"
  else
    BUSINESS_PROBE_REASON="HTTP ${BUSINESS_PROBE_HTTP_CODE}; expected 101 Switching Protocols"
  fi

  rm -rf "$probe_tmp"
  return 1
}

business_probe_check() {
  local ip="$1"
  local host=${ws_probe_host:-}
  local path=${ws_probe_path:-/}

  BUSINESS_PROBE_REASON=""
  BUSINESS_PROBE_HTTP_CODE=""
  BUSINESS_PROBE_TCP_MS="0.00"
  BUSINESS_PROBE_TLS_MS="0.00"
  BUSINESS_PROBE_WS_MS="0.00"
  BUSINESS_PROBE_SCORE="999999.00"

  if ! _business_probe_valid_ipv4 "$ip"; then
    BUSINESS_PROBE_REASON="invalid IPv4 address"
    _business_probe_log "WARN" "Business probe $ip: FAIL ($BUSINESS_PROBE_REASON)"
    return 1
  fi

  if ! _business_probe_tcp "$ip"; then
    _business_probe_log "WARN" "Business probe $ip: TCP FAIL ($BUSINESS_PROBE_REASON)"
    return 1
  fi
  _business_probe_log "INFO" "Business probe $ip: TCP 443 OK"

  if ! _business_probe_tls "$ip" "$host"; then
    _business_probe_log "WARN" "Business probe $ip: TLS FAIL ($BUSINESS_PROBE_REASON)"
    return 1
  fi
  _business_probe_log "INFO" "Business probe $ip: TLS SNI OK ($host)"

  if ! _business_probe_websocket "$ip" "$host" "$path"; then
    _business_probe_log "WARN" "Business probe $ip: WS FAIL ($BUSINESS_PROBE_REASON)"
    return 1
  fi

  _business_probe_log "SUCCESS" \
    "Business probe $ip: WS 101 OK (TCP ${BUSINESS_PROBE_TCP_MS}ms, TLS ${BUSINESS_PROBE_TLS_MS}ms, WS ${BUSINESS_PROBE_WS_MS}ms, score ${BUSINESS_PROBE_SCORE})"
  return 0
}
