#!/bin/bash

# 快速构建并推送到 Docker Hub 的脚本

set -e  # 遇到错误立即退出

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=========================================${NC}"
echo -e "${BLUE}Cloudflare SpeedTest DDNS - 构建脚本${NC}"
echo -e "${BLUE}=========================================${NC}"
echo ""

# 检查 Docker
if ! command -v docker &> /dev/null; then
    echo -e "${RED}❌ Docker 未安装，请先安装 Docker${NC}"
    exit 1
fi

# 询问 Docker Hub 用户名
read -p "请输入你的 Docker Hub 用户名: " DOCKER_USERNAME
if [ -z "$DOCKER_USERNAME" ]; then
    echo -e "${RED}❌ 用户名不能为空${NC}"
    exit 1
fi

# 询问版本号
read -p "请输入版本号 (默认: v1.0.0): " VERSION
VERSION=${VERSION:-v1.0.0}

# 镜像名称
IMAGE_NAME="${DOCKER_USERNAME}/cloudflare-speedtest-ddns"

echo ""
echo -e "${YELLOW}构建配置:${NC}"
echo -e "  用户名: ${GREEN}${DOCKER_USERNAME}${NC}"
echo -e "  镜像名: ${GREEN}${IMAGE_NAME}${NC}"
echo -e "  版本号: ${GREEN}${VERSION}${NC}"
echo ""

# 询问是否继续
read -p "确认开始构建？(y/N): " CONFIRM
if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
    echo -e "${YELLOW}已取消${NC}"
    exit 0
fi

# 检查必要的文件
echo ""
echo -e "${BLUE}>>> 检查必要文件...${NC}"
required_files=("CloudflareST_amd64" "CloudflareST_arm64" "main.sh" "entrypoint.sh" "Dockerfile")
for file in "${required_files[@]}"; do
    if [ ! -f "$file" ]; then
        echo -e "${RED}❌ 缺少文件: $file${NC}"
        
        if [[ "$file" == "CloudflareST_"* ]]; then
            echo -e "${YELLOW}提示: 请从以下地址下载或运行 ./download-binaries.sh:${NC}"
            echo "  https://github.com/XIU2/CloudflareSpeedTest/releases/download/v2.3.4/cfst_linux_amd64.tar.gz"
            echo "  https://github.com/XIU2/CloudflareSpeedTest/releases/download/v2.3.4/cfst_linux_arm64.tar.gz"
        fi
        exit 1
    fi
    echo -e "${GREEN}✓${NC} $file"
done

# 构建镜像
echo ""
echo -e "${BLUE}>>> 构建 Docker 镜像...${NC}"
if docker build -t "${IMAGE_NAME}:latest" -t "${IMAGE_NAME}:${VERSION}" .; then
    echo -e "${GREEN}✓ 镜像构建成功${NC}"
else
    echo -e "${RED}❌ 镜像构建失败${NC}"
    exit 1
fi

# 询问是否推送
echo ""
read -p "是否推送到 Docker Hub？(y/N): " PUSH_CONFIRM
if [[ ! "$PUSH_CONFIRM" =~ ^[Yy]$ ]]; then
    echo -e "${YELLOW}已跳过推送，本地镜像已构建完成${NC}"
    echo ""
    echo -e "${GREEN}本地测试命令:${NC}"
    echo "  docker run --rm -e zone_id='...' -e api_token='...' -e host_name='...' -e speedtest_para='...' -e cron='* * * * *' ${IMAGE_NAME}:latest"
    exit 0
fi

# 登录 Docker Hub
echo ""
echo -e "${BLUE}>>> 登录 Docker Hub...${NC}"
if docker login; then
    echo -e "${GREEN}✓ 登录成功${NC}"
else
    echo -e "${RED}❌ 登录失败${NC}"
    exit 1
fi

# 推送镜像
echo ""
echo -e "${BLUE}>>> 推送镜像到 Docker Hub...${NC}"

echo -e "推送 ${YELLOW}latest${NC} 标签..."
if docker push "${IMAGE_NAME}:latest"; then
    echo -e "${GREEN}✓ latest 推送成功${NC}"
else
    echo -e "${RED}❌ latest 推送失败${NC}"
    exit 1
fi

echo -e "推送 ${YELLOW}${VERSION}${NC} 标签..."
if docker push "${IMAGE_NAME}:${VERSION}"; then
    echo -e "${GREEN}✓ ${VERSION} 推送成功${NC}"
else
    echo -e "${RED}❌ ${VERSION} 推送失败${NC}"
    exit 1
fi

# 完成
echo ""
echo -e "${GREEN}=========================================${NC}"
echo -e "${GREEN}✓ 全部完成！${NC}"
echo -e "${GREEN}=========================================${NC}"
echo ""
echo -e "${BLUE}你的镜像已发布:${NC}"
echo -e "  ${GREEN}${IMAGE_NAME}:latest${NC}"
echo -e "  ${GREEN}${IMAGE_NAME}:${VERSION}${NC}"
echo ""
echo -e "${BLUE}使用方式:${NC}"
echo "  docker pull ${IMAGE_NAME}:latest"
echo ""
echo -e "${BLUE}Docker Hub 地址:${NC}"
echo -e "  ${YELLOW}https://hub.docker.com/r/${IMAGE_NAME}${NC}"
echo ""
