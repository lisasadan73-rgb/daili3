#!/usr/bin/env bash
# One-click deploy: Xray VLESS+Reality (3 nodes) + subscription + Telegram MTProto + SOCKS5
# Usage (as root): bash install.sh
# Optional env:
#   APP_DIR=/root/proxy-setup
#   NODE_PREFIX=LA
#   MTG_FAKE_HOST=google.com
#   SKIP_NGINX=0
set -euo pipefail

if [[ "$(id -u)" -ne 0 ]]; then
  echo "请使用 root 运行：sudo bash install.sh"
  exit 1
fi

APP_DIR="${APP_DIR:-/root/proxy-setup}"
NODE_PREFIX="${NODE_PREFIX:-Node}"
MTG_FAKE_HOST="${MTG_FAKE_HOST:-google.com}"
SKIP_NGINX="${SKIP_NGINX:-0}"
MTG_VERSION="${MTG_VERSION:-2.2.8}"
XRAY_INSTALL_URL="${XRAY_INSTALL_URL:-https://github.com/XTLS/Xray-install/raw/main/install-release.sh}"

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "缺少命令: $1"
    exit 1
  }
}

detect_ip() {
  local ip=""
  for url in \
    "https://api.ipify.org" \
    "https://ifconfig.me/ip" \
    "https://ipv4.icanhazip.com"; do
    ip="$(curl -4 -fsS --max-time 8 "$url" 2>/dev/null | tr -d '[:space:]' || true)"
    if [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
      echo "$ip"
      return 0
    fi
  done
  ip="$(hostname -I 2>/dev/null | awk '{print $1}')"
  echo "${ip}"
}

echo "==> 安装系统依赖"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq curl wget ca-certificates openssl python3 nginx libnginx-mod-stream >/dev/null

echo "==> 安装 / 更新 Xray"
bash -c "$(curl -fsSL "$XRAY_INSTALL_URL")" @ install
need_cmd xray

echo "==> 安装 mtg ${MTG_VERSION}"
ARCH="$(uname -m)"
case "$ARCH" in
  x86_64|amd64) MTG_ARCH="linux-amd64" ;;
  aarch64|arm64) MTG_ARCH="linux-arm64" ;;
  *) echo "不支持的架构: $ARCH"; exit 1 ;;
esac
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
curl -fsSL \
  "https://github.com/9seconds/mtg/releases/download/v${MTG_VERSION}/mtg-${MTG_VERSION}-${MTG_ARCH}.tar.gz" \
  -o "$TMP/mtg.tar.gz"
tar -xzf "$TMP/mtg.tar.gz" -C "$TMP"
MTG_BIN="$(find "$TMP" -type f -name mtg | head -n 1)"
if [[ -z "$MTG_BIN" || ! -x "$MTG_BIN" ]]; then
  # some archives may lack +x; still try install after chmod
  MTG_BIN="$(find "$TMP" -type f -name mtg | head -n 1)"
fi
if [[ -z "$MTG_BIN" ]]; then
  echo "mtg 二进制未找到，解压内容："
  find "$TMP" -maxdepth 3 -type f | head -50
  exit 1
fi
chmod +x "$MTG_BIN"
install -m 755 "$MTG_BIN" /usr/local/bin/mtg
need_cmd mtg

PUBLIC_IP="${OVERRIDE_PUBLIC_IP:-$(detect_ip)}"
if [[ -z "$PUBLIC_IP" ]]; then
  echo "无法自动检测公网 IP，请设置：OVERRIDE_PUBLIC_IP=x.x.x.x bash install.sh"
  exit 1
fi

echo "==> 公网 IP: ${PUBLIC_IP}"
echo "==> 生成密钥（每台机器独立，勿复用到公开仓库）"

UUID1="$(xray uuid)"
UUID2="$(xray uuid)"
UUID3="$(xray uuid)"
SHORT1="$(openssl rand -hex 8)"
SHORT2="$(openssl rand -hex 8)"
SHORT3="$(openssl rand -hex 8)"
SUB_TOKEN="$(openssl rand -hex 16)"
SOCKS_USER="tguser"
SOCKS_PASS="TgPr0xy_${SUB_TOKEN:0:8}"

# xray x25519 output varies by version; parse PrivateKey / Password(PublicKey)
KEY_OUT="$(xray x25519)"
PRIVATE_KEY="$(echo "$KEY_OUT" | awk -F': ' '/Private/{print $2}' | tr -d '\r' | head -1)"
PUBLIC_KEY="$(echo "$KEY_OUT" | awk -F': ' '/Password|Public/{print $2}' | tr -d '\r' | head -1)"
if [[ -z "$PRIVATE_KEY" || -z "$PUBLIC_KEY" ]]; then
  echo "解析 Reality 密钥失败，原始输出："
  echo "$KEY_OUT"
  exit 1
fi

MTG_SECRET="$(mtg generate-secret -x "$MTG_FAKE_HOST")"

mkdir -p "$APP_DIR" /var/log/xray /etc/nginx/streams-enabled
touch /var/log/xray/access.log /var/log/xray/error.log
chown -R nobody:nogroup /var/log/xray 2>/dev/null || chown -R nobody:nobody /var/log/xray 2>/dev/null || true

echo "==> 写入 Xray 配置"
cat >/usr/local/etc/xray/config.json <<EOF
{
  "log": {
    "access": "/var/log/xray/access.log",
    "error": "/var/log/xray/error.log",
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "tag": "vless-reality-443",
      "listen": "127.0.0.1",
      "port": 11443,
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "${UUID1}",
            "flow": "xtls-rprx-vision",
            "email": "node1@local"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "show": false,
          "dest": "www.microsoft.com:443",
          "xver": 0,
          "serverNames": ["www.microsoft.com", "microsoft.com"],
          "privateKey": "${PRIVATE_KEY}",
          "shortIds": ["${SHORT1}", ""]
        }
      },
      "sniffing": {
        "
