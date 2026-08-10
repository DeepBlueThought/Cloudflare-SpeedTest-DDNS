#!/usr/bin/env bash

# Lightweight watchdog: validate current DNS IPs against the WebSocket service
# and trigger a full optimization only when one becomes unhealthy.

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
cd "$SCRIPT_DIR" || exit 1

log_file=${log_file:-/tmp/cloudflare-bestip.log}

log_msg() {
  local level="$1"
  local message="$2"
  local timestamp
  timestamp=$(date '+%Y-%m-%d %H:%M:%S')
  printf '[%s] [%s] %s\n' "$timestamp" "$level" "$message"
  if [[ -n "$log_file" ]]; then
    mkdir -p "$(dirname "$log_file")" 2>/dev/null || true
    printf '[%s] [%s] %s\n' "$timestamp" "$level" "$message" >> "$log_file" 2>/dev/null || true
  fi
}

# shellcheck source=lib/business_probe.sh
source "$SCRIPT_DIR/lib/business_probe.sh"

if ! business_probe_validate_config; then
  log_msg "ERROR" "Invalid WebSocket probe configuration: $BUSINESS_PROBE_REASON"
  exit 1
fi
if ! business_probe_enabled; then
  log_msg "INFO" "Watchdog skipped because WebSocket business probing is disabled"
  exit 0
fi

for required_var in zone_id api_token host_name; do
  if [[ -z "${!required_var:-}" ]]; then
    log_msg "ERROR" "Watchdog requires environment variable: $required_var"
    exit 1
  fi
done

base_url="https://api.cloudflare.com/client/v4/zones/$zone_id"
base_header=(-H "Authorization: Bearer $api_token" -H "Content-Type: application/json")
curl_args=(-sS --max-time 15)
[[ -n "${proxy_url:-}" ]] && curl_args+=(--proxy "$proxy_url")

IFS=', ' read -r -a host_names <<< "$host_name"
unhealthy=false
record_count=0

log_msg "INFO" "Watchdog checking current DNS IPs against https://${ws_probe_host}${ws_probe_path}"
for h in "${host_names[@]}"; do
  host_record_count=0
  response=$(curl "${curl_args[@]}" --get "$base_url/dns_records" \
    "${base_header[@]}" \
    --data-urlencode "name=$h" \
    --data-urlencode 'type=A')
  if ! jq -e '.success == true' >/dev/null 2>&1 <<< "$response"; then
    log_msg "ERROR" "Watchdog could not fetch DNS records for $h; leaving DNS unchanged"
    exit 1
  fi

  while IFS= read -r ip; do
    [[ -n "$ip" ]] || continue
    ((record_count++))
    ((host_record_count++))
    if ! business_probe_check "$ip"; then
      log_msg "WARN" "Watchdog marked $h -> $ip unhealthy: $BUSINESS_PROBE_REASON"
      unhealthy=true
    fi
  done < <(jq -r '.result[]? | .content' <<< "$response")
  if [[ $host_record_count -eq 0 ]]; then
    log_msg "WARN" "Watchdog found no managed DNS A record for $h"
    unhealthy=true
  fi
done

if [[ "$unhealthy" == false ]]; then
  log_msg "SUCCESS" "Watchdog health check passed for all $record_count DNS record(s)"
  exit 0
fi

log_msg "WARN" "Watchdog detected an unhealthy DNS state; starting a full re-selection"
exec bash "$SCRIPT_DIR/main.sh"
