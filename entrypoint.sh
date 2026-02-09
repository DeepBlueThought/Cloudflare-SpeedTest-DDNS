#!/bin/sh

# 设置默认版本
DEFAULT_VERSION="v2.3.4"
CLOUDFLARE_ST_VERSION=${CLOUDFLARE_ST_VERSION:-"$DEFAULT_VERSION"}

# 检测系统架构
arch=$(uname -m)
if [[ $arch =~ "x86_64" ]]; then
  binary_name="CloudflareST_linux_amd64"
  local_binary="CloudflareST_amd64"
elif [[ $arch =~ "aarch64" ]]; then
  binary_name="CloudflareST_linux_arm64"
  local_binary="CloudflareST_arm64"
else
  echo "Unsupported architecture: $arch"
  exit 1
fi

# 优化：如果请求的版本与fallback版本相同，直接使用fallback，跳过下载
if [ "$CLOUDFLARE_ST_VERSION" = "$DEFAULT_VERSION" ] && [ -f "/app/fallback/${local_binary}" ]; then
  echo "Using pre-installed CloudflareSpeedTest ${DEFAULT_VERSION} (fallback)"
  cp "/app/fallback/${local_binary}" "/app/${local_binary}"
  chmod +x "/app/${local_binary}"
  echo "✓ CloudflareSpeedTest ${DEFAULT_VERSION} ready"
else
  # 下载用户指定的其他版本
  echo "Attempting to download CloudflareSpeedTest ${CLOUDFLARE_ST_VERSION}..."
  download_url="https://github.com/XIU2/CloudflareSpeedTest/releases/download/${CLOUDFLARE_ST_VERSION}/${binary_name}.tar.gz"
  
  download_success=false
  
  if wget -q --timeout=30 -O /tmp/CloudflareST.tar.gz "$download_url" 2>/dev/null; then
    echo "Download successful, extracting..."
    if tar -xzf /tmp/CloudflareST.tar.gz -C /app 2>/dev/null; then
      mv /app/CloudflareST "/app/${local_binary}" 2>/dev/null
      chmod +x "/app/${local_binary}"
      rm /tmp/CloudflareST.tar.gz
      echo "✓ CloudflareSpeedTest ${CLOUDFLARE_ST_VERSION} installed successfully"
      download_success=true
    fi
  fi
  
  # 下载失败，使用预置的默认版本
  if [ "$download_success" = false ]; then
    echo "⚠ Failed to download CloudflareSpeedTest ${CLOUDFLARE_ST_VERSION}"
    echo "⚠ Reason: Network error or version not found"
    
    if [ -f "/app/fallback/${local_binary}" ]; then
      echo "→ Using fallback version ${DEFAULT_VERSION} (pre-installed)"
      cp "/app/fallback/${local_binary}" "/app/${local_binary}"
      chmod +x "/app/${local_binary}"
      echo "✓ Fallback to CloudflareSpeedTest ${DEFAULT_VERSION} successfully"
    else
      echo "✗ FATAL: Fallback version not found!"
      exit 1
    fi
  fi
fi

# 验证二进制文件
if [ ! -f "/app/${local_binary}" ]; then
  echo "✗ FATAL: CloudflareSpeedTest binary not found!"
  exit 1
fi

echo "CloudflareSpeedTest is ready"

# 设置定时任务
echo "$cron cd /app && bash main.sh > /proc/1/fd/1 2>&1" > /etc/cron.d/root

# 启动cron
crond -f