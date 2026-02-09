FROM alpine:3.19.1

# OCI 标签 - 提供镜像元数据
LABEL org.opencontainers.image.title="Cloudflare SpeedTest DDNS"
LABEL org.opencontainers.image.description="Intelligent DDNS updater that finds the fastest Cloudflare IP and updates DNS records automatically"
LABEL org.opencontainers.image.authors="DeepBlueThought"
LABEL org.opencontainers.image.url="https://github.com/DeepBlueThought/Cloudflare-SpeedTest-DDNS"
LABEL org.opencontainers.image.source="https://github.com/DeepBlueThought/Cloudflare-SpeedTest-DDNS"
LABEL org.opencontainers.image.documentation="https://github.com/DeepBlueThought/Cloudflare-SpeedTest-DDNS#readme"
LABEL org.opencontainers.image.licenses="MIT"
LABEL org.opencontainers.image.version="1.0.0"

ENV TZ="Asia/Shanghai"

RUN apk add --no-cache bash dcron tzdata curl jq wget tar && cp /usr/share/zoneinfo/$TZ /etc/localtime

WORKDIR /app

# 复制脚本和默认版本的二进制文件（用作fallback）
COPY entrypoint.sh main.sh ip.txt ./
COPY CloudflareST_amd64 CloudflareST_arm64 ./fallback/

ENTRYPOINT ["sh", "entrypoint.sh"]