# Cloudflare SpeedTest DDNS

**English** | [简体中文](README.zh-CN.md)

---

An intelligent DDNS update tool powered by [CloudflareSpeedTest](https://github.com/XIU2/CloudflareSpeedTest).

Current image release: `2.1.0` (`deepbluethought/cloudflarespeedtestddns:2.1.0`)

## ✨ Core Features

### ✅ Real Application Availability Gate
- **Staged validation**: Every candidate must pass TCP 443, TLS with the configured SNI, and an HTTP/1.1 WebSocket Upgrade
- **HTTP 101 only**: `403/1034`, `404`, `5xx`, and timeout responses are all rejected
- **Filter before download testing**: An application-incompatible IP never reaches final performance ranking
- **Existing records are rechecked**: Current DNS IPs cannot bypass the application gate

### 🧠 Intelligent IP Pool Management
- **Full Testing of Existing DNS Records**: Baseline test all existing IPs
- **Best N from N Strategy**: Intelligently select the best N IPs from both old and new (N = host_ip_max)
- **Speed-First Ranking**: HTTP `101` is a hard gate; every passing candidate is download-tested and ranked by speed, then latency and handshake time
- **Keep Healthy IPs**: Retain existing IPs only while they still pass the real application probe

### 📊 Dynamic Threshold Calculation
- **Worst-Case Performance Standards**: Use worst latency & speed from existing IPs as search thresholds
- **Adaptive Optimization**: Automatically adjust search criteria based on current network conditions
- **Availability Before Speed**: Replace an application-invalid IP even when its raw network benchmark looks fast
- **Smart Fallback**: Use safe defaults (latency <100ms, speed >1MB/s) if tests fail

### 🔒 Safe DNS Update Strategy
- **Seamless Transition**: Add new IP records first, then remove old ones
- **Zero Downtime**: Avoid DNS resolution gaps
- **Failure Protection**: Keep all old records if new IP additions fail
- **Safe Convergence**: Delete obsolete records only after every target record is confirmed present

### 📝 Clear Logging Output
- **Real-time Progress**: Show testing progress and candidate IP discovery
- **Explicit Tags**: Mark IPs with `[NEW]` and `[KEEP]` labels
- **Detailed Metrics**: Display HTTP failure reason plus TCP/TLS/WS timing, latency, and download speed
- **Update Summary**: Show counts of added, kept, and removed IPs

### 🐳 Full Docker Support
- **Multiple Startup Methods**: Support both docker-compose and docker run
- **Cross-Platform**: Support AMD64 and ARM64 architectures
- **Environment Variable Configuration**: Manage all parameters via `.env` file
- **Automated Deployment**: GitHub Actions auto-build and push to DockerHub

### ⏰ Flexible Scheduling
- **Cron Expression**: Support any scheduling strategy (hourly, every 30 min, etc.)
- **Manual Execution**: Trigger tests manually anytime
- **Container Auto-Run**: Lightweight scheduling based on dcron

### 🎯 Single-IP First
- **One A record by default**: `host_ip_max` defaults to `1`, preventing clients and DNS caches from randomly selecting a worse IP
- **Multi-IP remains optional**: Increase `host_ip_max` only when DNS round-robin is intentional; every retained IP must pass the application probe

### 🛠️ Additional Enhancements
- **Version Configuration + Fallback Mechanism**:
  - Specify CloudflareSpeedTest version via environment variable
  - Automatically download specified version on container startup
  - Fallback to pre-installed v2.3.5 if download fails
  - Ensures container starts successfully in any network environment

- **Cloudflare IP List Auto-Update**:
  - Automatically fetch latest IP ranges from Cloudflare official API
  - Support new nodes, automatically exclude offline nodes
  - No manual maintenance required, always up-to-date

## 🚀 Quick Start

### Method 1: Using Docker Compose (Recommended)

1. **Create `docker-compose.yml` file**
   ```yaml
   services:
     cloudflare-speedtest-ddns:
       image: deepbluethought/cloudflarespeedtestddns:latest
       container_name: cloudflare-ddns
       environment:
         - CLOUDFLARE_ST_VERSION=v2.3.5
         - zone_id=${zone_id}
         - api_token=${api_token}
         - host_name=${host_name}
         - host_ip_max=${host_ip_max}
         - ws_probe_enabled=${ws_probe_enabled}
         - ws_probe_host=${ws_probe_host}
         - ws_probe_path=${ws_probe_path}
         - speedtest_para=${speedtest_para}
         - cron=${cron}
         - healthcheck_cron=${healthcheck_cron}
       restart: unless-stopped
   ```

2. **Create `.env` file in the same directory**
   ```env
   zone_id=your_cloudflare_zone_id
   api_token=your_cloudflare_api_token
   host_name=testip.yourdomain.com
   host_ip_max=1
   ws_probe_enabled=true
   ws_probe_host=www.yourdomain.com
   ws_probe_path=/your-websocket-path
   ws_probe_tls_verify=true
   ws_probe_candidate_limit=20
   speedtest_para=-n 1000 -dn 2 -sl 5 -tl 100 -url https://download.parallels.com/desktop/v18/18.1.1-53328/ParallelsDesktop-18.1.1-53328.dmg
   cron=0 * * * *
   healthcheck_cron=15,45 * * * *
   ```

3. **Start the container**
   ```bash
   docker compose up -d
   ```

4. **View logs**
   ```bash
   docker compose logs -f
   ```

5. **Manually execute a test** (optional)
   ```bash
   docker compose exec cloudflare-speedtest-ddns bash -c "cd /app && bash main.sh"
   ```

> **Note**: If you want to build from source instead, clone the repository first:
> ```bash
> git clone https://github.com/DeepBlueThought/Cloudflare-SpeedTest-DDNS.git
> cd Cloudflare-SpeedTest-DDNS
> # Then modify docker-compose.yml to use "build: ." instead of "image:"
> ```

---

### Method 2: Using Docker Run

#### Using Environment File (Recommended)

```bash
docker run -d \
  --name cloudflare-ddns \
  --restart unless-stopped \
  --env-file .env \
  deepbluethought/cloudflarespeedtestddns:latest
```

#### Manually Specify All Parameters

```bash
docker run -d \
  --name cloudflare-ddns \
  `# Container name` \
  \
  --restart unless-stopped \
  `# Restart policy: always restart unless manually stopped` \
  \
  -e CLOUDFLARE_ST_VERSION=v2.3.5 \
  `# CloudflareSpeedTest version (optional, default v2.3.5)` \
  `# Fallback to pre-installed version if download fails` \
  \
  -e zone_id="your_cloudflare_zone_id" \
  `# Cloudflare Zone ID` \
  `# How to get: Cloudflare → Select domain → Zone ID in right sidebar` \
  \
  -e api_token="your_cloudflare_api_token" \
  `# Cloudflare API Token` \
  `# How to get: Cloudflare → My Profile → API Tokens → Create Token` \
  `# Required permission: Zone.DNS (Edit)` \
  \
  -e host_name="testip.yourdomain.com" \
  `# Domain to update (supports subdomains)` \
  \
  -e host_ip_max=1 \
  `# One application-valid IP avoids random DNS selection` \
  \
  -e ws_probe_enabled=true \
  -e ws_probe_host="www.yourdomain.com" \
  -e ws_probe_path="/your-websocket-path" \
  `# Real TLS SNI/HTTP Host and WebSocket path` \
  \
  -e speedtest_para="-n 1000 -dn 2 -sl 5 -tl 100 -url https://download.parallels.com/desktop/v18/18.1.1-53328/ParallelsDesktop-18.1.1-53328.dmg" \
  `# CloudflareSpeedTest parameters:` \
  `#   -n 1000    : Latency test threads (max 1000, higher for better performance)` \
  `#   -dn 2      : Ordinary-mode download count; WS mode tests every passing candidate` \
  `#   -sl 5      : Minimum speed threshold 5 MB/s (dynamically adjusted)` \
  `#   -tl 100    : Maximum latency threshold 100 ms (dynamically adjusted)` \
  `#   -url       : Speed test file URL (recommend large file via Cloudflare CDN)` \
  \
  -e cron="0 * * * *" \
  `# Linux Cron expression for scheduling tests` \
  `# Examples:` \
  `#   "0 * * * *"      Run every hour` \
  `#   "*/30 * * * *"   Run every 30 minutes` \
  `#   "0 */6 * * *"    Run every 6 hours` \
  \
  -e healthcheck_cron="15,45 * * * *" \
  `# Lightweight current-IP check every 30 minutes; reselect on failure` \
  \
  deepbluethought/cloudflarespeedtestddns:latest
```

#### Manually Execute One Test (Without Cron)

```bash
docker run --rm \
  --env-file .env \
  deepbluethought/cloudflarespeedtestddns:latest \
  bash -c "cd /app && bash main.sh"
```

---

## 📖 Docker Compose Configuration Example

Complete `docker-compose.yml` example:

```yaml
services:
  cloudflare-speedtest-ddns:
    build: .
    container_name: cloudflare-ddns
    environment:
      # CloudflareSpeedTest version (optional, default v2.3.5)
      - CLOUDFLARE_ST_VERSION=v2.3.5
      
      # Cloudflare API Configuration
      - zone_id=${zone_id}
      - api_token=${api_token}
      
      # Domain Configuration
      - host_name=${host_name}
      - host_ip_max=${host_ip_max}

      # Real WebSocket application configuration
      - ws_probe_enabled=${ws_probe_enabled}
      - ws_probe_host=${ws_probe_host}
      - ws_probe_path=${ws_probe_path}
      - ws_probe_tls_verify=${ws_probe_tls_verify}
      - ws_probe_candidate_limit=${ws_probe_candidate_limit}
      
      # CloudflareSpeedTest Parameters (read from .env)
      - speedtest_para=${speedtest_para}
      
      # Linux Cron Expression
      # Example: "0 * * * *" runs every hour
      # Example: "*/30 * * * *" runs every 30 minutes
      - cron=${cron}
      - healthcheck_cron=${healthcheck_cron}
      - log_file=${log_file}
    restart: unless-stopped
```

## 📋 Environment Variables

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `CLOUDFLARE_ST_VERSION` | No | v2.3.5 | CloudflareSpeedTest version (fallback on failure) |
| `host_name` | Yes | - | Domain name to update. Supports multiple domain names separated by commas or spaces (e.g., `cf1.example.com,cf2.example.com`). |
| `host_ip_max` | No | 1 | Number of DNS A records to retain; single-IP mode is recommended |
| `zone_id` | Yes | - | Cloudflare Zone ID, obtain from Cloudflare dashboard |
| `api_token` | Yes | - | Cloudflare API Token, obtain from Cloudflare dashboard |
| `speedtest_para` | Yes | - | Test parameters, see details below |
| `cron` | Yes | - | Cron expression for scheduling |
| `ws_probe_enabled` | No | auto | `auto` enables the gate when `ws_probe_host` is set; may be explicitly `true` or `false` |
| `ws_probe_host` | With probe | - | Real TLS SNI and HTTP Host, such as `www.example.com`; no scheme, port, or path |
| `ws_probe_path` | No | / | WebSocket request path, such as `/deepblue` |
| `ws_probe_tls_verify` | No | true | Verify the certificate chain and hostname; disabling it is not recommended |
| `ws_probe_candidate_limit` | No | 20 | Number of lowest-latency candidates that receive the full application probe |
| `ws_probe_tcp_timeout` / `ws_probe_tls_timeout` / `ws_probe_http_timeout` | No | 3 / 5 / 8 | Per-stage timeout in seconds |
| `healthcheck_cron` | No | `15,45 * * * *` | Current-DNS-IP probe; launches a full reselection on failure |
| `log_file` | No | `/tmp/cloudflare-bestip.log` | Plain runtime log path (`/tmp` does not survive container recreation) |

### speedtest_para Parameters

- `-n`: Latency test threads; more threads = faster testing, but don't set too high on weak devices (routers); default 200, max 1000
- `-dn`: Download test count. When WebSocket probing is enabled, the program overrides this for stage 2 so every business-valid candidate is download-tested.
- `-sl`: Minimum speed threshold in MB/s (uses the slowest business-valid current record, or 1 MB/s without a baseline)
- `-tl`: Maximum latency threshold in ms (uses the slowest business-valid current record, with a 20 ms floor and 100 ms fallback)

**Note**: `-sl` and `-tl` are replaced by the dynamic baseline values described above. Other `speedtest_para` options are preserved.

## 📊 Workflow

1. Fetch current DNS A records and recheck each old IP using the real `ws_probe_host` and `ws_probe_path`.
2. Run CloudflareST in latency-only mode (`-dd`) and take the first `ws_probe_candidate_limit` results.
3. Run TCP 443, TLS SNI, and WebSocket Upgrade checks in order; only HTTP `101` enters the usable pool.
4. Run CloudflareSpeedTest download testing against every IP in that usable pool.
5. Rank by download speed descending, then latency and WebSocket handshake score. Availability remains a hard gate and cannot be compensated by speed.
6. Ensure replacement records exist before deleting obsolete records. If an add fails, old records are retained.
7. The watchdog periodically checks only current DNS IPs and launches a full reselection if any stops returning `101`.

> `host_name` is the DDNS record being written. `ws_probe_host` is the actual Cloudflare application Host/SNI. They may differ, so the program does not guess this mapping.

> HTTP `101` measures WebSocket handshake availability, not VLESS/Xray payload throughput. This project does not bundle or run Xray; download speed remains the closest in-scope performance metric after the real-business gate.

**Note:**
CloudflareSpeedTest tool workflow:
1. Latency test (default TCPing mode, HTTPing requires manual parameter)
2. Latency sorting (sorted low to high with filtering, different packet loss rates sorted separately)
3. Download test (test from lowest latency IPs, default stops after 10)
4. Speed sorting (sorted high to low)
5. Output results (controlled by parameters: command line (-p 0) or file (-o ""))

### Quick Test

```bash
# Offline regression tests; no Cloudflare credentials required
bash tests/business_probe_test.sh
bash tests/main_flow_test.sh
bash tests/healthcheck_test.sh

# Local test script
./test.sh

# Build and push to Docker Hub (interactive)
./build-and-push.sh
```

## 📝 Example Logs

### WebSocket application gate

```text
[2026-08-10 04:38:00] [INFO] Business probe 162.159.44.212: TLS SNI OK (www.example.com)
[2026-08-10 04:38:00] [WARN] Business probe 162.159.44.212: WS FAIL (HTTP 403: error code: 1034)
[2026-08-10 04:38:01] [SUCCESS] Business probe 172.64.229.53: WS 101 OK (TCP 20.00ms, TLS 55.00ms, WS 105.00ms, score 69.50)
[2026-08-10 04:38:01] [SUCCESS] Selected 1 business-valid IP(s) for DNS:
```

### IP List Auto-Update
```
2026-02-06 14:00:00 Updating Cloudflare IP list...
2026-02-06 14:00:01 ✓ Successfully updated IP list from Cloudflare (14 ranges)
```

Or on network error:
```
2026-02-06 14:00:00 Updating Cloudflare IP list...
2026-02-06 14:00:10 ⚠ Failed to download IP list from Cloudflare
2026-02-06 14:00:10 → Using backup IP list
```

### Version Download Success
```
Attempting to download CloudflareSpeedTest v2.3.0...
Download successful, extracting...
✓ CloudflareSpeedTest v2.3.0 installed successfully
CloudflareSpeedTest is ready
```

### Version Download Failed (Fallback)
```
Attempting to download CloudflareSpeedTest v9.9.9...
⚠ Failed to download CloudflareSpeedTest v9.9.9
⚠ Reason: Network error or version not found
→ Using fallback version v2.3.5 (pre-installed)
✓ Fallback to CloudflareSpeedTest v2.3.5 successfully
CloudflareSpeedTest is ready
```

### Smart Comparison Execution
```
2026-02-06 12:00:00 Getting current DNS A record...
2026-02-06 12:00:01 Found current DNS IP: 1.1.1.1
2026-02-06 12:00:01 Performing baseline test on current IP: 1.1.1.1
2026-02-06 12:00:15 Baseline test results - Latency: 45.23ms, Speed: 35.67MB/s
2026-02-06 12:00:15 Using dynamic test parameters - Latency threshold: 45ms, Speed threshold: 35MB/s
2026-02-06 12:00:15 Start execute the speedtest with parameters: -n 800 -dn 1 -sl 35 -tl 45
2026-02-06 12:05:30 Best test result - IP: 1.0.0.1, Latency: 42.10ms, Speed: 38.21MB/s
2026-02-06 12:05:30 New IP is better than current baseline, will update DNS
2026-02-06 12:05:31 Successfully added dns: your.domain.com with ip address: 1.0.0.1
```

## 🤝 Contributing

Issues and Pull Requests are welcome!

## 📄 License

MIT License
