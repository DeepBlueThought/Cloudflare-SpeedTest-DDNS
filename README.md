# Cloudflare SpeedTest DDNS

**English** | [简体中文](README.zh-CN.md)

---

An intelligent DDNS update tool powered by [CloudflareSpeedTest](https://github.com/XIU2/CloudflareSpeedTest).

## ✨ Core Features

### 🧠 Intelligent IP Pool Management
- **Full Testing of Existing DNS Records**: Baseline test all existing IPs
- **Best N from N Strategy**: Intelligently select the best N IPs from both old and new (N = host_ip_max)
- **Performance-Based Ranking**: Comprehensive scoring based on latency and speed
- **Keep High-Quality IPs**: Retain existing IPs if they're still performing well

### 📊 Dynamic Threshold Calculation
- **Worst-Case Performance Standards**: Use worst latency & speed from existing IPs as search thresholds
- **Adaptive Optimization**: Automatically adjust search criteria based on current network conditions
- **Prevent Performance Degradation**: Only update when better IPs are found
- **Smart Fallback**: Use safe defaults (latency <100ms, speed >1MB/s) if tests fail

### 🔒 Safe DNS Update Strategy
- **Seamless Transition**: Add new IP records first, then remove old ones
- **Zero Downtime**: Avoid DNS resolution gaps
- **Failure Protection**: Keep all old records if new IP additions fail
- **Atomic Operations**: Ensure DNS records are always valid

### 📝 Clear Logging Output
- **Real-time Progress**: Show testing progress and candidate IP discovery
- **Explicit Tags**: Mark IPs with `[NEW]` and `[KEEP]` labels
- **Detailed Metrics**: Display latency, speed, and datacenter location for each IP
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

### 🔢 Multi-IP Load Balancing
- **Configurable Count**: Control DNS record count via `host_ip_max` parameter
- **Load Distribution**: Multiple A records for simple load balancing
- **Fault Tolerance**: Other IPs remain available if one fails

### 🛠️ Additional Enhancements
- **Version Configuration + Fallback Mechanism**:
  - Specify CloudflareSpeedTest version via environment variable
  - Automatically download specified version on container startup
  - Fallback to pre-installed v2.3.4 if download fails
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
         - CLOUDFLARE_ST_VERSION=v2.3.4
         - zone_id=${zone_id}
         - api_token=${api_token}
         - host_name=${host_name}
         - host_ip_max=${host_ip_max}
         - speedtest_para=${speedtest_para}
         - cron=${cron}
       restart: unless-stopped
   ```

2. **Create `.env` file in the same directory**
   ```env
   zone_id=your_cloudflare_zone_id
   api_token=your_cloudflare_api_token
   host_name=testip.yourdomain.com
   host_ip_max=2
   speedtest_para=-n 1000 -dn 2 -sl 5 -tl 100 -url https://download.parallels.com/desktop/v18/18.1.1-53328/ParallelsDesktop-18.1.1-53328.dmg
   cron=0 * * * *
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
  -e CLOUDFLARE_ST_VERSION=v2.3.4 \
  `# CloudflareSpeedTest version (optional, default v2.3.4)` \
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
  -e host_ip_max=2 \
  `# Maximum number of IPs in DNS (recommended: 2 for load balancing + fault tolerance)` \
  \
  -e speedtest_para="-n 1000 -dn 2 -sl 5 -tl 100 -url https://download.parallels.com/desktop/v18/18.1.1-53328/ParallelsDesktop-18.1.1-53328.dmg" \
  `# CloudflareSpeedTest parameters:` \
  `#   -n 1000    : Latency test threads (max 1000, higher for better performance)` \
  `#   -dn 2      : Download test count (stops after finding 2 qualifying IPs)` \
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
      # CloudflareSpeedTest version (optional, default v2.3.4)
      - CLOUDFLARE_ST_VERSION=v2.3.4
      
      # Cloudflare API Configuration
      - zone_id=${zone_id}
      - api_token=${api_token}
      
      # Domain Configuration
      - host_name=${host_name}
      - host_ip_max=${host_ip_max}
      
      # CloudflareSpeedTest Parameters (read from .env)
      - speedtest_para=${speedtest_para}
      
      # Linux Cron Expression
      # Example: "0 * * * *" runs every hour
      # Example: "*/30 * * * *" runs every 30 minutes
      - cron=${cron}
    restart: unless-stopped
```

## 📋 Environment Variables

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `CLOUDFLARE_ST_VERSION` | No | v2.3.4 | CloudflareSpeedTest version (fallback on failure) |
| `host_name` | Yes | - | Domain name to update |
| `host_ip_max` | No | 2 | Maximum IPs to add to DNS (default 2 for load balancing + failover) |
| `zone_id` | Yes | - | Cloudflare Zone ID, obtain from Cloudflare dashboard |
| `api_token` | Yes | - | Cloudflare API Token, obtain from Cloudflare dashboard |
| `speedtest_para` | Yes | - | Test parameters, see details below |
| `cron` | Yes | - | Cron expression for scheduling |

### speedtest_para Parameters

- `-n`: Latency test threads; more threads = faster testing, but don't set too high on weak devices (routers); default 200, max 1000
- `-dn`: Download test count; number of IPs to test from lowest latency; default 10. When `-sl` parameter is configured, download testing stops when the number of IPs meeting the download speed threshold reaches the `-dn` value. **Recommended: 2**
- `-sl`: Minimum speed threshold in MB/s (dynamically adjusted to `max(baseline speed, 20)`)
- `-tl`: Maximum latency threshold in ms (dynamically adjusted to `min(baseline latency, 100)`)

**Note**: `-sl` and `-tl` parameters are dynamically adjusted based on baseline test. Values in speedtest_para serve as default thresholds.

## 📊 Workflow

1. **Container Startup**
   - Attempt to download specified CloudflareSpeedTest version
   - If download fails → Use pre-installed v2.3.4 (fallback)
   - Output detailed logs about version used
   
2. **Scheduled Task Trigger**
   - Automatically update IP range list from Cloudflare official API
   - Get current DNS A record IP
   - Perform latency and speed tests on current IP (using CloudflareSpeedTest) [Baseline Test]
   - Obtain baseline latency t and speed s
   - Use `min(t,100)` and `max(s,20)` as test thresholds [Smart Comparison]
   - Execute full CloudflareSpeedTest
   - Only update DNS when new IP meets latency ≤ t AND speed ≥ s
   
3. **Quality Assurance**
   - Every update guarantees network quality improvement
   - Won't degrade network due to occasional test fluctuations

**Note:**
CloudflareSpeedTest tool workflow:
1. Latency test (default TCPing mode, HTTPing requires manual parameter)
2. Latency sorting (sorted low to high with filtering, different packet loss rates sorted separately)
3. Download test (test from lowest latency IPs, default stops after 10)
4. Speed sorting (sorted high to low)
5. Output results (controlled by parameters: command line (-p 0) or file (-o ""))

### Quick Test

```bash
# Local test script
./test.sh

# Build and push to Docker Hub (interactive)
./build-and-push.sh
```

## 📝 Example Logs

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
→ Using fallback version v2.3.4 (pre-installed)
✓ Fallback to CloudflareSpeedTest v2.3.4 successfully
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
