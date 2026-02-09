#!/bin/bash

# 本地测试脚本 - 用于在非容器环境下测试 main.sh 逻辑

# Load environment variables from .env file if it exists
if [ -f .env ]; then
    echo "Loading environment variables from .env file..."
    # Use set -a to auto-export variables, then source the file
    set -a
    source .env
    set +a
    echo "✓ Environment variables loaded"
else
    echo "❌ .env file not found!"
    echo ""
    echo "Please create .env file from .env.example:"
    echo "  cp .env.example .env"
    echo "  # Then edit .env with your actual values"
    echo ""
    exit 1
fi

# Validate required variables
if [ -z "$zone_id" ] || [ -z "$api_token" ] || [ -z "$host_name" ]; then
    echo "❌ Error: Missing required environment variables!"
    echo "   Please configure zone_id, api_token, and host_name in .env"
    exit 1
fi

echo "========================================="
echo "Cloudflare SpeedTest DDNS - Local Test"
echo "========================================="
echo ""
echo "⚠️  请确保已经设置正确的环境变量："
echo "   - zone_id: $zone_id"
echo "   - api_token: $api_token"
echo "   - host_name: $host_name"
echo ""
echo "⚠️  请确保当前目录下存在 ip.txt 文件"
echo "⚠️  请确保已下载对应架构的 CloudflareST 二进制文件"
echo ""
read -p "按回车继续，或 Ctrl+C 取消..."

# 检测操作系统和架构，自动下载对应的二进制文件
echo "========================================="
echo "检测系统环境..."
echo "========================================="

os=$(uname -s)
arch=$(uname -m)
echo "操作系统: $os"
echo "架构: $arch"

# 确定需要的二进制文件
if [[ "$os" == "Darwin" ]]; then
  # macOS
  if [[ "$arch" == "arm64" ]]; then
    binary="./CloudflareST_darwin_arm64"
    download_url="https://github.com/XIU2/CloudflareSpeedTest/releases/download/v2.3.4/cfst_darwin_arm64.zip"
    zip_name="cfst_darwin_arm64.zip"
  elif [[ "$arch" == "x86_64" ]]; then
    binary="./CloudflareST_darwin_amd64"
    download_url="https://github.com/XIU2/CloudflareSpeedTest/releases/download/v2.3.4/cfst_darwin_amd64.zip"
    zip_name="cfst_darwin_amd64.zip"
  else
    echo "❌ 不支持的 macOS 架构: $arch"
    exit 1
  fi
elif [[ "$os" == "Linux" ]]; then
  # Linux
  if [[ "$arch" == "arm64" ]] || [[ "$arch" == "aarch64" ]]; then
    binary="./CloudflareST_linux_arm64"
    download_url="https://github.com/XIU2/CloudflareSpeedTest/releases/download/v2.3.4/cfst_linux_arm64.tar.gz"
    tar_name="cfst_linux_arm64.tar.gz"
  elif [[ "$arch" == "x86_64" ]] || [[ "$arch" == "amd64" ]]; then
    binary="./CloudflareST_linux_amd64"
    download_url="https://github.com/XIU2/CloudflareSpeedTest/releases/download/v2.3.4/cfst_linux_amd64.tar.gz"
    tar_name="cfst_linux_amd64.tar.gz"
  else
    echo "❌ 不支持的 Linux 架构: $arch"
    exit 1
  fi
else
  echo "❌ 不支持的操作系统: $os"
  echo "支持的系统: Darwin (macOS), Linux"
  exit 1
fi

echo "需要的二进制文件: $binary"
echo ""

# 检查二进制文件是否存在且可执行
if [ -f "$binary" ] && [ -x "$binary" ]; then
  echo "✓ 二进制文件已存在: $binary"
else
  echo "⚠️  二进制文件不存在，开始下载..."
  echo "下载地址: $download_url"
  echo ""
  
  # 下载文件
  if [[ "$os" == "Darwin" ]]; then
    # macOS: 下载 zip 文件
    if curl -L --progress-bar "$download_url" -o "/tmp/$zip_name"; then
      echo "✓ 下载完成"
      echo "正在解压..."
      
      # 只解压 cfst 文件
      if unzip -o -qq -j "/tmp/$zip_name" "cfst" -d /tmp/ 2>&1; then
        mv /tmp/cfst "$binary"
        chmod +x "$binary"
        rm "/tmp/$zip_name"
        echo "✓ 安装完成: $binary"
      else
        echo "❌ 解压失败"
        rm -f "/tmp/$zip_name"
        exit 1
      fi
    else
      echo "❌ 下载失败"
      exit 1
    fi
  else
    # Linux: 下载 tar.gz 文件
    if curl -L --progress-bar "$download_url" -o "/tmp/$tar_name"; then
      echo "✓ 下载完成"
      echo "正在解压..."
      
      if tar -xzf "/tmp/$tar_name" -C /tmp/ > /dev/null 2>&1; then
        mv /tmp/CloudflareST "$binary"
        chmod +x "$binary"
        rm "/tmp/$tar_name"
        echo "✓ 安装完成: $binary"
      else
        echo "❌ 解压失败"
        rm -f "/tmp/$tar_name"
        exit 1
      fi
    else
      echo "❌ 下载失败"
      exit 1
    fi
  fi
fi

# 验证二进制文件
echo ""
echo "验证二进制文件..."
if ! "$binary" -h > /dev/null 2>&1; then
  echo "❌ 二进制文件无法执行"
  echo "文件信息: $(file $binary)"
  exit 1
fi

echo "✓ 二进制文件验证通过"
echo ""

if [ ! -f "ip.txt" ]; then
  echo "❌ ip.txt file not found"
  echo "Attempting to download latest Cloudflare IP ranges..."
  
  if curl -s --max-time 10 https://www.cloudflare.com/ips-v4 -o ip.txt; then
    if [ -s ip.txt ] && grep -qE '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/[0-9]+$' ip.txt; then
      echo "✓ Successfully downloaded ip.txt from Cloudflare"
    else
      echo "❌ Downloaded file is invalid"
      rm -f ip.txt
      echo "Please manually download ip.txt from:"
      echo "  https://www.cloudflare.com/ips-v4"
      exit 1
    fi
  else
    echo "❌ Failed to download ip.txt"
    echo "Please manually download it from:"
    echo "  https://www.cloudflare.com/ips-v4"
    echo "Or copy from the project directory if you have it"
    exit 1
  fi
fi

echo ""
echo "✓ 环境检查通过，开始执行测试..."
echo ""
echo "提示："
echo "• 测试可能需要几分钟，取决于IP列表大小和网络状况"
echo "• 延迟测速：测试所有IP的延迟"
echo "• 下载测速：对延迟最低的IP进行速度测试"
echo "• 本地macOS测试仅用于验证逻辑，生产环境请使用Docker"
echo ""

# 运行主脚本（非交互模式，重定向标准输入避免卡住）
bash main.sh < /dev/null

echo ""
echo "========================================="
echo "测试完成！"
echo "========================================="
