#!/usr/bin/env bash
set -euo pipefail

# ══════════════════════════════════════════════════════════════════
#  GoClaw — VPS Setup Script (No Docker)
#  Ubuntu 22.04 / 24.04 · Debian 11 / 12
#  Stack: PostgreSQL 16 + pgvector · Go binary · systemd · Caddy
#  Run: sudo bash goclaw-setup.sh
# ══════════════════════════════════════════════════════════════════

R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'
B='\033[0;34m'; C='\033[0;36m'; W='\033[1m'; N='\033[0m'

ok()  { echo -e "${G}[✔]${N} $*"; }
inf() { echo -e "${B}[→]${N} $*"; }
wrn() { echo -e "${Y}[!]${N} $*"; }
die() { echo -e "${R}[✘]${N} $*" >&2; exit 1; }
sec() { echo -e "\n${C}${W}━━━  $*  ━━━${N}"; }
hr()  { echo -e "${C}──────────────────────────────────────────${N}"; }

# ── Constants ──────────────────────────────────────────────────────
SERVICE_NAME="goclaw"
SERVICE_USER="goclaw"
WORK_DIR="/opt/goclaw"
STATIC_DIR="/opt/goclaw/public"
ENV_FILE="/etc/goclaw.env"
SERVICE_FILE="/etc/systemd/system/goclaw.service"
CADDYFILE="/etc/caddy/Caddyfile"
SYSCTL_CONF="/etc/sysctl.d/99-goclaw.conf"
PG_VERSION="16"
MIN_GO_VERSION="1.22"
GOCLAW_PKG="github.com/nextlevelbuilder/goclaw@latest"

# ── Pre-flight ─────────────────────────────────────────────────────
[[ $EUID -ne 0 ]] && die "Chạy với quyền root: sudo bash $0"

clear
echo -e "${C}${W}"
cat << 'BANNER'
   ██████╗  ██████╗  ██████╗██╗      █████╗ ██╗    ██╗
  ██╔════╝ ██╔═══██╗██╔════╝██║     ██╔══██╗██║    ██║
  ██║  ███╗██║   ██║██║     ██║     ███████║██║ █╗ ██║
  ██║   ██║██║   ██║██║     ██║     ██╔══██║██║███╗██║
  ╚██████╔╝╚██████╔╝╚██████╗███████╗██║  ██║╚███╔███╔╝
   ╚═════╝  ╚═════╝  ╚═════╝╚══════╝╚═╝  ╚═╝ ╚══╝╚══╝
BANNER
echo -e "${N}"
echo -e "  ${W}AI Agent Gateway — VPS Setup (No Docker)${N}"
hr

# ── OS check ───────────────────────────────────────────────────────
if ! grep -qE "Ubuntu|Debian" /etc/os-release 2>/dev/null; then
  die "Script chỉ hỗ trợ Ubuntu/Debian. OS hiện tại: $(grep '^NAME=' /etc/os-release | cut -d= -f2)"
fi

# ── Architecture ───────────────────────────────────────────────────
ARCH=$(uname -m)
case "$ARCH" in
  x86_64)  GO_ARCH="amd64" ;;
  aarch64) GO_ARCH="arm64" ;;
  *) die "Kiến trúc không hỗ trợ: $ARCH" ;;
esac

# ── VPS info ───────────────────────────────────────────────────────
VPS_IP=$(curl -fsSL --max-time 5 ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}')
TOTAL_RAM=$(awk '/MemTotal/ {printf "%.0f", $2/1024}' /proc/meminfo)
TOTAL_DISK=$(df -BG / | awk 'NR==2 {print $4}' | tr -d 'G')
OS_INFO=$(. /etc/os-release 2>/dev/null && echo "$PRETTY_NAME" || echo "Unknown")
CPU_CORES=$(nproc)

echo -e "  IP       : ${Y}${W}${VPS_IP}${N}"
echo -e "  OS       : ${OS_INFO}"
echo -e "  CPU      : ${CPU_CORES} cores"
echo -e "  RAM      : ${TOTAL_RAM} MB"
echo -e "  Disk free: ${TOTAL_DISK} GB"
hr

[[ $TOTAL_RAM -lt 900 ]] && wrn "RAM thấp (${TOTAL_RAM}MB). Script sẽ tạo swap 2GB."

# ── Detect install mode ────────────────────────────────────────────
INSTALL_MODE="install"
if [[ -f "$ENV_FILE" ]] && [[ -s "$ENV_FILE" ]] \
   && systemctl list-unit-files ${SERVICE_NAME}.service &>/dev/null; then
  INSTALL_MODE="update"
fi

# ══════════════════════════════════════════════════════════════════
#  Interactive config
# ══════════════════════════════════════════════════════════════════
sec "Cấu hình"

source_existing_env() {
  set -a
  # shellcheck source=/dev/null
  source "$ENV_FILE"
  set +a
  INTERNAL_PORT="${PORT:-3000}"
  EXTERNAL_PORT="${EXTERNAL_PORT:-8080}"
  DOMAIN="${DOMAIN:-}"
  TZ_SET="${TZ:-Asia/Ho_Chi_Minh}"
  DB_MODE="${DB_MODE:-local}"
  DATABASE_URL="${DATABASE_URL:-}"
}

if [[ "$INSTALL_MODE" == "update" ]]; then
  echo -e "\n  ${C}${W}Chế độ: Cập nhật${N} (GoClaw đã được cài trước đó)\n"
  source_existing_env
  [[ -n "$DOMAIN" ]] \
    && echo -e "  Domain         : ${G}${DOMAIN}${N}" \
    || echo -e "  Domain         : ${Y}(IP only — http://${VPS_IP}:${EXTERNAL_PORT})${N}"
  echo -e "  Internal port  : ${INTERNAL_PORT}"
  echo -e "  External port  : ${EXTERNAL_PORT}"
  echo -e "  DB mode        : ${DB_MODE}"
  echo -e "  Timezone       : ${TZ_SET}"
  echo ""
  echo -e "${W}Nhấn Enter để giữ nguyên giá trị hiện tại.${N}"
  echo ""

else
  echo -e "\n  ${Y}${W}Chế độ: Cài đặt mới${N}\n"

  echo -e "${W}[1/5] Domain (bỏ trống nếu chỉ dùng IP):${N}"
  echo -e "      ${B}Ví dụ: goclaw.example.com${N}"
  read -rp "  → Domain: " DOMAIN </dev/tty
  DOMAIN="${DOMAIN// /}"

  echo -e "\n${W}[2/5] Port nội bộ (app lắng nghe):${N}"
  echo -e "      ${B}Enter = 3000${N}"
  read -rp "  → Internal port: " INTERNAL_PORT </dev/tty
  INTERNAL_PORT="${INTERNAL_PORT:-3000}"

  if [[ -z "$DOMAIN" ]]; then
    echo -e "\n${W}[2b] Port ngoài (truy cập từ internet):${N}"
    echo -e "      ${B}Enter = 8080${N}"
    read -rp "  → External port: " EXTERNAL_PORT </dev/tty
    EXTERNAL_PORT="${EXTERNAL_PORT:-8080}"
  else
    EXTERNAL_PORT="443"
  fi

  echo -e "\n${W}[3/5] Database:${N}"
  echo -e "      ${B}[1] Local PostgreSQL (cài trên VPS này)${N}"
  echo -e "      ${B}[2] External URL (Supabase, Neon, RDS...)${N}"
  read -rp "  → Chọn [1/2]: " _db_choice </dev/tty
  _db_choice="${_db_choice:-1}"

  if [[ "$_db_choice" == "2" ]]; then
    DB_MODE="external"
    while true; do
      echo -e "\n  Nhập DATABASE_URL:"
      echo -e "  ${B}Ví dụ: postgres://user:pass@host:5432/dbname${N}"
      read -rp "  → URL: " DATABASE_URL </dev/tty
      if [[ -z "$DATABASE_URL" ]]; then
        wrn "DATABASE_URL không được để trống"
        continue
      fi
      if [[ ! "$DATABASE_URL" =~ ^postgres(ql)?:// ]]; then
        wrn "URL phải bắt đầu bằng postgres:// hoặc postgresql://"
        continue
      fi
      ok "DATABASE_URL đã nhập"
      break
    done
    DB_PASSWORD=""
  else
    DB_MODE="local"
    DATABASE_URL=""
    echo -e "\n${W}  Mật khẩu PostgreSQL cho user 'goclaw':${N}"
    echo -e "      ${B}Enter = tạo ngẫu nhiên${N}"
    read -rsp "  → DB Password: " DB_PASSWORD </dev/tty
    echo ""
    if [[ -z "$DB_PASSWORD" ]]; then
      DB_PASSWORD=$(openssl rand -base64 18 | tr -dc 'a-zA-Z0-9' | head -c 20)
      wrn "Mật khẩu tự tạo: ${DB_PASSWORD}"
    fi
    DATABASE_URL="postgres://goclaw:${DB_PASSWORD}@localhost:5432/goclaw?sslmode=disable"
  fi

  echo -e "\n${W}[4/5] Timezone:${N}"
  echo -e "      ${B}Enter = Asia/Ho_Chi_Minh${N}"
  read -rp "  → Timezone: " TZ_SET </dev/tty
  TZ_SET="${TZ_SET:-Asia/Ho_Chi_Minh}"

  # Generate secrets on fresh install
  JWT_SECRET=$(openssl rand -hex 32)
  SESSION_SECRET=$(openssl rand -hex 32)
fi

# ── Derived values ─────────────────────────────────────────────────
if [[ -n "$DOMAIN" ]]; then
  APP_HOST="127.0.0.1"
  APP_PORT="$INTERNAL_PORT"
  BASE_URL="https://$DOMAIN"
else
  APP_HOST="0.0.0.0"
  APP_PORT="$EXTERNAL_PORT"
  BASE_URL="http://$VPS_IP:$EXTERNAL_PORT"
fi

# ── Summary ────────────────────────────────────────────────────────
echo ""
hr
echo -e "  ${W}Xác nhận cấu hình:${N}"
echo -e "  IP             : ${Y}${VPS_IP}${N}"
if [[ -n "$DOMAIN" ]]; then
  echo -e "  Domain         : ${G}${DOMAIN}${N}  ← Caddy + HTTPS tự động"
else
  echo -e "  Domain         : ${Y}(IP only)${N}"
  echo -e "  External port  : ${Y}${EXTERNAL_PORT}${N}"
fi
echo -e "  Internal port  : ${INTERNAL_PORT}"
echo -e "  DB mode        : ${DB_MODE}"
[[ "$DB_MODE" == "local" ]] && echo -e "  DB URL         : postgres://goclaw:***@localhost:5432/goclaw"
[[ "$DB_MODE" == "external" ]] && echo -e "  DB URL         : ${DATABASE_URL%%@*}@***"
echo -e "  Timezone       : ${TZ_SET}"
if [[ "$INSTALL_MODE" == "install" ]]; then
  echo -e "  Secrets        : ${G}tự tạo${N}"
fi
hr
echo ""
read -rp "  Bắt đầu? [Y/n] " _go </dev/tty
[[ "${_go:-Y}" =~ ^[Nn]$ ]] && { echo "Đã huỷ."; exit 0; }

START_TIME=$SECONDS

# ── Helper functions ───────────────────────────────────────────────
wait_for_service() {
  local svc="$1" max="${2:-15}" interval="${3:-2}" attempt=0
  inf "Chờ ${svc} khởi động..."
  while [[ $attempt -lt $max ]]; do
    systemctl is-active --quiet "$svc" && { ok "${svc} đang chạy"; return 0; }
    attempt=$(( attempt + 1 ))
    sleep "$interval"
  done
  die "${svc} không start được sau $((max * interval))s. Kiểm tra: journalctl -u ${svc} -n 30"
}

ensure_ufw_rule() {
  local rule="$1"
  ufw status | grep -qE "^${rule}.*ALLOW" 2>/dev/null || ufw allow "$rule" &>/dev/null
}

write_env_file() {
  cat > "$ENV_FILE" << EOF
# GoClaw configuration — $(date '+%Y-%m-%d %H:%M:%S')
DATABASE_URL=${DATABASE_URL}
PORT=${APP_PORT}
HOST=${APP_HOST}
INTERNAL_PORT=${INTERNAL_PORT}
EXTERNAL_PORT=${EXTERNAL_PORT}
DOMAIN=${DOMAIN}
STATIC_DIR=${STATIC_DIR}
TZ=${TZ_SET}
DB_MODE=${DB_MODE}
# Secrets
JWT_SECRET=${JWT_SECRET:-$(openssl rand -hex 32)}
SESSION_SECRET=${SESSION_SECRET:-$(openssl rand -hex 32)}
# LLM API keys (thêm sau khi cần)
# GOCLAW_OPENAI_API_KEY=
# GOCLAW_ANTHROPIC_API_KEY=
# GOCLAW_GOOGLE_API_KEY=
EOF
  chmod 600 "$ENV_FILE"
}

# ══════════════════════════════════════════════════════════════════
#  Phase 1 — System update & optimize
# ══════════════════════════════════════════════════════════════════
sec "Phase 1 — System update & optimize"

timedatectl set-timezone "$TZ_SET" 2>/dev/null && ok "Timezone → ${TZ_SET}" || wrn "Không set được timezone"

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
  ufw fail2ban build-essential
ok "Essential tools installed"

# ── Swap ───────────────────────────────────────────────────────────
SWAP_NEEDED=2048
if [[ $(swapon --show --noheadings 2>/dev/null | wc -l) -eq 0 ]]; then
  inf "Tạo swap ${SWAP_NEEDED}MB..."
  SWAPFILE=/swapfile
  [[ -f "$SWAPFILE" ]] && swapoff "$SWAPFILE" 2>/dev/null || true
  fallocate -l "${SWAP_NEEDED}M" "$SWAPFILE"
  chmod 600 "$SWAPFILE"
  mkswap -q "$SWAPFILE"
  swapon "$SWAPFILE"
  grep -q "$SWAPFILE" /etc/fstab || echo "$SWAPFILE none swap sw 0 0" >> /etc/fstab
  ok "Swap ${SWAP_NEEDED}MB active"
else
  ok "Swap đã có: $(free -h | awk '/Swap/ {print $2}')"
fi

# ── sysctl ─────────────────────────────────────────────────────────
inf "Applying sysctl optimizations..."
cat > "$SYSCTL_CONF" << 'EOF'
net.core.somaxconn            = 65535
net.ipv4.tcp_max_syn_backlog  = 65535
net.ipv4.tcp_fin_timeout      = 15
net.ipv4.tcp_keepalive_time   = 300
net.ipv4.tcp_keepalive_intvl  = 30
net.ipv4.tcp_keepalive_probes = 5
net.ipv4.tcp_tw_reuse         = 1
net.core.netdev_max_backlog   = 65535
fs.file-max                   = 1000000
vm.swappiness                 = 10
vm.dirty_ratio                = 15
vm.dirty_background_ratio     = 5
EOF
sysctl -p "$SYSCTL_CONF" &>/dev/null
ok "sysctl applied"

# ── ulimits ────────────────────────────────────────────────────────
grep -q "^# goclaw" /etc/security/limits.conf 2>/dev/null || cat >> /etc/security/limits.conf << 'EOF'
# goclaw
*    soft nofile 65535
*    hard nofile 65535
root soft nofile 65535
root hard nofile 65535
EOF
ok "ulimits set (nofile=65535)"

# ── UFW ────────────────────────────────────────────────────────────
inf "Configuring UFW..."
ufw status | grep -q "Status: inactive" && {
  ufw default deny incoming  &>/dev/null
  ufw default allow outgoing &>/dev/null
}
ensure_ufw_rule ssh
ensure_ufw_rule "80/tcp"
ensure_ufw_rule "443/tcp"
[[ -z "$DOMAIN" ]] && ensure_ufw_rule "${EXTERNAL_PORT}/tcp" || true
[[ "$DB_MODE" == "local" ]] && { ufw deny 5432/tcp &>/dev/null || true; }
ufw status | grep -q "Status: active" || ufw --force enable &>/dev/null
ok "UFW configured (ssh, 80, 443$([ -z "$DOMAIN" ] && echo ", ${EXTERNAL_PORT}" || echo "")$([ "$DB_MODE" == "local" ] && echo ", 5432 blocked" || echo ""))"

# ── fail2ban ───────────────────────────────────────────────────────
systemctl enable fail2ban &>/dev/null
systemctl restart fail2ban
ok "fail2ban active"

# ── SSH hardening ──────────────────────────────────────────────────
SSHD=/etc/ssh/sshd_config
grep -q "^ClientAliveInterval" "$SSHD" || echo "ClientAliveInterval 120" >> "$SSHD"
grep -q "^ClientAliveCountMax" "$SSHD"  || echo "ClientAliveCountMax 3"   >> "$SSHD"
systemctl reload sshd 2>/dev/null || systemctl reload ssh 2>/dev/null || true
ok "SSH keepalive configured"

# ══════════════════════════════════════════════════════════════════
#  Phase 2 — Database
# ══════════════════════════════════════════════════════════════════
sec "Phase 2 — Database (${DB_MODE})"

if [[ "$DB_MODE" == "local" ]]; then
  inf "Checking PostgreSQL ${PG_VERSION}..."

  if ! command -v psql &>/dev/null || ! psql --version 2>/dev/null | grep -q "PostgreSQL ${PG_VERSION}"; then
    inf "Cài PostgreSQL ${PG_VERSION} + pgvector..."
    apt-get install -y -qq curl gnupg lsb-release

    # PGDG repo
    install -d /usr/share/postgresql-common/pgdg
    curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc \
      | gpg --yes --dearmor -o /usr/share/postgresql-common/pgdg/apt.postgresql.org.gpg 2>/dev/null

    sh -c "echo 'deb [signed-by=/usr/share/postgresql-common/pgdg/apt.postgresql.org.gpg] \
      https://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main' \
      > /etc/apt/sources.list.d/pgdg.list"

    apt-get update -qq
    apt-get install -y -qq "postgresql-${PG_VERSION}" "postgresql-${PG_VERSION}-pgvector"
    systemctl enable "postgresql@${PG_VERSION}-main" 2>/dev/null || systemctl enable postgresql 2>/dev/null
    systemctl start "postgresql@${PG_VERSION}-main" 2>/dev/null || systemctl start postgresql 2>/dev/null
    ok "PostgreSQL ${PG_VERSION} + pgvector installed"
  else
    ok "PostgreSQL $(psql --version | awk '{print $3}') already installed"
  fi

  inf "Cấu hình database..."
  PG_SERVICE="postgresql@${PG_VERSION}-main"
  systemctl is-active --quiet "$PG_SERVICE" 2>/dev/null || PG_SERVICE="postgresql"
  systemctl is-active --quiet "$PG_SERVICE" 2>/dev/null || { systemctl start "$PG_SERVICE"; sleep 2; }

  # Create user + db (idempotent)
  su -c "psql -tAc \"SELECT 1 FROM pg_roles WHERE rolname='goclaw'\"" postgres 2>/dev/null | grep -q 1 \
    || su -c "psql -c \"CREATE USER goclaw WITH PASSWORD '${DB_PASSWORD}'\"" postgres

  su -c "psql -tAc \"SELECT 1 FROM pg_database WHERE datname='goclaw'\"" postgres 2>/dev/null | grep -q 1 \
    || su -c "psql -c 'CREATE DATABASE goclaw OWNER goclaw';" postgres

  su -c "psql -c 'GRANT ALL PRIVILEGES ON DATABASE goclaw TO goclaw;'" postgres &>/dev/null

  # Enable pgvector extension
  su -c "psql -d goclaw -c 'CREATE EXTENSION IF NOT EXISTS vector;'" postgres &>/dev/null \
    && ok "pgvector extension enabled" || wrn "pgvector extension không cài được (thử thủ công sau)"

  ok "Database 'goclaw' sẵn sàng"

else
  # Validate external DB connection
  inf "Kiểm tra kết nối database ngoài..."
  apt-get install -y -qq "postgresql-client" 2>/dev/null || true
  if command -v psql &>/dev/null; then
    if PGPASSWORD="" psql "$DATABASE_URL" -c "SELECT 1" &>/dev/null; then
      ok "Kết nối database thành công"
    else
      wrn "Không thể kết nối DB — tiếp tục nhưng cần kiểm tra DATABASE_URL"
    fi
  else
    wrn "psql không có — bỏ qua kiểm tra kết nối"
  fi
fi

# ══════════════════════════════════════════════════════════════════
#  Phase 3 — Go
# ══════════════════════════════════════════════════════════════════
sec "Phase 3 — Go"

GO_BIN="/usr/local/go/bin/go"
GO_OK=false
if [[ -x "$GO_BIN" ]]; then
  INSTALLED_GO=$($GO_BIN version 2>/dev/null | awk '{print $3}' | sed 's/go//')
  # Compare major.minor
  IFS='.' read -r _maj _min _ <<< "$INSTALLED_GO"
  IFS='.' read -r _req_maj _req_min _ <<< "$MIN_GO_VERSION"
  if [[ $_maj -gt $_req_maj ]] || [[ $_maj -eq $_req_maj && $_min -ge $_req_min ]]; then
    GO_OK=true
    ok "Go ${INSTALLED_GO} already installed"
  fi
fi

if [[ "$GO_OK" == "false" ]]; then
  inf "Cài Go >= ${MIN_GO_VERSION}..."
  LATEST_GO=$(timeout 15 curl -fsSL "https://go.dev/dl/?mode=json" 2>/dev/null \
    | grep -oP '"version":\s*"\Kgo[0-9.]+' | head -1 || echo "")
  [[ -z "$LATEST_GO" ]] && LATEST_GO="1.24.3" && wrn "Dùng fallback Go ${LATEST_GO}"

  GO_URL="https://go.dev/dl/${LATEST_GO}.linux-${GO_ARCH}.tar.gz"
  inf "Downloading Go ${LATEST_GO}..."
  timeout 120 curl -fsSL --fail "$GO_URL" -o /tmp/go.tar.gz \
    || die "Không tải được Go từ ${GO_URL}"

  rm -rf /usr/local/go
  tar -C /usr/local -xzf /tmp/go.tar.gz
  rm -f /tmp/go.tar.gz

  # Add to PATH for all users (idempotent — use profile.d, không overwrite /etc/environment)
  if ! grep -q '/usr/local/go/bin' /etc/profile.d/go.sh 2>/dev/null; then
    echo 'export PATH="/usr/local/go/bin:$PATH"' > /etc/profile.d/go.sh
    chmod 644 /etc/profile.d/go.sh
  fi
  grep -q '/usr/local/go/bin' /root/.bashrc 2>/dev/null \
    || echo 'export PATH="/usr/local/go/bin:$PATH"' >> /root/.bashrc
  export PATH="/usr/local/go/bin:$PATH"

  $GO_BIN version &>/dev/null || die "Go installation verification failed"
  ok "Go ${LATEST_GO} installed"
fi

export PATH="/usr/local/go/bin:$PATH"

# ══════════════════════════════════════════════════════════════════
#  Phase 4 — GoClaw binary
# ══════════════════════════════════════════════════════════════════
sec "Phase 4 — GoClaw binary"

[[ "$INSTALL_MODE" == "update" ]] && systemctl stop "$SERVICE_NAME" 2>/dev/null || true

GOPATH_TMP=$(mktemp -d)
inf "go install ${GOCLAW_PKG}..."
GOPATH="$GOPATH_TMP" GOBIN="/usr/local/bin" go install "$GOCLAW_PKG" \
  || die "go install thất bại. Kiểm tra kết nối internet và Go version."

rm -rf "$GOPATH_TMP"

if ! command -v goclaw &>/dev/null && [[ ! -x "/usr/local/bin/goclaw" ]]; then
  die "Binary 'goclaw' không tìm thấy sau khi install"
fi

ok "GoClaw binary → /usr/local/bin/goclaw"

# ══════════════════════════════════════════════════════════════════
#  Phase 5 — Directories & service user
# ══════════════════════════════════════════════════════════════════
sec "Phase 5 — Directories & user"

# Service user
if ! id "$SERVICE_USER" &>/dev/null; then
  useradd -r -s /bin/false -d "$WORK_DIR" -M "$SERVICE_USER"
  ok "User '${SERVICE_USER}' created"
else
  ok "User '${SERVICE_USER}' already exists"
fi

mkdir -p "$WORK_DIR" "$STATIC_DIR"
chown -R "${SERVICE_USER}:${SERVICE_USER}" "$WORK_DIR"
ok "Directories: ${WORK_DIR}, ${STATIC_DIR}"

# ══════════════════════════════════════════════════════════════════
#  Phase 6 — Config & env
# ══════════════════════════════════════════════════════════════════
sec "Phase 6 — Config & env"

write_env_file
ok "Env → ${ENV_FILE} (chmod 600)"

# ══════════════════════════════════════════════════════════════════
#  Phase 7 — Systemd service
# ══════════════════════════════════════════════════════════════════
sec "Phase 7 — Systemd service"

# Determine if DB is local to add dependency
AFTER_DB=""
[[ "$DB_MODE" == "local" ]] && AFTER_DB=" postgresql.service"

cat > "$SERVICE_FILE" << EOF
[Unit]
Description=GoClaw AI Agent Gateway
Documentation=https://goclaw.sh
After=network-online.target${AFTER_DB}
Wants=network-online.target

[Service]
Type=simple
User=${SERVICE_USER}
Group=${SERVICE_USER}
WorkingDirectory=${WORK_DIR}
EnvironmentFile=${ENV_FILE}
ExecStart=/usr/local/bin/goclaw
Restart=on-failure
RestartSec=5
StandardOutput=journal
StandardError=journal
SyslogIdentifier=${SERVICE_NAME}

# Resource limits
LimitNOFILE=65535
LimitNPROC=4096

# Security hardening
NoNewPrivileges=true
PrivateTmp=yes
ProtectSystem=full
ReadWritePaths=${WORK_DIR}

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable "$SERVICE_NAME" &>/dev/null
systemctl restart "$SERVICE_NAME"
ok "Service ${SERVICE_NAME} started"
wait_for_service "$SERVICE_NAME" 15 2

# ── Journal log rotation ────────────────────────────────────────────
mkdir -p /etc/systemd/journald.conf.d
cat > /etc/systemd/journald.conf.d/goclaw.conf << 'EOF'
[Journal]
SystemMaxUse=200M
SystemKeepFree=500M
MaxFileSec=1month
EOF
systemctl restart systemd-journald 2>/dev/null || true
ok "Journal log rotation configured (max 200MB)"

# ══════════════════════════════════════════════════════════════════
#  Phase 8 — Caddy (only if domain provided)
# ══════════════════════════════════════════════════════════════════
if [[ -n "$DOMAIN" ]]; then
  sec "Phase 8 — Caddy + HTTPS"

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
    ok "Caddy $(caddy version 2>/dev/null | head -1) already installed"
  fi

  mkdir -p /etc/caddy

  CADDY_NEEDS_UPDATE=false
  [[ ! -f "$CADDYFILE" ]] && CADDY_NEEDS_UPDATE=true
  [[ -f "$CADDYFILE" ]] && ! grep -qE "^${DOMAIN} \{" "$CADDYFILE" 2>/dev/null && CADDY_NEEDS_UPDATE=true

  if [[ "$CADDY_NEEDS_UPDATE" == "true" ]]; then
    cat > "$CADDYFILE" << EOF
${DOMAIN} {
    encode gzip

    reverse_proxy 127.0.0.1:${INTERNAL_PORT} {
        header_up Host {host}
        header_up X-Real-IP {remote_host}
        header_up X-Forwarded-For {remote_host}
        header_up X-Forwarded-Proto {scheme}
    }

    log {
        output file /var/log/caddy/goclaw.log {
            roll_size 50mb
            roll_keep 5
        }
    }
}
EOF
    mkdir -p /var/log/caddy
    ok "Caddyfile → ${CADDYFILE}"
  else
    ok "Caddyfile unchanged (domain: ${DOMAIN})"
  fi

  systemctl enable caddy &>/dev/null
  systemctl restart caddy
  wait_for_service caddy 10 2
fi

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

echo -e "  ${W}GoClaw${N}"
echo -e "  URL            : ${C}${W}${BASE_URL}${N}"
[[ -n "$DOMAIN" ]] && echo -e "  HTTPS          : ${G}Tự động qua Caddy + Let's Encrypt${N}"
echo -e ""
echo -e "  ${W}Ports${N}"
echo -e "  Internal       : ${INTERNAL_PORT}  (app lắng nghe)"
[[ -z "$DOMAIN" ]] && echo -e "  External       : ${EXTERNAL_PORT}  (public access)"
echo -e ""
echo -e "  ${W}Database${N}"
echo -e "  Mode           : ${DB_MODE}"
[[ "$DB_MODE" == "local" ]] && echo -e "  URL            : postgres://goclaw:***@localhost:5432/goclaw"
echo -e ""
echo -e "  ${W}Files${N}"
echo -e "  Config         : ${ENV_FILE}"
echo -e "  Static/Web UI  : ${STATIC_DIR}"
echo -e "  Work dir       : ${WORK_DIR}"
echo -e ""
echo -e "  ${W}Commands${N}"
echo -e "  Logs           : ${B}journalctl -u ${SERVICE_NAME} -f${N}"
echo -e "  Restart        : ${B}systemctl restart ${SERVICE_NAME}${N}"
echo -e "  Status         : ${B}systemctl status ${SERVICE_NAME}${N}"
echo -e "  Edit config    : ${B}nano ${ENV_FILE} && systemctl restart ${SERVICE_NAME}${N}"
[[ -n "$DOMAIN" ]] && echo -e "  Caddy logs     : ${B}journalctl -u caddy -f${N}"
hr
echo ""

echo -e "${Y}${W}  ⚠  Bước tiếp theo:${N}"
echo -e "  1. Copy Web UI vào ${STATIC_DIR}/ (nếu dùng frontend riêng)"
echo -e "     ${B}rsync -avz ./dist/ root@${VPS_IP}:${STATIC_DIR}/${N}"
echo -e "  2. Thêm LLM API keys vào ${ENV_FILE}"
echo -e "     ${B}nano ${ENV_FILE}${N}"
echo -e "  3. Restart service sau khi cập nhật config:"
echo -e "     ${B}systemctl restart ${SERVICE_NAME}${N}"
[[ -n "$DOMAIN" ]] && echo -e "  4. Đảm bảo DNS của ${DOMAIN} trỏ về ${VPS_IP}"
echo ""

echo -e "${W}  Service status:${N}"
systemctl --no-pager --full status "$SERVICE_NAME" | head -20
