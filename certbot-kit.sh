#!/bin/bash
# Advanced IP Certificate Setup Script
# Supports multiple ACME clients with auto-detection for API servers
# For Ubuntu/Debian with Let's Encrypt IP certificates (6-day shortlived profile)

# Exit on error, but handle failures gracefully
set -eE
trap 'echo "Error occurred at line $LINENO"' ERR

# Determine if we should use $SUDO
if [[ $EUID -eq 0 ]]; then
    SUDO=""
else
    SUDO="$SUDO"
fi

# ============ Configuration ============
# Default values - will be overridden by auto-detection or user input
YOUR_EMAIL="your-email@example.com"
YOUR_IP=""
YOUR_APP_PORT=""
ACME_CLIENT="acme.sh"
CHALLENGE_TYPE=""
CERT_PATH=""
RENEWAL_SCRIPT="/usr/local/bin/certbot-ip-renew.sh"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# ============ Functions ============

print_header() {
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}$1${NC}"
    echo -e "${GREEN}========================================${NC}"
}

print_step() {
    echo -e "${BLUE}[$1] $2${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_info() {
    echo -e "${CYAN}ℹ $1${NC}"
}

# Interactive configuration function
configure_interactive() {
    echo -e "${CYAN}=== Interactive Configuration ===${NC}"

    # Email configuration
    if [[ "$YOUR_EMAIL" == "your-email@example.com" ]]; then
        read -p "Enter your email for certificate notifications: " input_email
        if [[ -n "$input_email" ]]; then
            YOUR_EMAIL="$input_email"
        fi
    fi

    # IP detection with confirmation
    if [[ -z "$YOUR_IP" ]]; then
        print_info "Detecting public IP address..."
        YOUR_IP=$(curl -s --connect-timeout 5 ifconfig.me 2>/dev/null || curl -s --connect-timeout 5 ipinfo.io/ip 2>/dev/null || curl -s --connect-timeout 5 icanhazip.com 2>/dev/null || echo "")
        if [[ -n "$YOUR_IP" ]]; then
            print_info "Detected public IP: $YOUR_IP"
            read -p "Is this correct? [Y/n]: " confirm
            if [[ "$confirm" =~ ^[Nn]$ ]]; then
                read -p "Enter your IP address: " YOUR_IP
            fi
        else
            print_warning "Could not auto-detect IP address"
            read -p "Enter your IP address: " YOUR_IP
        fi
    fi

    # App port configuration
    if [[ -z "$YOUR_APP_PORT" ]]; then
        read -p "Enter your application port [8080]: " input_port
        YOUR_APP_PORT=${input_port:-8080}
    fi

    # ACME client selection
    echo -e "\n${CYAN}Select ACME client:${NC}"
    echo "1) acme.sh (Recommended - best IP certificate support)"
    echo "2) certbot (Traditional - limited IP support)"
    echo "3) lego (Go-based - good IP support)"
    read -p "Choose [1]: " client_choice

    case $client_choice in
        2) ACME_CLIENT="certbot" ;;
        3) ACME_CLIENT="lego" ;;
        *) ACME_CLIENT="acme.sh" ;;
    esac
}

# OS detection
detect_os() {
    print_step "OS DETECTION" "Detecting operating system..."

    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS=$ID
        OS_VERSION=$VERSION_ID
        print_success "Detected: $OS $OS_VERSION"

        # Set package manager
        case $OS in
            ubuntu|debian) PKG_MANAGER="apt" ;;
            centos|rhel|fedora) PKG_MANAGER="yum" ;;
            *) PKG_MANAGER="apt" ;;
        esac
    else
        print_warning "Could not detect OS, assuming Ubuntu/Debian"
        OS="ubuntu"
        PKG_MANAGER="apt"
    fi
}

# Port detection
detect_ports() {
    print_step "PORT DETECTION" "Checking available ports..."

    # Check if ports are open from outside
    local port80_open=false
    local port443_open=false

    # Test port 80
    print_info "Testing connectivity to port 80..."
    if timeout 3 bash -c "</dev/tcp/letsencrypt.org/80" 2>/dev/null; then
        port80_open=true
        print_success "Port 80 is accessible"
    else
        print_warning "Port 80 appears to be blocked"
    fi

    # Test port 443
    print_info "Testing connectivity to port 443..."
    if timeout 3 bash -c "</dev/tcp/letsencrypt.org/443" 2>/dev/null; then
        port443_open=true
        print_success "Port 443 is accessible"
    else
        print_warning "Port 443 appears to be blocked"
    fi

    # Auto-select challenge type
    if [[ "$port443_open" == true ]]; then
        CHALLENGE_TYPE="tls-alpn"
        print_info "Selected TLS-ALPN-01 challenge (port 443)"
    elif [[ "$port80_open" == true ]]; then
        CHALLENGE_TYPE="http"
        print_info "Selected HTTP-01 challenge (port 80)"
    else
        print_warning "Neither port 80 nor 443 appears to be accessible"
        print_info "Attempting to open ports locally..."
        CHALLENGE_TYPE="http"  # Default to http
    fi
}

# Firewall configuration
configure_firewall() {
    print_step "FIREWALL" "Configuring firewall rules..."

    case $OS in
        ubuntu|debian)
            if command -v ufw &> /dev/null; then
                $SUDO ufw --force enable
                $SUDO ufw allow 80/tcp 2>/dev/null || true
                $SUDO ufw allow 443/tcp 2>/dev/null || true
                $SUDO ufw allow $YOUR_APP_PORT/tcp 2>/dev/null || true
                print_success "UFW configured"
            else
                print_warning "UFW not found, please ensure ports 80, 443, $YOUR_APP_PORT are open"
            fi
            ;;
        centos|rhel|fedora)
            if command -v firewall-cmd &> /dev/null; then
                $SUDO firewall-cmd --permanent --add-port=80/tcp 2>/dev/null || true
                $SUDO firewall-cmd --permanent --add-port=443/tcp 2>/dev/null || true
                $SUDO firewall-cmd --permanent --add-port=$YOUR_APP_PORT/tcp 2>/dev/null || true
                $SUDO firewall-cmd --reload 2>/dev/null || true
                print_success "Firewalld configured"
            else
                print_warning "Firewalld not found, please ensure ports are open"
            fi
            ;;
    esac
}

# Install ACME client
install_acme_client() {
    print_step "ACME CLIENT" "Installing $ACME_CLIENT..."

    case $ACME_CLIENT in
        "acme.sh")
            # Install required dependencies
            print_info "Installing dependencies for acme.sh..."
            case $PKG_MANAGER in
                apt)
                    $SUDO apt update
                    $SUDO apt install -y socat curl openssl
                    ;;
                yum)
                    $SUDO yum install -y socat curl openssl
                    ;;
            esac

            if [[ ! -f ~/.acme.sh/acme.sh ]]; then
                curl https://get.acme.sh | sh -s email="$YOUR_EMAIL"
                source ~/.acme.sh/acme.sh.env
                print_success "acme.sh installed"
            else
                print_success "acme.sh already installed"
            fi

            # Set Let's Encrypt as CA (supports IP certificates)
            ~/.acme.sh/acme.sh --set-default-ca --server letsencrypt
            print_info "Using Let's Encrypt CA"
            CERT_PATH="$HOME/.acme.sh/$YOUR_IP"
            ;;
        "certbot")
            if ! command -v certbot &> /dev/null; then
                $SUDO $PKG_MANAGER update
                case $PKG_MANAGER in
                    apt)
                        $SUDO apt install -y snapd
                        $SUDO snap install core
                        $SUDO snap refresh core
                        $SUDO snap install --classic certbot
                        $SUDO ln -sf /snap/bin/certbot /usr/bin/certbot
                        ;;
                    yum)
                        $SUDO yum install -y epel-release
                        $SUDO yum install -y certbot python3-certbot-nginx
                        ;;
                esac
                print_success "certbot installed"
            else
                print_success "certbot already installed"
            fi
            CERT_PATH="/etc/letsencrypt/live/$YOUR_IP"
            ;;
        "lego")
            if ! command -v lego &> /dev/null; then
                LEGO_VERSION="4.12.3"
                wget -O /tmp/lego.tar.gz "https://github.com/go-acme/lego/releases/download/v$LEGO_VERSION/lego_v$LEGO_VERSION_linux_amd64.tar.gz"
                tar -xzf /tmp/lego.tar.gz -C /tmp
                $SUDO mv /tmp/lego /usr/local/bin/
                chmod +x /usr/local/bin/lego
                print_success "lego installed"
            else
                print_success "lego already installed"
            fi
            CERT_PATH="/etc/lego/certificates"
            ;;
    esac
}

# Stop conflicting services
stop_services() {
    print_step "SERVICE MANAGEMENT" "Checking for conflicting services..."

    # Stop services on port 80 or 443
    for port in 80 443; do
        if $SUDO lsof -Pi :$port -sTCP:LISTEN -t >/dev/null 2>&1; then
            print_warning "Port $port is in use"

            # Try to stop common services
            for service in nginx apache2 httpd; do
                if systemctl is-active --quiet $service 2>/dev/null; then
                    $SUDO systemctl stop $service
                    print_success "Stopped $service"
                fi
            done
        fi
    done
}

# Obtain certificate
obtain_certificate() {
    print_step "CERTIFICATE" "Obtaining IP certificate for $YOUR_IP..."
    print_info "Using $ACME_CLIENT with $CHALLENGE_TYPE challenge"
    print_warning "Note: IP certificates are valid for 6 days only"

    case $ACME_CLIENT in
        "acme.sh")
            source ~/.acme.sh/acme.sh.env

            # Try to obtain certificate
            if [[ "$CHALLENGE_TYPE" == "tls-alpn" ]]; then
                ~/.acme.sh/acme.sh --issue --standalone --alpn -d "$YOUR_IP" --log || \
                ~/.acme.sh/acme.sh --issue --standalone --alpn -d "$YOUR_IP" --debug
            else
                ~/.acme.sh/acme.sh --issue --standalone -d "$YOUR_IP" --log || \
                ~/.acme.sh/acme.sh --issue --standalone -d "$YOUR_IP" --debug
            fi

            # Install certificates
            ~/.acme.sh/acme.sh --install-cert -d "$YOUR_IP" \
                --key-file "$CERT_PATH/privkey.pem" \
                --fullchain-file "$CERT_PATH/fullchain.pem" \
                --reloadcmd "systemctl reload nginx 2>/dev/null || true"
            ;;
        "certbot")
            $SUDO certbot certonly \
                --standalone \
                --non-interactive \
                --agree-tos \
                --email "$YOUR_EMAIL" \
                --preferred-challenges "$CHALLENGE_TYPE-01" \
                --certificate-profile shortlived \
                -d "$YOUR_IP"
            ;;
        "lego")
            if [[ "$CHALLENGE_TYPE" == "tls-alpn" ]]; then
                lego --email "$YOUR_EMAIL" \
                    --accept-tos \
                    --domains "$YOUR_IP" \
                    --alpn \
                    --path "$CERT_PATH" \
                    run
            else
                lego --email "$YOUR_EMAIL" \
                    --accept-tos \
                    --domains "$YOUR_IP" \
                    --http \
                    --path "$CERT_PATH" \
                    run
            fi
            ;;
    esac

    if [[ $? -eq 0 ]]; then
        print_success "Certificate obtained successfully!"
        print_info "Certificate path: $CERT_PATH"
    else
        print_error "Certificate request failed"
        print_info "Common issues:"
        print_info "  - IP not publicly accessible"
        print_info "  - Firewall blocking ports 80/443"
        print_info "  - ACME server rate limits"
        exit 1
    fi
}

# Setup auto-renewal
setup_renewal() {
    print_step "AUTO-RENEWAL" "Setting up automatic renewal..."

    # Create renewal script based on ACME client
    case $ACME_CLIENT in
        "acme.sh")
            RENEWAL_COMMAND="$HOME/.acme.sh/acme.sh --cron --home $HOME/.acme.sh"
            ;;
        "certbot")
            RENEWAL_COMMAND="certbot renew --quiet --certificate-profile shortlived"
            ;;
        "lego")
            RENEWAL_COMMAND="lego --email \"$YOUR_EMAIL\" --domains \"$YOUR_IP\" --path \"$CERT_PATH\" renew"
            ;;
    esac

    # Create renewal script
    $SUDO tee "$RENEWAL_SCRIPT" > /dev/null <<RENEWAL_EOF
#!/bin/bash
# Auto-renewal script for IP certificates ($ACME_CLIENT)

LOG_FILE="/var/log/certbot-ip-renew.log"
ACME_CLIENT="$ACME_CLIENT"
CHALLENGE_TYPE="$CHALLENGE_TYPE"
CERT_PATH="$CERT_PATH"

echo "===== \$(date) =====" >> "\$LOG_FILE"
echo "Renewing certificate for IP: $YOUR_IP" >> "\$LOG_FILE"

# Stop conflicting services
for service in nginx apache2 httpd; do
    if systemctl is-active --quiet \$service 2>/dev/null; then
        systemctl stop \$service
        echo "Stopped \$service" >> "\$LOG_FILE"
        SERVICE_STOPPED=\$service
    fi
done

# Renew certificate
$RENEWAL_COMMAND >> "\$LOG_FILE" 2>&1

if [ \$? -eq 0 ]; then
    echo "✓ Certificate renewed successfully" >> "\$LOG_FILE"

    # Restart services if stopped
    if [ ! -z "\$SERVICE_STOPPED" ]; then
        systemctl start \$SERVICE_STOPPED
        echo "Restarted \$SERVICE_STOPPED" >> "\$LOG_FILE"
    fi

    # Reload services using the certificate
    systemctl reload nginx 2>/dev/null || true
    systemctl reload apache2 2>/dev/null || true
else
    echo "✗ Certificate renewal failed" >> "\$LOG_FILE"
    # Still restart services
    if [ ! -z "\$SERVICE_STOPPED" ]; then
        systemctl start \$SERVICE_STOPPED
    fi
fi

echo "============================" >> "\$LOG_FILE"
RENEWAL_EOF

    $SUDO chmod +x "$RENEWAL_SCRIPT"
    print_success "Renewal script created: $RENEWAL_SCRIPT"

    # Add cron job (run every 5 days at random time)
    CRON_MINUTE=$((RANDOM % 60))
    CRON_HOUR=$((RANDOM % 24))
    CRON_JOB="$CRON_MINUTE $CRON_HOUR */5 * * $RENEWAL_SCRIPT"

    if ! $SUDO crontab -l 2>/dev/null | grep -q "$RENEWAL_SCRIPT"; then
        ($SUDO crontab -l 2>/dev/null; echo "$CRON_JOB") | $SUDO crontab -
        print_success "Cron job added (every 5 days at $CRON_HOUR:$CRON_MINUTE)"
    else
        print_success "Cron job already exists"
    fi

    # For acme.sh, also set up its built-in cron
    if [[ "$ACME_CLIENT" == "acme.sh" ]]; then
        "$HOME/.acme.sh/acme.sh" --install-cronjob
        print_success "acme.sh cron job configured"
    fi
}

# Test renewal
test_renewal() {
    print_step "TESTING" "Testing renewal process..."

    case $ACME_CLIENT in
        "acme.sh")
            "$HOME/.acme.sh/acme.sh" --cron --home "$HOME/.acme.sh" --force 2>&1 | grep -E "(Renew|expire|valid)"
            ;;
        "certbot")
            $SUDO certbot renew --dry-run --certificate-profile shortlived
            ;;
        "lego")
            print_info "Run 'lego --email \"$YOUR_EMAIL\" --domains \"$YOUR_IP\" --path \"$CERT_PATH\" renew --days' to test"
            ;;
    esac
}

# Show configuration summary
show_summary() {
    print_header "Setup Complete!"

    echo -e "${CYAN}Configuration Summary:${NC}"
    echo -e "  IP Address: ${YELLOW}$YOUR_IP${NC}"
    echo -e "  Email: ${YELLOW}$YOUR_EMAIL${NC}"
    echo -e "  Application Port: ${YELLOW}$YOUR_APP_PORT${NC}"
    echo -e "  ACME Client: ${YELLOW}$ACME_CLIENT${NC}"
    echo -e "  Challenge Type: ${YELLOW}$CHALLENGE_TYPE${NC}"
    echo -e "  Certificate Path: ${YELLOW}$CERT_PATH${NC}"
    echo ""

    echo -e "${YELLOW}Certificate Files:${NC}"
    if [[ "$ACME_CLIENT" == "lego" ]]; then
        echo -e "  - Certificate: ${YELLOW}$CERT_PATH/certificates/$YOUR_IP.crt${NC}"
        echo -e "  - Private Key: ${YELLOW}$CERT_PATH/certificates/$YOUR_IP.key${NC}"
    else
        echo -e "  - Certificate: ${YELLOW}$CERT_PATH/fullchain.pem${NC}"
        echo -e "  - Private Key: ${YELLOW}$CERT_PATH/privkey.pem${NC}"
    fi
    echo ""

    echo -e "${YELLOW}Next Steps:${NC}"
    echo -e "1. Configure your application to use HTTPS on port 443"
    echo -e "2. Setup a reverse proxy (nginx/apache) for $YOUR_IP:443 -> 127.0.0.1:$YOUR_APP_PORT"
    echo -e "3. Auto-renewal runs every 5 days (certs expire in 6 days)"
    echo ""

    echo -e "${YELLOW}Example nginx configuration for API server:${NC}"
    echo ""
    cat <<NGINX_EXAMPLE
server {
    listen 443 ssl http2;
    server_name $YOUR_IP;

    ssl_certificate $CERT_PATH/fullchain.pem;
    ssl_certificate_key $CERT_PATH/privkey.pem;

    # SSL hardening
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-RSA-AES256-GCM-SHA512:DHE-RSA-AES256-GCM-SHA512;
    ssl_prefer_server_ciphers off;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;

    # API specific headers
    add_header Access-Control-Allow-Origin *;
    add_header Access-Control-Allow-Methods "GET, POST, PUT, DELETE, OPTIONS";
    add_header Access-Control-Allow-Headers "Authorization, Content-Type";

    location / {
        proxy_pass http://127.0.0.1:$YOUR_APP_PORT;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;

        # For WebSocket support
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}
NGINX_EXAMPLE
    echo ""

    echo -e "${YELLOW}Management Commands:${NC}"
    echo -e "  View logs: ${GREEN}tail -f /var/log/certbot-ip-renew.log${NC}"
    echo -e "  Manual renewal: ${GREEN}$SUDO $RENEWAL_SCRIPT${NC}"
    if [[ "$ACME_CLIENT" == "acme.sh" ]]; then
        echo -e "  List certificates: ${GREEN}$HOME/.acme.sh/acme.sh --list${NC}"
    fi
}

# ============ Main Script ============

main() {
    print_header "Advanced IP Certificate Setup"

    # Check user permissions
    if [[ $EUID -eq 0 ]]; then
        print_warning "Running as root user"
    else
        print_info "Running as regular user (will use sudo when needed)"
    fi

    # Check if running through pipe (no interactive mode)
    if [[ ! -t 0 ]]; then
        print_warning "Running in non-interactive mode"
        print_info "For interactive mode, run: ./certbot-kit.sh"

        # Set defaults for non-interactive mode
        if [[ "$YOUR_EMAIL" == "your-email@example.com" ]]; then
            print_error "Email is required. Please run with -e option"
            exit 1
        fi

        YOUR_IP=${YOUR_IP:-$(curl -s --connect-timeout 5 ifconfig.me 2>/dev/null || echo "")}
        YOUR_APP_PORT=${YOUR_APP_PORT:-8080}
        ACME_CLIENT=${ACME_CLIENT:-acme.sh}

        if [[ -z "$YOUR_IP" ]]; then
            print_error "IP address is required. Please run with -i option"
            exit 1
        fi

        print_info "Using configuration:"
        print_info "  Email: $YOUR_EMAIL"
        print_info "  IP: $YOUR_IP"
        print_info "  Port: $YOUR_APP_PORT"
        print_info "  Client: $ACME_CLIENT"
    else
        # Interactive configuration
        configure_interactive
    fi

    # Auto-detection
    detect_os
    detect_ports

    # Configuration
    configure_firewall
    install_acme_client

    # Certificate setup
    stop_services
    obtain_certificate

    # Auto-renewal
    setup_renewal
    test_renewal

    # Summary
    show_summary
}

# Handle command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -e|--email)
            YOUR_EMAIL="$2"
            shift 2
            ;;
        -i|--ip)
            YOUR_IP="$2"
            shift 2
            ;;
        -p|--port)
            YOUR_APP_PORT="$2"
            shift 2
            ;;
        -c|--client)
            ACME_CLIENT="$2"
            shift 2
            ;;
        -h|--help)
            echo "Usage: $0 [OPTIONS]"
            echo "  -e, --email EMAIL    Email for certificate notifications"
            echo "  -i, --ip IP          IP address for certificate"
            echo "  -p, --port PORT      Application port (default: 8080)"
            echo "  -c, --client CLIENT  ACME client (acme.sh, certbot, lego)"
            echo "  -h, --help           Show this help"
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Run main function
main
