#!/usr/bin/env bash

set -u

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TEST_TMP=$(mktemp -d "${TMPDIR:-/tmp}/cfst-healthcheck.XXXXXX")
trap 'rm -rf "$TEST_TMP"' EXIT

mkdir -p "$TEST_TMP/app/lib" "$TEST_TMP/fake-bin"
cp "$ROOT_DIR/healthcheck.sh" "$TEST_TMP/app/healthcheck.sh"
cp "$ROOT_DIR/lib/business_probe.sh" "$TEST_TMP/app/lib/business_probe.sh"

cat > "$TEST_TMP/app/main.sh" <<'MOCK'
#!/usr/bin/env bash
printf 'RESELECT\n' >> "$MOCK_ACTION_LOG"
MOCK

cat > "$TEST_TMP/fake-bin/timeout" <<'MOCK'
#!/usr/bin/env bash
shift
[[ "${1:-}" == bash ]] && exit 0
exec "$@"
MOCK

cat > "$TEST_TMP/fake-bin/openssl" <<'MOCK'
#!/usr/bin/env bash
if [[ "${1:-}" == rand ]]; then
  printf 'dGhlIHNhbXBsZSBub25jZQ==\n'
else
  printf 'Protocol : TLSv1.3\nCipher is TLS_AES_256_GCM_SHA384\n'
fi
MOCK

cat > "$TEST_TMP/fake-bin/curl" <<'MOCK'
#!/usr/bin/env bash
set -u

resolve=""
output_file=""
headers_file=""
args=("$@")
for ((i = 0; i < ${#args[@]}; i++)); do
  case "${args[$i]}" in
    --resolve) resolve=${args[$((i + 1))]}; ((i++)) ;;
    -o) output_file=${args[$((i + 1))]}; ((i++)) ;;
    -D) headers_file=${args[$((i + 1))]}; ((i++)) ;;
  esac
done

if [[ -z "$resolve" ]]; then
  printf '%s\n' '{"success":true,"result":[{"id":"record-current","content":"172.64.229.53"}]}'
  exit 0
fi

printf 'HTTP/1.1 %s Mock\r\n\r\n' "$MOCK_HEALTH_CODE" > "$headers_file"
if [[ "$MOCK_HEALTH_CODE" == 101 ]]; then
  : > "$output_file"
else
  printf 'Cloudflare error code: 1034\n' > "$output_file"
fi
printf '%s\t0.010\t0.030\t0.080' "$MOCK_HEALTH_CODE"
[[ "$MOCK_HEALTH_CODE" == 101 ]] && exit 28
exit 0
MOCK

chmod +x "$TEST_TMP/app/main.sh" "$TEST_TMP/fake-bin/"*

run_watchdog() {
  local code="$1"
  local output="$2"
  PATH="$TEST_TMP/fake-bin:$PATH" \
  MOCK_HEALTH_CODE="$code" \
  MOCK_ACTION_LOG="$TEST_TMP/actions.log" \
  zone_id=test-zone \
  api_token=test-token \
  host_name=bestip.example.com \
  ws_probe_enabled=true \
  ws_probe_host=www.example.com \
  ws_probe_path=/deepblue \
  log_file="$TEST_TMP/application.log" \
  bash "$TEST_TMP/app/healthcheck.sh" > "$output" 2>&1
}

failures=0
: > "$TEST_TMP/actions.log"
if run_watchdog 101 "$TEST_TMP/healthy.out" \
  && grep -q 'health check passed' "$TEST_TMP/healthy.out" \
  && [[ ! -s "$TEST_TMP/actions.log" ]]; then
  printf 'ok - watchdog does not reselect while current IP returns 101\n'
else
  printf 'not ok - watchdog does not reselect while current IP returns 101\n'
  ((failures++))
fi

: > "$TEST_TMP/actions.log"
if run_watchdog 403 "$TEST_TMP/unhealthy.out" \
  && grep -q 'HTTP 403.*1034' "$TEST_TMP/unhealthy.out" \
  && grep -q '^RESELECT$' "$TEST_TMP/actions.log"; then
  printf 'ok - watchdog triggers a full reselection after business failure\n'
else
  printf 'not ok - watchdog triggers a full reselection after business failure\n'
  ((failures++))
fi

if [[ $failures -gt 0 ]]; then
  sed -n '1,160p' "$TEST_TMP/healthy.out"
  sed -n '1,160p' "$TEST_TMP/unhealthy.out"
  exit 1
fi

printf 'all watchdog tests passed\n'
