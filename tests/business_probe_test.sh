#!/usr/bin/env bash

set -u

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

MOCK_TCP=pass
MOCK_TLS=pass
MOCK_HTTP_CODE=101
MOCK_CURL_CALLED=0

log_msg() { :; }

timeout() {
  shift
  if [[ "${1:-}" == "bash" ]]; then
    [[ "$MOCK_TCP" == pass ]]
    return
  fi
  "$@"
}

openssl() {
  if [[ "${1:-}" == "rand" ]]; then
    printf 'dGhlIHNhbXBsZSBub25jZQ==\n'
    return 0
  fi
  if [[ "$MOCK_TLS" == pass ]]; then
    printf 'Protocol : TLSv1.3\nCipher is TLS_AES_256_GCM_SHA384\n'
    return 0
  fi
  printf 'verify error:num=62:hostname mismatch\n' >&2
  return 1
}

curl() {
  local headers_file=""
  local body_file=""
  local arg

  MOCK_CURL_CALLED=1
  while [[ $# -gt 0 ]]; do
    arg="$1"
    case "$arg" in
      -D|-o|-w|--resolve|--connect-timeout|--max-time|-H)
        if [[ "$arg" == "-D" ]]; then headers_file="$2"; fi
        if [[ "$arg" == "-o" ]]; then body_file="$2"; fi
        shift 2
        ;;
      *) shift ;;
    esac
  done

  printf 'HTTP/1.1 %s Test\r\n\r\n' "$MOCK_HTTP_CODE" > "$headers_file"
  if [[ "$MOCK_HTTP_CODE" == "403" ]]; then
    printf '<html>Cloudflare error code: 1034</html>\n' > "$body_file"
  else
    : > "$body_file"
  fi
  printf '%s\t0.010\t0.030\t0.080' "$MOCK_HTTP_CODE"

  # A real upgraded connection may stay open until curl's deadline. The probe
  # must accept the already-received 101 even when curl reports a timeout.
  [[ "$MOCK_HTTP_CODE" == "101" ]] && return 28
  return 0
}

# shellcheck source=../lib/business_probe.sh
source "$ROOT_DIR/lib/business_probe.sh"

failures=0
assert_success() {
  local name="$1"
  shift
  if "$@"; then
    printf 'ok - %s\n' "$name"
  else
    printf 'not ok - %s\n' "$name"
    ((failures++))
  fi
}

assert_failure() {
  local name="$1"
  shift
  if "$@"; then
    printf 'not ok - %s\n' "$name"
    ((failures++))
  else
    printf 'ok - %s\n' "$name"
  fi
}

unset ws_probe_host
ws_probe_enabled=auto
assert_failure 'auto mode stays disabled without an explicit business host' business_probe_enabled

ws_probe_enabled=true
if business_probe_validate_config || [[ "$BUSINESS_PROBE_REASON" != *ws_probe_host* ]]; then
  printf 'not ok - enabled mode requires ws_probe_host\n'
  ((failures++))
else
  printf 'ok - enabled mode requires ws_probe_host\n'
fi

ws_probe_host=www.example.com
ws_probe_path=/websocket
ws_probe_tls_verify=true
assert_success 'valid WebSocket probe configuration is accepted' business_probe_validate_config

MOCK_TCP=pass
MOCK_TLS=pass
MOCK_HTTP_CODE=101
assert_success 'HTTP 101 passes the hard business gate' business_probe_check 172.64.229.53
if [[ "$BUSINESS_PROBE_HTTP_CODE" != 101 || "$BUSINESS_PROBE_SCORE" != 32.00 ]]; then
  printf 'not ok - successful probe records timings and weighted score\n'
  ((failures++))
else
  printf 'ok - successful probe records timings and weighted score\n'
fi

MOCK_HTTP_CODE=403
assert_failure 'HTTP 403 is rejected' business_probe_check 162.159.44.212
if [[ "$BUSINESS_PROBE_REASON" != *1034* ]]; then
  printf 'not ok - Cloudflare 1034 is preserved in the failure reason\n'
  ((failures++))
else
  printf 'ok - Cloudflare 1034 is preserved in the failure reason\n'
fi

MOCK_TLS=fail
MOCK_HTTP_CODE=101
MOCK_CURL_CALLED=0
assert_failure 'TLS hostname verification failure is rejected before HTTP' business_probe_check 172.64.229.53
if [[ "$MOCK_CURL_CALLED" -ne 0 ]]; then
  printf 'not ok - WebSocket request is skipped after TLS failure\n'
  ((failures++))
else
  printf 'ok - WebSocket request is skipped after TLS failure\n'
fi

MOCK_TLS=pass
MOCK_TCP=fail
assert_failure 'TCP failure is rejected before TLS and HTTP' business_probe_check 172.64.229.53

MOCK_TCP=pass
assert_failure 'invalid IPv4 input is rejected' business_probe_check '172.64.229.999'

if [[ $failures -gt 0 ]]; then
  printf '%s test(s) failed\n' "$failures"
  exit 1
fi
printf 'all business probe tests passed\n'
