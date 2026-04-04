#!/usr/bin/env bash
set -euo pipefail

# ══════════════════════════════════════════════════════════════════
#  9Router — One-shot VPS Installer
#  Supports: Ubuntu 22.04 / 24.04 · Debian 11 / 12
#  Run: sudo bash install.sh
# ══════════════════════════════════════════════════════════════════

R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'
B='\033[0;34m'; C='\033[0;36m'; W='\033[1m'; N='\033[0m'

ok()  { echo -e "${G}[✔]${N} $*"; }
inf() { echo -e "${B}[→]${N} $*"; }
wrn() { echo -e "${Y}[!]${N} $*"; }
die() { echo -e "${R}[✘]${N} $*" >&2; exit 1; }
sec() { echo -e "\n${C}${W}━━━  $*  ━━━${N}"; }
hr()  { echo -e "${C}──────────────────────────────────────────${N}"; }

[[ $EUID -ne 0 ]] && die "Chạy với quyền root: sudo bash $0"

clear
echo -e "${C}${W}"
cat << 'BANNER'
  ██████╗ ██████╗  ██████╗ ██╗   ██╗████████╗███████╗██████╗
  ██╔══██╗██╔══██╗██╔═══██╗██║   ██║╚══██╔══╝██╔════╝██╔══██╗
  ██████╔╝██████╔╝██║   ██║██║   ██║   ██║   █████╗  ██████╔╝
  ██╔══██╗██╔══██╗██║   ██║██║   ██║   ██║   ██╔══╝  ██╔══██╗
  ██║  ██║██║  ██║╚██████╔╝╚██████╔╝   ██║   ███████╗██║  ██║
  ╚═╝  ╚═╝╚═╝  ╚═╝ ╚═════╝  ╚═════╝   ╚═╝   ╚══════╝╚═╝  ╚═╝
BANNER
echo -e "${N}"
echo -e "  ${W}AI Proxy Router — VPS Installer${N}"
hr

# ── Detect VPS IP ──────────────────────────────────────────────
VPS_IP=$(curl -fsSL --max-time 5 ifconfig.me 2>/dev/null \
         || hostname -I | awk '{print $1}')
echo -e "  VPS IP: ${Y}${W}$VPS_IP${N}"
hr

# ══════════════════════════════════════════════════════════════════
#  Interactive config
# ══════════════════════════════════════════════════════════════════
sec "Cấu hình"

# Domain
echo -e "\n${W}Domain của bạn (bỏ trống nếu chỉ dùng IP):${N}"
echo -e "  ${B}Ví dụ: llm.example.com${N}"
read -rp "  → Domain: " DOMAIN
DOMAIN="${DOMAIN// /}"   # strip spaces

# Password
echo -e "\n${W}Mật khẩu đăng nhập:${N}"
echo -e "  ${B}(Enter để dùng mặc định: ChangeMe123!)${N}"
read -rp "  → Password: " INITIAL_PASSWORD
INITIAL_PASSWORD="${INITIAL_PASSWORD:-ChangeMe123!}"

# Port
echo -e "\n${W}Port ứng dụng:${N}"
echo -e "  ${B}(Enter để dùng mặc định: 20128)${N}"
read -rp "  → Port: " APP_PORT
APP_PORT="${APP_PORT:-20128}"

# ── Summarize & confirm ────────────────────────────────────────
echo ""
hr
echo -e "  ${W}Xác nhận cài đặt:${N}"
echo -e "  VPS IP    : ${Y}$VPS_IP${N}"
if [[ -n "$DOMAIN" ]]; then
  echo -e "  Domain    : ${G}$DOMAIN${N}  (Caddy + HTTPS tự động)"
else
  echo -e "  Domain    : ${Y}(không có — truy cập qua IP)${N}"
fi
echo -e "  Port      : $APP_PORT"
echo -e "  Password  : ${Y}$INITIAL_PASSWORD${N}"
hr
echo ""
read -rp "  Tiếp tục? [Y/n] " _confirm
[[ "${_confirm:-Y}" =~ ^[Nn]$ ]] && { echo "Đã huỷ."; exit 0; }

# ── Derived values ─────────────────────────────────────────────
REPO_URL="https://github.com/decolua/9router.git"
BUILD_DIR="/opt/9router-build"
RUNTIME_DIR="/opt/9router"
DATA_DIR="/var/lib/9router"
ENV_FILE="/etc/9router.env"
SERVICE_FILE="/etc/systemd/system/9router.service"
CADDYFILE="/etc/caddy/Caddyfile"

JWT_SECRET=$(openssl rand -hex 32)
API_KEY_SECRET=$(openssl rand -hex 32)
MACHINE_ID_SALT=$(openssl rand -hex 16)

if [[ -n "$DOMAIN" ]]; then
  BASE_URL="https://$DOMAIN"
else
  BASE_URL="http://$VPS_IP:$APP_PORT"
fi

# ══════════════════════════════════════════════════════════════════
#  Phase 1 — System dependencies
# ══════════════════════════════════════════════════════════════════
sec "Phase 1 — System dependencies"

apt-get update -qq
apt-get install -y -qq git curl ca-certificates openssl
ok "Base packages ready"

if ! command -v node &>/dev/null; then
  inf "Cài Node.js 20..."
  curl -fsSL https://deb.nodesource.com/setup_20.x | bash - &>/dev/null
  apt-get install -y -qq nodejs
  ok "Node.js $(node -v) installed"
else
  ok "Node.js $(node -v) already installed"
fi

if ! command -v pnpm &>/dev/null; then
  inf "Cài pnpm..."
  npm install -g pnpm --silent
  ok "pnpm $(pnpm -v) installed"
else
  ok "pnpm $(pnpm -v) already installed"
fi

# ══════════════════════════════════════════════════════════════════
#  Phase 2 — Build
# ══════════════════════════════════════════════════════════════════
sec "Phase 2 — Build 9Router"

systemctl stop 9router 2>/dev/null && wrn "Stopped existing 9router" || true

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR" "$DATA_DIR"
inf "Cloning repository..."
git clone --depth=1 "$REPO_URL" "$BUILD_DIR" &>/dev/null
ok "Cloned"

cd "$BUILD_DIR"
unset NODE_ENV
export NEXT_TELEMETRY_DISABLED=1
export NODE_OPTIONS=--max-old-space-size=768

inf "Installing dependencies..."
pnpm install --include=optional --silent
pnpm add -D @tailwindcss/postcss --silent
pnpm add prop-types --silent
ok "Dependencies ready"

inf "Building Next.js (2-4 phút)..."
export NODE_ENV=production
pnpm run build 2>&1 | tail -3
ok "Build xong"

test -f .next/standalone/server.js || die "Build thất bại: server.js không tìm thấy"

# ══════════════════════════════════════════════════════════════════
#  Phase 3 — Deploy
# ══════════════════════════════════════════════════════════════════
sec "Phase 3 — Deploy runtime"

rm -rf "$RUNTIME_DIR"
mkdir -p "$RUNTIME_DIR/.next"
cp -a .next/standalone/.   "$RUNTIME_DIR/"
cp -a .next/static         "$RUNTIME_DIR/.next/"
[[ -d public ]] && cp -a public "$RUNTIME_DIR/"
ok "Runtime → $RUNTIME_DIR"

# ══════════════════════════════════════════════════════════════════
#  Phase 4 — Env + Systemd
# ══════════════════════════════════════════════════════════════════
sec "Phase 4 — Systemd service"

cat > "$ENV_FILE" << EOF
JWT_SECRET=$JWT_SECRET
INITIAL_PASSWORD=$INITIAL_PASSWORD
DATA_DIR=$DATA_DIR
PORT=$APP_PORT
HOSTNAME=0.0.0.0
NODE_ENV=production
NEXT_PUBLIC_BASE_URL=$BASE_URL
NEXT_PUBLIC_CLOUD_URL=https://9router.com
API_KEY_SECRET=$API_KEY_SECRET
MACHINE_ID_SALT=$MACHINE_ID_SALT
EOF
chmod 600 "$ENV_FILE"
ok "Env → $ENV_FILE (chmod 600)"

cat > "$SERVICE_FILE" << EOF
[Unit]
Description=9router AI proxy
After=network.target

[Service]
Type=simple
WorkingDirectory=$RUNTIME_DIR
EnvironmentFile=$ENV_FILE
ExecStart=/usr/bin/node $RUNTIME_DIR/server.js
Restart=on-failure
RestartSec=5
User=root

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable 9router &>/dev/null
systemctl restart 9router
ok "Service 9router started"

# ══════════════════════════════════════════════════════════════════
#  Phase 5 — Caddy (chỉ khi có domain)
# ══════════════════════════════════════════════════════════════════
if [[ -n "$DOMAIN" ]]; then
  sec "Phase 5 — Caddy + HTTPS"

  apt-get install -y -qq debian-keyring debian-archive-keyring apt-transport-https

  if ! command -v caddy &>/dev/null; then
    inf "Cài Caddy..."
    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' \
      | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' \
      | tee /etc/apt/sources.list.d/caddy-stable.list &>/dev/null
    apt-get update -qq
    apt-get install -y -qq caddy
    ok "Caddy installed"
  else
    ok "Caddy already installed"
  fi

  mkdir -p /etc/caddy
  cat > "$CADDYFILE" << EOF
$DOMAIN {
    reverse_proxy 127.0.0.1:$APP_PORT
}
EOF
  ok "Caddyfile → $CADDYFILE"

  # Update base URL in env to use domain
  sed -i "s|^NEXT_PUBLIC_BASE_URL=.*|NEXT_PUBLIC_BASE_URL=https://$DOMAIN|" "$ENV_FILE"
  systemctl restart 9router

  systemctl enable caddy &>/dev/null
  systemctl restart caddy
  ok "Caddy restarted"

  inf "Chờ Caddy xin cert (5s)..."
  sleep 5
  if curl -fsI "https://$DOMAIN" &>/dev/null; then
    ok "HTTPS live: https://$DOMAIN"
  else
    wrn "DNS chưa propagate tới $VPS_IP — HTTPS sẽ tự lên khi DNS lan truyền xong"
  fi
fi

# ══════════════════════════════════════════════════════════════════
#  Phase 6 — Cleanup
# ══════════════════════════════════════════════════════════════════
sec "Phase 6 — Cleanup"

cd /
rm -rf "$BUILD_DIR"
pnpm store prune &>/dev/null || true
apt-get autoremove --purge -y -qq
apt-get clean -qq
ok "Build artifacts removed"

if command -v ufw &>/dev/null; then
  ufw allow 80/tcp  &>/dev/null || true
  ufw allow 443/tcp &>/dev/null || true
  [[ -z "$DOMAIN" ]] && { ufw allow "$APP_PORT/tcp" &>/dev/null || true; }
  ok "UFW updated"
fi

# ══════════════════════════════════════════════════════════════════
#  Done
# ══════════════════════════════════════════════════════════════════
echo ""
hr
echo -e "${G}${W}"
echo "   ✅  9Router đã cài xong!"
echo -e "${N}"
echo -e "   URL      : ${C}${W}$BASE_URL${N}"
echo -e "   Password : ${Y}$INITIAL_PASSWORD${N}"
echo -e "   Env file : $ENV_FILE"
echo -e "   Logs     : journalctl -u 9router -f"
echo ""
[[ "$INITIAL_PASSWORD" == "ChangeMe123!" ]] && \
  wrn "Đang dùng mật khẩu mặc định! Đổi ngay:"
  echo -e "     ${B}nano $ENV_FILE  →  systemctl restart 9router${N}"
echo ""
hr
echo ""
systemctl --no-pager --full status 9router
