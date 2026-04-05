#!/bin/bash

##############################################################################
# CLIProxyAPI PLUS - All-in-One Deployment Script
# Target: Ubuntu/Debian Linux (amd64, arm64)
# Stack: Go binary + Caddy (HTTPS) + systemd + UFW
##############################################################################

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
REPO_URL="https://github.com/router-for-me/CLIProxyAPIPlus.git"
SERVICE_NAME="cliproxyapi-plus"
SERVICE_USER="cliproxy"
WORK_DIR="/opt/cliproxyapi-plus"
CONFIG_DIR="/etc/cliproxyapi-plus"
LOG_DIR="/var/log/cliproxyapi-plus"
BIN_NAME="cli-proxy-api-plus"
MIN_GO_VERSION="1.24"

##############################################################################
# Utilities
##############################################################################

log_info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

log_success() {
    echo -e "${GREEN}[✓]${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*"
    exit 1
}

separator() {
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

##############################################################################
# Pre-flight checks
##############################################################################

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "Script must be run as root. Use: sudo bash deploy-cliproxyapi-plus.sh"
    fi
}

check_os() {
    if ! grep -qE "Ubuntu|Debian" /etc/os-release; then
        log_error "This script supports Ubuntu/Debian only. Current OS: $(grep '^NAME=' /etc/os-release)"
    fi
    log_success "OS check passed"
}

detect_arch() {
    ARCH=$(uname -m)
    case "$ARCH" in
        x86_64) GO_ARCH="amd64" ;;
        aarch64) GO_ARCH="arm64" ;;
        *) log_error "Unsupported architecture: $ARCH" ;;
    esac
    log_success "Architecture detected: $ARCH ($GO_ARCH)"
}

##############################################################################
# Input Collection
##############################################################################

collect_inputs() {
    separator
    echo -e "${BLUE}CLIProxyAPI PLUS Deployment Configuration${NC}"
    separator
    echo ""

    # Domain (required)
    while true; do
        echo -n "Enter domain (required, e.g., api.example.com): "
        read -r DOMAIN
        if [[ -z "$DOMAIN" ]]; then
            log_warn "Domain cannot be empty"
            continue
        fi
        if [[ ! "$DOMAIN" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$ ]]; then
            log_warn "Invalid domain format"
            continue
        fi
        log_success "Domain set: $DOMAIN"
        break
    done
    echo ""

    # API Keys (at least 1 required)
    API_KEYS=""
    while true; do
        echo "Enter API keys (separate multiple with comma, e.g., key1,key2,key3):"
        echo -n "> "
        read -r API_INPUT
        if [[ -z "$API_INPUT" ]]; then
            log_warn "At least one API key is required"
            continue
        fi
        # Basic validation: no spaces, no empty values
        if [[ "$API_INPUT" =~ \ |,, ]]; then
            log_warn "Invalid format (spaces or empty values)"
            continue
        fi
        API_KEYS="$API_INPUT"
        log_success "API keys set ($(echo "$API_KEYS" | tr ',' '\n' | wc -l) key(s))"
        break
    done
    echo ""

    # Management Web UI Password (required)
    while true; do
        echo -n "Enter Management Web UI password (min 8 chars): "
        read -rs UI_PASSWORD
        echo ""
        if [[ ${#UI_PASSWORD} -lt 8 ]]; then
            log_warn "Password must be at least 8 characters"
            continue
        fi
        echo -n "Confirm password: "
        read -rs UI_PASSWORD_CONFIRM
        echo ""
        if [[ "$UI_PASSWORD" != "$UI_PASSWORD_CONFIRM" ]]; then
            log_warn "Passwords do not match"
            continue
        fi
        log_success "Password set"
        break
    done
    echo ""

    # Proxy URL (optional)
    echo -n "Enter Proxy URL (optional, press Enter to skip): "
    read -r PROXY_URL
    if [[ -n "$PROXY_URL" ]]; then
        log_success "Proxy URL set: $PROXY_URL"
    else
        PROXY_URL=""
        log_success "No proxy URL configured"
    fi
    echo ""
}

##############################################################################
# Summary & Confirmation
##############################################################################

show_summary() {
    separator
    echo -e "${BLUE}Deployment Summary${NC}"
    separator
    echo "Domain                  : $DOMAIN"
    echo "API Keys                : $(echo "$API_KEYS" | tr ',' '\n' | wc -l) key(s)"
    echo "Management Password     : ••••••••"
    echo "Proxy URL               : ${PROXY_URL:-(not set)}"
    echo "Service Name            : $SERVICE_NAME"
    echo "Service User            : $SERVICE_USER"
    echo "Work Directory          : $WORK_DIR"
    echo "Config Directory        : $CONFIG_DIR"
    echo "Architecture            : $ARCH ($GO_ARCH)"
    separator
    echo ""

    # Ask for confirmation
    while true; do
        echo -n "Proceed with deployment? (yes/no): "
        read -r CONFIRM
        case "$CONFIRM" in
            yes|YES|y|Y)
                log_success "Deployment confirmed"
                break
                ;;
            no|NO|n|N)
                log_error "Deployment cancelled by user"
                ;;
            *)
                log_warn "Please answer yes or no"
                ;;
        esac
    done
    echo ""
}

##############################################################################
# Installation Functions
##############################################################################

install_go() {
    log_info "Checking Go installation..."
    
    if command -v go &> /dev/null; then
        GO_VERSION=$(go version | awk '{print $3}' | sed 's/go//')
        log_success "Go is already installed: $GO_VERSION"
        return 0
    fi

    log_info "Installing Go >= $MIN_GO_VERSION..."
    
    # Get latest Go release
    LATEST_GO=$(curl -s https://api.github.com/repos/golang/go/releases | grep -oP '"tag_name": "\Kgo[0-9.]+" ' | head -1 | tr -d '"go ')
    
    if [[ -z "$LATEST_GO" ]]; then
        log_error "Could not determine latest Go version"
    fi

    GO_URL="https://go.dev/dl/go${LATEST_GO}.linux-${GO_ARCH}.tar.gz"
    
    log_info "Downloading Go from: $GO_URL"
    curl -fsSL "$GO_URL" -o /tmp/go.tar.gz
    
    rm -rf /usr/local/go
    tar -C /usr/local -xzf /tmp/go.tar.gz
    rm -f /tmp/go.tar.gz
    
    # Add to PATH
    export PATH="/usr/local/go/bin:$PATH"
    echo 'export PATH="/usr/local/go/bin:$PATH"' >> /root/.bashrc
    
    log_success "Go $LATEST_GO installed"
}

install_caddy() {
    log_info "Checking Caddy installation..."
    
    if command -v caddy &> /dev/null; then
        CADDY_VERSION=$(caddy version)
        log_success "Caddy is already installed: $CADDY_VERSION"
        return 0
    fi

    log_info "Installing Caddy via apt..."
    
    # Add Caddy apt repo
    curl -fsSL https://apt.fury.io/caddy/gpg.key | gpg --yes --dearmor -o /usr/share/keyrings/caddy-fury.gpg
    echo "deb [signed-by=/usr/share/keyrings/caddy-fury.gpg] https://apt.fury.io/caddy/ /" > /etc/apt/sources.list.d/caddy-fury.list
    
    apt-get update
    apt-get install -y caddy
    
    log_success "Caddy installed"
}

install_dependencies() {
    log_info "Installing system dependencies..."
    
    apt-get update
    apt-get install -y \
        git \
        curl \
        wget \
        build-essential \
        ufw \
        fail2ban \
        htop
    
    log_success "Dependencies installed"
}

clone_and_build() {
    log_info "Cloning CLIProxyAPI PLUS repository..."
    
    rm -rf /tmp/cliproxyapi-build
    git clone --depth 1 "$REPO_URL" /tmp/cliproxyapi-build
    
    cd /tmp/cliproxyapi-build
    
    log_info "Building CLIProxyAPI PLUS..."
    go build -o "$BIN_NAME" .
    
    if [[ ! -f "$BIN_NAME" ]]; then
        log_error "Build failed: binary not found"
    fi
    
    log_success "Build completed: $BIN_NAME"
    
    # Move to work directory
    mkdir -p "$WORK_DIR"
    mv "$BIN_NAME" "$WORK_DIR/"
    
    cd - > /dev/null
}

create_service_user() {
    log_info "Creating service user: $SERVICE_USER..."
    
    if id "$SERVICE_USER" &>/dev/null; then
        log_success "User $SERVICE_USER already exists"
        return 0
    fi
    
    useradd -r -s /bin/false -d "$WORK_DIR" "$SERVICE_USER"
    log_success "User $SERVICE_USER created"
}

create_directories() {
    log_info "Creating directories..."
    
    mkdir -p "$CONFIG_DIR"
    mkdir -p "$LOG_DIR"
    mkdir -p "$WORK_DIR"
    
    chown -R "$SERVICE_USER:$SERVICE_USER" "$WORK_DIR" "$LOG_DIR"
    chmod 755 "$CONFIG_DIR" "$LOG_DIR"
    
    log_success "Directories created and configured"
}

create_config_yaml() {
    log_info "Creating configuration file..."
    
    # Convert comma-separated keys to YAML array
    KEYS_YAML=$(echo "$API_KEYS" | tr ',' '\n' | sed 's/^/      - /' | sed 's/^  $//')
    
    cat > "$CONFIG_DIR/config.yaml" << EOF
server:
  host: "127.0.0.1"
  port: 8080
  read_timeout: 30s
  write_timeout: 30s

auth:
  api_keys:
$KEYS_YAML

web_ui:
  password: "$UI_PASSWORD"

proxy:
  url: "${PROXY_URL}"

logging:
  level: "info"
  format: "json"
  output: "$LOG_DIR/cliproxyapi.log"
EOF

    chown "$SERVICE_USER:$SERVICE_USER" "$CONFIG_DIR/config.yaml"
    chmod 600 "$CONFIG_DIR/config.yaml"
    
    log_success "Config file created: $CONFIG_DIR/config.yaml"
}

create_systemd_service() {
    log_info "Creating systemd service..."
    
    cat > "/etc/systemd/system/${SERVICE_NAME}.service" << EOF
[Unit]
Description=CLIProxyAPI PLUS Service
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=$SERVICE_USER
Group=$SERVICE_USER
WorkingDirectory=$WORK_DIR
ExecStart=$WORK_DIR/$BIN_NAME -config=$CONFIG_DIR/config.yaml
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal
SyslogIdentifier=$SERVICE_NAME

# Security & resource limits
PrivateTmp=yes
ProtectSystem=strict
ProtectHome=yes
NoNewPrivileges=true
LimitNOFILE=65536
LimitNPROC=4096

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable "$SERVICE_NAME"
    
    log_success "Systemd service created and enabled"
}

create_caddy_config() {
    log_info "Creating Caddy configuration..."
    
    cat > "/etc/caddy/Caddyfile" << EOF
{
    acme_ca https://acme-v02.api.letsencrypt.org/directory
}

$DOMAIN {
    encode gzip

    # Reverse proxy to CLIProxyAPI PLUS
    reverse_proxy 127.0.0.1:8080 {
        header_up X-Forwarded-For {http.request.remote}
        header_up X-Forwarded-Proto {http.request.scheme}
    }

    # Logging
    log {
        output file $LOG_DIR/caddy.log {
            roll_size 100mb
            roll_keep 5
        }
        format json
    }
}
EOF

    systemctl reload caddy
    
    log_success "Caddy configuration updated"
}

optimize_system() {
    log_info "Optimizing system configuration..."
    
    # Create/extend swap if not enough
    SWAP_SIZE=$(free | grep Swap | awk '{print $2}')
    if [[ $SWAP_SIZE -lt 2097152 ]]; then
        log_info "Creating 2GB swap..."
        fallocate -l 2G /swapfile
        chmod 600 /swapfile
        mkswap /swapfile
        swapon /swapfile
        echo '/swapfile none swap sw 0 0' >> /etc/fstab
        log_success "Swap created"
    fi
    
    # Network optimization
    log_info "Optimizing network parameters..."
    cat >> /etc/sysctl.conf << 'SYSCTL_EOF'

# CLIProxyAPI PLUS network optimization
net.core.somaxconn=65536
net.ipv4.tcp_max_syn_backlog=65536
net.ipv4.tcp_fin_timeout=30
net.ipv4.tcp_keepalive_time=300
net.core.netdev_max_backlog=65536
SYSCTL_EOF

    sysctl -p > /dev/null
    
    # File descriptor limits
    log_info "Increasing file descriptor limits..."
    cat >> /etc/security/limits.conf << 'LIMITS_EOF'

* soft nofile 65536
* hard nofile 65536
* soft nproc 4096
* hard nproc 4096
LIMITS_EOF

    log_success "System optimization completed"
}

setup_fail2ban() {
    log_info "Configuring fail2ban..."
    
    systemctl start fail2ban
    systemctl enable fail2ban
    
    # Create jail for SSH
    cat > /etc/fail2ban/jail.local << 'FAIL2BAN_EOF'
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 5

[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log
FAIL2BAN_EOF

    systemctl restart fail2ban
    log_success "fail2ban configured"
}

setup_firewall() {
    log_info "Configuring UFW firewall..."
    
    # Reset and enable UFW
    ufw --force enable
    ufw default deny incoming
    ufw default allow outgoing
    
    # Allow SSH, HTTP, HTTPS
    ufw allow 22/tcp comment "SSH"
    ufw allow 80/tcp comment "HTTP"
    ufw allow 443/tcp comment "HTTPS"
    
    log_success "UFW firewall configured"
}

##############################################################################
# Main Execution
##############################################################################

main() {
    clear
    separator
    echo -e "${BLUE}CLIProxyAPI PLUS - All-in-One Deployment${NC}"
    separator
    echo ""
    
    # Pre-flight checks
    check_root
    check_os
    detect_arch
    
    # Collect configuration
    collect_inputs
    show_summary
    
    # Installation phase
    separator
    echo -e "${BLUE}Starting Deployment...${NC}"
    separator
    echo ""
    
    install_dependencies
    install_go
    install_caddy
    clone_and_build
    create_service_user
    create_directories
    create_config_yaml
    create_systemd_service
    create_caddy_config
    optimize_system
    setup_fail2ban
    setup_firewall
    
    # Start services
    log_info "Starting services..."
    systemctl start "$SERVICE_NAME"
    sleep 2
    
    if systemctl is-active --quiet "$SERVICE_NAME"; then
        log_success "Service started successfully"
    else
        log_error "Service failed to start. Check logs: journalctl -u $SERVICE_NAME -n 50"
    fi
    
    # Final summary
    echo ""
    separator
    echo -e "${GREEN}✓ Deployment Complete!${NC}"
    separator
    echo ""
    
    # Test API endpoint
    TEST_KEY=$(echo "$API_KEYS" | cut -d',' -f1)
    API_URL="https://$DOMAIN/api/proxy"
    
    cat << SUMMARY

${BLUE}🎯 Service Information:${NC}
  Service Name          : $SERVICE_NAME
  Service Status        : $(systemctl is-active $SERVICE_NAME)
  System User           : $SERVICE_USER
  Work Directory        : $WORK_DIR
  Config File           : $CONFIG_DIR/config.yaml

${BLUE}🌐 Web Access:${NC}
  Domain                : https://$DOMAIN
  Management Web UI     : https://$DOMAIN/admin
  Username              : admin
  Password              : (as configured)

${BLUE}🔌 API Information:${NC}
  API Endpoint          : $API_URL
  API Keys              : $(echo "$API_KEYS" | tr ',' '\n' | wc -l) key(s)

${BLUE}📝 Test API Call:${NC}
  curl -X GET \\
    -H "Authorization: Bearer $TEST_KEY" \\
    "$API_URL"

${BLUE}🛠️  Service Management:${NC}
  View logs             : journalctl -u $SERVICE_NAME -f
  Check status          : systemctl status $SERVICE_NAME
  Restart service       : systemctl restart $SERVICE_NAME
  Stop service          : systemctl stop $SERVICE_NAME
  View caddy logs       : journalctl -u caddy -f

${BLUE}🚨 Firewall Status:${NC}
  Check rules           : sudo ufw status
  View fail2ban         : sudo fail2ban-client status sshd

${BLUE}📖 OAuth Provider Setup (use --no-browser):${NC}
  (Refer to CLIProxyAPI PLUS documentation for provider-specific flags)

${YELLOW}⚠️  Important Notes:${NC}
  1. Domain must point to this server's IP for SSL to work
  2. Certificate auto-renewal is handled by Caddy
  3. Config file edited? Run: systemctl restart $SERVICE_NAME
  4. Keep API keys secure - regenerate if compromised
  5. Monitor disk usage and logs regularly

SUMMARY

    echo ""
    separator
    log_success "Deployment finished. Service is running!"
}

# Run main function
main "$@"
