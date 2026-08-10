# Cloudflare SpeedTest DDNS

🚀 An intelligent DDNS update tool that automatically finds the fastest Cloudflare IP and updates your DNS records.

Current image release: `2.0.0` (`deepbluethought/cloudflarespeedtestddns:2.0.0`)

## ✨ Key Features

- **🧠 Intelligent IP Pool Management** - Tests all existing DNS records and selects the best N IPs
- **✅ WebSocket Application Gate** - Requires TCP 443, TLS SNI, and HTTP `101 Switching Protocols`
- **📊 Dynamic Threshold Calculation** - Adapts search criteria based on current network conditions
- **🔒 Safe DNS Updates** - Zero-downtime updates with rollback protection
- **🐳 Full Docker Support** - Works with both docker-compose and docker run
- **🎯 Single-IP by Default** - Avoids clients randomly selecting an application-incompatible record
- **⏰ Flexible Scheduling** - Customizable cron jobs for automated testing

## 🚀 Quick Start

### Using Docker Compose (Recommended)

```bash
git clone https://github.com/DeepBlueThought/Cloudflare-SpeedTest-DDNS.git
cd Cloudflare-SpeedTest-DDNS
cp .env.example .env
# Edit .env with your Cloudflare credentials
docker compose up -d
```

### Using Docker Run

```bash
docker run -d \
  --name cloudflare-ddns \
  --restart unless-stopped \
  -e zone_id="your_cloudflare_zone_id" \
  -e api_token="your_cloudflare_api_token" \
  -e host_name="testip.yourdomain.com" \
  -e host_ip_max=1 \
  -e ws_probe_enabled=true \
  -e ws_probe_host="www.yourdomain.com" \
  -e ws_probe_path="/your-websocket-path" \
  -e speedtest_para="-n 1000 -dn 2 -sl 5 -tl 100" \
  -e cron="0 * * * *" \
  -e healthcheck_cron="15,45 * * * *" \
  deepbluethought/cloudflarespeedtestddns:latest
```

## 📋 Environment Variables

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `zone_id` | Yes | - | Cloudflare Zone ID |
| `api_token` | Yes | - | Cloudflare API Token (needs Zone.DNS edit permission) |
| `host_name` | Yes | - | Domain to update (e.g., testip.example.com) |
| `host_ip_max` | No | 1 | Number of IPs to maintain; single-IP mode is recommended |
| `speedtest_para` | Yes | - | CloudflareSpeedTest parameters |
| `cron` | Yes | - | Cron expression for scheduling (e.g., "0 * * * *" for hourly) |
| `ws_probe_host` | For WS gate | - | Real TLS SNI and HTTP Host used by the application |
| `ws_probe_path` | No | / | WebSocket path, such as `/deepblue` |
| `healthcheck_cron` | No | `15,45 * * * *` | Current-IP watchdog schedule |

## 🔧 Configuration Example

**`.env` file:**
```env
zone_id=your_zone_id_here
api_token=your_api_token_here
host_name=testip.yourdomain.com
host_ip_max=1
ws_probe_enabled=true
ws_probe_host=www.yourdomain.com
ws_probe_path=/your-websocket-path
speedtest_para="-n 1000 -dn 2 -sl 5 -tl 100 -url https://download.example.com/largefile.bin"
cron=0 * * * *
healthcheck_cron=15,45 * * * *
```

### Getting Cloudflare Credentials

1. **Zone ID**: Login to Cloudflare → Select your domain → Zone ID in the right sidebar
2. **API Token**: Cloudflare → My Profile → API Tokens → Create Token
   - Template: Edit zone DNS
   - Permissions: Zone.DNS (Edit)

## 📊 How It Works

1. **Existing-IP Gate** - Rechecks current DNS IPs against the real WebSocket Host/path
2. **Latency Discovery** - Finds low-latency candidates without download testing
3. **Application Gate** - Rejects every candidate that does not return HTTP 101
4. **Performance Test** - Download-tests only the business-valid pool
5. **Safe Update** - Adds the selected IP before removing rejected or obsolete records

## 📝 Example Logs

```
[2026-02-09 12:00:00] [INFO] Testing 2 existing DNS record(s)...
[2026-02-09 12:00:10] [INFO] Existing IP 1.0.0.1: 45.23ms / 35.67MB/s
[2026-02-09 12:00:10] [INFO] Existing IP 1.0.0.2: 48.10ms / 32.10MB/s
[2026-02-09 12:00:10] [INFO] Search thresholds: Latency < 48ms, Speed > 32MB/s
[2026-02-09 12:00:10] [INFO] Searching for better IPs...
[2026-02-09 12:05:30] [INFO] New candidate IP: 1.0.0.3 (42.10ms / 38.21MB/s)
[2026-02-09 12:05:30] [SUCCESS] Selected top 2 IP(s) for DNS:
[2026-02-09 12:05:30] [INFO]   #1: 1.0.0.3 (42.10ms / 38.21MB/s) [NEW]
[2026-02-09 12:05:30] [INFO]   #2: 1.0.0.1 (45.23ms / 35.67MB/s) [KEEP]
[2026-02-09 12:05:31] [SUCCESS] DNS update completed
```

## 🔗 Links

- **GitHub**: https://github.com/DeepBlueThought/Cloudflare-SpeedTest-DDNS
- **Documentation**: [Full README](https://github.com/DeepBlueThought/Cloudflare-SpeedTest-DDNS#readme)
- **Issues**: https://github.com/DeepBlueThought/Cloudflare-SpeedTest-DDNS/issues

## 📄 License

MIT License - See [LICENSE](https://github.com/DeepBlueThought/Cloudflare-SpeedTest-DDNS/blob/main/LICENSE) for details

**Powered by [CloudflareSpeedTest](https://github.com/XIU2/CloudflareSpeedTest)**
