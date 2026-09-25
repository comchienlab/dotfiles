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
        log_error "Script must be run as root. Use: sudo bash setup_cliproxy.sh"
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
        GO_VERSION=$(go version 2>/dev/null | awk '{print $3}' | sed 's/go//')
        if [[ -n "$GO_VERSION" ]]; then
            log_success "Go already installed: $GO_VERSION"
            return 0
        fi
    fi

    log_info "Installing Go >= $MIN_GO_VERSION..."
    
    # Try to get latest Go release with timeout
    LATEST_GO=$(timeout 10 curl -fsSL https://api.github.com/repos/golang/go/releases | grep -oP '"tag_name": "\Kgo[0-9.]+" ' | head -1 | tr -d '"go ' || echo "1.24.3")
    
    if [[ -z "$LATEST_GO" ]]; then
        LATEST_GO="1.24.3"
        log_warn "Could not fetch latest, using fallback: $LATEST_GO"
    fi

    GO_URL="https://go.dev/dl/go${LATEST_GO}.linux-${GO_ARCH}.tar.gz"
    
    log_info "Downloading Go $LATEST_GO..."
    if ! timeout 120 curl -fsSL --fail "$GO_URL" -o /tmp/go.tar.gz; then
        log_error "Failed to download Go from $GO_URL"
    fi
    
    rm -rf /usr/local/go
    tar -C /usr/local -xzf /tmp/go.tar.gz 2>/dev/null || log_error "Failed to extract Go"
    rm -f /tmp/go.tar.gz
    
    # Add to PATH
    export PATH="/usr/local/go/bin:$PATH"
    grep -q 'export PATH="/usr/local/go/bin' /root/.bashrc || echo 'export PATH="/usr/local/go/bin:$PATH"' >> /root/.bashrc
    
    # Verify
    if ! /usr/local/go/bin/go version &>/dev/null; then
        log_error "Go installation verification failed"
    fi
    
    log_success "Go $LATEST_GO installed"
}

install_caddy() {
    log_info "Checking Caddy installation..."
    
    if command -v caddy &> /dev/null; then
        CADDY_VERSION=$(caddy version 2>/dev/null || echo "installed")
        log_success "Caddy already installed: $CADDY_VERSION"
        systemctl is-enabled caddy >/dev/null 2>&1 || systemctl enable caddy 2>/dev/null
        return 0
    fi

    log_info "Installing Caddy..."
    
    # Try official Caddy repo first
    if [[ ! -f /etc/apt/sources.list.d/caddy-fury.list ]]; then
        log_info "Attempting official Caddy repository..."
        
        # Download GPG key with retry
        for i in {1..3}; do
            if timeout 30 curl -fsSL https://apt.fury.io/caddy/gpg.key 2>/dev/null | gpg --yes --dearmor -o /usr/share/keyrings/caddy-fury.gpg 2>/dev/null; then
                echo "deb [signed-by=/usr/share/keyrings/caddy-fury.gpg] https://apt.fury.io/caddy/ /" > /etc/apt/sources.list.d/caddy-fury.list
                apt-get update >/dev/null 2>&1
                if apt-get install -y caddy 2>/dev/null; then
                    systemctl enable caddy 2>/dev/null || true
                    log_success "Caddy installed from official repo"
                    return 0
                fi
            fi
            [[ $i -lt 3 ]] && log_warn "Retry $i/3..."
        done
    fi
    
    # Fallback: try Ubuntu universe repo
    log_warn "Official repo failed, trying universe repository..."
    apt-get update >/dev/null 2>&1
    if apt-get install -y caddy 2>/dev/null; then
        systemctl enable caddy 2>/dev/null || true
        log_success "Caddy installed from universe repo"
        return 0
    fi
    
    # Last resort: build from source
    log_error "Could not install Caddy. Please install manually: apt-get install -y caddy"
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
    
    # Check if repo is accessible
    if ! timeout 10 git ls-remote --exit-code "$REPO_URL" >/dev/null 2>&1; then
        log_error "Repository not accessible: $REPO_URL\nPlease verify the URL or network connectivity."
    fi
    
    rm -rf /tmp/cliproxyapi-build
    timeout 300 git clone --depth 1 "$REPO_URL" /tmp/cliproxyapi-build 2>/dev/null || {
        log_error "Failed to clone repository"
    }
    
    cd /tmp/cliproxyapi-build || log_error "Failed to enter repo directory"
    
    log_info "Building CLIProxyAPI PLUS (this may take a while)..."
    
    if ! timeout 600 go build -o "$BIN_NAME" . 2>/dev/null; then
        log_error "Build failed. Check logs and Go installation."
    fi
    
    if [[ ! -f "$BIN_NAME" ]]; then
        log_error "Build failed: binary not found"
    fi
    
    log_success "Build completed: $BIN_NAME"
    
    # Move to work directory
    mkdir -p "$WORK_DIR"
    mv "$BIN_NAME" "$WORK_DIR/" || log_error "Failed to move binary"
    chmod +x "$WORK_DIR/$BIN_NAME"
    
    cd - > /dev/null
    rm -rf /tmp/cliproxyapi-build
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
    
    # Escape special chars in password
    ESCAPED_PASSWORD=$(printf '%s\n' "$UI_PASSWORD" | sed 's:[\/&]:\\&:g')
    ESCAPED_PROXY=$(printf '%s\n' "$PROXY_URL" | sed 's:[\/&]:\\&:g')
    
    # Convert comma-separated keys to YAML array
    KEYS_YAML=""
    IFS=',' read -ra KEYS <<< "$API_KEYS"
    for key in "${KEYS[@]}"; do
        KEYS_YAML+="      - \"${key// /}\""$'\n'
    done
    
    mkdir -p "$CONFIG_DIR"
    
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
  password: "$ESCAPED_PASSWORD"

proxy:
  url: "$ESCAPED_PROXY"

logging:
  level: "info"
  format: "json"
  output: "$LOG_DIR/cliproxyapi.log"
EOF

    chown "$SERVICE_USER:$SERVICE_USER" "$CONFIG_DIR/config.yaml" 2>/dev/null || true
    chmod 600 "$CONFIG_DIR/config.yaml"
    
    log_success "Config file created: $CONFIG_DIR/config.yaml"
}

create_systemd_service() {
    log_info "Creating systemd service..."
    
    # Check if port 8080 is available
    if netstat -tuln 2>/dev/null | grep -q :8080; then
        log_warn "Port 8080 already in use. Service may fail to start."
    fi
    
    cat > "/etc/systemd/system/${SERVICE_NAME}.service" << 'EOF'
[Unit]
Description=CLIProxyAPI PLUS Service
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=cliproxy
Group=cliproxy
WorkingDirectory=/opt/cliproxyapi-plus
ExecStart=/opt/cliproxyapi-plus/cli-proxy-api-plus -config=/etc/cliproxyapi-plus/config.yaml
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal
SyslogIdentifier=cliproxyapi-plus
TimeoutStartSec=60

# Security & resource limits
PrivateTmp=yes
NoNewPrivileges=true
LimitNOFILE=65536
LimitNPROC=4096

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable "$SERVICE_NAME" 2>/dev/null || log_warn "Failed to enable service"
    
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
    
    if ! command -v fail2ban-client &> /dev/null; then
        log_warn "fail2ban not installed, skipping..."
        return 0
    fi
    
    systemctl start fail2ban 2>/dev/null || log_warn "Failed to start fail2ban"
    systemctl enable fail2ban 2>/dev/null || true
    
    mkdir -p /etc/fail2ban
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

    systemctl restart fail2ban 2>/dev/null || log_warn "Could not restart fail2ban"
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
    
    # Check if already deployed
    if systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null; then
        log_warn "Service $SERVICE_NAME is already running!"
        echo -n "Proceed with redeployment? (yes/no): "
        read -r REDEPLOY
        [[ "$REDEPLOY" == "yes" ]] || log_error "Cancelled by user"
    fi
    
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
    systemctl restart caddy 2>/dev/null || log_warn "Failed to restart caddy"
    systemctl start "$SERVICE_NAME" 2>/dev/null || log_warn "Service may need manual start"
    
    sleep 3
    
    if systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null; then
        log_success "Service started successfully"
    else
        log_warn "Service not running yet. Check: journalctl -u $SERVICE_NAME -n 20"
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
  Domain                : $DOMAIN
  Service Status        : $(systemctl is-active $SERVICE_NAME 2>/dev/null || echo "inactive")
  Work Directory        : $WORK_DIR

${BLUE}🌐 Access:${NC}
  API Endpoint          : $API_URL
  Management Web UI     : https://$DOMAIN/admin
  Password              : (as configured)

${BLUE}📝 Test API:${NC}
  curl -H "Authorization: Bearer $TEST_KEY" \\
    "$API_URL"

${BLUE}🛠️  Service Commands:${NC}
  Logs                  : journalctl -u $SERVICE_NAME -f
  Status                : systemctl status $SERVICE_NAME
  Restart               : systemctl restart $SERVICE_NAME
  Stop                  : systemctl stop $SERVICE_NAME

${YELLOW}⚠️  Next Steps:${NC}
  1. Ensure domain DNS → VPS IP
  2. Wait 30-60s for Let's Encrypt SSL
  3. Test: curl -k https://$DOMAIN
  4. Monitor: journalctl -u $SERVICE_NAME -f

SUMMARY

    echo ""
    separator
    log_success "Ready!"
}

# Run main function
main "$@"
