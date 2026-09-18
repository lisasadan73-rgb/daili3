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
apt-get install -y -qq curl wget ca-certificates openssl python3 nginx >/dev/null

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
install -m 755 "$TMP/mtg" /usr/local/bin/mtg
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
        "enabled": true,
        "destOverride": ["http", "tls", "quic"]
      }
    },
    {
      "tag": "vless-reality-8443",
      "listen": "0.0.0.0",
      "port": 8443,
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "${UUID2}",
            "flow": "xtls-rprx-vision",
            "email": "node2@local"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "show": false,
          "dest": "www.cloudflare.com:443",
          "xver": 0,
          "serverNames": ["www.cloudflare.com", "cloudflare.com"],
          "privateKey": "${PRIVATE_KEY}",
          "shortIds": ["${SHORT2}", ""]
        }
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls", "quic"]
      }
    },
    {
      "tag": "vless-reality-2053",
      "listen": "0.0.0.0",
      "port": 2053,
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "${UUID3}",
            "flow": "xtls-rprx-vision",
            "email": "node3@local"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "show": false,
          "dest": "dl.google.com:443",
          "xver": 0,
          "serverNames": ["dl.google.com", "www.google.com"],
          "privateKey": "${PRIVATE_KEY}",
          "shortIds": ["${SHORT3}", ""]
        }
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls", "quic"]
      }
    },
    {
      "tag": "socks-tg",
      "listen": "0.0.0.0",
      "port": 10808,
      "protocol": "socks",
      "settings": {
        "auth": "password",
        "accounts": [
          {
            "user": "${SOCKS_USER}",
            "pass": "${SOCKS_PASS}"
          }
        ],
        "udp": true
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls", "quic"]
      }
    }
  ],
  "outbounds": [
    { "protocol": "freedom", "tag": "direct" },
    { "protocol": "blackhole", "tag": "block" }
  ],
  "routing": {
    "domainStrategy": "AsIs",
    "rules": [
      {
        "type": "field",
        "ip": ["geoip:private"],
        "outboundTag": "block"
      }
    ]
  }
}
EOF

if ! /usr/local/bin/xray run -test -config /usr/local/etc/xray/config.json >/dev/null; then
  echo "Xray 配置校验失败"
  /usr/local/bin/xray run -test -config /usr/local/etc/xray/config.json || true
  exit 1
fi

LINK1="vless://${UUID1}@${PUBLIC_IP}:443?encryption=none&flow=xtls-rprx-vision&security=reality&sni=www.microsoft.com&fp=chrome&pbk=${PUBLIC_KEY}&sid=${SHORT1}&type=tcp&headerType=none#${NODE_PREFIX}-Reality-443"
LINK2="vless://${UUID2}@${PUBLIC_IP}:8443?encryption=none&flow=xtls-rprx-vision&security=reality&sni=www.cloudflare.com&fp=chrome&pbk=${PUBLIC_KEY}&sid=${SHORT2}&type=tcp&headerType=none#${NODE_PREFIX}-Reality-8443"
LINK3="vless://${UUID3}@${PUBLIC_IP}:2053?encryption=none&flow=xtls-rprx-vision&security=reality&sni=dl.google.com&fp=chrome&pbk=${PUBLIC_KEY}&sid=${SHORT3}&type=tcp&headerType=none#${NODE_PREFIX}-Reality-2053"

printf '%s\n%s\n%s\n' "$LINK1" "$LINK2" "$LINK3" >"${APP_DIR}/nodes.txt"
base64 -w 0 <"${APP_DIR}/nodes.txt" >"${APP_DIR}/sub.b64" 2>/dev/null || base64 <"${APP_DIR}/nodes.txt" | tr -d '\n' >"${APP_DIR}/sub.b64"
echo >>"${APP_DIR}/sub.b64"

cat >"${APP_DIR}/secrets.env" <<EOF
# Generated by install.sh — DO NOT commit to public git
PUBLIC_IP=${PUBLIC_IP}
UUID1=${UUID1}
UUID2=${UUID2}
UUID3=${UUID3}
SHORT1=${SHORT1}
SHORT2=${SHORT2}
SHORT3=${SHORT3}
PRIVATE_KEY=${PRIVATE_KEY}
PUBLIC_KEY=${PUBLIC_KEY}
SUB_TOKEN=${SUB_TOKEN}
SOCKS_USER=${SOCKS_USER}
SOCKS_PASS=${SOCKS_PASS}
MTG_SECRET=${MTG_SECRET}
MTG_FAKE_HOST=${MTG_FAKE_HOST}
EOF
chmod 600 "${APP_DIR}/secrets.env"

cat >"${APP_DIR}/sub_server.py" <<EOF
#!/usr/bin/env python3
from http.server import BaseHTTPRequestHandler, HTTPServer
import pathlib

TOKEN = "${SUB_TOKEN}"
SUB_FILE = pathlib.Path("${APP_DIR}/sub.b64")
HOST, PORT = "0.0.0.0", 2080

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path.rstrip("/") == f"/sub/{TOKEN}":
            data = SUB_FILE.read_bytes()
            self.send_response(200)
            self.send_header("Content-Type", "text/plain; charset=utf-8")
            self.send_header("Content-Length", str(len(data)))
            self.send_header("Profile-Update-Interval", "6")
            self.send_header("Subscription-Userinfo", "upload=0; download=0; total=0; expire=0")
            self.end_headers()
            self.wfile.write(data)
        else:
            self.send_response(404)
            self.end_headers()
            self.wfile.write(b"not found")

    def log_message(self, fmt, *args):
        pass

if __name__ == "__main__":
    HTTPServer((HOST, PORT), Handler).serve_forever()
EOF
chmod 755 "${APP_DIR}/sub_server.py"

TG_PROXY="https://t.me/proxy?server=${PUBLIC_IP}&port=3128&secret=${MTG_SECRET}"
SUB_URL="http://${PUBLIC_IP}:2080/sub/${SUB_TOKEN}"

cat >"${APP_DIR}/CLIENT_INFO.txt" <<EOF
======== 客户端信息（请妥善保管）========
公网 IP: ${PUBLIC_IP}
生成时间: $(date -u +%Y-%m-%dT%H:%M:%SZ)

【订阅链接】v2rayN / 兼容客户端
${SUB_URL}

【节点 1】${NODE_PREFIX}-Reality-443
${LINK1}

【节点 2】${NODE_PREFIX}-Reality-8443
${LINK2}

【节点 3】${NODE_PREFIX}-Reality-2053
${LINK3}

【Telegram MTProto】
${TG_PROXY}

【Telegram SOCKS5】
服务器: ${PUBLIC_IP}
端口: 10808
用户: ${SOCKS_USER}
密码: ${SOCKS_PASS}

开放端口: 443, 8443, 2053, 3128, 2080, 10808
========================================
EOF
chmod 600 "${APP_DIR}/CLIENT_INFO.txt"

echo "==> 写入 systemd 服务"
cat >/etc/systemd/system/mtg.service <<EOF
[Unit]
Description=Telegram MTProto Proxy (mtg)
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/mtg simple-run 0.0.0.0:3128 ${MTG_SECRET} --prefer-ip prefer-ipv4
Restart=always
RestartSec=3
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

cat >/etc/systemd/system/v2ray-sub.service <<EOF
[Unit]
Description=V2RayN Subscription Server
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/python3 ${APP_DIR}/sub_server.py
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

if [[ "$SKIP_NGINX" != "1" ]]; then
  echo "==> 配置 Nginx stream SNI（443 → Xray Reality）"
  if ! grep -q 'streams-enabled' /etc/nginx/nginx.conf; then
    cat >>/etc/nginx/nginx.conf <<'NGX'

# Added by proxy-oneclick install.sh
stream {
    include /etc/nginx/streams-enabled/*.conf;
}
NGX
  fi
  mkdir -p /etc/nginx/streams-enabled
  cat >/etc/nginx/streams-enabled/443-sni.conf <<'EOF'
map $ssl_preread_server_name $backend_443 {
    default 127.0.0.1:11443;
}
server {
    listen 443;
    listen [::]:443;
    proxy_pass $backend_443;
    ssl_preread on;
    proxy_connect_timeout 5s;
    proxy_timeout 86400s;
}
EOF
  nginx -t
fi

echo "==> 启动服务"
systemctl daemon-reload
systemctl enable --now xray mtg v2ray-sub
if [[ "$SKIP_NGINX" != "1" ]]; then
  systemctl enable --now nginx
  systemctl reload nginx || systemctl restart nginx
fi

sleep 1
systemctl --no-pager --full is-active xray mtg v2ray-sub nginx 2>/dev/null || true

echo
echo "=========================================="
echo " 部署完成"
echo "=========================================="
echo "订阅: ${SUB_URL}"
echo "完整客户端信息: ${APP_DIR}/CLIENT_INFO.txt"
echo "密钥备份:       ${APP_DIR}/secrets.env"
echo
echo "请放行防火墙端口: 443 8443 2053 3128 2080 10808"
echo "勿将 secrets.env / CLIENT_INFO.txt / nodes.txt / sub.b64 提交到公开 GitHub"
echo "=========================================="
cat "${APP_DIR}/CLIENT_INFO.txt"
