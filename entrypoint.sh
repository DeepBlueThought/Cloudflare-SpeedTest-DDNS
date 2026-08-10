#!/bin/sh

set -u

echo "Cloudflare SpeedTest DDNS ${APP_VERSION:-2.0.0}"

DEFAULT_VERSION="v2.3.5"
FALLBACK_VERSION="v2.3.5"
CLOUDFLARE_ST_VERSION=${CLOUDFLARE_ST_VERSION:-"$DEFAULT_VERSION"}

case "$(uname -m)" in
  x86_64|amd64)
    release_arch="linux_amd64"
    local_binary="CloudflareST_amd64"
    ;;
  aarch64|arm64)
    release_arch="linux_arm64"
    local_binary="CloudflareST_arm64"
    ;;
  *)
    echo "Unsupported architecture: $(uname -m)"
    exit 1
    ;;
esac

install_fallback() {
  if [ ! -f "/app/fallback/${local_binary}" ]; then
    echo "FATAL: fallback binary not found"
    return 1
  fi
  cp "/app/fallback/${local_binary}" "/app/${local_binary}"
  chmod +x "/app/${local_binary}"
}

if [ "$CLOUDFLARE_ST_VERSION" = "$DEFAULT_VERSION" ] && [ -f "/app/fallback/${local_binary}" ]; then
  echo "Using pre-installed CloudflareSpeedTest ${DEFAULT_VERSION}"
  install_fallback || exit 1
  echo "CloudflareSpeedTest ${DEFAULT_VERSION} is ready"
else
  echo "Attempting to download CloudflareSpeedTest ${CLOUDFLARE_ST_VERSION}..."
  download_success=false
  download_dir=$(mktemp -d /tmp/cloudflarest-download.XXXXXX 2>/dev/null || true)

  if [ -n "$download_dir" ]; then
    mkdir -p "$download_dir/extracted"
    for archive_name in "cfst_${release_arch}.tar.gz" "CloudflareST_${release_arch}.tar.gz"; do
      download_url="https://github.com/XIU2/CloudflareSpeedTest/releases/download/${CLOUDFLARE_ST_VERSION}/${archive_name}"
      if wget -q --timeout=30 -O "$download_dir/release.tar.gz" "$download_url" 2>/dev/null; then
        echo "Downloaded ${archive_name}; extracting..."
        if tar -xzf "$download_dir/release.tar.gz" -C "$download_dir/extracted" 2>/dev/null; then
          extracted_binary=$(find "$download_dir/extracted" -type f \( -name cfst -o -name CloudflareST \) | head -n 1)
          if [ -n "$extracted_binary" ] && [ -f "$extracted_binary" ]; then
            cp "$extracted_binary" "/app/${local_binary}"
            chmod +x "/app/${local_binary}"
            echo "CloudflareSpeedTest ${CLOUDFLARE_ST_VERSION} installed successfully"
            download_success=true
            break
          fi
        fi
        rm -rf "$download_dir/extracted"
        mkdir -p "$download_dir/extracted"
      fi
    done
    rm -rf "$download_dir"
  fi

  if [ "$download_success" = false ]; then
    echo "Failed to download CloudflareSpeedTest ${CLOUDFLARE_ST_VERSION}; using fallback ${FALLBACK_VERSION}"
    install_fallback || exit 1
  fi
fi

if [ ! -x "/app/${local_binary}" ]; then
  echo "FATAL: CloudflareSpeedTest binary is not executable"
  exit 1
fi

# An explicit docker command is a one-shot operation, for example:
# docker run --rm --env-file .env IMAGE bash /app/main.sh
if [ "$#" -gt 0 ]; then
  exec "$@"
fi

main_cron=${cron:-"0 * * * *"}
watchdog_cron=${healthcheck_cron:-"15,45 * * * *"}

{
  echo "$main_cron cd /app && bash main.sh > /proc/1/fd/1 2>&1"
  case "${ws_probe_enabled:-auto}" in
    0|false|FALSE|no|NO|off|OFF) ;;
    *)
      if [ -n "${ws_probe_host:-}" ]; then
        echo "$watchdog_cron cd /app && bash healthcheck.sh > /proc/1/fd/1 2>&1"
      fi
      ;;
  esac
} > /etc/crontabs/root
chmod 600 /etc/crontabs/root

echo "Optimizer schedule: $main_cron"
if [ -n "${ws_probe_host:-}" ]; then
  echo "WebSocket watchdog schedule: $watchdog_cron"
fi

# dcron calls setpgid during startup. Docker Desktop starts PID 1 as a session
# leader, so exec-ing dcron as PID 1 can fail with "setpgid: Operation not
# permitted". Keep this shell as PID 1 and run dcron as its foreground child.
crond -f -l 2
