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
sec() {
  if ui_has_gum; then
    echo ""
    gum style --bold --foreground "$UI_ACCENT" "◆ $*"
  else
    echo -e "\n${C}${W}━━━  $*  ━━━${N}"
  fi
}
hr()  { echo -e "${C}──────────────────────────────────────────${N}"; }

# ── Gum UI helpers (TTY-first, ANSI fallback) ────────────────────────
UI_ACCENT="86"
UI_PURPLE="99"
UI_GREEN="46"
UI_YELLOW="226"
UI_RED="196"
UI_MUTED="245"

ui_has_gum() {
  command -v gum &>/dev/null && [[ -t 1 ]]
}

ui_style() {
  if ui_has_gum; then
    gum style "$@"
  else
    local text="${*: -1}"
    printf '%s\n' "$text"
  fi
}

ui_panel() {
  local title="$1"; shift
  local body="$*"
  if ui_has_gum; then
    gum style \
      --border rounded \
      --border-foreground "$UI_ACCENT" \
      --padding "1 2" \
      --margin "1 0" \
      --foreground "255" \
      "$title"$'\n\n'"$body"
  else
    sec "$title"
    printf '%b\n' "$body"
    hr
  fi
}

ui_step() {
  if ui_has_gum; then
    gum log --level info --prefix "9router" --message.foreground "$UI_ACCENT" "$*"
  else
    inf "$*"
  fi
}

ui_ok() {
  if ui_has_gum; then
    gum log --level info --prefix "9router" --level.foreground "$UI_GREEN" --message.foreground "$UI_GREEN" "✔ $*"
  else
    ok "$*"
  fi
}

ui_warn() {
  if ui_has_gum; then
    gum log --level warn --prefix "9router" --level.foreground "$UI_YELLOW" --message.foreground "$UI_YELLOW" "⚠ $*"
  else
    wrn "$*"
  fi
}

ui_error() {
  if ui_has_gum; then
    gum log --level error --prefix "9router" --level.foreground "$UI_RED" --message.foreground "$UI_RED" "✖ $*"
  else
    echo -e "${R}[✘]${N} $*" >&2
  fi
}

ui_table() {
  if ui_has_gum; then
    gum table \
      --print \
      --border rounded \
      --border.foreground "$UI_ACCENT" \
      --header.foreground "$UI_PURPLE" \
      --cell.foreground "255" \
      "$@"
  else
    cat
  fi
}

ui_hint() {
  if ui_has_gum; then
    gum style --foreground "$UI_MUTED" "↑↓ move  •  Enter select  •  Esc cancel"
  fi
}

ui_spin() {
  local title="$1"; shift
  if ui_has_gum; then
    if gum spin --help 2>/dev/null | grep -q -- '--show-error'; then
      gum spin --spinner dot --spinner.foreground "$UI_ACCENT" --title.foreground "$UI_ACCENT" --title "$title" --show-error -- "$@"
    else
      gum spin --spinner dot --title "$title" -- "$@"
    fi
  else
    inf "$title"
    "$@"
  fi
}

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
  if ui_has_gum; then
    gum style --bold --foreground "$UI_ACCENT" "  AI Proxy Router — VPS Toolkit"
    gum style --foreground "$UI_MUTED" "  Low-spec VPS install · update · doctor · rollback"
  else
    echo -e "  ${W}AI Proxy Router — VPS Toolkit${N}"
  fi
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
  local tier_label tier_note
  case "$TIER" in
    tiny)   tier_label="tiny"; tier_note="<1GB · aggressive low-spec mode" ;;
    small)  tier_label="small"; tier_note="1-2GB · default low-spec target" ;;
    medium) tier_label="medium+"; tier_note=">=2GB · comfortable" ;;
  esac
  if ui_has_gum; then
    {
      printf 'Metric\tValue\n'
      printf 'IP\t%s\n' "$VPS_IP"
      printf 'OS\t%s (kernel %s)\n' "$OS_INFO" "$KERNEL"
      printf 'CPU\t%s cores\n' "$CPU_CORES"
      printf 'RAM\t%s MB\n' "$TOTAL_RAM"
      printf 'Swap\t%s MB\n' "$SWAP_MB"
      printf 'Disk free\t%s GB\n' "$TOTAL_DISK"
      printf 'Tier\t%s (%s)\n' "$tier_label" "$tier_note"
    } | ui_table --separator $'\t'
  else
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
  fi
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
vm.vfs_cache_pressure         = 200
vm.min_free_kbytes            = 65536
EOF
}

tier_memory_high() {
  case "$TIER" in
    tiny)   echo "600M" ;;
    small)  echo "1000M" ;;
    medium) echo "" ;;   # unlimited
  esac
}
tier_memory_max() {
  case "$TIER" in
    tiny)   echo "700M" ;;
    small)  echo "1200M" ;;
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
  if [[ $TOTAL_RAM -le 1024 ]]; then
    echo 768
  elif [[ $TOTAL_RAM -le 2048 ]]; then
    echo 1024
  else
    echo 1536
  fi
}

build_available_mb() {
  awk '/MemAvailable/ {a=$2} /SwapFree/ {s=$2} END{printf "%.0f",(a+s)/1024}' /proc/meminfo 2>/dev/null || echo 0
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
  ui_step "Cài essential tools..."
  ui_spin "Installing essential VPS tools..." apt-get install -y -qq \
    curl wget git ca-certificates openssl gnupg \
    htop vim net-tools unzip lsof rsync \
    ufw fail2ban \
    build-essential jq
  ui_ok "Essential tools ready"
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
  ui_step "Chờ $svc khởi động..."
  while [[ $attempt -lt $max ]]; do
    systemctl is-active --quiet "$svc" && { ui_ok "$svc running"; return 0; }
    attempt=$(( attempt + 1 ))
    sleep "$interval"
  done
  return 1
}

wait_for_https() {
  local domain="$1" max=12 attempt=0
  ui_step "Chờ Caddy xin TLS cert (tối đa 60s)..."
  while [[ $attempt -lt $max ]]; do
    curl -fsI "https://$domain" &>/dev/null && { ui_ok "HTTPS live: https://$domain"; return 0; }
    attempt=$(( attempt + 1 ))
    sleep 5
  done
  ui_warn "DNS chưa propagate tới $VPS_IP — HTTPS tự lên sau khi DNS lan truyền"
  ui_warn "Kiểm tra: curl -I https://$domain"
}

ensure_ufw_rule() {
  local rule="$1"
  ufw status 2>/dev/null | grep -qE "^${rule}.*ALLOW" || ufw allow "$rule" &>/dev/null
}

clean_build_caches() {
  local scope="${1:-normal}"
  [[ -d "$BUILD_DIR" ]] || return 0
  ui_step "Cleaning build caches ($scope)..."
  rm -rf \
    "$BUILD_DIR/.next" \
    "$BUILD_DIR/node_modules/.cache" \
    "$BUILD_DIR/.turbo" \
    "$BUILD_DIR/.cache" \
    "$BUILD_DIR/tmp" \
    "$BUILD_DIR/.tmp" \
    "$BUILD_DIR"/tsconfig.tsbuildinfo \
    "$BUILD_DIR"/.eslintcache 2>/dev/null || true
  ui_spin "Pruning pnpm store..." bash -c 'pnpm store prune &>/dev/null' || true
  if [[ "$scope" == "retry" ]]; then
    rm -rf /tmp/next-* /tmp/turbopack-* /tmp/v8-compile-cache-* 2>/dev/null || true
    npm cache clean --force &>/dev/null || true
  fi
  ui_ok "Build caches cleaned"
}

show_build_memory_plan() {
  local heap="$1" free_total="$2" need="$3"
  if ui_has_gum; then
    ui_panel "Build memory plan" \
      "Tier              : $TIER"$'\n'"Node heap         : ${heap}MB"$'\n'"Available RAM+swap: ${free_total}MB"$'\n'"Target headroom   : ${need}MB"$'\n'"Cache policy      : clean before build + stronger retry cleanup"
  else
    ui_step "Build memory plan: tier=$TIER heap=${heap}MB free=${free_total}MB need=${need}MB"
  fi
}

remove_webpack_forced_builds() {
  local forced_build="next build --""webpack"
  if [[ -f package.json ]] && grep -q "$forced_build" package.json; then
    perl -0pi -e 's/next build --\x77ebpack/next build/g' package.json
    ui_ok "Removed forced webpack from Next.js build scripts"
  else
    ui_ok "No forced webpack build scripts found"
  fi
}

ensure_next_standalone_output() {
  local cfg=""
  for candidate in next.config.js next.config.mjs next.config.cjs next.config.ts next.config.mts; do
    if [[ -f "$candidate" ]]; then
      cfg="$candidate"
      break
    fi
  done

  if [[ -z "$cfg" ]]; then
    cat > next.config.mjs << 'EOF'
const nextConfig = {
  output: 'standalone',
};

export default nextConfig;
EOF
    ui_ok "Created next.config.mjs with output: standalone"
    return 0
  fi

  if grep -Eq "output[[:space:]]*:[[:space:]]*['\"]standalone['\"]" "$cfg"; then
    ui_ok "Next.js standalone output already enabled ($cfg)"
    return 0
  fi

  cp -a "$cfg" "$cfg.bak.$(date +%s)"
  if grep -Eq "module\.exports[[:space:]]*=[[:space:]]*\{" "$cfg"; then
    perl -0pi -e "s/module\.exports[[:space:]]*=[[:space:]]*\{/module.exports = {\n  output: 'standalone',/" "$cfg"
  elif grep -Eq "const[[:space:]]+nextConfig[[:space:]]*=[[:space:]]*\{" "$cfg"; then
    perl -0pi -e "s/const[[:space:]]+nextConfig[[:space:]]*=[[:space:]]*\{/const nextConfig = {\n  output: 'standalone',/" "$cfg"
  elif grep -Eq "export[[:space:]]+default[[:space:]]*\{" "$cfg"; then
    perl -0pi -e "s/export[[:space:]]+default[[:space:]]*\{/export default {\n  output: 'standalone',/" "$cfg"
  else
    die "Cannot safely enable output: 'standalone' in $cfg. Please add it to Next config."
  fi

  grep -Eq "output[[:space:]]*:[[:space:]]*['\"]standalone['\"]" "$cfg" \
    || die "Failed to enable output: 'standalone' in $cfg"
  ui_ok "Enabled Next.js standalone output in $cfg"
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
    out=$(gum input \
      --prompt "→ " \
      --prompt.foreground "$UI_ACCENT" \
      --placeholder "$default" \
      --placeholder.foreground "$UI_MUTED" \
      --header "$label" \
      --header.foreground "$UI_PURPLE" \
      --value "$default" \
      </dev/tty)
  else
    read -rp "  → $label [$default]: " out </dev/tty
    out="${out:-$default}"
  fi
  printf '%s' "$out"
}

ask_secret() {
  local label="$1" default="${2:-}" out
  if command -v gum &>/dev/null; then
    out=$(gum input \
      --password \
      --prompt "→ " \
      --prompt.foreground "$UI_ACCENT" \
      --placeholder "$default" \
      --placeholder.foreground "$UI_MUTED" \
      --header "$label" \
      --header.foreground "$UI_PURPLE" \
      </dev/tty)
  else
    read -rsp "  → $label [$default]: " out </dev/tty
    echo >/dev/tty
  fi
  out="${out:-$default}"
  printf '%s' "$out"
}

ask_confirm() {
  local label="$1"
  if command -v gum &>/dev/null; then
    gum confirm "$label" \
      --affirmative "Yes" \
      --negative "No" \
      --prompt.foreground "$UI_PURPLE" \
      --selected.background "$UI_ACCENT" \
      --selected.foreground "230" \
      --unselected.foreground "254" \
      --unselected.background "235" \
      </dev/tty
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

  ui_step "apt update + upgrade..."
  ui_spin "Refreshing apt package lists..." apt-get update -qq
  ui_spin "Applying package upgrades..." apt-get upgrade -y -qq \
    -o Dpkg::Options::="--force-confdef" \
    -o Dpkg::Options::="--force-confold"
  ui_ok "System packages updated"

  ensure_essentials

  # Sysctl per tier + common
  ui_step "Applying sysctl (tier=$TIER, BBR enabled)..."
  {
    echo "# Auto-generated by 9router (tier=$TIER, $(date -Iseconds))"
    tier_sysctl_block
  } > "$SYSCTL_CONF"
  sysctl -p "$SYSCTL_CONF" &>/dev/null || wrn "Some sysctl keys not applied (kernel may lack BBR module)"
  ui_ok "sysctl applied"

  # ulimits
  ui_step "Setting open file limits..."
  if ! grep -q "^\*.*soft.*nofile.*65535" /etc/security/limits.conf 2>/dev/null; then
    cat >> /etc/security/limits.conf << 'EOF'
# 9router
*         soft  nofile  65535
*         hard  nofile  65535
root      soft  nofile  65535
root      hard  nofile  65535
EOF
  fi
  ui_ok "ulimits set (nofile=65535)"

  # journald cap
  ui_step "Capping journald (200M / 50M file / 2 week retention)..."
  mkdir -p /etc/systemd/journald.conf.d
  cat > "$JOURNALD_DROPIN" << 'EOF'
# Auto-generated by 9router
[Journal]
SystemMaxUse=200M
SystemMaxFileSize=50M
MaxRetentionSec=2week
EOF
  ui_spin "Restarting systemd-journald..." bash -c 'systemctl restart systemd-journald 2>/dev/null' || true
  ui_ok "journald capped"

  # unattended-upgrades
  ui_step "Enabling unattended-upgrades..."
  ui_spin "Installing unattended-upgrades..." bash -c 'apt-get install -y -qq unattended-upgrades 2>/dev/null' || true
  if [[ -f /etc/apt/apt.conf.d/20auto-upgrades ]] \
     && grep -q "Unattended-Upgrade" /etc/apt/apt.conf.d/20auto-upgrades; then
    ui_ok "unattended-upgrades already configured"
  else
    cat > /etc/apt/apt.conf.d/20auto-upgrades << 'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
EOF
    ui_ok "unattended-upgrades enabled"
  fi
}

# ══════════════════════════════════════════════════════════════════
#  Phase: zram (tiny/small only)
# ══════════════════════════════════════════════════════════════════
phase_zram() {
  local size_mb; size_mb=$(tier_zram_mb)
  if [[ $size_mb -eq 0 ]]; then
    ui_step "zram skipped (tier=$TIER)"
    return 0
  fi

  sec "zram (compressed RAM swap, ${size_mb}MB)"

  # Use systemd-zram-generator (preferred, preinstalled on Ubuntu 22.04+)
  if [[ ! -d /etc/systemd/zram-generator.conf.d ]]; then
    ui_spin "Installing systemd-zram-generator..." bash -c 'apt-get install -y -qq systemd-zram-generator 2>/dev/null' \
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
  ui_spin "Reloading systemd..." systemctl daemon-reload
  ui_spin "Starting zram device..." bash -c 'systemctl restart systemd-zram-setup@zram0.service 2>/dev/null' || true
  if swapon --show 2>/dev/null | grep -q '^/dev/zram'; then
    ui_ok "zram active: $(swapon --show=NAME,SIZE,PRIO 2>/dev/null | grep zram | awk '{print $1, $2, "prio="$3}')"
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
    ui_ok "Swap already configured: $(free -h | awk '/Swap/ {print $2}')"
    return 0
  fi

  ui_step "Tạo swap ${needed}MB..."
  local swapfile=/swapfile
  [[ -f "$swapfile" ]] && swapoff "$swapfile" 2>/dev/null || true
  fallocate -l "${needed}M" "$swapfile" 2>/dev/null \
    || dd if=/dev/zero of="$swapfile" bs=1M count="$needed" status=none
  chmod 600 "$swapfile"
  mkswap -q "$swapfile"
  swapon "$swapfile"
  grep -q "$swapfile" /etc/fstab || echo "$swapfile none swap sw 0 0" >> /etc/fstab
  ui_ok "Swap ${needed}MB active"
}

# ══════════════════════════════════════════════════════════════════
#  Phase: security (UFW, fail2ban, SSH)
# ══════════════════════════════════════════════════════════════════
phase_security() {
  sec "Security (UFW · fail2ban · SSH)"

  ui_step "Configuring UFW..."
  if ufw status 2>/dev/null | grep -q "Status: inactive"; then
    ufw default deny incoming  &>/dev/null
    ufw default allow outgoing &>/dev/null
  fi
  ensure_ufw_rule ssh
  ensure_ufw_rule "80/tcp"
  ensure_ufw_rule "443/tcp"
  [[ -z "$DOMAIN" ]] && ensure_ufw_rule "$APP_PORT/tcp" || true
  ufw status 2>/dev/null | grep -q "Status: active" || ufw --force enable &>/dev/null
  ui_ok "UFW configured (ssh, 80, 443$([ -z "$DOMAIN" ] && echo ", $APP_PORT" || echo ""))"

  ui_spin "Enabling fail2ban..." bash -c 'systemctl enable fail2ban &>/dev/null'
  ui_spin "Restarting fail2ban..." systemctl restart fail2ban
  ui_ok "fail2ban active"

  local sshd=/etc/ssh/sshd_config
  grep -q "^ClientAliveInterval" "$sshd" || echo "ClientAliveInterval 120" >> "$sshd"
  grep -q "^ClientAliveCountMax" "$sshd" || echo "ClientAliveCountMax 3"   >> "$sshd"
  systemctl reload sshd 2>/dev/null || systemctl reload ssh 2>/dev/null || true
  ui_ok "SSH keepalive configured"
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
    ui_step "Cài Node.js 20..."
    ui_spin "Configuring NodeSource repository..." bash -c 'curl -fsSL https://deb.nodesource.com/setup_20.x | bash - &>/dev/null'
    ui_spin "Installing Node.js 20..." apt-get install -y -qq nodejs
    ui_ok "Node.js $(node -v) installed"
  else
    ui_ok "Node.js $(node -v) already installed"
  fi

  if ! command -v pnpm &>/dev/null; then
    ui_step "Cài pnpm..."
    ui_spin "Installing pnpm globally..." npm install -g pnpm --silent
    ui_ok "pnpm $(pnpm -v) installed"
  else
    ui_ok "pnpm $(pnpm -v) already installed"
  fi
}

# ══════════════════════════════════════════════════════════════════
#  Phase: Build (with headroom check + retry)
# ══════════════════════════════════════════════════════════════════
phase_build() {
  sec "Build 9Router"

  systemctl stop 9router 2>/dev/null && ui_warn "Stopped existing 9router" || true

  rm -rf "$BUILD_DIR"
  mkdir -p "$BUILD_DIR"
  ui_step "Cloning repository..."
  # shellcheck disable=SC2016
  ui_spin "Cloning 9Router source..." bash -c 'git clone --depth=1 "$1" "$2" &>/dev/null' _ "$REPO_URL" "$BUILD_DIR"
  ui_ok "Cloned"

  NEW_COMMIT=$(git -C "$BUILD_DIR" rev-parse --short HEAD 2>/dev/null || echo "?")
  ui_step "Phiên bản mới: $NEW_COMMIT"

  cd "$BUILD_DIR"
  unset NODE_ENV
  export NEXT_TELEMETRY_DISABLED=1
  export NEXT_DISABLE_WEBPACK_CACHE=1
  export CI=true

  remove_webpack_forced_builds
  ensure_next_standalone_output

  local mem_limit; mem_limit=$(tier_node_mem)
  export NODE_OPTIONS="--max-old-space-size=${mem_limit}"
  ui_step "Node build memory limit: ${mem_limit}MB"

  # Headroom pre-flight: keep RAM+swap above heap plus OS/build overhead.
  local free_total
  free_total=$(build_available_mb)
  local need=$(( mem_limit + 384 ))
  show_build_memory_plan "$mem_limit" "$free_total" "$need"
  if [[ $free_total -lt $need ]]; then
    ui_warn "Free RAM+swap = ${free_total}MB, build needs ${need}MB"
    ui_warn "Continuing with low-memory settings, but build may still OOM."
  fi

  clean_build_caches "pre-build"
  ui_step "Installing dependencies..."
  ui_spin "pnpm install (low-memory mode)..." pnpm install --frozen-lockfile --prefer-offline --silent
  ui_ok "Dependencies ready"

  BUILD_LOG="/tmp/9router-build-$$.log"
  ui_step "Building Next.js (2-4 phút)..."
  export NODE_ENV=production
  if ! pnpm run build 2>&1 | tee "$BUILD_LOG" | tail -5; then
    ui_warn "Build failed — clearing caches and retrying once..."
    clean_build_caches "retry"
    free_total=$(build_available_mb)
    mem_limit=$(tier_node_mem)
    export NODE_OPTIONS="--max-old-space-size=${mem_limit}"
    ui_step "Retry Node build memory limit: ${mem_limit}MB (free RAM+swap ${free_total}MB)"
    if ! pnpm run build 2>&1 | tee -a "$BUILD_LOG" | tail -5; then
      build_failure_recover "Build thất bại sau retry. Log đầy đủ: $BUILD_LOG"
    fi
  fi
  ui_ok "Build complete"
  if [[ ! -f .next/standalone/server.js ]]; then
    build_failure_recover "Build thất bại: server.js không tìm thấy"
  fi
}

# Recover from a build failure: in update mode, rollback to previous snapshot
# and restart service. In install mode, just die.
build_failure_recover() {
  local msg="$1"
  if [[ "$INSTALL_MODE" == "update" ]] && [[ -d "$PREVIOUS_DIR" ]]; then
    ui_warn "$msg"
    ui_warn "Update mode — rolling back to previous build"
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
    ui_step "Snapshotting current runtime → $PREVIOUS_DIR"
    rm -rf "$PREVIOUS_DIR"
    ui_spin "Saving previous runtime snapshot..." cp -a "$RUNTIME_DIR" "$PREVIOUS_DIR"
    ui_ok "Previous build saved"
  fi

  mkdir -p "$RUNTIME_DIR/.next" "$DATA_DIR"

  if command -v rsync &>/dev/null; then
    ui_spin "Syncing standalone runtime..." rsync -a --delete .next/standalone/ "$RUNTIME_DIR/"
    ui_spin "Syncing static assets..." rsync -a --delete .next/static/ "$RUNTIME_DIR/.next/static/"
    [[ -d public ]] && ui_spin "Syncing public assets..." rsync -a --delete public/ "$RUNTIME_DIR/public/" || true
  else
    cp -a .next/standalone/. "$RUNTIME_DIR/"
    cp -a .next/static       "$RUNTIME_DIR/.next/"
    [[ -d public ]] && cp -a public "$RUNTIME_DIR/" || true
  fi

  git -C "$BUILD_DIR" rev-parse --short HEAD > "$RUNTIME_DIR/.install-commit" 2>/dev/null || true
  chown -R "$SERVICE_USER:$SERVICE_GROUP" "$RUNTIME_DIR" "$DATA_DIR"
  ui_ok "Runtime → $RUNTIME_DIR"
}

# ══════════════════════════════════════════════════════════════════
#  Phase: systemd unit + drop-in for tier MemoryMax
# ══════════════════════════════════════════════════════════════════
phase_systemd() {
  sec "Systemd service"

  backup_env_file
  write_env_file
  ui_ok "Env → $ENV_FILE (chmod 600)"

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
    ui_ok "MemoryMax=$mmax MemoryHigh=$mhigh (tier=$TIER)"
  else
    rm -f "$SERVICE_DROPIN_DIR/10-memory.conf"
    ui_ok "No memory cap (tier=medium+)"
  fi

  echo "$TIER" > "$TIER_CACHE" 2>/dev/null || true

  ui_spin "Reloading systemd units..." systemctl daemon-reload
  ui_spin "Enabling 9router service..." bash -c 'systemctl enable 9router &>/dev/null'
  ui_spin "Restarting 9router service..." systemctl restart 9router

  if ! wait_for_service 9router 15 2; then
    ui_warn "9router không start — auto-rollback nếu có snapshot"
    if [[ "$INSTALL_MODE" == "update" ]] && [[ -d "$PREVIOUS_DIR" ]]; then
      auto_rollback
      die "Update rolled back. Service đang chạy build cũ."
    fi
    die "9router không start được. Check: journalctl -u 9router -n 30"
  fi
  ui_ok "9router running on port $APP_PORT"
}

# ══════════════════════════════════════════════════════════════════
#  Phase: Caddy
# ══════════════════════════════════════════════════════════════════
phase_caddy() {
  [[ -z "$DOMAIN" ]] && return 0
  sec "Caddy + HTTPS"

  ui_spin "Installing Caddy repository prerequisites..." apt-get install -y -qq debian-keyring debian-archive-keyring apt-transport-https

  if ! command -v caddy &>/dev/null; then
    ui_step "Cài Caddy..."
    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' \
      | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' \
      | tee /etc/apt/sources.list.d/caddy-stable.list &>/dev/null
    ui_spin "Refreshing apt package lists..." apt-get update -qq
    ui_spin "Installing Caddy..." apt-get install -y -qq caddy
    ui_ok "Caddy installed"
  else
    ui_ok "Caddy $(caddy version | head -1) already installed"
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
  ui_ok "Caddyfile → $CADDYFILE"

  ui_spin "Enabling Caddy service..." bash -c 'systemctl enable caddy &>/dev/null'
  ui_spin "Restarting Caddy service..." systemctl restart caddy
  wait_for_service caddy 10 2 || ui_warn "Caddy không start nhanh — kiểm tra: journalctl -u caddy -n 30"
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
    ui_step "Downloading toolkit..."
    curl -fsSL "$INSTALL_URL" -o "$tmp" \
      || { wrn "Download failed; skipping self-install"; return 0; }
  else
    cp "$SCRIPT_PATH" "$tmp" \
      || { wrn "Copy failed; skipping self-install"; return 0; }
  fi
  chmod 755 "$tmp"
  mv "$tmp" "$INSTALLED_BIN"
  compute_invoke_base
  ui_ok "Toolkit available as: sudo 9router"
}

# ══════════════════════════════════════════════════════════════════
#  Phase: Cleanup
# ══════════════════════════════════════════════════════════════════
phase_cleanup() {
  sec "Cleanup"
  cd /
  rm -rf "$BUILD_DIR"
  [[ -n "${BUILD_LOG:-}" ]] && [[ -f "$BUILD_LOG" ]] && rm -f "$BUILD_LOG"
  rm -rf /tmp/next-* /tmp/turbopack-* /tmp/v8-compile-cache-* 2>/dev/null || true
  ui_spin "Pruning pnpm store..." bash -c 'pnpm store prune &>/dev/null' || true
  ui_spin "Cleaning npm cache..." bash -c 'npm cache clean --force &>/dev/null' || true
  ui_spin "Removing unused apt packages..." apt-get autoremove --purge -y -qq
  ui_spin "Cleaning apt cache..." apt-get clean -qq
  ui_ok "Build artifacts removed"
}

# ══════════════════════════════════════════════════════════════════
#  cmd_install / cmd_update — flow drivers
# ══════════════════════════════════════════════════════════════════
collect_install_inputs() {
  ui_panel "Setup wizard · 1/4" "Domain (bỏ trống nếu chỉ dùng IP)"$'\n'"Ví dụ: llm.example.com"
  DOMAIN=$(prompt_validated "Domain" "" valid_domain)

  ui_panel "Setup wizard · 2/4" "Mật khẩu đăng nhập 9Router"$'\n'"Enter = ChangeMe123!"
  while true; do
    INITIAL_PASSWORD=$(ask_secret "Password" "ChangeMe123!")
    env_value_ok "$INITIAL_PASSWORD" && break
    wrn "Password chỉ được dùng chữ, số và các ký tự: _ @ % + = : , . / ! -"
  done
  [[ "$INITIAL_PASSWORD" == "ChangeMe123!" ]] && wrn "Đang dùng mật khẩu mặc định. Chỉ nên dùng để test, đổi ngay sau khi cài."

  ui_panel "Setup wizard · 3/4" "Port ứng dụng"$'\n'"Enter = 20128"
  APP_PORT=$(prompt_validated "Port" "20128" valid_port)

  ui_panel "Setup wizard · 4/4" "Timezone"$'\n'"Enter = Asia/Ho_Chi_Minh"
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
  local endpoint
  [[ -n "$DOMAIN" ]] && endpoint="$DOMAIN" || endpoint="IP only · http://$VPS_IP:$APP_PORT"
  ui_panel "Update settings" \
    "Phiên bản hiện tại : $OLD_COMMIT"$'\n'"Domain             : $endpoint"$'\n'"Port               : $APP_PORT"$'\n'"Timezone           : $TZ_SET"$'\n\n'"Đổi mật khẩu đăng nhập (Enter để giữ nguyên)"
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
  local domain_line secrets_line
  [[ -n "$DOMAIN" ]] \
    && domain_line="$DOMAIN · Caddy + HTTPS tự động" \
    || domain_line="IP only · http://$VPS_IP:$APP_PORT"
  secrets_line=""
  [[ "$INSTALL_MODE" == "update" ]] && secrets_line=$'\n'"Secrets   : giữ nguyên từ cài đặt trước"
  ui_panel "Xác nhận" \
    "IP        : $VPS_IP"$'\n'"Domain    : $domain_line"$'\n'"Password  : (hidden)"$'\n'"Port      : $APP_PORT"$'\n'"Timezone  : $TZ_SET"$'\n'"Tier      : $TIER$secrets_line"
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
    ui_panel "Mode" "9Router đã được cài. Chuyển sang chế độ Update."
    collect_update_inputs
  else
    INSTALL_MODE="install"
    ui_panel "Mode" "Chế độ: Cài đặt mới"
    collect_install_inputs
  fi

  [[ -n "$DOMAIN" ]] && BASE_URL="https://$DOMAIN" || BASE_URL="http://$VPS_IP:$APP_PORT"
  confirm_summary

  START_TIME=$SECONDS
  if timedatectl set-timezone "$TZ_SET" 2>/dev/null; then ui_ok "Timezone → $TZ_SET"; else ui_warn "Không set được timezone"; fi

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
    ui_warn "9router chưa cài."
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
  if ui_has_gum; then
    {
      printf 'Metric\tValue\n'
      printf 'RSS 9router\t%s\n' "$(ps -o rss= -C node 2>/dev/null | head -1 | awk '{printf "%.0f MB",$1/1024}')"
      printf 'RAM free\t%s\n' "$(free -m | awk '/Mem:/ {print $7" MB"}')"
      printf 'Swap used\t%s\n' "$(free -m | awk '/Swap:/ {print $3"/"$2" MB"}')"
      printf 'Disk free\t%s\n' "$(df -BG / | awk 'NR==2 {print $4}')"
    } | ui_table --separator $'\t'
    ui_panel "Next commands" "Logs   : $INVOKE_BASE logs"$'\n'"Doctor : $INVOKE_BASE doctor"
  else
    echo -e "  RSS 9router : $(ps -o rss= -C node 2>/dev/null | head -1 | awk '{printf "%.0f MB",$1/1024}')"
    echo -e "  RAM free    : $(free -m | awk '/Mem:/ {print $7" MB"}')"
    echo -e "  Swap used   : $(free -m | awk '/Swap:/ {print $3"/"$2" MB"}')"
    echo -e "  Disk free   : $(df -BG / | awk 'NR==2 {print $4}')"
    hr
    echo -e "  Logs   : ${B}$INVOKE_BASE logs${N}"
    echo -e "  Doctor : ${B}$INVOKE_BASE doctor${N}"
  fi
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
  local n=0 ok_n=0 warn_n=0 fail_n=0
  if ui_has_gum; then
    local rows="" sev name msg fix
    for f in "${DOCTOR_FINDINGS[@]}"; do
      n=$((n+1))
      sev=$(echo "$f" | awk -F'|' '{print $1}')
      name=$(echo "$f" | awk -F'|' '{print $2}')
      msg=$(echo "$f" | awk -F'|' '{print $3}')
      fix=$(echo "$f" | awk -F'|' '{print $4}')
      case "$sev" in
        OK) ok_n=$((ok_n+1)) ;;
        WARN) warn_n=$((warn_n+1)) ;;
        FAIL) fail_n=$((fail_n+1)) ;;
      esac
      rows+="$sev"$'\t'"$name"$'\t'"$msg"$'\t'"$fix"$'\n'
    done
    {
      printf 'Severity\tCheck\tMessage\tFix\n'
      printf '%s' "$rows"
    } | ui_table --separator $'\t'
    ui_panel "Doctor summary" "Total: $n  ·  OK $ok_n  ·  WARN $warn_n  ·  FAIL $fail_n"$'\n'"Tier : $TIER"
  else
    hr
    echo -e "  ${W}9router doctor — tier=$TIER${N}"
    hr
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
  fi
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
  [[ ${#fixable[@]} -eq 0 ]] && { ui_ok "Không có gì cần fix"; return; }

  echo ""
  if ask_confirm "Áp dụng tất cả ${#fixable[@]} fix theo thứ tự?"; then
    for f in "${fixable[@]}"; do
      local name fix
      name=$(echo "$f" | awk -F'|' '{print $2}')
      fix=$(echo "$f" | awk -F'|' '{print $4}')
      ui_step "$name: $fix"
      bash -c "$fix" || ui_warn "fix '$name' returned non-zero"
    done
    ui_ok "All fixes attempted. Re-run doctor để verify."
  else
    for f in "${fixable[@]}"; do
      local name msg fix
      name=$(echo "$f" | awk -F'|' '{print $2}')
      msg=$(echo "$f" | awk -F'|' '{print $3}')
      fix=$(echo "$f" | awk -F'|' '{print $4}')
      ui_panel "$name" "$msg"$'\n'"fix: $fix"
      if ask_confirm "Apply this fix?"; then
        bash -c "$fix" || ui_warn "fix '$name' returned non-zero"
      else
        ui_step "Skipped"
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
  local done_title
  [[ "$INSTALL_MODE" == "update" ]] && done_title="Cập nhật hoàn tất! ($elapsed_fmt)" || done_title="Cài đặt hoàn tất! ($elapsed_fmt)"
  echo ""
  if ui_has_gum; then
    local build_lines=""
    if [[ "$INSTALL_MODE" == "update" ]]; then
      build_lines=$'\n'"Build cũ     : ${OLD_COMMIT:-không rõ}"$'\n'"Build mới    : $NEW_COMMIT"
    fi
    ui_panel "✔ $done_title" \
      "URL          : $BASE_URL"$'\n'"Password     : $INITIAL_PASSWORD"$'\n'"Tier         : $TIER$build_lines"$'\n\n'"Config       : $ENV_FILE"$'\n'"Runtime      : $RUNTIME_DIR"$'\n'"Previous     : $PREVIOUS_DIR (for rollback)"$'\n'"Data         : $DATA_DIR"$'\n\n'"Status       : $INVOKE_BASE status"$'\n'"Doctor       : $INVOKE_BASE doctor"$'\n'"Logs         : $INVOKE_BASE logs"$'\n'"Update       : $INVOKE_BASE update"$'\n'"Rollback     : $INVOKE_BASE rollback"$'\n'"Uninstall    : $INVOKE_BASE uninstall"
  else
    hr
    echo -e "${G}${W}"
    echo "   ✅  $done_title"
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
  fi

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
  ui_panel "Toolkit status" "Status : $installed_label"$'\n'"Tier   : $TIER"$'\n'"IP     : $VPS_IP"

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
    ui_hint
    choice=$(gum choose \
      --header "9router toolkit · installed · tier=$TIER" \
      --height 9 \
      --cursor "➤ " \
      --cursor.foreground "$UI_ACCENT" \
      --selected.foreground "$UI_ACCENT" \
      --header.foreground "$UI_PURPLE" \
      "⬆ Update (pull latest + redeploy)" \
      "◆ Doctor (health check)" \
      "● Status (one-screen summary)" \
      "▣ Logs (follow service)" \
      "◈ Tune (re-apply tier tuning)" \
      "↩ Rollback (restore previous build)" \
      "✖ Uninstall (data preserved)" \
      "Exit" </dev/tty)
  else
    ui_hint
    choice=$(gum choose \
      --header "9router toolkit · not installed · tier=$TIER" \
      --height 5 \
      --cursor "➤ " \
      --cursor.foreground "$UI_ACCENT" \
      --selected.foreground "$UI_ACCENT" \
      --header.foreground "$UI_PURPLE" \
      "● Install (fresh install)" \
      "◆ Doctor (health check)" \
      "● Status (system spec only)" \
      "Exit" </dev/tty)
  fi

  case "$choice" in
    *"Install"*)   cmd_install ;;
    *"Update"*)    cmd_update ;;
    *"Doctor"*)    cmd_doctor ;;
    *"Status"*)    cmd_status ;;
    *"Logs"*)      cmd_logs ;;
    *"Tune"*)      cmd_tune ;;
    *"Rollback"*)  cmd_rollback ;;
    *"Uninstall"*) cmd_uninstall ;;
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
