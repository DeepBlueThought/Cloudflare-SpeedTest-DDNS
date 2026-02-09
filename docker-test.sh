#!/bin/bash
# Docker Test Script - 用于在容器内一次性执行测试

echo "==================================="
echo "Docker Environment Test"
echo "==================================="

# 1. 首先执行 entrypoint 逻辑来准备二进制文件
echo "Step 1: Preparing CloudflareSpeedTest binary..."
bash /app/entrypoint.sh &
ENTRYPOINT_PID=$!

# 等待二进制文件准备完成（最多30秒）
for i in {1..30}; do
  if ls /app/CloudflareST_* >/dev/null 2>&1; then
    echo "✓ Binary files are ready"
    kill $ENTRYPOINT_PID 2>/dev/null || true
    break
  fi
  sleep 1
done

# 2. 执行测速脚本
echo ""
echo "Step 2: Running speed test..."
echo "===================================" 
cd /app && bash main.sh

echo "==================================="
echo "Test completed!"
echo "==================================="
