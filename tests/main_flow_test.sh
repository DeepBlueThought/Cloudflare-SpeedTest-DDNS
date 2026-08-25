#!/usr/bin/env bash

set -u

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TEST_TMP=$(mktemp -d "${TMPDIR:-/tmp}/cfst-main-flow.XXXXXX")
trap 'rm -rf "$TEST_TMP"' EXIT

mkdir -p "$TEST_TMP/app/lib" "$TEST_TMP/fake-bin"
cp "$ROOT_DIR/main.sh" "$TEST_TMP/app/main.sh"
cp "$ROOT_DIR/lib/business_probe.sh" "$TEST_TMP/app/lib/business_probe.sh"
printf '173.245.48.0/20\n' > "$TEST_TMP/app/ip.txt"

for binary in CloudflareST_amd64 CloudflareST_arm64 CloudflareST_darwin_arm64 CloudflareST_darwin_amd64; do
  cp /dev/null "$TEST_TMP/app/$binary"
  chmod +x "$TEST_TMP/app/$binary"
done

cat > "$TEST_TMP/fake-bin/uname" <<'MOCK'
#!/usr/bin/env bash
[[ "${1:-}" == "-s" ]] && printf 'Linux\n' || printf 'x86_64\n'
MOCK

cat > "$TEST_TMP/fake-bin/timeout" <<'MOCK'
#!/usr/bin/env bash
shift
if [[ "${1:-}" == "bash" ]]; then
  exit 0
fi
exec "$@"
MOCK

cat > "$TEST_TMP/fake-bin/openssl" <<'MOCK'
#!/usr/bin/env bash
if [[ "${1:-}" == "rand" ]]; then
  printf 'dGhlIHNhbXBsZSBub25jZQ==\n'
  exit 0
fi
printf 'Protocol : TLSv1.3\nCipher is TLS_AES_256_GCM_SHA384\n'
MOCK

cat > "$TEST_TMP/fake-bin/curl" <<'MOCK'
#!/usr/bin/env bash
set -u

method=GET
url=""
output_file=""
headers_file=""
resolve=""
data=""
args=("$@")

for ((i = 0; i < ${#args[@]}; i++)); do
  case "${args[$i]}" in
    -X) method=${args[$((i + 1))]}; ((i++)) ;;
    -o) output_file=${args[$((i + 1))]}; ((i++)) ;;
    -D) headers_file=${args[$((i + 1))]}; ((i++)) ;;
    --resolve) resolve=${args[$((i + 1))]}; ((i++)) ;;
    -d) data=${args[$((i + 1))]}; ((i++)) ;;
    http://*|https://*) url=${args[$i]} ;;
  esac
done

if [[ -n "$resolve" ]]; then
  ip=${resolve##*:}
  if [[ "$ip" == "162.159.44.212" ]]; then
    code=403
    printf '<html>Cloudflare error code: 1034</html>\n' > "$output_file"
  else
    code=101
    : > "$output_file"
  fi
  printf 'HTTP/1.1 %s Mock\r\n\r\n' "$code" > "$headers_file"
  if [[ "$ip" == "104.16.2.2" ]]; then
    printf '%s\t0.020\t0.200\t0.500' "$code"
  else
    printf '%s\t0.010\t0.030\t0.080' "$code"
  fi
  [[ "$code" == 101 ]] && exit 28
  exit 0
fi

if [[ "$url" == "https://www.cloudflare.com/ips-v4" ]]; then
  printf '173.245.48.0/20\n' > "$output_file"
  exit 0
fi

if [[ "$url" == */dns_records* && "$method" == GET ]]; then
  printf '%s\n' '{"success":true,"result":[{"id":"record-bad","content":"162.159.44.212"},{"id":"record-good","content":"172.64.229.53"}]}'
  exit 0
fi

if [[ "$method" == DELETE ]]; then
  printf 'DELETE %s\n' "$url" >> "$MOCK_ACTION_LOG"
  printf '%s\n' '{"success":true,"result":{}}'
  exit 0
fi

if [[ "$method" == POST ]]; then
  printf 'POST %s %s\n' "$url" "$data" >> "$MOCK_ACTION_LOG"
  printf '%s\n' '{"success":true,"result":{"id":"record-new"}}'
  exit 0
fi

printf '%s\n' '{"success":true,"result":{"id":"zone-test"}}'
MOCK

cat > "$TEST_TMP/app/CloudflareST_amd64" <<'MOCK'
#!/usr/bin/env bash
set -u

output=result.csv
input_file=""
download_count=""
args=("$@")
for ((i = 0; i < ${#args[@]}; i++)); do
  if [[ "${args[$i]}" == "-o" ]]; then
    output=${args[$((i + 1))]}
  fi
  if [[ "${args[$i]}" == "-f" ]]; then
    input_file=${args[$((i + 1))]}
  fi
  if [[ "${args[$i]}" == "-dn" ]]; then
    download_count=${args[$((i + 1))]}
  fi
done

printf 'IP 地址,已发送,已接收,丢包率,平均延迟,下载速度 (MB/s),地区码\n' > "$output"
case "$output" in
  baseline_result.csv)
    printf '172.64.229.53,4,4,0.00,30.00,10.00,HKG\n' >> "$output"
    ;;
  latency_candidates.csv)
    if [[ "${MOCK_EMPTY_DISCOVERY:-false}" != "true" ]]; then
      printf '162.159.44.212,4,4,0.00,10.00,0.00,HKG\n' >> "$output"
      printf '172.64.229.53,4,4,0.00,20.00,0.00,HKG\n' >> "$output"
      printf '104.16.2.2,4,4,0.00,30.00,0.00,HKG\n' >> "$output"
    fi
    ;;
  result.csv)
    printf 'SPEED_INPUT %s\n' "$(tr '\n' ',' < "$input_file")" >> "$MOCK_ACTION_LOG"
    printf 'SPEED_DN %s\n' "$download_count" >> "$MOCK_ACTION_LOG"
    printf '172.64.229.53,4,4,0.00,20.00,20.00,HKG\n' >> "$output"
    printf '104.16.2.2,4,4,0.00,30.00,50.00,HKG\n' >> "$output"
    printf '104.16.1.1,4,4,0.00,1.00,100.00,HKG\n' >> "$output"
    ;;
esac
MOCK

chmod +x "$TEST_TMP/fake-bin/"* "$TEST_TMP/app/CloudflareST_amd64"
: > "$TEST_TMP/actions.log"

PATH="$TEST_TMP/fake-bin:$PATH" \
MOCK_ACTION_LOG="$TEST_TMP/actions.log" \
zone_id=test-zone \
api_token=test-token \
host_name=bestip.example.com \
host_ip_max=1 \
speedtest_para='-n 10 -dn 1 -sl 1 -tl 100' \
ws_probe_enabled=true \
ws_probe_host=www.example.com \
ws_probe_path=/deepblue \
ws_probe_candidate_limit=10 \
log_file="$TEST_TMP/application.log" \
lock_dir="$TEST_TMP/runtime.lock" \
bash "$TEST_TMP/app/main.sh" > "$TEST_TMP/run.out" 2>&1
status=$?

failures=0
if [[ $status -ne 0 ]]; then
  printf 'not ok - mocked main flow exits successfully\n'
  ((failures++))
else
  printf 'ok - mocked main flow exits successfully\n'
fi

if grep -q '162.159.44.212.*HTTP 403.*1034' "$TEST_TMP/run.out"; then
  printf 'ok - business-invalid existing IP records the 403/1034 reason\n'
else
  printf 'not ok - business-invalid existing IP records the 403/1034 reason\n'
  ((failures++))
fi

if grep -q 'Selected 1 business-valid IP' "$TEST_TMP/run.out" \
  && grep -q '#1: 104.16.2.2' "$TEST_TMP/run.out"; then
  printf 'ok - fastest WebSocket-valid IP wins despite its slower handshake\n'
else
  printf 'not ok - fastest WebSocket-valid IP wins despite its slower handshake\n'
  ((failures++))
fi

if grep -q '^SPEED_INPUT 172.64.229.53,104.16.2.2,$' "$TEST_TMP/actions.log" \
  && grep -q '^SPEED_DN 2$' "$TEST_TMP/actions.log"; then
  printf 'ok - download speed test covers the complete business-valid pool\n'
else
  printf 'not ok - download speed test covers the complete business-valid pool\n'
  ((failures++))
fi

if grep -q "Ignoring result IP 104.16.1.1 because it was not in this run's business-valid candidate pool" "$TEST_TMP/run.out"; then
  printf 'ok - final results cannot inject an IP outside the business-valid pool\n'
else
  printf 'not ok - final results cannot inject an IP outside the business-valid pool\n'
  ((failures++))
fi

if grep -q '^POST .*104.16.2.2' "$TEST_TMP/actions.log" \
  && grep -q 'DELETE.*/record-bad' "$TEST_TMP/actions.log" \
  && grep -q 'DELETE.*/record-good' "$TEST_TMP/actions.log"; then
  printf 'ok - DNS converges to the fastest business-valid IP\n'
else
  printf 'not ok - DNS converges to the fastest business-valid IP\n'
  ((failures++))
fi

printf '104.16.1.1,4,4,0.00,1.00,100.00,HKG\n' > "$TEST_TMP/app/result.csv"
: > "$TEST_TMP/stale-actions.log"

PATH="$TEST_TMP/fake-bin:$PATH" \
MOCK_ACTION_LOG="$TEST_TMP/stale-actions.log" \
MOCK_EMPTY_DISCOVERY=true \
zone_id=test-zone \
api_token=test-token \
host_name=bestip.example.com \
host_ip_max=1 \
speedtest_para='-n 10 -dn 2 -sl 1 -tl 100' \
ws_probe_enabled=true \
ws_probe_host=www.example.com \
ws_probe_path=/deepblue \
ws_probe_candidate_limit=10 \
log_file="$TEST_TMP/stale-application.log" \
lock_dir="$TEST_TMP/stale-runtime.lock" \
bash "$TEST_TMP/app/main.sh" > "$TEST_TMP/stale-run.out" 2>&1
stale_status=$?

if [[ $stale_status -eq 0 ]] \
  && grep -q 'Business prefilter: 0 of 0 candidate(s)' "$TEST_TMP/stale-run.out" \
  && grep -q 'No current-run result.csv found' "$TEST_TMP/stale-run.out" \
  && ! grep -q 'New candidate IP: 104.16.1.1' "$TEST_TMP/stale-run.out" \
  && ! grep -q '^POST ' "$TEST_TMP/stale-actions.log"; then
  printf 'ok - a stale result.csv cannot enter a later empty-candidate run\n'
else
  printf 'not ok - a stale result.csv cannot enter a later empty-candidate run\n'
  ((failures++))
fi

if [[ $failures -gt 0 ]]; then
  printf '\nmain output:\n'
  sed -n '1,240p' "$TEST_TMP/run.out"
  printf '\nactions:\n'
  sed -n '1,120p' "$TEST_TMP/actions.log"
  printf '\nstale-run output:\n'
  sed -n '1,240p' "$TEST_TMP/stale-run.out"
  exit 1
fi

printf 'all mocked main-flow tests passed\n'
