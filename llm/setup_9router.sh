#!/usr/bin/env bash
# ══════════════════════════════════════════════════════════════════
#  9Router — Interactive low-spec VPS toolkit
#  Ubuntu 22.04 / 24.04 · Debian 11/12 best-effort
#  Tiered tuning · zram · doctor · auto-rollback · uninstall
#
#  Usage:
#    sudo bash setup_9router.sh                # interactive menu
#    sudo bash setup_9router.sh install        # fresh install
#    sudo bash setup_9router.sh update         # pull latest + redeploy
#    sudo bash setup_9router.sh doctor         # health check + prompted fixes
#    sudo bash setup_9router.sh doctor --json  # JSON for cron/monitoring
#    sudo bash setup_9router.sh tune           # re-apply tier tuning
#    sudo bash setup_9router.sh status         # one-screen summary
#    sudo bash setup_9router.sh logs           # follow service logs
#    sudo bash setup_9router.sh rollback       # restore previous build
#    sudo bash setup_9router.sh uninstall      # remove service (data preserved)
#
#  Spec floor: 1 GB RAM / 1 vCPU / 20 GB disk
#  Tiers:      tiny <1G  ·  small 1–2G  ·  medium+ ≥2G
# ══════════════════════════════════════════════════════════════════
set -euo pipefail

# ── Colors / output helpers ─────────────────────────────────────────
R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'
B='\033[0;34m'; C='\033[0;36m'; W='\033[1m'; N='\033[0m'
ok()  { echo -e "${G}[✔]${N} $*"; }
inf() { echo -e "${B}[→]${N} $*"; }
wrn() { echo -e "${Y}[!]${N} $*"; }
die() { echo -e "${R}[✘]${N} $*" >&2; exit 1; }
sec() { echo -e "\n${C}${W}━━━  $*  ━━━${N}"; }
hr()  { echo -e "${C}──────────────────────────────────────────${N}"; }

# ── Path constants ──────────────────────────────────────────────────
REPO_URL="https://github.com/decolua/9router.git"
BUILD_DIR="/opt/9router-build"
RUNTIME_DIR="/opt/9router"
PREVIOUS_DIR="/opt/9router-previous"
DATA_DIR="/var/lib/9router"
SERVICE_USER="router9"
SERVICE_GROUP="router9"
ENV_FILE="/etc/9router.env"
ENV_BACKUP_GLOB="/etc/9router.env.bak.*"
SERVICE_FILE="/etc/systemd/system/9router.service"
SERVICE_DROPIN_DIR="/etc/systemd/system/9router.service.d"
CADDYFILE="/etc/caddy/Caddyfile"
SYSCTL_CONF="/etc/sysctl.d/99-9router.conf"
JOURNALD_DROPIN="/etc/systemd/journald.conf.d/99-9router.conf"
ZRAM_CONF="/etc/systemd/zram-generator.conf.d/99-9router.conf"
TIER_CACHE="/var/lib/9router/.tier"
INSTALL_URL="https://raw.githubusercontent.com/comchienlab/dotfiles/main/llm/setup_9router.sh"
INSTALLED_BIN="/usr/local/bin/9router"
SCRIPT_PATH="$0"
SCRIPT_NAME="$(basename "$0")"

# Detect curl|bash invocation. When piped, $0 is "bash" and any printed
# "sudo bash $0 <cmd>" is unrunnable because bash treats <cmd> as a script
# path and resolves it via PATH (e.g. /usr/bin/install).
PIPED=false
if [[ "$SCRIPT_NAME" == "bash" ]] || [[ "$SCRIPT_NAME" == "sh" ]] || [[ "$0" =~ ^/dev/fd/ ]]; then
  PIPED=true
fi
if [[ -n "${NINE_ROUTER_RELAUNCHED_FROM:-}" ]]; then
  PIPED=false
  trap 'rm -f "$NINE_ROUTER_RELAUNCHED_FROM"' EXIT
fi

# Recompute after self-install so printed help reflects the installed binary.
compute_invoke_base() {
  if [[ -x "$INSTALLED_BIN" ]]; then
    INVOKE_BASE="sudo 9router"
  elif $PIPED; then
    INVOKE_BASE="curl -fsSL $INSTALL_URL | sudo bash -s --"
  else
    INVOKE_BASE="sudo bash $SCRIPT_PATH"
  fi
}
compute_invoke_base

# ── Globals populated by detect_spec / classify_tier ────────────────
TOTAL_RAM=0; CPU_CORES=0; TOTAL_DISK=0
OS_INFO=""; KERNEL=""; VPS_IP=""; SWAP_MB=0
TIER=""

# ══════════════════════════════════════════════════════════════════
#  Banner
# ══════════════════════════════════════════════════════════════════
show_banner() {
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
  echo -e "  ${W}AI Proxy Router — VPS Toolkit${N}"
  hr
}

# ══════════════════════════════════════════════════════════════════
#  Spec detection & tier classification
# ══════════════════════════════════════════════════════════════════
detect_spec() {
  TOTAL_RAM=$(awk '/MemTotal/ {printf "%.0f", $2/1024}' /proc/meminfo 2>/dev/null || echo 0)
  CPU_CORES=$(nproc 2>/dev/null || echo 1)
  TOTAL_DISK=$(df -BG / 2>/dev/null | awk 'NR==2 {print $4}' | tr -d 'G' || echo 0)
  OS_INFO=$(. /etc/os-release 2>/dev/null && echo "$PRETTY_NAME" || echo "Unknown")
  KERNEL=$(uname -r 2>/dev/null || echo "?")
  VPS_IP=$(curl -fsSL --max-time 5 ifconfig.me 2>/dev/null \
        || hostname -I 2>/dev/null | awk '{print $1}' \
        || echo "unknown")
  SWAP_MB=$(awk '/SwapTotal/ {printf "%.0f", $2/1024}' /proc/meminfo 2>/dev/null || echo 0)
}

classify_tier() {
  if   [[ $TOTAL_RAM -lt 1024 ]]; then TIER="tiny"
  elif [[ $TOTAL_RAM -lt 2048 ]]; then TIER="small"
  else TIER="medium"
  fi
}

show_spec() {
  echo -e "  IP        : ${Y}${W}$VPS_IP${N}"
  echo -e "  OS        : $OS_INFO  (kernel $KERNEL)"
  echo -e "  CPU       : ${CPU_CORES} cores"
  echo -e "  RAM       : ${TOTAL_RAM} MB"
  echo -e "  Swap      : ${SWAP_MB} MB"
  echo -e "  Disk free : ${TOTAL_DISK} GB"
  case "$TIER" in
    tiny)   echo -e "  Tier      : ${R}${W}tiny${N} (<1GB) — aggressive low-spec mode" ;;
    small)  echo -e "  Tier      : ${Y}${W}small${N} (1–2GB) — default low-spec target" ;;
    medium) echo -e "  Tier      : ${G}${W}medium+${N} (≥2GB) — comfortable" ;;
  esac
  hr
}

# ══════════════════════════════════════════════════════════════════
#  Tier-config tables (R5)
# ══════════════════════════════════════════════════════════════════
tier_sysctl_block() {
  case "$TIER" in
    tiny)
      cat << 'EOF'
# ── tiny tier (<1GB) ─────────────────────────────────────────────
net.core.somaxconn            = 1024
net.ipv4.tcp_max_syn_backlog  = 2048
net.core.netdev_max_backlog   = 2048
net.core.rmem_max             = 4194304
net.core.wmem_max             = 4194304
net.ipv4.tcp_rmem             = 4096 87380 4194304
net.ipv4.tcp_wmem             = 4096 65536 4194304
EOF
      ;;
    small)
      cat << 'EOF'
# ── small tier (1–2GB) ───────────────────────────────────────────
net.core.somaxconn            = 4096
net.ipv4.tcp_max_syn_backlog  = 8192
net.core.netdev_max_backlog   = 8192
net.core.rmem_max             = 8388608
net.core.wmem_max             = 8388608
net.ipv4.tcp_rmem             = 4096 87380 8388608
net.ipv4.tcp_wmem             = 4096 65536 8388608
EOF
      ;;
    medium)
      cat << 'EOF'
# ── medium+ tier (≥2GB) ──────────────────────────────────────────
net.core.somaxconn            = 65535
net.ipv4.tcp_max_syn_backlog  = 65535
net.core.netdev_max_backlog   = 65535
net.core.rmem_max             = 16777216
net.core.wmem_max             = 16777216
net.ipv4.tcp_rmem             = 4096 87380 16777216
net.ipv4.tcp_wmem             = 4096 65536 16777216
EOF
      ;;
  esac
  cat << 'EOF'
# ── common (TCP/keepalive/BBR/files/VM) ──────────────────────────
net.ipv4.tcp_fin_timeout      = 15
net.ipv4.tcp_keepalive_time   = 300
net.ipv4.tcp_keepalive_intvl  = 30
net.ipv4.tcp_keepalive_probes = 5
net.ipv4.tcp_tw_reuse         = 1
net.core.default_qdisc        = fq
net.ipv4.tcp_congestion_control = bbr
fs.file-max                   = 1000000
fs.inotify.max_user_watches   = 524288
fs.inotify.max_user_instances = 512
vm.swappiness                 = 10
vm.dirty_ratio                = 15
vm.dirty_background_ratio     = 5
vm.overcommit_memory          = 1
EOF
}

tier_memory_high() {
  case "$TIER" in
    tiny)   echo "400M" ;;
    small)  echo "700M" ;;
    medium) echo "" ;;   # unlimited
  esac
}
tier_memory_max() {
  case "$TIER" in
    tiny)   echo "512M" ;;
    small)  echo "900M" ;;
    medium) echo "" ;;   # unlimited
  esac
}
tier_zram_mb() {
  case "$TIER" in
    tiny|small) echo $(( TOTAL_RAM / 2 )) ;;
    medium)     echo 0 ;;
  esac
}
tier_swap_mb() {
  case "$TIER" in
    tiny)   echo $(( TOTAL_RAM * 2 )) ;;
    small)  echo 2048 ;;
    medium) echo 0 ;;
  esac
}
tier_node_mem() {
  local m=$(( TOTAL_RAM / 2 ))
  [[ $m -lt 512  ]] && m=512
  [[ $m -gt 1536 ]] && m=1536
  echo "$m"
}

# ══════════════════════════════════════════════════════════════════
#  Common helpers
# ══════════════════════════════════════════════════════════════════
require_root() { [[ $EUID -eq 0 ]] || die "Chạy với quyền root: $INVOKE_BASE"; }

require_linux() {
  [[ "$(uname -s)" == "Linux" ]] || die "This script must run on Linux (Ubuntu/Debian)."
}

ensure_gum() {
  command -v gum &>/dev/null && return 0
  inf "Cài gum (interactive UI)..."
  if [[ -f /etc/debian_version ]]; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq
    apt-get install -y -qq curl ca-certificates gnupg
    mkdir -p /etc/apt/keyrings
    curl -fsSL https://repo.charm.sh/apt/gpg.key \
      | gpg --dearmor -o /etc/apt/keyrings/charm.gpg 2>/dev/null
    echo "deb [signed-by=/etc/apt/keyrings/charm.gpg] https://repo.charm.sh/apt/ * *" \
      > /etc/apt/sources.list.d/charm.list
    apt-get update -qq
    apt-get install -y -qq gum
  else
    die "gum auto-install only supports Debian/Ubuntu. Install manually."
  fi
  command -v gum &>/dev/null || die "gum install failed."
  ok "gum installed"
}

ensure_essentials() {
  inf "Cài essential tools..."
  apt-get install -y -qq \
    curl wget git ca-certificates openssl gnupg \
    htop vim net-tools unzip lsof rsync \
    ufw fail2ban \
    build-essential jq
  ok "Essential tools ready"
}

ensure_service_user() {
  if ! getent group "$SERVICE_GROUP" &>/dev/null; then
    groupadd --system "$SERVICE_GROUP"
  fi
  if ! id -u "$SERVICE_USER" &>/dev/null; then
    useradd --system --gid "$SERVICE_GROUP" --home-dir "$DATA_DIR" \
      --shell /usr/sbin/nologin "$SERVICE_USER"
  fi
}

wait_for_service() {
  local svc="$1" max="${2:-15}" interval="${3:-2}" attempt=0
  inf "Chờ $svc khởi động..."
  while [[ $attempt -lt $max ]]; do
    systemctl is-active --quiet "$svc" && { ok "$svc running"; return 0; }
    attempt=$(( attempt + 1 ))
    sleep "$interval"
  done
  return 1
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
  ufw status 2>/dev/null | grep -qE "^${rule}.*ALLOW" || ufw allow "$rule" &>/dev/null
}

backup_env_file() {
  [[ -f "$ENV_FILE" ]] || return 0
  local ts; ts="$(date +%s)"
  cp -a "$ENV_FILE" "$ENV_FILE.bak.$ts"
  chmod 600 "$ENV_FILE.bak.$ts"
  # keep last 5
  # shellcheck disable=SC2012,SC2086
  ls -1t $ENV_BACKUP_GLOB 2>/dev/null | tail -n +6 | xargs -r rm -f
}

env_value_ok() {
  [[ "$1" =~ ^[A-Za-z0-9_@%+=:,./!-]*$ ]]
}

env_file_get() {
  local key="$1" line val
  [[ -f "$ENV_FILE" ]] || return 1
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ "$line" == "$key="* ]] || continue
    val="${line#*=}"
    if [[ "$val" == \"*\" && "$val" == *\" ]]; then
      val="${val:1:${#val}-2}"
    elif [[ "$val" == \'*\' && "$val" == *\' ]]; then
      val="${val:1:${#val}-2}"
    fi
    printf '%s' "$val"
    return 0
  done < "$ENV_FILE"
  return 1
}

write_env_file() {
  local name value
  for name in JWT_SECRET INITIAL_PASSWORD DATA_DIR APP_PORT BASE_URL API_KEY_SECRET MACHINE_ID_SALT; do
    value="${!name}"
    env_value_ok "$value" || die "Invalid character in $name. Use letters, numbers, and common URL/password symbols only."
  done
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

source_existing_env() {
  JWT_SECRET=$(env_file_get JWT_SECRET || openssl rand -hex 32)
  INITIAL_PASSWORD=$(env_file_get INITIAL_PASSWORD || printf '%s' "ChangeMe123!")
  API_KEY_SECRET=$(env_file_get API_KEY_SECRET || openssl rand -hex 32)
  MACHINE_ID_SALT=$(env_file_get MACHINE_ID_SALT || openssl rand -hex 16)
  APP_PORT=$(env_file_get PORT || printf '%s' "20128")
  valid_port "$APP_PORT" || die "Invalid PORT in $ENV_FILE: $APP_PORT"
  TZ_SET=$(timedatectl show -p Timezone --value 2>/dev/null || echo "Asia/Ho_Chi_Minh")
  BASE_URL=$(env_file_get NEXT_PUBLIC_BASE_URL || printf '%s' "")
  if [[ "$BASE_URL" == https://* ]]; then
    DOMAIN="${BASE_URL#https://}"
    valid_domain "$DOMAIN" || die "Invalid NEXT_PUBLIC_BASE_URL domain in $ENV_FILE: $BASE_URL"
  else
    DOMAIN=""
  fi
}

is_installed() {
  [[ -f "$ENV_FILE" ]] && [[ -s "$ENV_FILE" ]] \
    && [[ -f "$RUNTIME_DIR/server.js" ]] \
    && systemctl list-unit-files 9router.service &>/dev/null
}

# Prompt helpers (gum if available, fallback to read)
ask_str() {
  local label="$1" default="${2:-}" out
  if command -v gum &>/dev/null; then
    out=$(gum input --prompt "  → $label: " --placeholder "$default" --value "$default" </dev/tty)
  else
    read -rp "  → $label [$default]: " out </dev/tty
    out="${out:-$default}"
  fi
  printf '%s' "$out"
}

ask_secret() {
  local label="$1" default="${2:-}" out
  read -rsp "  → $label [$default]: " out </dev/tty
  echo >/dev/tty
  out="${out:-$default}"
  printf '%s' "$out"
}

ask_confirm() {
  local label="$1"
  if command -v gum &>/dev/null; then
    gum confirm "$label" </dev/tty
  else
    read -rp "$label [y/N] " r </dev/tty
    [[ "$r" =~ ^[Yy]$ ]]
  fi
}

valid_domain() {
  local domain="$1"
  [[ -z "$domain" ]] && return 0
  [[ ${#domain} -le 253 ]] || return 1
  [[ "$domain" =~ ^[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?(\.[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?)+$ ]]
}

valid_port() {
  local port="$1"
  [[ "$port" =~ ^[0-9]+$ ]] || return 1
  [[ "$port" -ge 1024 && "$port" -le 65535 && "$port" -ne 80 && "$port" -ne 443 ]]
}

valid_timezone() {
  local timezone="$1"
  [[ -n "$timezone" ]] || return 1
  timedatectl list-timezones 2>/dev/null | grep -Fxq "$timezone"
}

prompt_validated() {
  local label="$1" default="$2" validator="$3" value
  while true; do
    value=$(ask_str "$label" "$default")
    value="${value// /}"
    if "$validator" "$value"; then
      printf '%s' "$value"
      return 0
    fi
    wrn "$label không hợp lệ. Vui lòng nhập lại."
  done
}

# ══════════════════════════════════════════════════════════════════
#  Phase: System optimize (sysctl, ulimits, journald, BBR)
# ══════════════════════════════════════════════════════════════════
phase_optimize_system() {
  sec "System optimize (tier=$TIER)"

  # Avoid interactive prompts from apt
  export DEBIAN_FRONTEND=noninteractive
  export NEEDRESTART_MODE=a

  inf "apt update + upgrade..."
  apt-get update -qq
  apt-get upgrade -y -qq \
    -o Dpkg::Options::="--force-confdef" \
    -o Dpkg::Options::="--force-confold"
  ok "System packages updated"

  ensure_essentials

  # Sysctl per tier + common
  inf "Applying sysctl (tier=$TIER, BBR enabled)..."
  {
    echo "# Auto-generated by 9router (tier=$TIER, $(date -Iseconds))"
    tier_sysctl_block
  } > "$SYSCTL_CONF"
  sysctl -p "$SYSCTL_CONF" &>/dev/null || wrn "Some sysctl keys not applied (kernel may lack BBR module)"
  ok "sysctl applied"

  # ulimits
  inf "Setting open file limits..."
  if ! grep -q "^\*.*soft.*nofile.*65535" /etc/security/limits.conf 2>/dev/null; then
    cat >> /etc/security/limits.conf << 'EOF'
# 9router
*         soft  nofile  65535
*         hard  nofile  65535
root      soft  nofile  65535
root      hard  nofile  65535
EOF
  fi
  ok "ulimits set (nofile=65535)"

  # journald cap
  inf "Capping journald (200M / 50M file / 2 week retention)..."
  mkdir -p /etc/systemd/journald.conf.d
  cat > "$JOURNALD_DROPIN" << 'EOF'
# Auto-generated by 9router
[Journal]
SystemMaxUse=200M
SystemMaxFileSize=50M
MaxRetentionSec=2week
EOF
  systemctl restart systemd-journald 2>/dev/null || true
  ok "journald capped"

  # unattended-upgrades
  inf "Enabling unattended-upgrades..."
  apt-get install -y -qq unattended-upgrades 2>/dev/null || true
  if [[ -f /etc/apt/apt.conf.d/20auto-upgrades ]] \
     && grep -q "Unattended-Upgrade" /etc/apt/apt.conf.d/20auto-upgrades; then
    ok "unattended-upgrades already configured"
  else
    cat > /etc/apt/apt.conf.d/20auto-upgrades << 'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
EOF
    ok "unattended-upgrades enabled"
  fi
}

# ══════════════════════════════════════════════════════════════════
#  Phase: zram (tiny/small only)
# ══════════════════════════════════════════════════════════════════
phase_zram() {
  local size_mb; size_mb=$(tier_zram_mb)
  if [[ $size_mb -eq 0 ]]; then
    inf "zram skipped (tier=$TIER)"
    return 0
  fi

  sec "zram (compressed RAM swap, ${size_mb}MB)"

  # Use systemd-zram-generator (preferred, preinstalled on Ubuntu 22.04+)
  if [[ ! -d /etc/systemd/zram-generator.conf.d ]]; then
    apt-get install -y -qq systemd-zram-generator 2>/dev/null \
      || { wrn "systemd-zram-generator not available; skipping zram"; return 0; }
  fi
  mkdir -p /etc/systemd/zram-generator.conf.d
  cat > "$ZRAM_CONF" << EOF
# Auto-generated by 9router (tier=$TIER)
[zram0]
zram-size = ${size_mb}
compression-algorithm = lz4
swap-priority = 100
EOF
  systemctl daemon-reload
  systemctl restart systemd-zram-setup@zram0.service 2>/dev/null || true
  if swapon --show 2>/dev/null | grep -q '^/dev/zram'; then
    ok "zram active: $(swapon --show=NAME,SIZE,PRIO 2>/dev/null | grep zram | awk '{print $1, $2, "prio="$3}')"
  else
    wrn "zram not yet active — will activate on next boot"
  fi
}

# ══════════════════════════════════════════════════════════════════
#  Phase: disk swap (only if no swap at all)
# ══════════════════════════════════════════════════════════════════
phase_swap() {
  local needed; needed=$(tier_swap_mb)
  [[ $needed -eq 0 ]] && return 0

  if [[ $(swapon --show --noheadings 2>/dev/null | wc -l) -gt 0 ]]; then
    ok "Swap already configured: $(free -h | awk '/Swap/ {print $2}')"
    return 0
  fi

  inf "Tạo swap ${needed}MB..."
  local swapfile=/swapfile
  [[ -f "$swapfile" ]] && swapoff "$swapfile" 2>/dev/null || true
  fallocate -l "${needed}M" "$swapfile" 2>/dev/null \
    || dd if=/dev/zero of="$swapfile" bs=1M count="$needed" status=none
  chmod 600 "$swapfile"
  mkswap -q "$swapfile"
  swapon "$swapfile"
  grep -q "$swapfile" /etc/fstab || echo "$swapfile none swap sw 0 0" >> /etc/fstab
  ok "Swap ${needed}MB active"
}

# ══════════════════════════════════════════════════════════════════
#  Phase: security (UFW, fail2ban, SSH)
# ══════════════════════════════════════════════════════════════════
phase_security() {
  sec "Security (UFW · fail2ban · SSH)"

  inf "Configuring UFW..."
  if ufw status 2>/dev/null | grep -q "Status: inactive"; then
    ufw default deny incoming  &>/dev/null
    ufw default allow outgoing &>/dev/null
  fi
  ensure_ufw_rule ssh
  ensure_ufw_rule "80/tcp"
  ensure_ufw_rule "443/tcp"
  [[ -z "$DOMAIN" ]] && ensure_ufw_rule "$APP_PORT/tcp" || true
  ufw status 2>/dev/null | grep -q "Status: active" || ufw --force enable &>/dev/null
  ok "UFW configured (ssh, 80, 443$([ -z "$DOMAIN" ] && echo ", $APP_PORT" || echo ""))"

  systemctl enable fail2ban &>/dev/null
  systemctl restart fail2ban
  ok "fail2ban active"

  local sshd=/etc/ssh/sshd_config
  grep -q "^ClientAliveInterval" "$sshd" || echo "ClientAliveInterval 120" >> "$sshd"
  grep -q "^ClientAliveCountMax" "$sshd" || echo "ClientAliveCountMax 3"   >> "$sshd"
  systemctl reload sshd 2>/dev/null || systemctl reload ssh 2>/dev/null || true
  ok "SSH keepalive configured"
}

# ══════════════════════════════════════════════════════════════════
#  Phase: Node.js + pnpm
# ══════════════════════════════════════════════════════════════════
phase_node_pnpm() {
  sec "Node.js + pnpm"

  local node_ok=false
  if command -v node &>/dev/null; then
    local major
    major=$(node -v 2>/dev/null | sed 's/v\([0-9]*\)\..*/\1/')
    [[ "$major" =~ ^[0-9]+$ ]] && [[ $major -ge 20 ]] && node_ok=true
  fi
  if [[ "$node_ok" == "false" ]]; then
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
}

# ══════════════════════════════════════════════════════════════════
#  Phase: Build (with headroom check + retry)
# ══════════════════════════════════════════════════════════════════
phase_build() {
  sec "Build 9Router"

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

  local mem_limit; mem_limit=$(tier_node_mem)
  export NODE_OPTIONS="--max-old-space-size=${mem_limit}"
  inf "Node build memory limit: ${mem_limit}MB"

  # Headroom pre-flight: free RAM + swap must exceed mem_limit + 256MB
  local free_total
  free_total=$(awk '/MemAvailable/ {a=$2} /SwapFree/ {s=$2} END{printf "%.0f",(a+s)/1024}' /proc/meminfo)
  local need=$(( mem_limit + 256 ))
  if [[ $free_total -lt $need ]]; then
    wrn "Free RAM+swap = ${free_total}MB, build needs ${need}MB"
    wrn "Phase B should have enabled zram/swap. Continuing but build may OOM."
  fi

  inf "Installing dependencies..."
  pnpm install --include=optional --silent
  pnpm add -D @tailwindcss/postcss --silent
  pnpm add prop-types --silent
  ok "Dependencies ready"

  BUILD_LOG="/tmp/9router-build-$$.log"
  inf "Building Next.js (2-4 phút)..."
  export NODE_ENV=production
  if ! pnpm run build 2>&1 | tee "$BUILD_LOG" | tail -5; then
    wrn "Build failed — clearing caches and retrying once..."
    pnpm store prune &>/dev/null || true
    sync; echo 3 > /proc/sys/vm/drop_caches 2>/dev/null || true
    if ! pnpm run build 2>&1 | tee -a "$BUILD_LOG" | tail -5; then
      build_failure_recover "Build thất bại sau retry. Log đầy đủ: $BUILD_LOG"
    fi
  fi
  ok "Build complete"
  if [[ ! -f .next/standalone/server.js ]]; then
    build_failure_recover "Build thất bại: server.js không tìm thấy"
  fi
}

# Recover from a build failure: in update mode, rollback to previous snapshot
# and restart service. In install mode, just die.
build_failure_recover() {
  local msg="$1"
  if [[ "$INSTALL_MODE" == "update" ]] && [[ -d "$PREVIOUS_DIR" ]]; then
    wrn "$msg"
    wrn "Update mode — rolling back to previous build"
    auto_rollback
    die "Update rolled back. Service đang chạy build cũ. Log: ${BUILD_LOG:-n/a}"
  fi
  die "$msg"
}

# ══════════════════════════════════════════════════════════════════
#  Phase: Deploy runtime (with snapshot for rollback)
# ══════════════════════════════════════════════════════════════════
phase_deploy_runtime() {
  sec "Deploy runtime"
  ensure_service_user

  # Snapshot current runtime for rollback
  if [[ -d "$RUNTIME_DIR" ]] && [[ -f "$RUNTIME_DIR/server.js" ]]; then
    inf "Snapshotting current runtime → $PREVIOUS_DIR"
    rm -rf "$PREVIOUS_DIR"
    cp -a "$RUNTIME_DIR" "$PREVIOUS_DIR"
    ok "Previous build saved"
  fi

  mkdir -p "$RUNTIME_DIR/.next" "$DATA_DIR"

  if command -v rsync &>/dev/null; then
    rsync -a --delete .next/standalone/ "$RUNTIME_DIR/"
    rsync -a --delete .next/static/     "$RUNTIME_DIR/.next/static/"
    [[ -d public ]] && rsync -a --delete public/ "$RUNTIME_DIR/public/" || true
  else
    cp -a .next/standalone/. "$RUNTIME_DIR/"
    cp -a .next/static       "$RUNTIME_DIR/.next/"
    [[ -d public ]] && cp -a public "$RUNTIME_DIR/" || true
  fi

  git -C "$BUILD_DIR" rev-parse --short HEAD > "$RUNTIME_DIR/.install-commit" 2>/dev/null || true
  chown -R "$SERVICE_USER:$SERVICE_GROUP" "$RUNTIME_DIR" "$DATA_DIR"
  ok "Runtime → $RUNTIME_DIR"
}

# ══════════════════════════════════════════════════════════════════
#  Phase: systemd unit + drop-in for tier MemoryMax
# ══════════════════════════════════════════════════════════════════
phase_systemd() {
  sec "Systemd service"

  backup_env_file
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
User=$SERVICE_USER
Group=$SERVICE_GROUP
NoNewPrivileges=true
PrivateTmp=true
ProtectHome=true

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

  # Tier-aware memory drop-in
  local mhigh mmax; mhigh=$(tier_memory_high); mmax=$(tier_memory_max)
  mkdir -p "$SERVICE_DROPIN_DIR"
  if [[ -n "$mmax" ]]; then
    cat > "$SERVICE_DROPIN_DIR/10-memory.conf" << EOF
# Auto-generated by 9router (tier=$TIER)
[Service]
MemoryHigh=$mhigh
MemoryMax=$mmax
EOF
    ok "MemoryMax=$mmax MemoryHigh=$mhigh (tier=$TIER)"
  else
    rm -f "$SERVICE_DROPIN_DIR/10-memory.conf"
    ok "No memory cap (tier=medium+)"
  fi

  echo "$TIER" > "$TIER_CACHE" 2>/dev/null || true

  systemctl daemon-reload
  systemctl enable 9router &>/dev/null
  systemctl restart 9router

  if ! wait_for_service 9router 15 2; then
    wrn "9router không start — auto-rollback nếu có snapshot"
    if [[ "$INSTALL_MODE" == "update" ]] && [[ -d "$PREVIOUS_DIR" ]]; then
      auto_rollback
      die "Update rolled back. Service đang chạy build cũ."
    fi
    die "9router không start được. Check: journalctl -u 9router -n 30"
  fi
  ok "9router running on port $APP_PORT"
}

# ══════════════════════════════════════════════════════════════════
#  Phase: Caddy
# ══════════════════════════════════════════════════════════════════
phase_caddy() {
  [[ -z "$DOMAIN" ]] && return 0
  sec "Caddy + HTTPS"

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
  [[ -f "$CADDYFILE" ]] && cp -a "$CADDYFILE" "$CADDYFILE.bak.$(date +%s)"
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
  if ! caddy validate --config "$CADDYFILE" &>/dev/null; then
    local latest_backup
    latest_backup=$(ls -1t "$CADDYFILE".bak.* 2>/dev/null | head -1 || true)
    if [[ -n "$latest_backup" ]]; then
      cp -a "$latest_backup" "$CADDYFILE"
    else
      rm -f "$CADDYFILE"
    fi
    die "Caddyfile invalid. Restored previous config if available."
  fi
  ok "Caddyfile → $CADDYFILE"

  systemctl enable caddy &>/dev/null
  systemctl restart caddy
  wait_for_service caddy 10 2 || wrn "Caddy không start nhanh — kiểm tra: journalctl -u caddy -n 30"
  wait_for_https "$DOMAIN"
}

# ══════════════════════════════════════════════════════════════════
#  Phase: Self-install (so future runs are `sudo 9router <cmd>`)
# ══════════════════════════════════════════════════════════════════
phase_self_install() {
  sec "Install toolkit → $INSTALLED_BIN"
  local tmp
  tmp=$(mktemp -t 9router-toolkit.XXXXXX)
  if $PIPED; then
    inf "Downloading toolkit..."
    curl -fsSL "$INSTALL_URL" -o "$tmp" \
      || { wrn "Download failed; skipping self-install"; return 0; }
  else
    cp "$SCRIPT_PATH" "$tmp" \
      || { wrn "Copy failed; skipping self-install"; return 0; }
  fi
  chmod 755 "$tmp"
  mv "$tmp" "$INSTALLED_BIN"
  compute_invoke_base
  ok "Toolkit available as: ${B}sudo 9router${N}"
}

# ══════════════════════════════════════════════════════════════════
#  Phase: Cleanup
# ══════════════════════════════════════════════════════════════════
phase_cleanup() {
  sec "Cleanup"
  cd /
  rm -rf "$BUILD_DIR"
  [[ -n "${BUILD_LOG:-}" ]] && [[ -f "$BUILD_LOG" ]] && rm -f "$BUILD_LOG"
  pnpm store prune &>/dev/null || true
  apt-get autoremove --purge -y -qq
  apt-get clean -qq
  ok "Build artifacts removed"
}

# ══════════════════════════════════════════════════════════════════
#  cmd_install / cmd_update — flow drivers
# ══════════════════════════════════════════════════════════════════
collect_install_inputs() {
  echo -e "\n${W}[1/4] Domain (bỏ trống nếu chỉ dùng IP):${N}"
  echo -e "      ${B}Ví dụ: llm.example.com${N}"
  DOMAIN=$(prompt_validated "Domain" "" valid_domain)

  echo -e "\n${W}[2/4] Mật khẩu đăng nhập 9Router:${N}"
  echo -e "      ${B}Enter = ChangeMe123!${N}"
  while true; do
    INITIAL_PASSWORD=$(ask_secret "Password" "ChangeMe123!")
    env_value_ok "$INITIAL_PASSWORD" && break
    wrn "Password chỉ được dùng chữ, số và các ký tự: _ @ % + = : , . / ! -"
  done
  [[ "$INITIAL_PASSWORD" == "ChangeMe123!" ]] && wrn "Đang dùng mật khẩu mặc định. Chỉ nên dùng để test, đổi ngay sau khi cài."

  echo -e "\n${W}[3/4] Port ứng dụng:${N}"
  echo -e "      ${B}Enter = 20128${N}"
  APP_PORT=$(prompt_validated "Port" "20128" valid_port)

  echo -e "\n${W}[4/4] Timezone:${N}"
  echo -e "      ${B}Enter = Asia/Ho_Chi_Minh${N}"
  while true; do
    TZ_SET=$(ask_str "Timezone" "Asia/Ho_Chi_Minh")
    valid_timezone "$TZ_SET" && break
    wrn "Timezone không hợp lệ. Ví dụ hợp lệ: Asia/Ho_Chi_Minh"
  done

  JWT_SECRET=$(openssl rand -hex 32)
  API_KEY_SECRET=$(openssl rand -hex 32)
  MACHINE_ID_SALT=$(openssl rand -hex 16)
}

collect_update_inputs() {
  source_existing_env
  OLD_COMMIT=$(cat "$RUNTIME_DIR/.install-commit" 2>/dev/null || echo "không rõ")
  echo -e "  Phiên bản hiện tại : ${Y}$OLD_COMMIT${N}"
  [[ -n "$DOMAIN" ]] \
    && echo -e "  Domain             : ${G}$DOMAIN${N}" \
    || echo -e "  Domain             : ${Y}(IP only — http://$VPS_IP:$APP_PORT)${N}"
  echo -e "  Port               : $APP_PORT"
  echo -e "  Timezone           : $TZ_SET"
  echo ""
  echo -e "${W}Đổi mật khẩu đăng nhập (Enter để giữ nguyên):${N}"
  local newp
  while true; do
    newp=$(ask_secret "Password mới (Enter giữ nguyên)" "")
    [[ -z "$newp" ]] && break
    env_value_ok "$newp" && { INITIAL_PASSWORD="$newp"; break; }
    wrn "Password chỉ được dùng chữ, số và các ký tự: _ @ % + = : , . / ! -"
  done
}

confirm_summary() {
  echo ""
  hr
  echo -e "  ${W}Xác nhận:${N}"
  echo -e "  IP        : ${Y}$VPS_IP${N}"
  [[ -n "$DOMAIN" ]] \
    && echo -e "  Domain    : ${G}$DOMAIN${N}  ← Caddy + HTTPS tự động" \
    || echo -e "  Domain    : ${Y}(IP only — http://$VPS_IP:$APP_PORT)${N}"
  echo -e "  Password  : ${Y}(hidden)${N}"
  echo -e "  Port      : $APP_PORT"
  echo -e "  Timezone  : $TZ_SET"
  echo -e "  Tier      : $TIER"
  [[ "$INSTALL_MODE" == "update" ]] && echo -e "  Secrets   : ${G}giữ nguyên từ cài đặt trước${N}"
  hr
  ask_confirm "Bắt đầu?" || { echo "Đã huỷ."; exit 0; }
}

cmd_install() {
  require_root
  require_linux
  ensure_gum
  show_banner
  detect_spec
  classify_tier
  show_spec

  if is_installed; then
    INSTALL_MODE="update"
    echo -e "\n  ${C}${W}9Router đã được cài. Chuyển sang chế độ Update.${N}\n"
    collect_update_inputs
  else
    INSTALL_MODE="install"
    echo -e "\n  ${Y}${W}Chế độ: Cài đặt mới${N}\n"
    collect_install_inputs
  fi

  [[ -n "$DOMAIN" ]] && BASE_URL="https://$DOMAIN" || BASE_URL="http://$VPS_IP:$APP_PORT"
  confirm_summary

  START_TIME=$SECONDS
  if timedatectl set-timezone "$TZ_SET" 2>/dev/null; then ok "Timezone → $TZ_SET"; else wrn "Không set được timezone"; fi

  phase_optimize_system
  phase_zram
  phase_swap
  phase_security
  phase_node_pnpm
  phase_build
  phase_deploy_runtime
  phase_systemd
  phase_caddy
  phase_self_install
  phase_cleanup

  print_done_summary
}

cmd_update() {
  is_installed || die "Chưa cài 9router. Chạy: $INVOKE_BASE install"
  INSTALL_MODE="update"
  cmd_install   # cmd_install detects existing install and switches mode
}

# ══════════════════════════════════════════════════════════════════
#  cmd_rollback — restore previous build
# ══════════════════════════════════════════════════════════════════
auto_rollback() {
  inf "Auto-rollback in progress..."
  rsync -a --delete "$PREVIOUS_DIR/" "$RUNTIME_DIR/"
  systemctl restart 9router
  if wait_for_service 9router 15 2; then
    ok "Rolled back to previous build"
  else
    wrn "Rollback restart failed — manual intervention needed"
  fi
}

cmd_rollback() {
  require_root
  show_banner
  detect_spec; classify_tier; show_spec
  [[ -d "$PREVIOUS_DIR" ]] || die "No previous snapshot at $PREVIOUS_DIR — chưa có gì để rollback"
  ask_confirm "Rollback runtime về snapshot trước đó?" || { echo "Đã huỷ."; exit 0; }
  auto_rollback
}

# ══════════════════════════════════════════════════════════════════
#  cmd_uninstall
# ══════════════════════════════════════════════════════════════════
cmd_uninstall() {
  require_root
  show_banner
  detect_spec; classify_tier; show_spec

  is_installed || { wrn "9router chưa cài hoặc đã xoá."; return 0; }
  source_existing_env

  local confirm_target
  confirm_target="${DOMAIN:-9router}"
  echo -e "${R}${W}⚠  Bạn sắp gỡ 9router. Data ($DATA_DIR) sẽ ĐƯỢC GIỮ.${N}"
  echo -e "  Để xác nhận, gõ chính xác: ${Y}${W}$confirm_target${N}"
  local typed
  read -rp "  → " typed </dev/tty
  [[ "$typed" == "$confirm_target" ]] || die "Nhập sai. Đã huỷ."

  systemctl stop 9router 2>/dev/null || true
  systemctl disable 9router 2>/dev/null || true
  rm -f "$SERVICE_FILE"
  rm -rf "$SERVICE_DROPIN_DIR"
  rm -rf "$RUNTIME_DIR" "$PREVIOUS_DIR" "$BUILD_DIR"
  rm -f "$ENV_FILE"
  # shellcheck disable=SC2086
  rm -f $ENV_BACKUP_GLOB 2>/dev/null || true
  rm -f "$SYSCTL_CONF" "$JOURNALD_DROPIN" "$ZRAM_CONF" "$TIER_CACHE"
  systemctl restart systemd-journald 2>/dev/null || true
  if [[ -n "${DOMAIN:-}" ]] && [[ -f "$CADDYFILE" ]]; then
    if grep -qE "^${DOMAIN} \{" "$CADDYFILE"; then
      systemctl stop caddy 2>/dev/null || true
      rm -f "$CADDYFILE"
      systemctl restart caddy 2>/dev/null || true
    fi
  fi
  systemctl daemon-reload

  ok "9router uninstalled. Data preserved at $DATA_DIR"
  echo -e "  Để xoá luôn data: ${B}rm -rf $DATA_DIR${N}"
}

# ══════════════════════════════════════════════════════════════════
#  cmd_status
# ══════════════════════════════════════════════════════════════════
cmd_status() {
  show_banner
  detect_spec; classify_tier; show_spec

  if ! is_installed; then
    wrn "9router chưa cài."
    return 0
  fi
  source_existing_env

  sec "9router status"
  systemctl --no-pager --full status 9router | head -10 || true
  echo ""
  if [[ -n "${DOMAIN:-}" ]]; then
    sec "Caddy status"
    systemctl --no-pager --full status caddy | head -8 || true
  fi
  echo ""
  sec "Resources"
  echo -e "  RSS 9router : $(ps -o rss= -C node 2>/dev/null | head -1 | awk '{printf "%.0f MB",$1/1024}')"
  echo -e "  RAM free    : $(free -m | awk '/Mem:/ {print $7" MB"}')"
  echo -e "  Swap used   : $(free -m | awk '/Swap:/ {print $3"/"$2" MB"}')"
  echo -e "  Disk free   : $(df -BG / | awk 'NR==2 {print $4}')"
  hr
  echo -e "  Logs   : ${B}$INVOKE_BASE logs${N}"
  echo -e "  Doctor : ${B}$INVOKE_BASE doctor${N}"
}

cmd_logs() {
  is_installed || die "Chưa cài 9router."
  exec journalctl -u 9router -f --no-pager
}

# ══════════════════════════════════════════════════════════════════
#  cmd_tune — re-apply tier configs (with optional override)
# ══════════════════════════════════════════════════════════════════
cmd_tune() {
  require_root
  show_banner
  detect_spec; classify_tier; show_spec

  if [[ "${1:-}" == "--tier" ]] && [[ -n "${2:-}" ]]; then
    case "$2" in
      tiny|small|medium) TIER="$2"; wrn "Tier overridden to: $TIER" ;;
      *) die "Invalid tier: $2 (use tiny|small|medium)" ;;
    esac
  fi

  ask_confirm "Re-apply tier=$TIER tuning (sysctl, journald, MemoryMax, zram)?" \
    || { echo "Đã huỷ."; exit 0; }

  phase_optimize_system
  phase_zram
  if is_installed; then
    INSTALL_MODE="update"
    source_existing_env
    [[ -n "$DOMAIN" ]] && BASE_URL="https://$DOMAIN" || BASE_URL="http://$VPS_IP:$APP_PORT"
    # rewrite drop-in only (don't touch env)
    local mhigh mmax; mhigh=$(tier_memory_high); mmax=$(tier_memory_max)
    mkdir -p "$SERVICE_DROPIN_DIR"
    if [[ -n "$mmax" ]]; then
      cat > "$SERVICE_DROPIN_DIR/10-memory.conf" << EOF
# Auto-generated by 9router (tier=$TIER)
[Service]
MemoryHigh=$mhigh
MemoryMax=$mmax
EOF
      ok "MemoryMax=$mmax MemoryHigh=$mhigh"
    else
      rm -f "$SERVICE_DROPIN_DIR/10-memory.conf"
      ok "Memory cap removed (tier=medium+)"
    fi
    echo "$TIER" > "$TIER_CACHE"
    systemctl daemon-reload
    systemctl restart 9router
    wait_for_service 9router 15 2 || wrn "9router restart slow — check journal"
  fi
  ok "Tuning re-applied for tier=$TIER"
}

# ══════════════════════════════════════════════════════════════════
#  cmd_doctor — read-only checks + prompted fixes
# ══════════════════════════════════════════════════════════════════
# Each finding: severity|name|message|fix_command
# Stored in DOCTOR_FINDINGS array.
DOCTOR_FINDINGS=()

doc_add() { DOCTOR_FINDINGS+=("$1|$2|$3|$4"); }

doc_check_service() {
  if ! is_installed; then
    doc_add WARN "install" "9router chưa được cài" "$INVOKE_BASE install"
    return
  fi
  if systemctl is-active --quiet 9router; then
    doc_add OK "service" "9router.service đang chạy" ""
  else
    doc_add FAIL "service" "9router.service KHÔNG chạy" "sudo systemctl restart 9router && journalctl -u 9router -n 30"
  fi
  if [[ -n "${DOMAIN:-}" ]]; then
    if systemctl is-active --quiet caddy; then
      doc_add OK "caddy" "caddy.service đang chạy" ""
    else
      doc_add FAIL "caddy" "caddy.service KHÔNG chạy" "sudo systemctl restart caddy"
    fi
  fi
}

doc_check_disk() {
  local free_gb; free_gb=$(df -BG / 2>/dev/null | awk 'NR==2 {print $4}' | tr -d 'G' || echo 0)
  if [[ "${free_gb:-0}" -ge 2 ]]; then
    doc_add OK "disk" "Disk free ${free_gb}G (≥2G)" ""
  else
    doc_add FAIL "disk" "Disk free chỉ ${free_gb:-0}G (<2G)" "sudo apt clean && sudo journalctl --vacuum-time=3d"
  fi
}

doc_check_memory() {
  local avail_swap
  avail_swap=$(awk '/MemAvailable/ {a=$2} /SwapFree/ {s=$2} END{printf "%.0f",(a+s)/1024}' /proc/meminfo 2>/dev/null || echo 0)
  avail_swap="${avail_swap:-0}"
  if [[ "$avail_swap" -ge 200 ]]; then
    doc_add OK "memory" "Available RAM+swap = ${avail_swap}MB" ""
  else
    doc_add WARN "memory" "Available RAM+swap chỉ ${avail_swap}MB (<200MB)" "$INVOKE_BASE tune"
  fi
}

doc_check_journal() {
  local sz
  sz=$(journalctl --disk-usage 2>/dev/null | grep -oE '[0-9.]+[KMG]' | head -1 || echo "?")
  if [[ -f "$JOURNALD_DROPIN" ]]; then
    doc_add OK "journal" "journald cap configured (current: $sz)" ""
  else
    doc_add WARN "journal" "journald không có cap (current: $sz)" "$INVOKE_BASE tune"
  fi
}

doc_check_sysctl_drift() {
  [[ -f "$SYSCTL_CONF" ]] || { doc_add WARN "sysctl" "$SYSCTL_CONF không tồn tại" "$INVOKE_BASE tune"; return; }
  local drift=0
  while IFS= read -r line; do
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    [[ -z "${line// }" ]] && continue
    local key val cur
    key=$(echo "$line" | awk -F= '{print $1}' | tr -d ' ')
    val=$(echo "$line" | awk -F= '{print $2}' | tr -d ' ')
    cur=$(sysctl -n "$key" 2>/dev/null | tr -d '\t ' || echo "?")
    [[ "$cur" != "$val" ]] && drift=$(( drift + 1 ))
  done < "$SYSCTL_CONF"
  if [[ $drift -eq 0 ]]; then
    doc_add OK "sysctl" "Sysctl khớp file ($(grep -cE '^[^#]' "$SYSCTL_CONF") keys)" ""
  else
    doc_add WARN "sysctl" "$drift sysctl key bị drift" "sudo sysctl -p $SYSCTL_CONF"
  fi
}

doc_check_cert() {
  [[ -z "${DOMAIN:-}" ]] && return
  local end_epoch days
  end_epoch=$(echo | openssl s_client -servername "$DOMAIN" -connect "$DOMAIN:443" 2>/dev/null \
             | openssl x509 -noout -enddate 2>/dev/null \
             | sed 's/notAfter=//' | xargs -I{} date -d "{}" +%s 2>/dev/null || echo 0)
  if [[ "$end_epoch" -eq 0 ]]; then
    doc_add WARN "cert" "Không kiểm tra được TLS cert cho $DOMAIN" "curl -I https://$DOMAIN"
    return
  fi
  days=$(( (end_epoch - $(date +%s)) / 86400 ))
  if [[ $days -gt 14 ]]; then
    doc_add OK "cert" "TLS cert OK (còn ${days} ngày)" ""
  else
    doc_add WARN "cert" "TLS cert sắp hết hạn (${days} ngày)" "sudo systemctl reload caddy"
  fi
}

doc_check_security_updates() {
  local count=0
  if command -v apt &>/dev/null; then
    count=$(apt list --upgradable 2>/dev/null | awk 'tolower($0) ~ /security/ {count++} END {print count+0}')
  fi
  if [[ "$count" -eq 0 ]]; then
    doc_add OK "updates" "Không có security updates pending" ""
  else
    doc_add WARN "updates" "$count security updates pending" "sudo apt upgrade -y"
  fi
}

doc_check_zram() {
  local needed; needed=$(tier_zram_mb)
  [[ $needed -eq 0 ]] && return
  if swapon --show 2>/dev/null | grep -q '^/dev/zram'; then
    doc_add OK "zram" "zram active" ""
  else
    doc_add WARN "zram" "zram không hoạt động (tier=$TIER cần ${needed}MB)" "$INVOKE_BASE tune"
  fi
}

doc_check_memory_cap() {
  is_installed || return
  local mmax_expected; mmax_expected=$(tier_memory_max)
  local actual=""
  [[ -f "$SERVICE_DROPIN_DIR/10-memory.conf" ]] && \
    actual=$(awk -F= '/MemoryMax/ {print $2}' "$SERVICE_DROPIN_DIR/10-memory.conf" | tr -d ' ')
  if [[ -z "$mmax_expected" ]] && [[ -z "$actual" ]]; then
    doc_add OK "memmax" "MemoryMax: unlimited (tier=medium+)" ""
  elif [[ "$actual" == "$mmax_expected" ]]; then
    doc_add OK "memmax" "MemoryMax=$actual khớp tier=$TIER" ""
  else
    doc_add WARN "memmax" "MemoryMax='$actual' không khớp tier=$TIER (expected '$mmax_expected')" "$INVOKE_BASE tune"
  fi
}

doc_render_text() {
  echo ""
  hr
  echo -e "  ${W}9router doctor — tier=$TIER${N}"
  hr
  local n=0 ok_n=0 warn_n=0 fail_n=0
  for f in "${DOCTOR_FINDINGS[@]}"; do
    n=$((n+1))
    local sev name msg fix
    sev=$(echo "$f" | awk -F'|' '{print $1}')
    name=$(echo "$f" | awk -F'|' '{print $2}')
    msg=$(echo "$f" | awk -F'|' '{print $3}')
    fix=$(echo "$f" | awk -F'|' '{print $4}')
    case "$sev" in
      OK)   echo -e "  ${G}[OK]${N}   $name — $msg"; ok_n=$((ok_n+1)) ;;
      WARN) echo -e "  ${Y}[WARN]${N} $name — $msg"; [[ -n "$fix" ]] && echo -e "         ${B}fix:${N} $fix"; warn_n=$((warn_n+1)) ;;
      FAIL) echo -e "  ${R}[FAIL]${N} $name — $msg"; [[ -n "$fix" ]] && echo -e "         ${B}fix:${N} $fix"; fail_n=$((fail_n+1)) ;;
    esac
  done
  hr
  echo -e "  Total: $n  ·  ${G}OK $ok_n${N}  ·  ${Y}WARN $warn_n${N}  ·  ${R}FAIL $fail_n${N}"
  hr
}

doc_render_json() {
  printf '{"tier":"%s","findings":[' "$TIER"
  local first=1
  for f in "${DOCTOR_FINDINGS[@]}"; do
    local sev name msg fix
    sev=$(echo "$f" | awk -F'|' '{print $1}')
    name=$(echo "$f" | awk -F'|' '{print $2}')
    msg=$(echo "$f" | awk -F'|' '{print $3}')
    fix=$(echo "$f" | awk -F'|' '{print $4}')
    [[ $first -eq 1 ]] || printf ','
    first=0
    printf '{"severity":"%s","name":"%s","message":%s,"fix":%s}' \
      "$sev" "$name" \
      "$(printf '%s' "$msg" | jq -Rs . 2>/dev/null || printf '"%s"' "${msg//\"/\\\"}")" \
      "$(printf '%s' "$fix" | jq -Rs . 2>/dev/null || printf '"%s"' "${fix//\"/\\\"}")"
  done
  printf ']}\n'
}

doc_offer_fixes() {
  local fixable=()
  for f in "${DOCTOR_FINDINGS[@]}"; do
    local sev fix
    sev=$(echo "$f" | awk -F'|' '{print $1}')
    fix=$(echo "$f" | awk -F'|' '{print $4}')
    [[ "$sev" != "OK" ]] && [[ -n "$fix" ]] && fixable+=("$f")
  done
  [[ ${#fixable[@]} -eq 0 ]] && { ok "Không có gì cần fix"; return; }

  echo ""
  if ask_confirm "Áp dụng tất cả ${#fixable[@]} fix theo thứ tự?"; then
    for f in "${fixable[@]}"; do
      local name fix
      name=$(echo "$f" | awk -F'|' '{print $2}')
      fix=$(echo "$f" | awk -F'|' '{print $4}')
      inf "→ $name: $fix"
      bash -c "$fix" || wrn "fix '$name' returned non-zero"
    done
    ok "All fixes attempted. Re-run doctor để verify."
  else
    for f in "${fixable[@]}"; do
      local name msg fix
      name=$(echo "$f" | awk -F'|' '{print $2}')
      msg=$(echo "$f" | awk -F'|' '{print $3}')
      fix=$(echo "$f" | awk -F'|' '{print $4}')
      echo ""
      echo -e "  ${W}$name${N} — $msg"
      echo -e "  fix: ${B}$fix${N}"
      if ask_confirm "Apply this fix?"; then
        bash -c "$fix" || wrn "fix '$name' returned non-zero"
      else
        inf "Skipped"
      fi
    done
  fi
}

cmd_doctor() {
  local json_mode=false
  [[ "${1:-}" == "--json" ]] && json_mode=true

  detect_spec; classify_tier
  is_installed && source_existing_env

  if ! $json_mode; then
    show_banner
    show_spec
  fi

  doc_check_service          || true
  doc_check_disk             || true
  doc_check_memory           || true
  doc_check_journal          || true
  doc_check_sysctl_drift     || true
  doc_check_zram             || true
  doc_check_memory_cap       || true
  doc_check_cert             || true
  doc_check_security_updates || true

  if $json_mode; then
    doc_render_json
    return
  fi

  doc_render_text
  if [[ $EUID -eq 0 ]]; then
    doc_offer_fixes
  else
    wrn "Run with sudo to apply fixes."
  fi
}

# ══════════════════════════════════════════════════════════════════
#  print_done_summary (for install/update)
# ══════════════════════════════════════════════════════════════════
print_done_summary() {
  local elapsed=$(( SECONDS - START_TIME ))
  local elapsed_fmt; elapsed_fmt=$(printf '%dm%02ds' $((elapsed/60)) $((elapsed%60)))
  echo ""
  hr
  echo -e "${G}${W}"
  if [[ "$INSTALL_MODE" == "update" ]]; then
    echo "   ✅  Cập nhật hoàn tất! (${elapsed_fmt})"
  else
    echo "   ✅  Cài đặt hoàn tất! (${elapsed_fmt})"
  fi
  echo -e "${N}"
  hr
  echo -e "  ${W}9Router${N}"
  echo -e "  URL          : ${C}${W}$BASE_URL${N}"
  echo -e "  Password     : ${Y}$INITIAL_PASSWORD${N}"
  echo -e "  Tier         : $TIER"
  if [[ "$INSTALL_MODE" == "update" ]]; then
    echo -e "  Build cũ     : ${Y}${OLD_COMMIT:-không rõ}${N}"
    echo -e "  Build mới    : ${G}$NEW_COMMIT${N}"
  fi
  echo ""
  echo -e "  ${W}Files${N}"
  echo -e "  Config       : $ENV_FILE"
  echo -e "  Runtime      : $RUNTIME_DIR"
  echo -e "  Previous     : $PREVIOUS_DIR (for rollback)"
  echo -e "  Data         : $DATA_DIR"
  echo ""
  echo -e "  ${W}Commands${N}"
  echo -e "  Status       : ${B}$INVOKE_BASE status${N}"
  echo -e "  Doctor       : ${B}$INVOKE_BASE doctor${N}     (chạy hàng tuần)"
  echo -e "  Logs         : ${B}$INVOKE_BASE logs${N}"
  echo -e "  Update       : ${B}$INVOKE_BASE update${N}"
  echo -e "  Rollback     : ${B}$INVOKE_BASE rollback${N}"
  echo -e "  Uninstall    : ${B}$INVOKE_BASE uninstall${N}"
  hr
  echo ""

  if [[ "$INITIAL_PASSWORD" == "ChangeMe123!" ]]; then
    echo -e "${Y}${W}  ⚠  Đang dùng mật khẩu mặc định! Đổi ngay:${N}"
    echo -e "     ${B}sudo nano $ENV_FILE${N}"
    echo -e "     ${B}sudo systemctl restart 9router${N}"
    echo ""
  fi
}

# ══════════════════════════════════════════════════════════════════
#  Interactive menu (default when no args)
# ══════════════════════════════════════════════════════════════════
interactive_menu() {
  show_banner
  detect_spec; classify_tier; show_spec

  local installed_label="not installed"
  is_installed && installed_label="installed (commit $(cat $RUNTIME_DIR/.install-commit 2>/dev/null || echo '?'))"
  echo -e "  Status    : $installed_label"
  hr
  echo ""

  if ! command -v gum &>/dev/null; then
    if [[ $EUID -eq 0 ]] && [[ -f /etc/debian_version ]]; then
      ensure_gum
    else
      echo "Available commands:"
      echo "  install · update · doctor · tune · status · logs · rollback · uninstall"
      echo ""
      echo "Run e.g.: $INVOKE_BASE install"
      exit 0
    fi
  fi

  local choice
  if is_installed; then
    choice=$(gum choose --header "9router toolkit (tier=$TIER)" \
      "Update (pull latest + redeploy)" \
      "Doctor (health check)" \
      "Status (one-screen summary)" \
      "Logs (follow service)" \
      "Tune (re-apply tier tuning)" \
      "Rollback (restore previous build)" \
      "Uninstall (data preserved)" \
      "Exit" </dev/tty)
  else
    choice=$(gum choose --header "9router toolkit (tier=$TIER)" \
      "Install (fresh install)" \
      "Doctor (health check)" \
      "Status (system spec only)" \
      "Exit" </dev/tty)
  fi

  case "$choice" in
    "Install"*)   cmd_install ;;
    "Update"*)    cmd_update ;;
    "Doctor"*)    cmd_doctor ;;
    "Status"*)    cmd_status ;;
    "Logs"*)      cmd_logs ;;
    "Tune"*)      cmd_tune ;;
    "Rollback"*)  cmd_rollback ;;
    "Uninstall"*) cmd_uninstall ;;
    *)            exit 0 ;;
  esac
}

# ══════════════════════════════════════════════════════════════════
#  Dispatcher
# ══════════════════════════════════════════════════════════════════
main() {
  if $PIPED; then
    local tmp
    tmp=$(mktemp -t setup_9router.XXXXXX)
    curl -fsSL "$INSTALL_URL" -o "$tmp"
    chmod +x "$tmp"
    export NINE_ROUTER_RELAUNCHED_FROM="$tmp"
    exec "$tmp" "$@"
  fi

  case "${1:-menu}" in
    install)    shift; cmd_install "$@" ;;
    update)     shift; cmd_update "$@" ;;
    doctor)     shift; cmd_doctor "$@" ;;
    tune)       shift; cmd_tune "$@" ;;
    status)     shift; cmd_status "$@" ;;
    logs)       shift; cmd_logs "$@" ;;
    rollback)   shift; cmd_rollback "$@" ;;
    uninstall)  shift; cmd_uninstall "$@" ;;
    menu|"")    interactive_menu ;;
    -h|--help|help)
      sed -n '2,22p' "$0"
      ;;
    *)
      die "Unknown subcommand: $1   (try: $INVOKE_BASE help)"
      ;;
  esac
}

main "$@"
