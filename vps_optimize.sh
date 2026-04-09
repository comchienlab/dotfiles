#!/usr/bin/env bash
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

info()    { echo -e "${CYAN}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
err()     { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

[[ $EUID -ne 0 ]] && err "Run as root: sudo bash $0"

SWAP_SIZE="${1:-2G}"

banner() {
  echo -e "${CYAN}"
  echo "╔══════════════════════════════════════════╗"
  echo "║   VPS Optimize - Ubuntu 24.04 LTS        ║"
  echo "║   Multi-task performance tuning          ║"
  echo "╚══════════════════════════════════════════╝"
  echo -e "${NC}"
}

step_update() {
  info "Updating system packages..."
  apt update -qq && apt upgrade -y -qq && apt autoremove -y -qq
  success "System updated"
}

step_install_tools() {
  info "Installing monitoring tools..."
  apt install -y -qq htop iftop curl wget unzip ufw fail2ban
  success "Tools installed: htop, iftop, ufw, fail2ban"
}

step_swap() {
  if swapon --show | grep -q '/swapfile'; then
    warn "Swapfile already exists, skipping"
    return
  fi
  info "Creating swap: $SWAP_SIZE..."
  fallocate -l "$SWAP_SIZE" /swapfile
  chmod 600 /swapfile
  mkswap /swapfile
  swapon /swapfile
  grep -q '/swapfile' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
  success "Swap $SWAP_SIZE created and enabled"
}

step_sysctl() {
  info "Applying sysctl optimizations..."
  cat > /etc/sysctl.d/99-vps-optimize.conf <<'EOF'
net.core.somaxconn = 65535
net.core.netdev_max_backlog = 65536
net.ipv4.tcp_max_syn_backlog = 65535
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_keepalive_time = 300
net.ipv4.tcp_keepalive_probes = 5
net.ipv4.tcp_keepalive_intvl = 15
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
net.ipv4.tcp_fastopen = 3
fs.file-max = 2097152
fs.inotify.max_user_watches = 524288
vm.swappiness = 10
vm.dirty_ratio = 15
vm.dirty_background_ratio = 5
vm.overcommit_memory = 1
kernel.pid_max = 4194304
EOF
  sysctl -p /etc/sysctl.d/99-vps-optimize.conf > /dev/null
  success "Sysctl tuning applied (BBR, TCP, FS, VM)"
}

step_limits() {
  info "Setting system file descriptor limits..."
  cat > /etc/security/limits.d/99-vps-optimize.conf <<'EOF'
* soft nofile 65535
* hard nofile 65535
* soft nproc  65535
* hard nproc  65535
root soft nofile 65535
root hard nofile 65535
EOF
  grep -q 'pam_limits' /etc/pam.d/common-session \
    || echo 'session required pam_limits.so' >> /etc/pam.d/common-session
  success "File descriptor limits set to 65535"
}

step_ufw() {
  info "Configuring UFW firewall..."
  ufw --force reset > /dev/null
  ufw default deny incoming  > /dev/null
  ufw default allow outgoing > /dev/null
  ufw allow OpenSSH          > /dev/null
  ufw allow 80/tcp           > /dev/null
  ufw allow 443/tcp          > /dev/null
  ufw --force enable         > /dev/null
  success "UFW enabled: SSH, HTTP, HTTPS allowed"
}

step_fail2ban() {
  info "Configuring Fail2ban..."
  cat > /etc/fail2ban/jail.local <<'EOF'
[DEFAULT]
bantime  = 3600
findtime = 600
maxretry = 5

[sshd]
enabled = true
port    = ssh
logpath = %(sshd_log)s
backend = systemd
EOF
  systemctl enable --now fail2ban > /dev/null 2>&1
  success "Fail2ban configured and running"
}

step_systemd_tune() {
  info "Tuning systemd journal & timeout..."
  mkdir -p /etc/systemd/journald.conf.d
  cat > /etc/systemd/journald.conf.d/99-vps.conf <<'EOF'
[Journal]
SystemMaxUse=200M
RuntimeMaxUse=50M
EOF
  sed -i 's/#DefaultTimeoutStopSec=.*/DefaultTimeoutStopSec=10s/' /etc/systemd/system.conf 2>/dev/null || true
  systemctl restart systemd-journald
  success "Journal capped at 200M, stop timeout = 10s"
}

step_disable_unused() {
  info "Disabling unused services..."
  SERVICES=(bluetooth ModemManager avahi-daemon apport)
  for svc in "${SERVICES[@]}"; do
    if systemctl list-unit-files --state=enabled | grep -q "^${svc}"; then
      systemctl disable --now "$svc" > /dev/null 2>&1 && info "  Disabled: $svc" || true
    fi
  done
  success "Unused services disabled"
}

step_bbr_check() {
  info "Verifying TCP BBR..."
  modprobe tcp_bbr 2>/dev/null || true
  CURRENT=$(sysctl net.ipv4.tcp_congestion_control 2>/dev/null | awk '{print $3}')
  if [[ "$CURRENT" == "bbr" ]]; then
    success "TCP BBR active"
  else
    warn "BBR not active (current: $CURRENT) - may need reboot"
  fi
}

summary() {
  echo ""
  echo -e "${GREEN}══════════════════════════════════════════${NC}"
  echo -e "${GREEN}  Optimization complete!${NC}"
  echo -e "${GREEN}══════════════════════════════════════════${NC}"
  echo -e "  Swap      : $(free -h | awk '/Swap/{print $2}')"
  echo -e "  BBR       : $(sysctl -n net.ipv4.tcp_congestion_control)"
  echo -e "  nofile    : $(ulimit -n)"
  echo -e "  UFW       : $(ufw status | head -1)"
  echo -e "  Fail2ban  : $(systemctl is-active fail2ban)"
  echo ""
  warn "Reboot recommended to apply all changes: sudo reboot"
}

main() {
  banner
  step_update
  step_install_tools
  step_swap
  step_sysctl
  step_limits
  step_ufw
  step_fail2ban
  step_systemd_tune
  step_disable_unused
  step_bbr_check
  summary
}

main
