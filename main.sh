#!/usr/bin/env bash

# Cloudflare SpeedTest DDNS
# Network performance is considered only after the candidate passes the
# configured Cloudflare TLS + WebSocket business probe.

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
cd "$SCRIPT_DIR" || exit 1

log_file=${log_file:-/tmp/cloudflare-bestip.log}

log_msg() {
  local level="$1"
  local message="$2"
  local timestamp
  local color_reset='\033[0m'
  local color='\033[0;36m'

  timestamp=$(date '+%Y-%m-%d %H:%M:%S')
  case "$level" in
    SUCCESS) color='\033[0;32m' ;;
    WARN) color='\033[0;33m' ;;
    ERROR) color='\033[0;31m' ;;
  esac

  if [[ -t 1 ]]; then
    printf "%b[%s] [%s]%b %s\n" "$color" "$timestamp" "$level" "$color_reset" "$message"
  else
    printf '[%s] [%s] %s\n' "$timestamp" "$level" "$message"
  fi

  if [[ -n "$log_file" ]]; then
    mkdir -p "$(dirname "$log_file")" 2>/dev/null || true
    printf '[%s] [%s] %s\n' "$timestamp" "$level" "$message" >> "$log_file" 2>/dev/null || true
  fi
}

print() { log_msg "INFO" "$1"; }

# shellcheck source=lib/business_probe.sh
source "$SCRIPT_DIR/lib/business_probe.sh"

declare -a runtime_files=(
  baseline_ips.txt baseline_result.csv latency_candidates.csv
  business_valid_ips.txt result.csv speedtest.log
)
lock_dir=${lock_dir:-/tmp/cloudflare-speedtest-ddns.lock}
lock_owned=false

cleanup_runtime() {
  rm -f "${runtime_files[@]}"
  if [[ "$lock_owned" == true ]]; then
    rm -f "$lock_dir/pid"
    rmdir "$lock_dir" 2>/dev/null || true
  fi
}

acquire_lock() {
  local previous_pid=""

  if mkdir "$lock_dir" 2>/dev/null; then
    printf '%s\n' "$$" > "$lock_dir/pid"
    lock_owned=true
    return 0
  fi

  [[ -r "$lock_dir/pid" ]] && read -r previous_pid < "$lock_dir/pid"
  if [[ "$previous_pid" =~ ^[0-9]+$ ]] && kill -0 "$previous_pid" 2>/dev/null; then
    log_msg "WARN" "Another optimization run is active (PID $previous_pid); skipping this run"
    return 1
  fi

  rm -f "$lock_dir/pid"
  if rmdir "$lock_dir" 2>/dev/null && mkdir "$lock_dir" 2>/dev/null; then
    printf '%s\n' "$$" > "$lock_dir/pid"
    lock_owned=true
    log_msg "WARN" "Recovered a stale runtime lock"
    return 0
  fi

  log_msg "WARN" "Could not acquire runtime lock; skipping this run"
  return 1
}

trap cleanup_runtime EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
acquire_lock || exit 0

# Runtime outputs are valid only for the optimization run that created them.
# Clear files left by an interrupted run before any result can be consumed.
rm -f "${runtime_files[@]}"

for required_var in zone_id api_token host_name speedtest_para; do
  if [[ -z "${!required_var:-}" ]]; then
    log_msg "ERROR" "Required environment variable is missing: $required_var"
    exit 1
  fi
done

IFS=', ' read -r -a host_names <<< "$host_name"
if [[ ${#host_names[@]} -eq 0 ]]; then
  log_msg "ERROR" "host_name is empty"
  exit 1
fi

max_ips=${host_ip_max:-1}
if [[ ! "$max_ips" =~ ^[1-9][0-9]*$ ]]; then
  log_msg "ERROR" "host_ip_max must be a positive integer"
  exit 1
fi

if ! business_probe_validate_config; then
  log_msg "ERROR" "Invalid WebSocket probe configuration: $BUSINESS_PROBE_REASON"
  exit 1
fi

probe_enabled=false
if business_probe_enabled; then
  probe_enabled=true
  for command_name in openssl timeout; do
    if ! command -v "$command_name" >/dev/null 2>&1; then
      log_msg "ERROR" "WebSocket probing requires command: $command_name"
      exit 1
    fi
  done
  log_msg "INFO" "Business probe enabled: https://${ws_probe_host}${ws_probe_path} (HTTP/1.1 WebSocket 101 required)"
else
  log_msg "WARN" "Business probe is disabled; TCP/download speed alone cannot prove that an IP serves the real Cloudflare application"
fi

for command_name in curl jq awk sort; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    log_msg "ERROR" "Required command not found: $command_name"
    exit 1
  fi
done

update_ip_list() {
  local ip_file="$SCRIPT_DIR/ip.txt"

  if curl -s --max-time 10 https://www.cloudflare.com/ips-v4 -o "${ip_file}.tmp"; then
    if [[ -s "${ip_file}.tmp" ]] && grep -qE '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/[0-9]+$' "${ip_file}.tmp"; then
      mv "${ip_file}.tmp" "$ip_file"
      log_msg "SUCCESS" "IP list updated from Cloudflare"
      return 0
    fi
  fi

  rm -f "${ip_file}.tmp"
  log_msg "WARN" "Could not update Cloudflare IP ranges; using the existing ip.txt"
}

get_arg_value() {
  local flag="$1"
  local fallback="$2"
  shift 2
  local -a args=("$@")
  local i

  for ((i = 0; i < ${#args[@]}; i++)); do
    if [[ "${args[$i]}" == "$flag" && $((i + 1)) -lt ${#args[@]} ]]; then
      printf '%s' "${args[$((i + 1))]}"
      return 0
    fi
  done
  printf '%s' "$fallback"
}

declare -a MODIFIED_ARGS=()
replace_value_arg() {
  local flag="$1"
  local value="$2"
  shift 2
  local -a args=("$@")
  local found=false
  local i

  MODIFIED_ARGS=()
  for ((i = 0; i < ${#args[@]}; i++)); do
    if [[ "${args[$i]}" == "$flag" ]]; then
      if [[ "$found" == false ]]; then
        MODIFIED_ARGS+=("$flag" "$value")
        found=true
      fi
      ((i++))
    else
      MODIFIED_ARGS+=("${args[$i]}")
    fi
  done
  [[ "$found" == true ]] || MODIFIED_ARGS+=("$flag" "$value")
}

remove_value_arg() {
  local flag="$1"
  shift
  local -a args=("$@")
  local i

  MODIFIED_ARGS=()
  for ((i = 0; i < ${#args[@]}; i++)); do
    if [[ "${args[$i]}" == "$flag" ]]; then
      ((i++))
    else
      MODIFIED_ARGS+=("${args[$i]}")
    fi
  done
}

remove_flag_arg() {
  local flag="$1"
  shift
  local arg

  MODIFIED_ARGS=()
  for arg in "$@"; do
    [[ "$arg" == "$flag" ]] || MODIFIED_ARGS+=("$arg")
  done
}

update_ip_list

base_url="https://api.cloudflare.com/client/v4/zones/$zone_id"
base_header=(-H "Authorization: Bearer $api_token" -H "Content-Type: application/json")
curl_args=(-sS --max-time 15)
[[ -n "${proxy_url:-}" ]] && curl_args+=(--proxy "$proxy_url")

log_msg "INFO" "Checking Cloudflare authentication..."
response=$(curl "${curl_args[@]}" -X GET "$base_url" "${base_header[@]}")
if ! jq -e '.success == true' >/dev/null 2>&1 <<< "$response"; then
  log_msg "ERROR" "Authentication failed: $response"
  exit 1
fi
log_msg "SUCCESS" "Authentication successful"

os=$(uname -s)
arch=$(uname -m)
CloudflareST=""
if [[ "$os" == "Darwin" ]]; then
  [[ "$arch" == "arm64" ]] && CloudflareST="$SCRIPT_DIR/CloudflareST_darwin_arm64"
  [[ "$arch" == "x86_64" ]] && CloudflareST="$SCRIPT_DIR/CloudflareST_darwin_amd64"
elif [[ "$os" == "Linux" ]]; then
  [[ "$arch" == "x86_64" || "$arch" == "amd64" ]] && CloudflareST="$SCRIPT_DIR/CloudflareST_amd64"
  [[ "$arch" == "aarch64" || "$arch" == "arm64" ]] && CloudflareST="$SCRIPT_DIR/CloudflareST_arm64"
fi

if [[ -z "$CloudflareST" || ! -f "$CloudflareST" ]]; then
  log_msg "ERROR" "CloudflareST binary not found (OS: $os, Arch: $arch)"
  exit 1
fi
chmod +x "$CloudflareST" 2>/dev/null || true

declare -A old_records=()
declare -A unique_ips=()
declare -A valid_existing_ips=()
declare -A ip_metrics=()
declare -A business_checked=()
declare -A business_valid=()
declare -A business_scores=()
declare -A business_reasons=()

for h in "${host_names[@]}"; do
  log_msg "INFO" "Fetching existing DNS A records for $h..."
  response=$(curl "${curl_args[@]}" --get "$base_url/dns_records" \
    "${base_header[@]}" \
    --data-urlencode "name=$h" \
    --data-urlencode 'type=A')
  if ! jq -e '.success == true' >/dev/null 2>&1 <<< "$response"; then
    log_msg "ERROR" "Could not fetch DNS records for $h: $response"
    exit 1
  fi
  while IFS= read -r line; do
    ip=$(jq -r '.content' <<< "$line")
    id=$(jq -r '.id' <<< "$line")
    old_records["$h:$ip"]=$id
    unique_ips["$ip"]=1
  done < <(jq -c '.result[]?' <<< "$response")
done

cache_successful_business_probe() {
  local ip="$1"
  business_checked["$ip"]=1
  business_valid["$ip"]=1
  business_scores["$ip"]="$BUSINESS_PROBE_SCORE"
}

probe_candidate() {
  local ip="$1"

  if [[ "${business_checked[$ip]:-}" == "1" ]]; then
    if [[ "${business_valid[$ip]:-}" == "1" ]]; then
      return 0
    fi
    BUSINESS_PROBE_REASON=${business_reasons[$ip]:-"cached business probe failure"}
    return 1
  fi

  business_checked["$ip"]=1
  if business_probe_check "$ip"; then
    cache_successful_business_probe "$ip"
    return 0
  fi
  business_valid["$ip"]=0
  business_reasons["$ip"]=$BUSINESS_PROBE_REASON
  return 1
}

if [[ ${#unique_ips[@]} -gt 0 ]]; then
  if [[ "$probe_enabled" == true ]]; then
    print "Checking ${#unique_ips[@]} existing DNS IP(s) against the real WebSocket service..."
    for ip in "${!unique_ips[@]}"; do
      if probe_candidate "$ip"; then
        valid_existing_ips["$ip"]=1
      else
        log_msg "WARN" "Existing DNS IP $ip is excluded from baseline and selection: $BUSINESS_PROBE_REASON"
      fi
    done
  else
    for ip in "${!unique_ips[@]}"; do
      valid_existing_ips["$ip"]=1
    done
  fi
fi

read -r -a configured_speed_args <<< "$speedtest_para"
test_url=$(get_arg_value -url \
  'https://download.parallels.com/desktop/v18/18.1.1-53328/ParallelsDesktop-18.1.1-53328.dmg' \
  "${configured_speed_args[@]}")

if [[ ${#valid_existing_ips[@]} -gt 0 ]]; then
  print "Performance-testing ${#valid_existing_ips[@]} business-valid existing DNS IP(s)..."
  for ip in "${!valid_existing_ips[@]}"; do
    printf '%s\n' "$ip" >> baseline_ips.txt
  done

  "$CloudflareST" \
    -f baseline_ips.txt \
    -n 100 \
    -dn "${#valid_existing_ips[@]}" \
    -url "$test_url" \
    -dt 5 \
    -p 0 \
    -o baseline_result.csv \
    >/dev/null 2>&1 || log_msg "WARN" "Existing-IP performance test did not complete successfully"

  if [[ -f baseline_result.csv ]]; then
    while IFS=, read -r ip sent recv loss lat spd colo; do
      ip=${ip//$'\r'/}
      [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || continue
      [[ -n "$lat" && "$lat" != "0.00" ]] || lat="999.99"
      [[ -n "$spd" && "$spd" != "0.00" ]] || spd="0.01"
      ip_metrics["$ip"]="$lat,$spd"
      log_msg "INFO" "Existing IP $ip: ${lat}ms / ${spd}MB/s"
    done < baseline_result.csv
  fi
else
  print "No business-valid existing DNS records are available as a performance baseline."
fi

worst_latency=0
worst_speed=999999
for metrics in "${ip_metrics[@]}"; do
  lat=${metrics%%,*}
  spd=${metrics#*,}
  if awk -v left="$lat" -v right="$worst_latency" 'BEGIN { exit !(left > right) }'; then
    worst_latency=$lat
  fi
  if awk -v left="$spd" -v right="$worst_speed" 'BEGIN { exit !(left < right) }'; then
    worst_speed=$spd
  fi
done

tl_param=$(awk -v value="$worst_latency" 'BEGIN { n=int(value+0.5); if (n <= 0) n=100; if (n < 20) n=20; print n }')
sl_param=$(awk -v value="$worst_speed" 'BEGIN { n=int(value+0.5); if (n <= 0 || n >= 999999) n=1; print n }')
print "Search thresholds: Latency < ${tl_param}ms, Speed > ${sl_param}MB/s"

final_args=("${configured_speed_args[@]}")
replace_value_arg -tl "$tl_param" "${final_args[@]}"
final_args=("${MODIFIED_ARGS[@]}")
replace_value_arg -sl "$sl_param" "${final_args[@]}"
final_args=("${MODIFIED_ARGS[@]}")
replace_value_arg -url "$test_url" "${final_args[@]}"
final_args=("${MODIFIED_ARGS[@]}")
replace_value_arg -o result.csv "${final_args[@]}"
final_args=("${MODIFIED_ARGS[@]}")
replace_value_arg -p 0 "${final_args[@]}"
final_args=("${MODIFIED_ARGS[@]}")
result_ready=false

if [[ "$probe_enabled" == true ]]; then
  print "Stage 1/2: discovering low-latency candidates (download test disabled)..."
  latency_args=("${final_args[@]}")
  for value_flag in -dn -dt -sl -o -p; do
    remove_value_arg "$value_flag" "${latency_args[@]}"
    latency_args=("${MODIFIED_ARGS[@]}")
  done
  remove_flag_arg -dd "${latency_args[@]}"
  latency_args=("${MODIFIED_ARGS[@]}" -dd -p 0 -o latency_candidates.csv)

  "$CloudflareST" "${latency_args[@]}" > speedtest.log 2>&1 \
    || log_msg "WARN" "Latency candidate discovery did not complete successfully"

  probe_limit=${ws_probe_candidate_limit:-20}
  if [[ ! "$probe_limit" =~ ^[1-9][0-9]*$ ]]; then
    log_msg "ERROR" "ws_probe_candidate_limit must be a positive integer"
    exit 1
  fi
  if [[ $probe_limit -lt $max_ips ]]; then
    log_msg "WARN" "ws_probe_candidate_limit is below host_ip_max; raising it to $max_ips for this run"
    probe_limit=$max_ips
  fi

  tested_count=0
  passed_count=0
  if [[ -f latency_candidates.csv ]]; then
    while IFS=, read -r ip sent recv loss lat spd colo; do
      ip=${ip//$'\r'/}
      [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || continue
      ((tested_count++))
      if probe_candidate "$ip"; then
        printf '%s\n' "$ip" >> business_valid_ips.txt
        ((passed_count++))
      fi
      [[ $tested_count -ge $probe_limit ]] && break
    done < latency_candidates.csv
  fi
  log_msg "INFO" "Business prefilter: $passed_count of $tested_count candidate(s) passed all TCP/TLS/WS stages"

  if [[ $passed_count -gt 0 ]]; then
    print "Stage 2/2: performance-testing all $passed_count business-valid candidate(s)..."
    speed_args=("${final_args[@]}")
    for value_flag in -f -ip; do
      remove_value_arg "$value_flag" "${speed_args[@]}"
      speed_args=("${MODIFIED_ARGS[@]}")
    done
    replace_value_arg -dn "$passed_count" "${speed_args[@]}"
    speed_args=("${MODIFIED_ARGS[@]}")
    speed_args+=( -f business_valid_ips.txt )
    "$CloudflareST" "${speed_args[@]}" >> speedtest.log 2>&1 \
      || log_msg "WARN" "Business-valid candidate speed test did not complete successfully"
    if [[ -s result.csv ]]; then
      result_ready=true
    else
      rm -f result.csv
      log_msg "WARN" "Business-valid candidate speed test produced no current result.csv"
    fi
  else
    rm -f result.csv
    log_msg "WARN" "No candidate passed WebSocket 101; result.csv will not be produced"
  fi
else
  print "Searching for faster IPs..."
  "$CloudflareST" "${final_args[@]}" > speedtest.log 2>&1 \
    || log_msg "WARN" "CloudflareST did not complete successfully"
  if [[ -s result.csv ]]; then
    result_ready=true
  else
    rm -f result.csv
  fi
fi

if [[ "$result_ready" == true && -f result.csv ]]; then
  candidate_count=0
  while IFS=, read -r ip sent recv loss lat spd colo; do
    ip=${ip//$'\r'/}
    [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || continue

    if [[ "$probe_enabled" == true ]]; then
      if [[ "${business_valid[$ip]:-}" != "1" ]]; then
        log_msg "WARN" "Ignoring result IP $ip because it was not in this run's business-valid candidate pool"
        continue
      fi
      if [[ -z "$spd" || "$spd" == "0.00" ]]; then
        log_msg "INFO" "Ignoring result IP $ip because no download-speed result was produced"
        continue
      fi
    fi

    [[ -n "$lat" && "$lat" != "0.00" ]] || lat="999.99"
    [[ -n "$spd" && "$spd" != "0.00" ]] || spd="0.01"
    ip_metrics["$ip"]="$lat,$spd"
    log_msg "INFO" "New candidate IP: $ip (${lat}ms / ${spd}MB/s)"
    ((candidate_count++))
  done < result.csv
  log_msg "INFO" "Found $candidate_count performance-tested candidate IP(s)"
else
  log_msg "WARN" "No current-run result.csv found; no new qualifying IPs were produced"
fi

if [[ ${#ip_metrics[@]} -eq 0 ]]; then
  log_msg "WARN" "No business-valid IP is available; DNS records are left unchanged"
  exit 0
fi

declare -a sorted_ips=()
while IFS='|' read -r spd lat score ip; do
  [[ -n "$ip" ]] && sorted_ips+=("$ip")
done < <(
  for ip in "${!ip_metrics[@]}"; do
    metrics=${ip_metrics[$ip]}
    lat=${metrics%%,*}
    spd=${metrics#*,}
    score=${business_scores[$ip]:-999999}
    printf '%s|%s|%s|%s\n' "$spd" "$lat" "$score" "$ip"
  done | sort -t '|' -k1,1nr -k2,2n -k3,3n
)

declare -a target_ips=()
for ((i = 0; i < max_ips && i < ${#sorted_ips[@]}; i++)); do
  target_ips+=("${sorted_ips[$i]}")
done

if [[ ${#target_ips[@]} -eq 0 ]]; then
  log_msg "WARN" "Selection produced no target IP; DNS records are left unchanged"
  exit 0
fi

log_msg "SUCCESS" "Selected ${#target_ips[@]} business-valid IP(s) for DNS:"
for i in "${!target_ips[@]}"; do
  ip=${target_ips[$i]}
  metrics=${ip_metrics[$ip]}
  lat=${metrics%%,*}
  spd=${metrics#*,}
  label=NEW
  for h in "${host_names[@]}"; do
    if [[ -n "${old_records["$h:$ip"]:-}" ]]; then
      label=KEEP
      break
    fi
  done
  if [[ "$probe_enabled" == true ]]; then
    log_msg "INFO" "  #$((i + 1)): $ip (${lat}ms / ${spd}MB/s, business score ${business_scores[$ip]}) [$label]"
  else
    log_msg "INFO" "  #$((i + 1)): $ip (${lat}ms / ${spd}MB/s) [$label]"
  fi
done

print "Updating DNS records for ${#host_names[@]} host(s)..."
for h in "${host_names[@]}"; do
  log_msg "INFO" "Updating DNS records for $h..."
  all_targets_present=true

  for ip in "${target_ips[@]}"; do
    if [[ -z "${old_records["$h:$ip"]:-}" ]]; then
      data=$(jq -nc --arg name "$h" --arg content "$ip" \
        '{type:"A", name:$name, content:$content, ttl:1, proxied:false}')
      response=$(curl "${curl_args[@]}" -X POST "$base_url/dns_records" "${base_header[@]}" -d "$data")
      if jq -e '.success == true' >/dev/null 2>&1 <<< "$response"; then
        new_id=$(jq -r '.result.id' <<< "$response")
        old_records["$h:$ip"]=$new_id
        log_msg "SUCCESS" "[$h] Added DNS record: $ip (ID: $new_id)"
      else
        error_msg=$(jq -r '.errors[0].message // "Unknown error"' <<< "$response" 2>/dev/null)
        log_msg "ERROR" "[$h] Failed to add $ip: $error_msg"
        all_targets_present=false
      fi
    else
      log_msg "INFO" "[$h] Keeping existing record: $ip (ID: ${old_records["$h:$ip"]})"
    fi
  done

  if [[ "$all_targets_present" != true ]]; then
    log_msg "WARN" "[$h] At least one target could not be added; obsolete records are retained for safety"
    continue
  fi

  for key in "${!old_records[@]}"; do
    cur_h=${key%%:*}
    cur_ip=${key#*:}
    [[ "$cur_h" == "$h" ]] || continue

    in_target=false
    for target_ip in "${target_ips[@]}"; do
      if [[ "$cur_ip" == "$target_ip" ]]; then
        in_target=true
        break
      fi
    done

    if [[ "$in_target" == false ]]; then
      old_id=${old_records[$key]}
      delete_response=$(curl "${curl_args[@]}" -X DELETE "$base_url/dns_records/$old_id" "${base_header[@]}")
      if jq -e '.success == true' >/dev/null 2>&1 <<< "$delete_response"; then
        log_msg "INFO" "[$h] Removed obsolete or business-invalid record: $cur_ip (ID: $old_id)"
        unset 'old_records[$key]'
      else
        log_msg "WARN" "[$h] Failed to remove record: $cur_ip (ID: $old_id)"
      fi
    fi
  done
done

log_msg "SUCCESS" "DNS update completed"
