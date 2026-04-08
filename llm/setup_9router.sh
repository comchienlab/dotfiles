#!/usr/bin/env bash
set -euo pipefail

# ══════════════════════════════════════════════════════════════════
#  9Router — Complete VPS Installer / Updater
#  Ubuntu 22.04 / 24.04 · Debian 11 / 12
#  Bao gồm: system optimize · security · swap · 9router · caddy
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

# ── Path constants (defined early for detect_install_mode) ──────────
REPO_URL="https://github.com/decolua/9router.git"
BUILD_DIR="/opt/9router-build"
RUNTIME_DIR="/opt/9router"
DATA_DIR="/var/lib/9router"
ENV_FILE="/etc/9router.env"
SERVICE_FILE="/etc/systemd/system/9router.service"
CADDYFILE="/etc/caddy/Caddyfile"
SYSCTL_CONF="/etc/sysctl.d/99-9router.conf"

clear
echo -e "${C}${W}"
cat << 'BANNER'
▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄
█▀▄▄▀███░▄▄▀█▀▄▄▀█░██░█▄░▄█░▄▄█░▄▄▀██
█▄▀▀░███░▀▀▄█░██░█░██░██░██░▄▄█░▀▀▄██
██▀▀▄███▄█▄▄██▄▄███▄▄▄██▄██▄▄▄█▄█▄▄██
▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀
BANNER
echo -e "${N}"
echo -e "  ${W}AI Proxy Router — Complete VPS Installer${N}"
hr

# ──────────────────────────────────────────────────────────────────
# Detect VPS info
# ──────────────────────────────────────────────────────────────────
VPS_IP=$(curl -fsSL --max-time 5 ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}')
TOTAL_RAM=$(awk '/MemTotal/ {printf "%.0f", $2/1024}' /proc/meminfo)
TOTAL_DISK=$(df -BG / | awk 'NR==2 {print $4}' | tr -d 'G')
OS_INFO=$(. /etc/os-release 2>/dev/null && echo "$PRETTY_NAME" || echo "Unknown")
CPU_CORES=$(nproc)

echo -e "  IP       : ${Y}${W}$VPS_IP${N}"
echo -e "  OS       : $OS_INFO"
echo -e "  CPU      : ${CPU_CORES} cores"
echo -e "  RAM      : ${TOTAL_RAM} MB"
echo -e "  Disk free: ${TOTAL_DISK} GB"
hr

# Warn low RAM
if [[ $TOTAL_RAM -lt 900 ]]; then
  wrn "RAM thấp (${TOTAL_RAM}MB). Script sẽ tạo swap 2GB để build an toàn."
fi

# ──────────────────────────────────────────────────────────────────
# Detect install mode
# ──────────────────────────────────────────────────────────────────
INSTALL_MODE="install"
if [[ -f "$ENV_FILE" ]] && [[ -s "$ENV_FILE" ]] \
   && [[ -f "$RUNTIME_DIR/server.js" ]] \
   && systemctl list-unit-files 9router.service &>/dev/null; then
  INSTALL_MODE="update"
fi

# ══════════════════════════════════════════════════════════════════
#  Interactive config
# ══════════════════════════════════════════════════════════════════
sec "Cấu hình"

# ── Helper: source existing env ─────────────────────────────────────
source_existing_env() {
  set -a
  # shellcheck source=/dev/null
  source "$ENV_FILE"
  set +a
  APP_PORT="${PORT:-20128}"
  TZ_SET=$(timedatectl show -p Timezone --value 2>/dev/null || echo "Asia/Ho_Chi_Minh")
  if [[ "${NEXT_PUBLIC_BASE_URL:-}" == https://* ]]; then
    DOMAIN="${NEXT_PUBLIC_BASE_URL#https://}"
  else
    DOMAIN=""
  fi
  BASE_URL="${NEXT_PUBLIC_BASE_URL:-}"
}

if [[ "$INSTALL_MODE" == "update" ]]; then
  echo -e "\n  ${C}${W}Chế độ: Cập nhật${N} (9Router đã được cài trước đó)\n"
  source_existing_env

  OLD_COMMIT=$(cat "$RUNTIME_DIR/.install-commit" 2>/dev/null || echo "không rõ")
  echo -e "  Phiên bản hiện tại : ${Y}$OLD_COMMIT${N}"
  [[ -n "$DOMAIN" ]] \
    && echo -e "  Domain             : ${G}$DOMAIN${N}" \
    || echo -e "  Domain             : ${Y}(IP only — http://$VPS_IP:$APP_PORT)${N}"
  echo -e "  Port               : $APP_PORT"
  echo -e "  Timezone           : $TZ_SET"
  echo ""

  echo -e "${W}[1/1] Đổi mật khẩu đăng nhập (Enter để giữ nguyên):${N}"
  read -rp "  → Password mới: " _new_pass </dev/tty
  if [[ -n "$_new_pass" ]]; then
    INITIAL_PASSWORD="$_new_pass"
  fi
  # INITIAL_PASSWORD đã được load từ env file qua source_existing_env nếu không đổi

else
  echo -e "\n  ${Y}${W}Chế độ: Cài đặt mới${N}\n"

  echo -e "${W}[1/4] Domain (bỏ trống nếu chỉ dùng IP):${N}"
  echo -e "      ${B}Ví dụ: llm.example.com${N}"
  read -rp "  → Domain: " DOMAIN </dev/tty
  DOMAIN="${DOMAIN// /}"

  echo -e "\n${W}[2/4] Mật khẩu đăng nhập 9Router:${N}"
  echo -e "      ${B}Enter = ChangeMe123!${N}"
  read -rp "  → Password: " INITIAL_PASSWORD </dev/tty
  INITIAL_PASSWORD="${INITIAL_PASSWORD:-ChangeMe123!}"

  echo -e "\n${W}[3/4] Port ứng dụng:${N}"
  echo -e "      ${B}Enter = 20128${N}"
  read -rp "  → Port: " APP_PORT </dev/tty
  APP_PORT="${APP_PORT:-20128}"

  echo -e "\n${W}[4/4] Timezone:${N}"
  echo -e "      ${B}Enter = Asia/Ho_Chi_Minh${N}"
  read -rp "  → Timezone: " TZ_SET </dev/tty
  TZ_SET="${TZ_SET:-Asia/Ho_Chi_Minh}"

  # Generate secrets only on fresh install
  JWT_SECRET=$(openssl rand -hex 32)
  API_KEY_SECRET=$(openssl rand -hex 32)
  MACHINE_ID_SALT=$(openssl rand -hex 16)
fi

# ── Derived values ──────────────────────────────────────────────────
[[ -n "$DOMAIN" ]] && BASE_URL="https://$DOMAIN" || BASE_URL="http://$VPS_IP:$APP_PORT"

# ── Summary ────────────────────────────────────────────────────────
echo ""
hr
echo -e "  ${W}Xác nhận:${N}"
echo -e "  IP        : ${Y}$VPS_IP${N}"
[[ -n "$DOMAIN" ]] \
  && echo -e "  Domain    : ${G}$DOMAIN${N}  ← Caddy + HTTPS tự động" \
  || echo -e "  Domain    : ${Y}(IP only — http://$VPS_IP:$APP_PORT)${N}"
echo -e "  Password  : ${Y}$INITIAL_PASSWORD${N}"
echo -e "  Port      : $APP_PORT"
echo -e "  Timezone  : $TZ_SET"
if [[ "$INSTALL_MODE" == "update" ]]; then
  echo -e "  Secrets   : ${G}giữ nguyên từ cài đặt trước${N}"
fi
hr
echo ""
read -rp "  Bắt đầu? [Y/n] " _go </dev/tty
[[ "${_go:-Y}" =~ ^[Nn]$ ]] && { echo "Đã huỷ."; exit 0; }

START_TIME=$SECONDS

# ── Helper functions ────────────────────────────────────────────────
wait_for_service() {
  local svc="$1" max="${2:-15}" interval="${3:-2}" attempt=0
  inf "Chờ $svc khởi động..."
  while [[ $attempt -lt $max ]]; do
    systemctl is-active --quiet "$svc" && { ok "$svc running"; return 0; }
    attempt=$(( attempt + 1 ))
    sleep "$interval"
  done
  die "$svc không start được sau $((max * interval))s. Check: journalctl -u $svc -n 30"
}

wait_for_https() {
  local domain="$1" max=12 attempt=0
  inf "Chờ Caddy xin TLS cert (tối đa 60s)..."
  while [[ $attempt -lt $max ]]; do
    curl -fsI "https://$domain" &>/dev/null && { ok "HTTPS live: https://$domain"; return 0; }
    attempt=$(( attempt + 1 ))
    sleep 5
  done
  wrn "DNS chưa propagate tới $VPS_IP — HTTPS tự lên sau khi DNS lan truyền"
  wrn "Kiểm tra: curl -I https://$domain"
}

ensure_ufw_rule() {
  local rule="$1"
  ufw status | grep -qE "^${rule}.*ALLOW" 2>/dev/null || ufw allow "$rule" &>/dev/null
}

write_env_file() {
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
}

# ══════════════════════════════════════════════════════════════════
#  Phase 0 — System update & optimize
# ══════════════════════════════════════════════════════════════════
sec "Phase 0 — System update & optimize"

# Timezone
timedatectl set-timezone "$TZ_SET" 2>/dev/null && ok "Timezone → $TZ_SET" || wrn "Không set được timezone"

# Avoid interactive prompts from apt
export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a

inf "apt update + upgrade..."
apt-get update -qq
apt-get upgrade -y -qq \
  -o Dpkg::Options::="--force-confdef" \
  -o Dpkg::Options::="--force-confold"
ok "System packages updated"

inf "Cài essential tools..."
apt-get install -y -qq \
  curl wget git ca-certificates openssl gnupg \
  htop vim net-tools unzip lsof rsync \
  ufw fail2ban \
  build-essential
ok "Essential tools installed"

# ── Swap ────────────────────────────────────────────────────────────
SWAP_NEEDED=2048  # MB
if [[ $(swapon --show --noheadings 2>/dev/null | wc -l) -eq 0 ]]; then
  inf "Tạo swap ${SWAP_NEEDED}MB..."
  SWAPFILE=/swapfile
  [[ -f "$SWAPFILE" ]] && swapoff "$SWAPFILE" 2>/dev/null || true
  fallocate -l "${SWAP_NEEDED}M" "$SWAPFILE"
  chmod 600 "$SWAPFILE"
  mkswap -q "$SWAPFILE"
  swapon "$SWAPFILE"
  grep -q "$SWAPFILE" /etc/fstab \
    || echo "$SWAPFILE none swap sw 0 0" >> /etc/fstab
  ok "Swap ${SWAP_NEEDED}MB active"
else
  ok "Swap already configured: $(free -h | awk '/Swap/ {print $2}')"
fi

# ── Kernel / sysctl tuning ──────────────────────────────────────────
inf "Applying sysctl optimizations..."
cat > "$SYSCTL_CONF" << 'EOF'
# ── Network ──────────────────────────────────────────────────────
net.core.somaxconn            = 65535
net.ipv4.tcp_max_syn_backlog  = 65535
net.ipv4.tcp_fin_timeout      = 15
net.ipv4.tcp_keepalive_time   = 300
net.ipv4.tcp_keepalive_intvl  = 30
net.ipv4.tcp_keepalive_probes = 5
net.ipv4.tcp_tw_reuse         = 1
net.core.netdev_max_backlog   = 65535
net.core.rmem_max             = 16777216
net.core.wmem_max             = 16777216
net.ipv4.tcp_rmem             = 4096 87380 16777216
net.ipv4.tcp_wmem             = 4096 65536 16777216
# ── Files ────────────────────────────────────────────────────────
fs.file-max                   = 1000000
fs.inotify.max_user_watches   = 524288
fs.inotify.max_user_instances = 512
# ── VM / Swap ────────────────────────────────────────────────────
vm.swappiness                 = 10
vm.dirty_ratio                = 15
vm.dirty_background_ratio     = 5
vm.overcommit_memory          = 1
EOF
sysctl -p "$SYSCTL_CONF" &>/dev/null
ok "sysctl applied"

# ── ulimits ─────────────────────────────────────────────────────────
inf "Setting open file limits..."
grep -q "^\*.*soft.*nofile.*65535" /etc/security/limits.conf 2>/dev/null \
  || cat >> /etc/security/limits.conf << 'EOF'
# 9router
*         soft  nofile  65535
*         hard  nofile  65535
root      soft  nofile  65535
root      hard  nofile  65535
EOF
ok "ulimits set (nofile=65535)"

# ── UFW (idempotent — never reset existing rules) ──────────────────
inf "Configuring UFW..."
ufw status | grep -q "Status: inactive" && {
  ufw default deny incoming  &>/dev/null
  ufw default allow outgoing &>/dev/null
}
ensure_ufw_rule ssh
ensure_ufw_rule "80/tcp"
ensure_ufw_rule "443/tcp"
[[ -z "$DOMAIN" ]] && ensure_ufw_rule "$APP_PORT/tcp" || true
ufw status | grep -q "Status: active" || ufw --force enable &>/dev/null
ok "UFW configured (ssh, 80, 443$([ -z "$DOMAIN" ] && echo ", $APP_PORT" || echo ""))"

# ── fail2ban ────────────────────────────────────────────────────────
systemctl enable fail2ban &>/dev/null
systemctl restart fail2ban
ok "fail2ban active"

# ── SSH hardening (non-destructive) ─────────────────────────────────
SSHD=/etc/ssh/sshd_config
grep -q "^ClientAliveInterval" "$SSHD" \
  || echo "ClientAliveInterval 120" >> "$SSHD"
grep -q "^ClientAliveCountMax" "$SSHD" \
  || echo "ClientAliveCountMax 3"   >> "$SSHD"
systemctl reload sshd 2>/dev/null || systemctl reload ssh 2>/dev/null || true
ok "SSH keepalive configured"

# ══════════════════════════════════════════════════════════════════
#  Phase 1 — Node.js + pnpm
# ══════════════════════════════════════════════════════════════════
sec "Phase 1 — Node.js + pnpm"

NODE_VER_OK=false
if command -v node &>/dev/null; then
  NODE_MAJOR=$(node -v 2>/dev/null | sed 's/v\([0-9]*\)\..*/\1/')
  [[ "$NODE_MAJOR" =~ ^[0-9]+$ ]] && [[ $NODE_MAJOR -ge 20 ]] && NODE_VER_OK=true
fi

if [[ "$NODE_VER_OK" == "false" ]]; then
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
#  Phase 2 — Build 9Router
# ══════════════════════════════════════════════════════════════════
sec "Phase 2 — Build 9Router"

if [[ "$INSTALL_MODE" == "update" ]]; then
  OLD_COMMIT=$(cat "$RUNTIME_DIR/.install-commit" 2>/dev/null || echo "không rõ")
  inf "Phiên bản hiện tại: $OLD_COMMIT"
fi

systemctl stop 9router 2>/dev/null && wrn "Stopped existing 9router" || true

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"
inf "Cloning repository..."
git clone --depth=1 "$REPO_URL" "$BUILD_DIR" &>/dev/null
ok "Cloned"

NEW_COMMIT=$(git -C "$BUILD_DIR" rev-parse --short HEAD 2>/dev/null || echo "?")
inf "Phiên bản mới: $NEW_COMMIT"

cd "$BUILD_DIR"
unset NODE_ENV
export NEXT_TELEMETRY_DISABLED=1

# Dynamic memory: half of total RAM, min 512, max 1536
MEM_LIMIT=$(( TOTAL_RAM / 2 ))
[[ $MEM_LIMIT -lt 512  ]] && MEM_LIMIT=512
[[ $MEM_LIMIT -gt 1536 ]] && MEM_LIMIT=1536
export NODE_OPTIONS="--max-old-space-size=${MEM_LIMIT}"
inf "Node build memory limit: ${MEM_LIMIT}MB"

inf "Installing dependencies..."
pnpm install --include=optional --silent
pnpm add -D @tailwindcss/postcss --silent
pnpm add prop-types --silent
ok "Dependencies ready"

BUILD_LOG="/tmp/9router-build-$$.log"
inf "Building Next.js (2-4 phút)..."
export NODE_ENV=production
if ! pnpm run build 2>&1 | tee "$BUILD_LOG" | tail -5; then
  die "Build thất bại. Log đầy đủ: $BUILD_LOG"
fi
ok "Build complete"

test -f .next/standalone/server.js || die "Build thất bại: server.js không tìm thấy"

# ══════════════════════════════════════════════════════════════════
#  Phase 3 — Deploy runtime (in-place, no rm -rf)
# ══════════════════════════════════════════════════════════════════
sec "Phase 3 — Deploy runtime"

mkdir -p "$RUNTIME_DIR/.next"
# Only create data dir on fresh install — never touch it on updates
[[ "$INSTALL_MODE" == "install" ]] && mkdir -p "$DATA_DIR"

if command -v rsync &>/dev/null; then
  rsync -a --delete .next/standalone/ "$RUNTIME_DIR/"
  rsync -a --delete .next/static/     "$RUNTIME_DIR/.next/static/"
  [[ -d public ]] && rsync -a --delete public/ "$RUNTIME_DIR/public/" || true
else
  cp -a .next/standalone/. "$RUNTIME_DIR/"
  cp -a .next/static        "$RUNTIME_DIR/.next/"
  [[ -d public ]] && cp -a public "$RUNTIME_DIR/" || true
fi

# Record installed commit for future update display
git -C "$BUILD_DIR" rev-parse --short HEAD > "$RUNTIME_DIR/.install-commit" 2>/dev/null || true
ok "Runtime → $RUNTIME_DIR"

# ══════════════════════════════════════════════════════════════════
#  Phase 4 — Env + Systemd
# ══════════════════════════════════════════════════════════════════
sec "Phase 4 — Systemd service"

write_env_file
ok "Env → $ENV_FILE (chmod 600)"

cat > "$SERVICE_FILE" << EOF
[Unit]
Description=9router AI proxy
Documentation=https://github.com/decolua/9router
After=network.target

[Service]
Type=simple
WorkingDirectory=$RUNTIME_DIR
EnvironmentFile=$ENV_FILE
ExecStart=/usr/bin/node $RUNTIME_DIR/server.js
Restart=on-failure
RestartSec=5
User=root

# Resource limits
LimitNOFILE=65535
LimitNPROC=65535

# Logging
StandardOutput=journal
StandardError=journal
SyslogIdentifier=9router

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable 9router &>/dev/null
systemctl restart 9router
ok "Service 9router started"

wait_for_service 9router 15 2
inf "9router running on port $APP_PORT"

# ══════════════════════════════════════════════════════════════════
#  Phase 5 — Caddy (only if domain provided)
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
    ok "Caddy $(caddy version | head -1) already installed"
  fi

  mkdir -p /etc/caddy

  # Only rewrite Caddyfile if domain changed or file doesn't exist
  CADDY_NEEDS_UPDATE=false
  if [[ ! -f "$CADDYFILE" ]]; then
    CADDY_NEEDS_UPDATE=true
  elif ! grep -qE "^${DOMAIN} \{" "$CADDYFILE" 2>/dev/null; then
    CADDY_NEEDS_UPDATE=true
  fi

  if [[ "$CADDY_NEEDS_UPDATE" == "true" ]]; then
    cat > "$CADDYFILE" << EOF
$DOMAIN {
    encode gzip
    reverse_proxy 127.0.0.1:$APP_PORT {
        header_up Host {host}
        header_up X-Real-IP {remote_host}
        header_up X-Forwarded-For {remote_host}
        header_up X-Forwarded-Proto {scheme}
    }
}
EOF
    ok "Caddyfile → $CADDYFILE"
  else
    ok "Caddyfile unchanged (domain: $DOMAIN)"
  fi

  systemctl enable caddy &>/dev/null
  systemctl restart caddy
  wait_for_service caddy 10 2

  wait_for_https "$DOMAIN"
fi

# ══════════════════════════════════════════════════════════════════
#  Phase 6 — Cleanup
# ══════════════════════════════════════════════════════════════════
sec "Phase 6 — Cleanup"

cd /
rm -rf "$BUILD_DIR"
[[ -f "$BUILD_LOG" ]] && rm -f "$BUILD_LOG" || true
pnpm store prune &>/dev/null || true
apt-get autoremove --purge -y -qq
apt-get clean -qq
ok "Build artifacts removed"

# ══════════════════════════════════════════════════════════════════
#  Done
# ══════════════════════════════════════════════════════════════════
ELAPSED=$(( SECONDS - START_TIME ))
ELAPSED_FMT=$(printf '%dm%02ds' $((ELAPSED/60)) $((ELAPSED%60)))

echo ""
hr
echo -e "${G}${W}"
if [[ "$INSTALL_MODE" == "update" ]]; then
  echo "   ✅  Cập nhật hoàn tất! (${ELAPSED_FMT})"
else
  echo "   ✅  Cài đặt hoàn tất! (${ELAPSED_FMT})"
fi
echo -e "${N}"
hr
echo -e "  ${W}9Router${N}"
echo -e "  URL          : ${C}${W}$BASE_URL${N}"
echo -e "  Password     : ${Y}$INITIAL_PASSWORD${N}"
if [[ "$INSTALL_MODE" == "update" ]]; then
  echo -e "  Build cũ     : ${Y}${OLD_COMMIT:-không rõ}${N}"
  echo -e "  Build mới    : ${G}$NEW_COMMIT${N}"
fi
echo -e ""
echo -e "  ${W}Files${N}"
echo -e "  Config       : $ENV_FILE"
echo -e "  Runtime      : $RUNTIME_DIR"
echo -e "  Data         : $DATA_DIR"
echo -e ""
echo -e "  ${W}Commands${N}"
echo -e "  Logs         : ${B}journalctl -u 9router -f${N}"
echo -e "  Restart      : ${B}systemctl restart 9router${N}"
echo -e "  Edit config  : ${B}nano $ENV_FILE${N}"
[[ -n "$DOMAIN" ]] && \
echo -e "  Caddy logs   : ${B}journalctl -u caddy -f${N}"
hr
echo ""

[[ "$INITIAL_PASSWORD" == "ChangeMe123!" ]] && {
  echo -e "${Y}${W}  ⚠  Đang dùng mật khẩu mặc định! Đổi ngay:${N}"
  echo -e "     ${B}nano $ENV_FILE${N}"
  echo -e "     ${B}systemctl restart 9router${N}"
  echo ""
}

echo -e "${W}  Service status:${N}"
systemctl --no-pager --full status 9router
