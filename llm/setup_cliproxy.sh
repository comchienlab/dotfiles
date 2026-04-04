#!/usr/bin/env bash
set -uo pipefail

# Guard: neu chay qua pipe (bash <(...)) stdin van la tty nen OK
# Neu ai do chay curl | bash → exit va huong dan
if [[ ! -t 0 ]]; then
  exec < /dev/tty 2>/dev/null || {
    echo "[WARN] Stdin khong phai TTY. Chay bang lenh sau:"
    echo ""
    echo "  bash <(curl -fsSL https://raw.githubusercontent.com/comchienlab/dotfiles/main/llm/setup_cliproxy.sh)"
    echo ""
    exit 1
  }
fi

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

INSTALL_DIR="/opt/cliproxyapi"
SERVICE_USER="cliproxyapi"
SERVICE_NAME="cliproxyapi"
AUTH_DIR="/opt/cliproxyapi/auth"
LOG_DIR="/var/log/cliproxyapi"
PORT=8317
GO_REQUIRED_MINOR=24
GO_VERSION="go1.24.3"
REPO_URL="https://github.com/router-for-me/CLIProxyAPIPlus.git"

log_info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }
log_step()  { echo -e "\n${CYAN}══════════════════════════════════════════════${NC}\n${BOLD} $*${NC}"; }

die() { log_error "$*"; exit 1; }

safe_read() {
  # Wrapper cho read tranh set -e exit
  local _var="$1"; shift
  local _prompt="$1"; shift
  local _default="${1:-}"
  local _val=""
  read -rp "$_prompt" _val </dev/tty || true
  printf -v "$_var" '%s' "${_val:-$_default}"
}

print_banner() {
  echo -e "${CYAN}"
  echo "████████████████████████████████████████"
  echo "█▄▄░███░██░██░█░▄▄░███░▄▄█░▄▄█▄░▄█░█░▀▄▄▀"
  echo "█▀▄███▄░██░██░█░▄▄░███░▄▄▀░▄▄░█░░████▀░▀░"
  echo "█▄▄▄███▄▄█▄▄█▄▄███▄███▄▄▄░█▄▄▄░▄██▄▄▄░███"
  echo "████████████████████████████████████████"
  echo -e "${NC}"
  echo -e "${BOLD}  CLIProxyAPI PLUS — All-in-One VPS Setup (No Docker)${NC}"
  echo -e "  Stack: Go binary + Caddy HTTPS + systemd + Web UI"
  echo -e "  Repo : github.com/router-for-me/CLIProxyAPIPlus"
  echo ""
}

check_root() {
  [[ $EUID -eq 0 ]] || die "Script phai chay voi quyen root. Dung: sudo bash $0"
}

detect_os() {
  [[ -f /etc/os-release ]] || die "Khong the detect OS."
  source /etc/os-release
  OS=$ID
  log_info "OS: $OS ${VERSION_ID:-unknown}"
  case $OS in
    ubuntu|debian) ;;
    *)
      log_warn "Script toi uu cho Ubuntu/Debian. OS hien tai: $OS"
      local _c=""
      safe_read _c "Tiep tuc? [y/N]: "
      [[ "$_c" =~ ^[Yy]$ ]] || { echo "Da huy."; exit 0; }
      ;;
  esac
}

prompt_config() {
  log_step "⚙️  Cau hinh"

  DOMAIN=""
  while [[ -z "$DOMAIN" ]]; do
    safe_read DOMAIN $'\nDomain cua ban (vi du: api.example.com): '
    [[ -z "$DOMAIN" ]] && log_warn "Domain khong duoc de trong."
  done

  echo ""
  echo "API keys dung de client xac thuc (Bearer token):"
  echo "Nhap it nhat 1 key. Enter trong de ket thuc."
  API_KEYS=()
  local i=1
  while true; do
    local _key=""
    safe_read _key "  Key $i (Enter de ket thuc): "
    if [[ -z "$_key" ]]; then
      [[ ${#API_KEYS[@]} -gt 0 ]] && break
      log_warn "Can it nhat 1 API key."
      continue
    fi
    API_KEYS+=("$_key")
    ((i++))
  done

  echo ""
  echo -e "${BOLD}Management Web UI${NC} — truy cap tai https://$DOMAIN/management.html"
  MGMT_PASSWORD=""
  while [[ -z "$MGMT_PASSWORD" ]]; do
    safe_read MGMT_PASSWORD "  Password dang nhap Web UI: "
    [[ -z "$MGMT_PASSWORD" ]] && log_warn "Password khong duoc de trong."
  done

  PROXY_URL=""
  safe_read PROXY_URL $'\nHTTP/SOCKS5 proxy URL (bo trong neu khong dung): '

  echo ""
  echo -e "${CYAN}────────────────── Tom tat cau hinh ──────────────────${NC}"
  echo -e "  Domain      : ${BOLD}https://$DOMAIN${NC}"
  echo -e "  Port noi bo : ${BOLD}127.0.0.1:$PORT${NC}"
  echo -e "  API Keys    : ${BOLD}${#API_KEYS[@]} key(s)${NC}"
  echo -e "  Web UI      : ${BOLD}https://$DOMAIN/management.html${NC}"
  [[ -n "$PROXY_URL" ]] && echo -e "  Proxy URL   : ${BOLD}$PROXY_URL${NC}"
  echo -e "${CYAN}──────────────────────────────────────────────────────${NC}"
  echo ""

  local _confirm=""
  safe_read _confirm "Tien hanh cai dat? [Y/n]: "
  if [[ "$_confirm" =~ ^[Nn]$ ]]; then
    echo "Da huy."
    exit 0
  fi
}

optimize_system() {
  log_step "🚀  Toi uu he thong VPS"

  log_info "Cap nhat package list..."
  apt-get update -qq

  log_info "Upgrade toan bo packages..."
  DEBIAN_FRONTEND=noninteractive apt-get upgrade -y -qq

  log_info "Cai them tien ich..."
  apt-get install -y -qq \
    htop curl wget git ca-certificates gnupg lsb-release \
    build-essential unzip jq net-tools ufw fail2ban

  apt-get autoremove -y -qq
  apt-get autoclean -qq

  local _total_ram_mb
  _total_ram_mb=$(( $(grep MemTotal /proc/meminfo | awk '{print $2}') / 1024 ))
  local _swap_size_mb=$(( _total_ram_mb <= 2048 ? 2048 : 1024 ))

  local _existing_swap=""
  _existing_swap=$(swapon --show=SIZE --noheadings 2>/dev/null | head -1 || true)

  if [[ -n "$_existing_swap" ]]; then
    log_info "Swap da ton tai ($_existing_swap) — bo qua."
  else
    log_info "Tao swap ${_swap_size_mb}MB (RAM: ${_total_ram_mb}MB)..."
    fallocate -l "${_swap_size_mb}M" /swapfile
    chmod 600 /swapfile
    mkswap /swapfile -q
    swapon /swapfile
    grep -q '/swapfile' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
    log_info "Swap ${_swap_size_mb}MB da kich hoat."
  fi

  sysctl -w vm.swappiness=10 >/dev/null || true
  sysctl -w vm.vfs_cache_pressure=50 >/dev/null || true
  grep -q 'vm.swappiness'         /etc/sysctl.conf || echo 'vm.swappiness=10'          >> /etc/sysctl.conf
  grep -q 'vm.vfs_cache_pressure' /etc/sysctl.conf || echo 'vm.vfs_cache_pressure=50' >> /etc/sysctl.conf

  grep -q 'net.core.somaxconn' /etc/sysctl.conf || cat >> /etc/sysctl.conf << 'SYSCTL'
net.core.somaxconn=65535
net.ipv4.tcp_max_syn_backlog=65535
net.ipv4.ip_local_port_range=1024 65535
net.ipv4.tcp_tw_reuse=1
net.ipv4.tcp_fin_timeout=15
net.core.netdev_max_backlog=65535
fs.file-max=200000
SYSCTL
  sysctl -p >/dev/null 2>&1 || true

  grep -q '# cliproxyapi-limits' /etc/security/limits.conf || cat >> /etc/security/limits.conf << 'LIMITS'
# cliproxyapi-limits
* soft nofile 65535
* hard nofile 65535
root soft nofile 65535
root hard nofile 65535
LIMITS

  systemctl enable fail2ban >/dev/null 2>&1 || true
  systemctl start  fail2ban >/dev/null 2>&1 || true

  log_info "✓ Toi uu he thong hoan tat."
}

install_go() {
  log_step "🔧  Kiem tra / Cai dat Go"

  export PATH=$PATH:/usr/local/go/bin

  local _need_install=true
  if command -v go &>/dev/null; then
    local _cur_major _cur_minor
    _cur_major=$(go version 2>/dev/null | grep -oP 'go\K[0-9]+' | head -1 || echo 0)
    _cur_minor=$(go version 2>/dev/null | grep -oP 'go[0-9]+\.\K[0-9]+' | head -1 || echo 0)
    if [[ "$_cur_major" -gt 1 ]] || [[ "$_cur_major" -eq 1 && "$_cur_minor" -ge $GO_REQUIRED_MINOR ]]; then
      log_info "Go da du phien ban: $(go version | awk '{print $3}') (>= 1.${GO_REQUIRED_MINOR}) — bo qua."
      _need_install=false
    else
      log_warn "Go hien tai $(go version | awk '{print $3}') < 1.${GO_REQUIRED_MINOR}. Cap nhat..."
    fi
  fi

  if $_need_install; then
    local _arch="amd64"
    [[ "$(uname -m)" == "aarch64" ]] && _arch="arm64"
    local _archive="${GO_VERSION}.linux-${_arch}.tar.gz"

    log_info "Tai ${GO_VERSION} (${_arch})..."
    wget -q "https://go.dev/dl/${_archive}" -O /tmp/go.tar.gz \
      || die "Khong the tai Go. Kiem tra ket noi mang."
    rm -rf /usr/local/go
    tar -C /usr/local -xzf /tmp/go.tar.gz
    rm /tmp/go.tar.gz

    echo 'export PATH=$PATH:/usr/local/go/bin' > /etc/profile.d/go.sh
    export PATH=$PATH:/usr/local/go/bin
    log_info "Go da cai: $(go version)"
  fi
}

install_caddy() {
  log_step "🌐  Cai dat Caddy"

  if command -v caddy &>/dev/null; then
    log_info "Caddy da co san: $(caddy version) — bo qua."
    return
  fi

  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' \
    | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg \
    || die "Khong the tai GPG key cua Caddy."
  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' \
    | tee /etc/apt/sources.list.d/caddy-stable.list
  apt-get update -qq
  apt-get install -y -qq caddy || die "Khong the cai Caddy."
  log_info "Caddy da cai: $(caddy version)"
}

build_cliproxyapi() {
  log_step "🏗️  Build CLIProxyAPI PLUS tu source"

  if ! id "$SERVICE_USER" &>/dev/null; then
    useradd -r -s /bin/bash -d "$INSTALL_DIR" -m "$SERVICE_USER"
    log_info "Tao service user: $SERVICE_USER"
  fi

  mkdir -p "$INSTALL_DIR" "$AUTH_DIR" "$LOG_DIR"

  if [[ -d "$INSTALL_DIR/repo/.git" ]]; then
    log_info "Repo da ton tai, git pull..."
    git -C "$INSTALL_DIR/repo" pull -q || log_warn "git pull that bai, dung cache hien tai."
  else
    log_info "Clone repo CLIProxyAPIPlus..."
    git clone -q "$REPO_URL" "$INSTALL_DIR/repo" \
      || die "Khong the clone repo: $REPO_URL"
  fi

  export PATH=$PATH:/usr/local/go/bin
  export GOPATH="/tmp/go-build-cliproxy"
  export GOCACHE="/tmp/go-cache-cliproxy"

  cd "$INSTALL_DIR/repo"
  log_info "Build binary (lan dau mat 1-3 phut)..."

  local _built=false
  if go build -o "$INSTALL_DIR/cli-proxy-api" ./cmd/server 2>/dev/null; then
    log_info "Build thanh cong (./cmd/server)."
    _built=true
  elif go build -o "$INSTALL_DIR/cli-proxy-api" . 2>/dev/null; then
    log_info "Build thanh cong (root package)."
    _built=true
  fi

  if ! $_built; then
    log_error "Build that bai! Chay thu cach debug:"
    log_error "  cd $INSTALL_DIR/repo && go build -v -o $INSTALL_DIR/cli-proxy-api ./cmd/server"
    die "Build CLIProxyAPI that bai."
  fi

  rm -rf /tmp/go-build-cliproxy /tmp/go-cache-cliproxy
  chmod +x "$INSTALL_DIR/cli-proxy-api"
  log_info "Binary: $INSTALL_DIR/cli-proxy-api"
}

create_config() {
  log_step "📝  Tao config.yaml"

  local _keys_block=""
  for _k in "${API_KEYS[@]}"; do
    _keys_block+="  - \"${_k}\""$'\n'
  done

  cat > "$INSTALL_DIR/config.yaml" << YAML
host: "127.0.0.1"
port: ${PORT}

commercial-mode: true

remote-management:
  allow-remote: true
  secret-key: "${MGMT_PASSWORD}"
  disable-control-panel: false

auth-dir: "${AUTH_DIR}"

api-keys:
${_keys_block}
debug: false
logging-to-file: true
logs-max-total-size-mb: 100
usage-statistics-enabled: true
proxy-url: "${PROXY_URL}"
request-retry: 3
max-retry-interval: 30
routing:
  strategy: "round-robin"

quota-exceeded:
  switch-project: true
  switch-preview-model: true
YAML

  chown -R "$SERVICE_USER:$SERVICE_USER" "$INSTALL_DIR" "$LOG_DIR"
  chmod 640 "$INSTALL_DIR/config.yaml"
  log_info "Config: $INSTALL_DIR/config.yaml"
}

create_systemd_service() {
  log_step "⚙️  Tao systemd service"

  cat > "/etc/systemd/system/${SERVICE_NAME}.service" << UNIT
[Unit]
Description=CLIProxyAPI PLUS Service
Documentation=https://help.router-for.me
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=${SERVICE_USER}
Group=${SERVICE_USER}
WorkingDirectory=${INSTALL_DIR}
ExecStart=${INSTALL_DIR}/cli-proxy-api --config ${INSTALL_DIR}/config.yaml
Restart=on-failure
RestartSec=5s
LimitNOFILE=65535
StandardOutput=append:${LOG_DIR}/stdout.log
StandardError=append:${LOG_DIR}/stderr.log
NoNewPrivileges=true
ProtectSystem=strict
ReadWritePaths=${INSTALL_DIR} ${LOG_DIR}
PrivateTmp=true

[Install]
WantedBy=multi-user.target
UNIT

  systemctl daemon-reload
  systemctl enable "$SERVICE_NAME"
  systemctl restart "$SERVICE_NAME" || true

  sleep 3
  if systemctl is-active --quiet "$SERVICE_NAME"; then
    log_info "CLIProxyAPI PLUS service dang chay ✓"
  else
    log_warn "Service chua start. Kiem tra: journalctl -u $SERVICE_NAME -n 50"
  fi
}

configure_caddy() {
  log_step "🔒  Cau hinh Caddy HTTPS cho $DOMAIN"

  mkdir -p /var/log/caddy

  cat > "/etc/caddy/Caddyfile" << CADDY
${DOMAIN} {
  reverse_proxy 127.0.0.1:${PORT}

  log {
    output file /var/log/caddy/cliproxyapi-access.log
    format json
  }

  header {
    Strict-Transport-Security "max-age=31536000; includeSubDomains"
    X-Content-Type-Options "nosniff"
    X-Frame-Options "SAMEORIGIN"
    -Server
  }
}
CADDY

  systemctl enable caddy
  systemctl restart caddy || true

  sleep 3
  if systemctl is-active --quiet caddy; then
    log_info "Caddy dang chay ✓"
  else
    log_warn "Caddy chua start. Kiem tra: journalctl -u caddy -n 50"
  fi
}

configure_firewall() {
  log_step "🔥  Cau hinh firewall"

  if command -v ufw &>/dev/null; then
    ufw default deny incoming  >/dev/null 2>&1 || true
    ufw default allow outgoing >/dev/null 2>&1 || true
    ufw allow ssh      >/dev/null 2>&1 || true
    ufw allow 80/tcp   >/dev/null 2>&1 || true
    ufw allow 443/tcp  >/dev/null 2>&1 || true
    ufw allow 443/udp  >/dev/null 2>&1 || true
    ufw --force enable >/dev/null 2>&1 || true
    log_info "UFW: default deny + cho phep SSH, 80, 443."
  else
    log_warn "UFW khong tim thay. Tu mo port 80/443 tren firewall cloud provider."
  fi
}

print_summary() {
  local _first_key="${API_KEYS[0]}"

  echo ""
  echo -e "${GREEN}╔═══════════════════════════════════════════════════════╗${NC}"
  echo -e "${GREEN}║     ✅  CLIProxyAPI PLUS — Cai dat hoan tat!          ║${NC}"
  echo -e "${GREEN}╚═══════════════════════════════════════════════════════╝${NC}"
  echo ""
  echo -e "  ${BOLD}API Endpoint:${NC}  https://${DOMAIN}/v1"
  echo -e "  ${BOLD}Web UI:${NC}        https://${DOMAIN}/management.html"
  echo -e "  ${BOLD}Web UI Pass:${NC}   ${MGMT_PASSWORD}"
  echo ""
  echo -e "  ${BOLD}RAM:${NC}    $(free -h | grep Mem  | awk '{print $2}')"
  echo -e "  ${BOLD}Swap:${NC}   $(free -h | grep Swap | awk '{print $2}')"
  echo ""
  echo -e "${BOLD}  Test API:${NC}"
  echo -e "  ${CYAN}curl https://${DOMAIN}/v1/models \\"
  echo -e "    -H \"Authorization: Bearer ${_first_key}\"${NC}"
  echo ""
  echo -e "${BOLD}  Login provider OAuth (--no-browser in URL ra terminal):${NC}"
  echo -e "  ${YELLOW}sudo -u ${SERVICE_USER} ${INSTALL_DIR}/cli-proxy-api --login --no-browser${NC}              # Gemini"
  echo -e "  ${YELLOW}sudo -u ${SERVICE_USER} ${INSTALL_DIR}/cli-proxy-api --claude-login --no-browser${NC}       # Claude"
  echo -e "  ${YELLOW}sudo -u ${SERVICE_USER} ${INSTALL_DIR}/cli-proxy-api --codex-login --no-browser${NC}        # OpenAI Codex"
  echo -e "  ${YELLOW}sudo -u ${SERVICE_USER} ${INSTALL_DIR}/cli-proxy-api --antigravity-login --no-browser${NC}  # Antigravity"
  echo -e "  ${YELLOW}sudo -u ${SERVICE_USER} ${INSTALL_DIR}/cli-proxy-api --qwen-login --no-browser${NC}         # Qwen"
  echo -e "  ${YELLOW}sudo -u ${SERVICE_USER} ${INSTALL_DIR}/cli-proxy-api --iflow-login --no-browser${NC}        # iFlow"
  echo ""
  echo -e "${BOLD}  Sau khi login xong, restart service:${NC}"
  echo -e "  systemctl restart ${SERVICE_NAME}"
  echo ""
  echo -e "${BOLD}  Quan ly service:${NC}"
  echo -e "  systemctl status ${SERVICE_NAME}"
  echo -e "  systemctl restart ${SERVICE_NAME}"
  echo -e "  journalctl -u ${SERVICE_NAME} -f"
  echo ""
  echo -e "  ${BOLD}Config:${NC}   $INSTALL_DIR/config.yaml"
  echo -e "  ${BOLD}Auth:${NC}     $AUTH_DIR/"
  echo -e "  ${BOLD}Logs:${NC}     $LOG_DIR/"
  echo ""
  echo -e "${YELLOW}  ⚠️  DNS: A record cua ${DOMAIN} phai tro ve IP VPS truoc khi Caddy cap SSL${NC}"
  echo -e "${YELLOW}  ⚠️  secret-key se tu bcrypt hash khi service khoi dong lan dau${NC}"
  echo ""
}

main() {
  print_banner
  check_root
  detect_os
  prompt_config
  optimize_system
  install_go
  install_caddy
  build_cliproxyapi
  create_config
  create_systemd_service
  configure_caddy
  configure_firewall
  print_summary
}

main "$@"
