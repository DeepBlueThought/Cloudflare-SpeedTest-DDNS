# Cloudflare SpeedTest DDNS

🚀 An intelligent DDNS update tool that automatically finds the fastest Cloudflare IP and updates your DNS records.

## ✨ Key Features

- **🧠 Intelligent IP Pool Management** - Tests all existing DNS records and selects the best N IPs
- **📊 Dynamic Threshold Calculation** - Adapts search criteria based on current network conditions
- **🔒 Safe DNS Updates** - Zero-downtime updates with rollback protection
- **🐳 Full Docker Support** - Works with both docker-compose and docker run
- **🔢 Multi-IP Load Balancing** - Configure multiple A records for fault tolerance
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
  -e host_ip_max=2 \
  -e speedtest_para="-n 1000 -dn 2 -sl 5 -tl 100" \
  -e cron="0 * * * *" \
  deepbluethought/cloudflarespeedtestddns:latest
```

## 📋 Environment Variables

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `zone_id` | Yes | - | Cloudflare Zone ID |
| `api_token` | Yes | - | Cloudflare API Token (needs Zone.DNS edit permission) |
| `host_name` | Yes | - | Domain to update (e.g., testip.example.com) |
| `host_ip_max` | No | 2 | Number of IPs to maintain in DNS records |
| `speedtest_para` | Yes | - | CloudflareSpeedTest parameters |
| `cron` | Yes | - | Cron expression for scheduling (e.g., "0 * * * *" for hourly) |

## 🔧 Configuration Example

**`.env` file:**
```env
zone_id=your_zone_id_here
api_token=your_api_token_here
host_name=testip.yourdomain.com
host_ip_max=2
speedtest_para="-n 1000 -dn 2 -sl 5 -tl 100 -url https://download.example.com/largefile.bin"
cron=0 * * * *
```

### Getting Cloudflare Credentials

1. **Zone ID**: Login to Cloudflare → Select your domain → Zone ID in the right sidebar
2. **API Token**: Cloudflare → My Profile → API Tokens → Create Token
   - Template: Edit zone DNS
   - Permissions: Zone.DNS (Edit)

## 📊 How It Works

1. **Baseline Testing** - Tests all existing DNS record IPs
2. **Dynamic Thresholds** - Uses worst-case performance as search criteria
3. **IP Discovery** - Scans Cloudflare IP ranges for better performance
4. **Intelligent Selection** - Chooses best N IPs from both old and new
5. **Safe Updates** - Adds new records before removing old ones

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
