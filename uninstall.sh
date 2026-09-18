#!/usr/bin/env bash
# Remove services installed by install.sh (does NOT uninstall nginx/xray packages by default)
set -euo pipefail

if [[ "$(id -u)" -ne 0 ]]; then
  echo "请使用 root 运行：sudo bash uninstall.sh"
  exit 1
fi

APP_DIR="${APP_DIR:-/root/proxy-setup}"
REMOVE_XRAY="${REMOVE_XRAY:-0}"
REMOVE_NGINX_STREAM="${REMOVE_NGINX_STREAM:-1}"

echo "==> 停止服务"
systemctl disable --now mtg v2ray-sub 2>/dev/null || true
if [[ "$REMOVE_XRAY" == "1" ]]; then
  systemctl disable --now xray 2>/dev/null || true
fi

rm -f /etc/systemd/system/mtg.service
rm -f /etc/systemd/system/v2ray-sub.service
systemctl daemon-reload

if [[ "$REMOVE_NGINX_STREAM" == "1" ]]; then
  rm -f /etc/nginx/streams-enabled/443-sni.conf
  if [[ -f /etc/nginx/nginx.conf ]]; then
    nginx -t 2>/dev/null && systemctl reload nginx || true
  fi
fi

rm -f /usr/local/bin/mtg

if [[ -d "$APP_DIR" ]]; then
  echo "==> 删除 ${APP_DIR}（含密钥与订阅）"
  rm -rf "$APP_DIR"
fi

if [[ "$REMOVE_XRAY" == "1" ]]; then
  if [[ -f /usr/local/bin/xray ]]; then
    bash -c "$(curl -fsSL https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ remove || true
  fi
fi

echo "卸载完成。"
echo "如需同时卸载 Xray：REMOVE_XRAY=1 bash uninstall.sh"
