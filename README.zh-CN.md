# Cloudflare SpeedTest DDNS

[English](README.md) | **简体中文**

---


感谢 [CloudflareSpeedTest](https://github.com/XIU2/CloudflareSpeedTest) 的Cloudflare测速工具。

当前镜像版本：`2.0.0`（`deepbluethought/cloudflarespeedtestddns:2.0.0`）

## ✨ 核心特性

### ✅ 真实业务可用性硬门槛
- **分阶段检查**：候选 IP 必须依次通过 TCP 443、TLS SNI 和 HTTP/1.1 WebSocket Upgrade
- **只接受 101**：`403/1034`、`404`、`5xx`、超时等结果全部淘汰
- **先过滤再下载测速**：业务不可用的 IP 不会参与最终性能排序
- **旧记录同样复检**：已经存在于 DNS 中的 IP 也不能绕过业务检查

### 🧠 智能IP池管理
- **全量测试现有DNS记录**：对所有现有IP进行基准测试
- **最优N选N策略**：从新旧IP中智能选择最优的N个（N = host_ip_max）
- **业务优先排序**：仅在通过者中按 TCP/TLS/WS 握手时间排序，再比较延迟和速度
- **保留健康IP**：现有 IP 只有继续通过真实业务探测才可能被保留

### 📊 动态阈值计算
- **基于最差性能设置标准**：使用现有IP中的最差延迟和速度作为搜索阈值
- **自适应优化**：根据当前网络环境自动调整搜索标准
- **可用性高于速度**：即使坏 IP 的传统测速很快，只要业务探测失败就必须替换
- **智能回退**：如果测试失败，使用安全的默认值（延迟<100ms，速度>1MB/s）

### 🔒 安全DNS更新策略
- **无缝切换**：先添加新IP记录，再删除旧记录
- **零停机时间**：避免DNS解析空窗期
- **失败保护**：如果新IP添加失败，保留所有旧记录不做改动
- **安全收敛**：确认所有目标记录均已存在后，才删除过期记录

### 📝 清晰的日志输出
- **实时进度**：显示测试进度和候选IP发现过程
- **明确标记**：用 `[NEW]` 和 `[KEEP]` 标记新增和保留的IP
- **详细指标**：输出 HTTP 失败原因、TCP/TLS/WS 耗时、延迟和下载速度
- **更新摘要**：显示添加、保留、删除的IP数量

### 🐳 完整Docker支持
- **多种启动方式**：支持 docker-compose 和 docker run
- **跨平台支持**：支持 AMD64 和 ARM64 架构
- **环境变量配置**：所有参数可通过 `.env` 文件管理
- **自动化部署**：GitHub Actions 自动构建并推送到 DockerHub

### ⏰ 灵活的定时任务
- **Cron表达式配置**：支持任意定时策略（每小时、每30分钟等）
- **手动执行**：支持随时手动触发测试
- **容器内自动运行**：基于dcron实现轻量级定时任务

### 🎯 单 IP 优先
- **默认一个 A 记录**：`host_ip_max` 默认值为 `1`，避免客户端、代理或 DNS 缓存随机命中较差 IP
- **仍支持多 IP**：明确需要 DNS 轮询时可以把 `host_ip_max` 调大，但每个 IP 都必须通过业务探测

### 🛠️ 其他增强功能
- **版本可配置 + Fallback 机制**：
  - 通过环境变量指定 CloudflareSpeedTest 版本
  - 容器启动时自动下载指定版本
  - 下载失败自动使用预置的 v2.3.5 版本
  - 确保容器在任何网络环境下都能正常启动

- **Cloudflare IP 列表自动更新**：
  - 每次执行时自动从 Cloudflare 官方 API 获取最新 IP 地址段
  - 支持新增节点，自动排除下线节点
  - 无需手动维护，始终保持最新

## 🚀 快速开始

### 方式1：使用 Docker Compose（推荐）

1. **创建 `docker-compose.yml` 文件**
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
         - ws_probe_tls_verify=${ws_probe_tls_verify}
         - ws_probe_candidate_limit=${ws_probe_candidate_limit}
         - speedtest_para=${speedtest_para}
         - cron=${cron}
         - healthcheck_cron=${healthcheck_cron}
       restart: unless-stopped
   ```

2. **在同一目录创建 `.env` 文件**
   ```env
   zone_id=你的_cloudflare_zone_id
   api_token=你的_cloudflare_api_token
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

3. **启动容器**
   ```bash
   docker compose up -d
   ```

4. **查看日志**
   ```bash
   docker compose logs -f
   ```

5. **手动执行一次测试**（可选）
   ```bash
   docker compose exec cloudflare-speedtest-ddns bash -c "cd /app && bash main.sh"
   ```

> **注意**：如果你想从源码构建，可以先克隆仓库：
> ```bash
> git clone https://github.com/DeepBlueThought/Cloudflare-SpeedTest-DDNS.git
> cd Cloudflare-SpeedTest-DDNS
> # 然后修改 docker-compose.yml，将 "image:" 改为 "build: ."
> ```

---

### 方式2：使用 Docker Run

#### 使用环境变量文件（推荐）

```bash
docker run -d \
  --name cloudflare-ddns \
  --restart unless-stopped \
  --env-file .env \
  deepbluethought/cloudflarespeedtestddns:latest
```

#### 手动指定所有参数

```bash
docker run -d \
  --name cloudflare-ddns \
  `# 容器名称` \
  \
  --restart unless-stopped \
  `# 容器重启策略：除非手动停止，否则总是重启` \
  \
  -e CLOUDFLARE_ST_VERSION=v2.3.5 \
  `# CloudflareSpeedTest 工具版本号（可选，默认 v2.3.5）` \
  `# 如果下载失败会自动使用预置的 fallback 版本` \
  \
  -e zone_id="your_cloudflare_zone_id" \
  `# Cloudflare Zone ID` \
  `# 获取方式：登录 Cloudflare → 选择域名 → 右侧栏查看 Zone ID` \
  \
  -e api_token="your_cloudflare_api_token" \
  `# Cloudflare API Token` \
  `# 获取方式：Cloudflare → My Profile → API Tokens → Create Token` \
  `# 权限需要：Zone.DNS (编辑)` \
  \
  -e host_name="testip.yourdomain.com" \
  `# 要更新的域名（支持子域名）` \
  \
  -e host_ip_max=1 \
  `# 推荐只维护一个业务可用 IP，避免 DNS 随机选择` \
  \
  -e ws_probe_enabled=true \
  -e ws_probe_host="www.yourdomain.com" \
  -e ws_probe_path="/your-websocket-path" \
  `# 上面两项指定真实业务的 TLS SNI/Host 与 WebSocket 路径` \
  \
  -e speedtest_para="-n 1000 -dn 2 -sl 5 -tl 100 -url https://download.parallels.com/desktop/v18/18.1.1-53328/ParallelsDesktop-18.1.1-53328.dmg" \
  `# CloudflareSpeedTest 测试参数：` \
  `#   -n 1000    : 延迟测试线程数（最大 1000，性能强可设高）` \
  `#   -dn 2      : 下载测速数量（找到 2 个符合条件的 IP 就停止）` \
  `#   -sl 5      : 最低速度阈值 5 MB/s（会根据基准测试动态调整）` \
  `#   -tl 100    : 最高延迟阈值 100 ms（会根据基准测试动态调整）` \
  `#   -url       : 测速文件 URL（建议使用通过 Cloudflare CDN 的大文件）` \
  \
  -e cron="0 * * * *" \
  `# Linux Cron 表达式，定时执行测速和更新任务` \
  `# 示例：` \
  `#   "0 * * * *"      每小时执行一次` \
  `#   "*/30 * * * *"   每 30 分钟执行一次` \
  `#   "0 */6 * * *"    每 6 小时执行一次` \
  \
  -e healthcheck_cron="15,45 * * * *" \
  `# 每 30 分钟轻量检查当前 DNS IP，失败才触发完整重选` \
  \
  deepbluethought/cloudflarespeedtestddns:latest
```

#### 手动执行一次测试（不启动定时任务）

```bash
docker run --rm \
  --env-file .env \
  deepbluethought/cloudflarespeedtestddns:latest \
  bash -c "cd /app && bash main.sh"
```

---

## 📖 Docker Compose 配置示例

完整的 `docker-compose.yml` 示例：

```yaml
services:
  cloudflare-speedtest-ddns:
    build: .
    container_name: cloudflare-ddns
    environment:
      # CloudflareSpeedTest 版本（可选，默认 v2.3.5）
      - CLOUDFLARE_ST_VERSION=v2.3.5
      
      # Cloudflare API 配置
      - zone_id=${zone_id}
      - api_token=${api_token}
      
      # 域名配置
      - host_name=${host_name}
      - host_ip_max=${host_ip_max}

      # WebSocket 真实业务配置
      - ws_probe_enabled=${ws_probe_enabled}
      - ws_probe_host=${ws_probe_host}
      - ws_probe_path=${ws_probe_path}
      - ws_probe_tls_verify=${ws_probe_tls_verify}
      - ws_probe_candidate_limit=${ws_probe_candidate_limit}
      
      # CloudflareSpeedTest 测试参数（从 .env 读取）
      - speedtest_para=${speedtest_para}
      
      # Linux 定时任务 (Cron格式)
      # 示例: "0 * * * *" 表示每小时执行一次
      # 示例: "*/30 * * * *" 表示每30分钟执行一次
      - cron=${cron}
      - healthcheck_cron=${healthcheck_cron}
      - log_file=${log_file}
    restart: unless-stopped
```

## 📋 环境变量说明

| 变量名 | 必填 | 默认值 | 说明 |
|--------|--------------|------|
| `CLOUDFLARE_ST_VERSION` | 否 | v2.3.5 | CloudflareSpeedTest 版本号（下载失败会fallback） |
| `host_name` | 是 | - | 需要更新的域名（支持多个，用逗号或空格分隔，如 `cf1.a.com,cf2.a.com`） |
| `host_ip_max` | 否 | 1 | DNS 中保留的 A 记录数量；推荐保持单 IP |
| `zone_id` | 是 | - | Cloudflare Zone ID，自行从 Cloudflare 管理面板获取 |
| `api_token` | 是 | - | Cloudflare API Token，自行从 Cloudflare 管理面板获取 |
| `speedtest_para` | 是 | - | 测试参数，详见下方说明 |
| `cron` | 是 | - | Cron 表达式，定时执行 |
| `ws_probe_enabled` | 否 | auto | `auto` 在设置 `ws_probe_host` 时启用；也可显式设为 `true/false` |
| `ws_probe_host` | 业务探测时是 | - | 真实 TLS SNI 与 HTTP Host，例如 `www.example.com`；不要填写 `https://` 或路径 |
| `ws_probe_path` | 否 | / | WebSocket 路径，例如 `/deepblue` |
| `ws_probe_tls_verify` | 否 | true | 验证证书链及证书主机名；不建议关闭 |
| `ws_probe_candidate_limit` | 否 | 20 | 对延迟排名最前的多少个候选执行完整业务探测 |
| `ws_probe_tcp_timeout` / `ws_probe_tls_timeout` / `ws_probe_http_timeout` | 否 | 3 / 5 / 8 | 各阶段超时时间（秒） |
| `healthcheck_cron` | 否 | `15,45 * * * *` | 当前 DNS IP 的轻量业务健康检查；失败时触发完整重选 |
| `log_file` | 否 | `/tmp/cloudflare-bestip.log` | 无 ANSI 颜色的持久运行日志路径（容器重建后 `/tmp` 不保留） |

### speedtest_para 参数说明

- `-n`: 延迟测速线程；越多延迟测速越快，性能弱的设备 (如路由器) 请勿太高；(默认 200 最多 1000)
- `-dn`: 下载测速数量；延迟测速并排序后，从最低延迟起下载测速的数量；(默认 10 个)，如果配置了-sl参数，那么当下载测速达到-sl参数的ip达到dn数量的时候，下载测速会停止。建议配置为2
- `-sl`: 最低速度阈值 MB/s（取业务有效旧记录中的最慢速度；无基准时为 1 MB/s）
- `-tl`: 最高延迟阈值 ms（取业务有效旧记录中的最慢延迟，最低 20 ms；无基准时为 100 ms）

**注意**：`speedtest_para` 中的 `-sl` 和 `-tl` 会被上述动态基准值替换，其他参数保持不变。

## 📊 工作流程

1. 获取当前 DNS A 记录，并用真实 `ws_probe_host`/`ws_probe_path` 复检旧 IP。
2. CloudflareST 只做候选延迟发现（`-dd`），从低延迟结果中取前 `ws_probe_candidate_limit` 个。
3. 每个候选依次执行 TCP 443、带 SNI 的 TLS 握手和 WebSocket Upgrade；只有 HTTP `101` 才进入可用池。
4. CloudflareST 只对可用池执行下载测速。
5. 对通过者按 `TCP×0.3 + TLS×0.2 + WS×0.5` 的业务握手分数排序，延迟和下载速度用于后续比较。
6. 先确保目标记录已经存在，再删除非目标记录；如果添加失败，则保留旧记录。
7. watchdog 定期只检查当前 DNS IP；一旦不再返回 `101`，立即触发完整重选。

> `host_name` 是要写入的 DDNS 记录名；`ws_probe_host` 是 Cloudflare 实际承载业务的 Host/SNI。二者可能相同，也可能不同。程序不会猜测这个映射。

**注意：**
CloudflareSpeedTest工具整个流程大概步骤：
1. 延迟测速（默认 TCPing 模式，HTTPing 模式需要手动加上参数）
2. 延迟排序（延迟 从低到高 排序并按条件过滤，不同丢包率会分开排序，因此可能会有一些延迟低但丢包的 IP 排到后面）
3. 下载测速（从延迟最低的 IP 开始依次下载测速，默认测够 10 个就会停止）
4. 速度排序（速度从高到低排序）
5. 输出结果（通过参数控制是否输出到命令行(-p 0)或输出到文件(-o "")）

### 快速测试

```bash
# 无网络、无 Cloudflare 凭据的回归测试
bash tests/business_probe_test.sh
bash tests/main_flow_test.sh
bash tests/healthcheck_test.sh

# 本地测试脚本
./test.sh

# 构建并推送到 Docker Hub（交互式）
./build-and-push.sh
```

## 📝 示例日志

### WebSocket 业务门槛

```text
[2026-08-10 04:38:00] [INFO] Business probe 162.159.44.212: TLS SNI OK (www.example.com)
[2026-08-10 04:38:00] [WARN] Business probe 162.159.44.212: WS FAIL (HTTP 403: error code: 1034)
[2026-08-10 04:38:01] [SUCCESS] Business probe 172.64.229.53: WS 101 OK (TCP 20.00ms, TLS 55.00ms, WS 105.00ms, score 69.50)
[2026-08-10 04:38:01] [SUCCESS] Selected 1 business-valid IP(s) for DNS:
```

### IP 列表自动更新
```
2026-02-06 14:00:00 Updating Cloudflare IP list...
2026-02-06 14:00:01 ✓ Successfully updated IP list from Cloudflare (14 ranges)
```

或网络异常时：
```
2026-02-06 14:00:00 Updating Cloudflare IP list...
2026-02-06 14:00:10 ⚠ Failed to download IP list from Cloudflare
2026-02-06 14:00:10 → Using backup IP list
```

### 版本下载成功
```
Attempting to download CloudflareSpeedTest v2.3.0...
Download successful, extracting...
✓ CloudflareSpeedTest v2.3.0 installed successfully
CloudflareSpeedTest is ready
```

### 版本下载失败（Fallback）
```
Attempting to download CloudflareSpeedTest v9.9.9...
⚠ Failed to download CloudflareSpeedTest v9.9.9
⚠ Reason: Network error or version not found
→ Using fallback version v2.3.5 (pre-installed)
✓ Fallback to CloudflareSpeedTest v2.3.5 successfully
CloudflareSpeedTest is ready
```

### 智能对比执行
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

## 🤝 贡献

欢迎提交 Issue 和 Pull Request！

## 📄 许可

MIT License
