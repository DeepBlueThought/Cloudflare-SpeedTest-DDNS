#!/bin/bash

# Cloudflare SpeedTest DDNS - Final Stable Version
SCRIPT_NAME="$(basename "$0")"
SCRIPT_PID=$$

log_msg() {
  local level="$1"
  local message="$2"
  local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
  local color_reset="\033[0m"
  local color_info="\033[0;36m"
  local color_success="\033[0;32m"
  local color_error="\033[0;31m"
  
  local c=""
  [[ "$level" == "INFO" ]] && c="$color_info"
  [[ "$level" == "SUCCESS" ]] && c="$color_success"
  [[ "$level" == "ERROR" ]] && c="$color_error"
  
  echo -e "${c}[${timestamp}] [${level}]${color_reset} ${message}"
}

print() { log_msg "INFO" "$1"; }

# 1. Update IP list
update_ip_list() {
  local ip_file="ip.txt"
  if curl -s --max-time 10 https://www.cloudflare.com/ips-v4 -o "${ip_file}.tmp"; then
    if [ -s "${ip_file}.tmp" ] && grep -qE '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/[0-9]+$' "${ip_file}.tmp"; then
      mv "${ip_file}.tmp" "$ip_file"
      log_msg "SUCCESS" "IP list updated from Cloudflare"
    else
      rm -f "${ip_file}.tmp"
    fi
  fi
}

update_ip_list

# 2. Cloudflare API Auth
base_url="https://api.cloudflare.com/client/v4/zones/$zone_id"
base_header=(-H "Authorization: Bearer $api_token" -H "Content-Type:application/json")
curl_args=(-sm15)
[[ -n "$proxy_url" ]] && curl_args+=(--proxy "$proxy_url")

log_msg "INFO" "Checking Cloudflare authentication..."
response=$(curl "${curl_args[@]}" -X GET "$base_url" "${base_header[@]}")
if ! echo "$response" | jq -e '.success' 2>/dev/null | grep -q 'true'; then
  log_msg "ERROR" "Authentication failed: $response"
  exit 1
fi
log_msg "SUCCESS" "Authentication successful"

# 3. Binary Selection
os=$(uname -s); arch=$(uname -m)

if [[ "$os" == "Darwin" ]]; then
  [[ "$arch" == "arm64" ]] && CloudflareST="./CloudflareST_darwin_arm64"
  [[ "$arch" == "x86_64" ]] && CloudflareST="./CloudflareST_darwin_amd64"
elif [[ "$os" == "Linux" ]]; then
  [[ "$arch" == "x86_64" || "$arch" == "amd64" ]] && CloudflareST="./CloudflareST_amd64"
  [[ "$arch" == "aarch64" || "$arch" == "arm64" ]] && CloudflareST="./CloudflareST_arm64"
fi

if [[ ! -f "$CloudflareST" ]]; then
  log_msg "ERROR" "CloudflareST binary not found: $CloudflareST (OS: $os, Arch: $arch)"
  exit 1
fi

chmod +x "$CloudflareST" 2>/dev/null || true

# 4. Test existing DNS records and build IP pool
response=$(curl "${curl_args[@]}" -X GET "$base_url/dns_records?name=$host_name&type=A" "${base_header[@]}")
declare -A old_ip_to_id  # IP -> DNS Record ID 映射
declare -A ip_metrics    # IP -> "latency,speed" 指标

# 提取现有记录
while IFS= read -r line; do
  ip=$(echo "$line" | jq -r '.content')
  id=$(echo "$line" | jq -r '.id')
  old_ip_to_id["$ip"]=$id
done < <(echo "$response" | jq -c '.result[]')

# 测速URL
test_url=$(echo "$speedtest_para" | grep -oE "\-url [^ ]+" | awk '{print $2}')
[[ -z "$test_url" ]] && test_url="https://download.parallels.com/desktop/v18/18.1.1-53328/ParallelsDesktop-18.1.1-53328.dmg"

# 测试现有IP
if [[ ${#old_ip_to_id[@]} -gt 0 ]]; then
  print "Testing ${#old_ip_to_id[@]} existing DNS record(s)..."
  
  rm -f baseline_ips.txt
  for ip in "${!old_ip_to_id[@]}"; do
    echo "$ip" >> baseline_ips.txt
  done
  
  $CloudflareST -f baseline_ips.txt -n 100 -dn ${#old_ip_to_id[@]} -url "$test_url" -dt 5 -o baseline_result.csv > /dev/null 2>&1
  
  if [[ -f baseline_result.csv ]]; then
    while IFS=, read -r ip sent recv loss lat spd colo; do
      [[ "$ip" == "IP 地址" ]] && continue  # 跳过标题行
      
      # 如果测试失败，设为极差值
      [[ -z "$lat" || "$lat" == "0.00" ]] && lat="999.99"
      [[ -z "$spd" || "$spd" == "0.00" ]] && spd="0.01"
      
      ip_metrics["$ip"]="$lat,$spd"
      log_msg "INFO" "Existing IP $ip: ${lat}ms / ${spd}MB/s"
    done < baseline_result.csv
  fi
  rm -f baseline_ips.txt baseline_result.csv
else
  print "No existing DNS records found."
fi

# 5. 计算动态阈值（基于现有IP的最差性能）
worst_latency=0
worst_speed=999999

for metrics in "${ip_metrics[@]}"; do
  lat=$(echo "$metrics" | cut -d',' -f1)
  spd=$(echo "$metrics" | cut -d',' -f2)
  
  if (( $(echo "$lat > $worst_latency" | bc -l) )); then
    worst_latency=$lat
  fi
  
  if (( $(echo "$spd < $worst_speed" | bc -l) )); then
    worst_speed=$spd
  fi
done

# 设置阈值
tl_param=$(printf "%.0f" "$worst_latency")
tl_param=$((tl_param > 0 ? tl_param : 100))
[[ $tl_param -lt 20 ]] && tl_param=20

sl_param=$(printf "%.0f" "$worst_speed")
sl_param=$((sl_param > 0 && sl_param < 999999 ? sl_param : 1))

print "Search thresholds: Latency < ${tl_param}ms, Speed > ${sl_param}MB/s"

# 6. 搜索新的优质IP
final_para=$(echo "$speedtest_para" | sed -E "s/-tl [0-9]+/-tl $tl_param/g" | sed -E "s/-sl [0-9]+/-sl $sl_param/g")
[[ ! "$final_para" =~ "-url" ]] && final_para="$final_para -url $test_url"

print "Searching for better IPs..."
$CloudflareST $final_para > speedtest.log 2>&1

# 7. 合并新旧IP并选择最优的N个
max_ips=${host_ip_max:-2}

if [[ -f result.csv ]]; then
  # 读取所有新候选IP（包括可能与现有IP重复的）
  candidate_count=0
  while IFS=, read -r ip sent recv loss lat spd colo; do
    [[ "$ip" == "IP 地址" ]] && continue
    
    [[ -z "$lat" || "$lat" == "0.00" ]] && lat="999.99"
    [[ -z "$spd" || "$spd" == "0.00" ]] && spd="0.01"
    
    # 如果IP已存在，更新其指标（使用新的测试结果）
    ip_metrics["$ip"]="$lat,$spd"
    log_msg "INFO" "New candidate IP: $ip (${lat}ms / ${spd}MB/s)"
    ((candidate_count++))
  done < result.csv
  
  if [[ $candidate_count -eq 0 ]]; then
    log_msg "INFO" "No new candidate IPs found matching the criteria"
  else
    log_msg "SUCCESS" "Found $candidate_count new candidate IP(s)"
  fi
else
  log_msg "INFO" "No result.csv found - CloudflareST did not find any qualifying IPs"
fi

# 如果没有找到任何IP（新旧都没有）
if [[ ${#ip_metrics[@]} -eq 0 ]]; then
  log_msg "SUCCESS" "No IPs available for DNS update"
  rm -f result.csv speedtest.log
  exit 0
fi

# 对所有IP按性能排序（延迟优先，速度次之）
declare -a sorted_ips
while IFS= read -r line; do
  sorted_ips+=("$(echo "$line" | awk '{print $2}')")
done < <(
  for ip in "${!ip_metrics[@]}"; do
    metrics="${ip_metrics[$ip]}"
    lat=$(echo "$metrics" | cut -d',' -f1)
    spd=$(echo "$metrics" | cut -d',' -f2)
    # 输出格式：score IP
    # score = latency * 1000 - speed (越小越好)
    score=$(echo "$lat * 1000 - $spd" | bc -l)
    echo "$score $ip"
  done | sort -n
)

# 选择前N个最优IP
declare -a target_ips
for i in $(seq 0 $((max_ips - 1))); do
  [[ -n "${sorted_ips[$i]}" ]] && target_ips+=("${sorted_ips[$i]}")
done

log_msg "SUCCESS" "Selected top ${#target_ips[@]} IP(s) for DNS:"
for i in "${!target_ips[@]}"; do
  ip="${target_ips[$i]}"
  metrics="${ip_metrics[$ip]}"
  lat=$(echo "$metrics" | cut -d',' -f1)
  spd=$(echo "$metrics" | cut -d',' -f2)
  
  # 判断是新IP还是保留的旧IP
  if [[ -n "${old_ip_to_id[$ip]}" ]]; then
    log_msg "INFO" "  #$((i+1)): $ip (${lat}ms / ${spd}MB/s) [KEEP]"
  else
    log_msg "INFO" "  #$((i+1)): $ip (${lat}ms / ${spd}MB/s) [NEW]"
  fi
done

# 8. 更新DNS记录（先添加新的，再删除多余的）
print "Updating DNS records..."
declare -A target_ip_to_new_id

# 添加目标IP（如果不存在）
for ip in "${target_ips[@]}"; do
  if [[ -z "${old_ip_to_id[$ip]}" ]]; then
    # 这是新IP，需要添加
    data="{\"type\":\"A\",\"name\":\"$host_name\",\"content\":\"$ip\",\"ttl\":1,\"proxied\":false}"
    response=$(curl "${curl_args[@]}" -X POST "$base_url/dns_records" "${base_header[@]}" -d "$data")
    
    if echo "$response" | jq -e '.success' > /dev/null; then
      new_id=$(echo "$response" | jq -r '.result.id')
      target_ip_to_new_id["$ip"]=$new_id
      log_msg "SUCCESS" "Added DNS record: $ip (ID: $new_id)"
    else
      error_msg=$(echo "$response" | jq -r '.errors[0].message // "Unknown error"')
      log_msg "ERROR" "Failed to add $ip: $error_msg"
    fi
  else
    # 旧IP保留
    target_ip_to_new_id["$ip"]="${old_ip_to_id[$ip]}"
    log_msg "INFO" "Keeping existing record: $ip (ID: ${old_ip_to_id[$ip]})"
  fi
done

# 删除不在目标列表中的旧IP
for ip in "${!old_ip_to_id[@]}"; do
  # 检查是否在目标列表中
  in_target=false
  for target_ip in "${target_ips[@]}"; do
    [[ "$ip" == "$target_ip" ]] && in_target=true && break
  done
  
  if [[ "$in_target" == false ]]; then
    old_id="${old_ip_to_id[$ip]}"
    if curl "${curl_args[@]}" -X DELETE "$base_url/dns_records/$old_id" "${base_header[@]}" | jq -e '.success' > /dev/null 2>&1; then
      log_msg "INFO" "Removed obsolete record: $ip (ID: $old_id)"
    else
      log_msg "WARN" "Failed to remove: $ip (ID: $old_id)"
    fi
  fi
done

log_msg "SUCCESS" "DNS update completed"

rm -f result.csv speedtest.log
