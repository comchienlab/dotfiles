#!/usr/bin/env bash
set -euo pipefail

exec < /dev/tty

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
GO_VERSION="go1.24.3"
REPO_URL="https://github.com/router-for-me/CLIProxyAPIPlus.git"

log_info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }
log_step()  { echo -e "\n${CYAN}══════════════════════════════════════════${NC}\n${BOLD} $*${NC}"; }

print_banner() {
  echo -e "${CYAN}"
  echo "▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄"
  echo "█▄▄░███░██░██░▄▀▄░███░▄▄█░▄▄█▄░▄█░██░█▀▄▄▀"
  echo "█▀▄████░██░██░█▄█░███▄▄▀█░▄▄██░██░██░█░▀▀░"
  echo "█▄▄▄███▄▄█▄▄█▄███▄███▄▄▄█▄▄▄██▄███▄▄▄█░███"
  echo "▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀"
  echo -e "${NC}"
  echo -e "${BOLD}  CLIProxyAPI PLUS — All-in-One VPS Setup (No Docker)${NC}"
  echo -e "  Stack: Go binary + Caddy HTTPS + systemd + Web UI"
  echo -e "  Repo : github.com/router-for-me/CLIProxyAPIPlus"
  echo ""
}

check_root() {
  if [[ $EUID -ne 0 ]]; then
    log_error "Script phải chạy với quyền root. Dùng: sudo bash $0"
    exit 1
  fi
}

detect_os() {
  if [[ ! -f /etc/os-release ]]; then
    log_error "Không thể detect OS."
    exit 1
  fi
  source /etc/os-release
  OS=$ID
  log_info "OS: $OS $VERSION_ID"
  case $OS in
    ubuntu|debian) ;;
    *)
      log_warn "Script tối ưu cho Ubuntu/Debian. OS hiện tại: $OS"
      read -rp "Tiếp tục? [y/N]: " _c
      [[ "$_c" =~ ^[Yy]$ ]] || exit 1
      ;;
  esac
}

prompt_config() {
  log_step "⚙️  Cấu hình"

  while true; do
    read -rp $'\nDomain của bạn (ví dụ: api.example.com): ' DOMAIN
    [[ -n "$DOMAIN" ]] && break
    log_warn "Domain không được để trống."
  done

  echo ""
  echo "API keys dùng để client xác thực (Bearer token):"
  echo "Nhập ít nhất 1 key. Enter trống để kết thúc."
  API_KEYS=()
  local i=1
  while true; do
    read -rp "  Key $i (Enter để kết thúc): " _key
    [[ -z "$_key" && ${#API_KEYS[@]} -gt 0 ]] && break
    [[ -z "$_key" ]] && log_warn "Cần ít nhất 1 API key." && continue
    API_KEYS+=("$_key")
    ((i++))
  done

  echo ""
  echo -e "${BOLD}Management Web UI${NC} — truy cập tại https://$DOMAIN/management.html"
  while true; do
    read -rp "  Password đăng nhập Web UI: " MGMT_PASSWORD
    [[ -n "$MGMT_PASSWORD" ]] && break
    log_warn "Password không được để trống."
  done

  read -rp $'\nHTTP/SOCKS5 proxy URL (bỏ trống nếu không dùng): ' PROXY_URL
  PROXY_URL="${PROXY_URL:-}"

  echo ""
  echo -e "${CYAN}─────────────── Tóm tắt cấu hình ────────────────${NC}"
  echo -e "  Domain      : ${BOLD}https://$DOMAIN${NC}"
  echo -e "  Port nội bộ : ${BOLD}127.0.0.1:$PORT${NC}"
  echo -e "  API Keys    : ${BOLD}${#API_KEYS[@]} key(s)${NC}"
  echo -e "  Web UI      : ${BOLD}https://$DOMAIN/management.html${NC}"
  [[ -n "$PROXY_URL" ]] && echo -e "  Proxy URL   : ${BOLD}$PROXY_URL${NC}"
  echo -e "${CYAN}──────────────────────────────────────────────────${NC}"
  echo ""

  read -rp "Tiến hành cài đặt? [Y/n]: " _confirm
  [[ "$_confirm" =~ ^[Nn]$ ]] && echo "Đã hủy." && exit 0
}

optimize_system() {
  log_step "🚀  Tối ưu hệ thống VPS"

  log_info "Cập nhật package list..."
  apt-get update -qq

  log_info "Upgrade toàn bộ packages..."
  DEBIAN_FRONTEND=noninteractive apt-get upgrade -y -qq

  log_info "Cài thêm tiện ích hữu dụng..."
  apt-get install -y -qq \
    htop curl wget git ca-certificates gnupg lsb-release \
    build-essential unzip jq net-tools ufw fail2ban

  log_info "Dọn dẹp packages không cần thiết..."
  apt-get autoremove -y -qq
  apt-get autoclean -qq

  local _total_ram_kb
  _total_ram_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
  local _total_ram_mb=$(( _total_ram_kb / 1024 ))
  local _swap_size_mb

  if (( _total_ram_mb <= 2048 )); then
    _swap_size_mb=2048
  else
    _swap_size_mb=1024
  fi

  local _existing_swap
  _existing_swap=$(swapon --show=SIZE --noheadings 2>/dev/null | head -1 || echo "")

  if [[ -n "$_existing_swap" ]]; then
    log_info "Swap đã tồn tại: $_existing_swap — bỏ qua."
  else
    log_info "Tạo swap ${_swap_size_mb}MB (RAM hiện tại: ${_total_ram_mb}MB)..."
    fallocate -l "${_swap_size_mb}M" /swapfile
    chmod 600 /swapfile
    mkswap /swapfile -q
    swapon /swapfile
    grep -q '/swapfile' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
    log_info "Swap ${_swap_size_mb}MB đã kích hoạt và persistent."
  fi

  log_info "Cấu hình swappiness = 10..."
  sysctl -w vm.swappiness=10 >/dev/null
  sysctl -w vm.vfs_cache_pressure=50 >/dev/null
  grep -q 'vm.swappiness' /etc/sysctl.conf       || echo 'vm.swappiness=10'          >> /etc/sysctl.conf
  grep -q 'vm.vfs_cache_pressure' /etc/sysctl.conf || echo 'vm.vfs_cache_pressure=50' >> /etc/sysctl.conf

  log_info "Tuning network kernel parameters..."
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

  log_info "Tăng giới hạn file descriptor..."
  grep -q '# cliproxyapi-limits' /etc/security/limits.conf || cat >> /etc/security/limits.conf << 'LIMITS'
# cliproxyapi-limits
* soft nofile 65535
* hard nofile 65535
root soft nofile 65535
root hard nofile 65535
LIMITS

  log_info "Cấu hình fail2ban bảo vệ SSH..."
  systemctl enable fail2ban >/dev/null 2>&1 || true
  systemctl start  fail2ban >/dev/null 2>&1 || true

  log_info "✓ Tối ưu hệ thống hoàn tất."
}

install_go() {
  log_step "🔧  Kiểm tra / Cài đặt Go"

  export PATH=$PATH:/usr/local/go/bin

  if command -v go &>/dev/null; then
    local _cur
    _cur=$(go version | awk '{print $3}')
    log_info "Go đã có sẵn: $_cur — bỏ qua cài đặt."
    return
  fi

  local _arch="amd64"
  [[ "$(uname -m)" == "aarch64" ]] && _arch="arm64"
  local _archive="${GO_VERSION}.linux-${_arch}.tar.gz"

  log_info "Tải ${GO_VERSION} (${_arch})..."
  wget -q "https://go.dev/dl/${_archive}" -O /tmp/go.tar.gz

  rm -rf /usr/local/go
  tar -C /usr/local -xzf /tmp/go.tar.gz
  rm /tmp/go.tar.gz

  echo 'export PATH=$PATH:/usr/local/go/bin' > /etc/profile.d/go.sh
  log_info "Go đã cài: $(go version)"
}

install_caddy() {
  log_step "🌐  Cài đặt Caddy"

  if command -v caddy &>/dev/null; then
    log_info "Caddy đã có sẵn: $(caddy version) — bỏ qua."
    return
  fi

  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' \
    | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg

  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' \
    | tee /etc/apt/sources.list.d/caddy-stable.list

  apt-get update -qq
  apt-get install -y -qq caddy
  log_info "Caddy đã cài: $(caddy version)"
}

build_cliproxyapi() {
  log_step "🏗️  Build CLIProxyAPI PLUS từ source"

  if ! id "$SERVICE_USER" &>/dev/null; then
    useradd -r -s /bin/bash -d "$INSTALL_DIR" -m "$SERVICE_USER"
    log_info "Tạo service user: $SERVICE_USER"
  fi

  mkdir -p "$INSTALL_DIR" "$AUTH_DIR" "$LOG_DIR"

  if [[ -d "$INSTALL_DIR/repo/.git" ]]; then
    log_info "Repo đã tồn tại, tiến hành git pull..."
    cd "$INSTALL_DIR/repo"
    git pull -q
  else
    log_info "Clone repo CLIProxyAPIPlus..."
    git clone -q "$REPO_URL" "$INSTALL_DIR/repo"
    cd "$INSTALL_DIR/repo"
  fi

  export PATH=$PATH:/usr/local/go/bin
  export GOPATH="/tmp/go-build-cliproxy"
  export GOCACHE="/tmp/go-cache-cliproxy"

  log_info "Đang build binary (lần đầu có thể mất 1-3 phút)..."

  if go build -o "$INSTALL_DIR/cli-proxy-api" ./cmd/server 2>/dev/null; then
    log_info "Build thành công (./cmd/server)."
  elif go build -o "$INSTALL_DIR/cli-proxy-api" . 2>/dev/null; then
    log_info "Build thành công (root package)."
  else
    log_error "Build thất bại! Chạy thủ công để xem lỗi:"
    log_error "  cd $INSTALL_DIR/repo && go build -v -o $INSTALL_DIR/cli-proxy-api ./cmd/server"
    exit 1
  fi

  rm -rf /tmp/go-build-cliproxy /tmp/go-cache-cliproxy

  chmod +x "$INSTALL_DIR/cli-proxy-api"
  log_info "Binary: $INSTALL_DIR/cli-proxy-api"
}

create_config() {
  log_step "📝  Tạo config.yaml"

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
  log_step "⚙️  Tạo systemd service"

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
  systemctl restart "$SERVICE_NAME"

  sleep 2
  if systemctl is-active --quiet "$SERVICE_NAME"; then
    log_info "CLIProxyAPI PLUS service đang chạy ✓"
  else
    log_warn "Service có thể chưa start. Kiểm tra: journalctl -u $SERVICE_NAME -n 50"
  fi
}

configure_caddy() {
  log_step "🔒  Cấu hình Caddy HTTPS cho $DOMAIN"

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
  systemctl restart caddy

  sleep 2
  if systemctl is-active --quiet caddy; then
    log_info "Caddy đang chạy ✓"
  else
    log_warn "Caddy chưa start. Kiểm tra: journalctl -u caddy -n 50"
  fi
}

configure_firewall() {
  log_step "🔥  Cấu hình firewall"

  if command -v ufw &>/dev/null; then
    ufw default deny incoming >/dev/null 2>&1 || true
    ufw default allow outgoing >/dev/null 2>&1 || true
    ufw allow ssh    >/dev/null 2>&1 || true
    ufw allow 80/tcp >/dev/null 2>&1 || true
    ufw allow 443/tcp>/dev/null 2>&1 || true
    ufw allow 443/udp>/dev/null 2>&1 || true
    ufw --force enable >/dev/null 2>&1 || true
    log_info "UFW: default deny + cho phép SSH, 80, 443."
  else
    log_warn "UFW không tìm thấy. Tự mở port 80/443 trên firewall của cloud provider."
  fi
}

print_summary() {
  local _first_key="${API_KEYS[0]}"
  local _swap_info
  _swap_info=$(free -h | grep Swap | awk '{print $2}')

  echo ""
  echo -e "${GREEN}╔══════════════════════════════════════════════════════╗${NC}"
  echo -e "${GREEN}║     ✅  CLIProxyAPI PLUS — Cài đặt hoàn tất!        ║${NC}"
  echo -e "${GREEN}╚══════════════════════════════════════════════════════╝${NC}"
  echo ""
  echo -e "  ${BOLD}API Endpoint:${NC}  https://${DOMAIN}/v1"
  echo -e "  ${BOLD}Web UI:${NC}        https://${DOMAIN}/management.html"
  echo -e "  ${BOLD}Web UI Pass:${NC}   ${MGMT_PASSWORD}"
  echo ""
  echo -e "  ${BOLD}RAM:${NC}    $(free -h | grep Mem  | awk '{print $2}')"
  echo -e "  ${BOLD}Swap:${NC}   ${_swap_info}"
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
  echo -e "${BOLD}  Quản lý service:${NC}"
  echo -e "  systemctl status ${SERVICE_NAME}"
  echo -e "  systemctl restart ${SERVICE_NAME}"
  echo -e "  journalctl -u ${SERVICE_NAME} -f"
  echo ""
  echo -e "  ${BOLD}Config:${NC}   $INSTALL_DIR/config.yaml"
  echo -e "  ${BOLD}Auth:${NC}     $AUTH_DIR/"
  echo -e "  ${BOLD}Logs:${NC}     $LOG_DIR/"
  echo ""
  echo -e "${YELLOW}  ⚠️  DNS: A record của ${DOMAIN} phải trỏ về IP VPS trước khi Caddy cấp SSL${NC}"
  echo -e "${YELLOW}  ⚠️  secret-key trong config.yaml sẽ tự bcrypt hash khi service khởi động${NC}"
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
