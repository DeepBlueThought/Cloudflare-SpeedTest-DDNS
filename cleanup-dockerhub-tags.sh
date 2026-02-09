#!/bin/bash

# DockerHub 标签清理脚本
# 使用方法：./cleanup-dockerhub-tags.sh

set -e

# 配置
USERNAME="deepbluethought"
REPOSITORY="cloudflarespeedtestddns"
DOCKERHUB_USERNAME="${USERNAME}"

# 要删除的标签列表
TAGS_TO_DELETE=(
  "buildcache"
  "main-be217dc"
  "main"
)

echo "🗑️  DockerHub 标签清理工具"
echo "================================"
echo "仓库: ${USERNAME}/${REPOSITORY}"
echo ""

# 提示输入 DockerHub 密码/Token
read -sp "请输入 DockerHub 密码或 Access Token: " DOCKERHUB_PASSWORD
echo ""
echo ""

# 获取登录 token
echo "🔐 正在登录 DockerHub..."
LOGIN_RESPONSE=$(curl -s -X POST \
  -H "Content-Type: application/json" \
  -d "{\"username\": \"${DOCKERHUB_USERNAME}\", \"password\": \"${DOCKERHUB_PASSWORD}\"}" \
  https://hub.docker.com/v2/users/login/)

TOKEN=$(echo "$LOGIN_RESPONSE" | jq -r '.token')

if [ "$TOKEN" == "null" ] || [ -z "$TOKEN" ]; then
  echo "❌ 登录失败！请检查用户名和密码"
  echo "响应: $LOGIN_RESPONSE"
  exit 1
fi

echo "✅ 登录成功"
echo ""

# 删除标签
for TAG in "${TAGS_TO_DELETE[@]}"; do
  echo "🗑️  正在删除标签: ${TAG}..."
  
  DELETE_RESPONSE=$(curl -s -X DELETE \
    -H "Authorization: JWT ${TOKEN}" \
    "https://hub.docker.com/v2/repositories/${USERNAME}/${REPOSITORY}/tags/${TAG}/")
  
  # 检查是否成功（空响应或 204 状态码表示成功）
  if [ -z "$DELETE_RESPONSE" ] || echo "$DELETE_RESPONSE" | jq -e 'has("detail")' > /dev/null 2>&1; then
    if echo "$DELETE_RESPONSE" | grep -q "not found"; then
      echo "  ⚠️  标签 ${TAG} 不存在，跳过"
    elif [ -z "$DELETE_RESPONSE" ]; then
      echo "  ✅ 成功删除: ${TAG}"
    else
      echo "  ❌ 删除失败: ${TAG}"
      echo "  响应: $DELETE_RESPONSE"
    fi
  else
    echo "  ✅ 成功删除: ${TAG}"
  fi
done

echo ""
echo "🎉 清理完成！"
echo ""
echo "查看剩余标签："
echo "https://hub.docker.com/r/${USERNAME}/${REPOSITORY}/tags"
