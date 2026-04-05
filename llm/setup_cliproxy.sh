#!/bin/bash

##############################################################################
# CLIProxyAPI PLUS - Remote Deployment via SSH
# Usage: bash remote-deploy-oneliner.sh <vps-ip-or-domain> [ssh-user]
# Example: bash remote-deploy-oneliner.sh 192.168.1.10
#          bash remote-deploy-oneliner.sh api.example.com root
##############################################################################

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

if [[ $# -lt 1 ]]; then
    echo "Usage: bash $0 <vps-ip-or-domain> [ssh-user]"
    echo "Example: bash $0 192.168.1.10"
    echo "         bash $0 api.example.com root"
    exit 1
fi

VPS_HOST="$1"
SSH_USER="${2:-root}"
SCRIPT_URL="https://raw.githubusercontent.com/comchienlab/dotfiles/refs/heads/main/llm/setup_cliproxy.sh"
TIMEOUT_DEPLOY=1800  # 30 minutes

log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[✓]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
separator() { echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"; }

# Pre-flight checks
check_connectivity() {
    log_info "Checking SSH connectivity to $VPS_HOST..."
    
    if ! timeout 10 ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new \
        "$SSH_USER@$VPS_HOST" "echo ok" &>/dev/null; then
        log_error "Cannot connect to $SSH_USER@$VPS_HOST. Check:"
        echo "  1. VPS IP/domain is correct"
        echo "  2. SSH key is set up (ssh-copy-id $SSH_USER@$VPS_HOST)"
        echo "  3. Firewall allows SSH (port 22)"
    fi
    log_success "SSH connectivity OK"
}

check_internet() {
    log_info "Checking internet connectivity from VPS..."
    
    if ! timeout 10 ssh -o StrictHostKeyChecking=accept-new \
        "$SSH_USER@$VPS_HOST" "curl -fsSL --max-time 5 https://github.com" &>/dev/null; then
        log_warn "VPS may not have internet access"
        read -p "Continue anyway? (yes/no): " CONTINUE
        [[ "$CONTINUE" == "yes" ]] || log_error "Deployment aborted"
    fi
    log_success "Internet connectivity OK"
}

# Main deployment
separator
echo -e "${BLUE}CLIProxyAPI PLUS - Remote Deployment${NC}"
separator
echo ""
echo "VPS Target        : $SSH_USER@$VPS_HOST"
echo "Deployment Script : $SCRIPT_URL"
echo "Timeout           : ${TIMEOUT_DEPLOY}s (30 min)"
echo ""

# Pre-flight
check_connectivity
check_internet

separator
echo -e "${BLUE}Starting Deployment...${NC}"
separator
echo ""

# Deploy with timeout and TTY allocation (-t flag for interactive input)
EXIT_CODE=0
if timeout "$TIMEOUT_DEPLOY" ssh -t -o StrictHostKeyChecking=accept-new \
    "$SSH_USER@$VPS_HOST" << 'REMOTE_EXEC'
curl -fsSL https://raw.githubusercontent.com/comchienlab/dotfiles/refs/heads/main/llm/setup_cliproxy.sh | sudo bash
REMOTE_EXEC
then
    EXIT_CODE=$?
else
    EXIT_CODE=$?
fi

echo ""
separator
if [[ $EXIT_CODE -eq 0 ]]; then
    log_success "Deployment completed!"
    echo ""
    echo "Next steps:"
    echo "  1. Check status: ssh $SSH_USER@$VPS_HOST systemctl status cliproxyapi-plus"
    echo "  2. View logs: ssh $SSH_USER@$VPS_HOST journalctl -u cliproxyapi-plus -f"
    echo "  3. Ensure domain DNS points to $VPS_HOST"
else
    log_error "Deployment failed (exit code: $EXIT_CODE)"
    echo ""
    echo "Troubleshooting:"
    echo "  1. Check logs: ssh $SSH_USER@$VPS_HOST journalctl -u cliproxyapi-plus -n 50"
    echo "  2. Verify VPS: ssh $SSH_USER@$VPS_HOST systemctl status"
    echo "  3. Run again: bash $0 $VPS_HOST $SSH_USER"
fi
separator
