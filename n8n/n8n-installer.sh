#!/bin/bash

# Ensure the script is run as root
if [[ $EUID -ne 0 ]]; then
  echo "This script needs to be run with root privileges"
  exit 1
fi

# Source common library functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Try multiple locations for common.sh
if [ -f "$SCRIPT_DIR/lib/common.sh" ]; then
    source "$SCRIPT_DIR/lib/common.sh"
elif [ -f "$(dirname "$SCRIPT_DIR")/lib/common.sh" ]; then
    source "$(dirname "$SCRIPT_DIR")/lib/common.sh"
elif [ -f "$HOME/.local/lib/common.sh" ]; then
    source "$HOME/.local/lib/common.sh"
else
    echo "Error: Cannot find lib/common.sh"
    exit 1
fi

# Install Gum if not installed
ensure_gum_installed

# Install jq (used for parsing JSON from Docker Hub)
if ! command -v jq &>/dev/null; then
  gum spin --spinner dot --title "Installing jq..." -- bash -c "
    apt-get update &&
    apt-get install -y jq
  "
fi

# Ensure dnsutils is installed for dig
if ! command -v dig &>/dev/null; then
  gum spin --spinner dot --title "Installing dnsutils..." -- bash -c "
    apt-get update &&
    apt-get install -y dnsutils
  "
  if ! command -v dig &>/dev/null; then
    gum style --foreground 9 "The 'dig' command is required but could not be installed. Aborting."
    exit 1
  fi
fi

# Prompt user to choose an action
ACTION=$(gum choose "Install n8n" "Update n8n" "Show current n8n version")

# Common setup
N8N_DIR="/home/n8n"
IMAGE="n8nio/n8n"

check_domain() {
  local domain=$1
  local server_ip=$(curl -s https://api.ipify.org)
  local domain_ip=$(dig +short $domain)
  [[ "$domain_ip" == "$server_ip" ]]
}

if [[ "$ACTION" == "Install n8n" ]]; then
  DOMAIN=$(gum input --placeholder "Enter your domain or subdomain")

  if check_domain $DOMAIN; then
    gum style --foreground 10 "Domain $DOMAIN is correctly pointed to this server."
  else
    gum style --foreground 9 "Domain $DOMAIN is not pointed to this server."
    gum style --foreground 9 "Please point it to: $(curl -s https://api.ipify.org)"
    exit 1
  fi

  gum confirm "Proceed with installing n8n for $DOMAIN?" || exit 1

  # Install Docker
  gum spin --spinner dot --title "Installing Docker..." -- bash -c "
    apt-get update &&
    apt-get install -y apt-transport-https ca-certificates curl software-properties-common &&
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add - &&
    add-apt-repository -y 'deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable' &&
    apt-get update &&
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose
  "

  mkdir -p $N8N_DIR

  cat << EOF > $N8N_DIR/docker-compose.yml
version: "3"
services:
  n8n:
    image: n8nio/n8n
    restart: always
    ports:
      - "5678:5678"
    environment:
      - N8N_HOST=${DOMAIN}
      - N8N_PORT=5678
      - N8N_PROTOCOL=https
      - NODE_ENV=production
      - WEBHOOK_URL=https://${DOMAIN}
      - GENERIC_TIMEZONE=Asia/Ho_Chi_Minh
    volumes:
      - $N8N_DIR:/home/node/.n8n
  caddy:
    image: caddy:2
    restart: always
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - $N8N_DIR/Caddyfile:/etc/caddy/Caddyfile
      - caddy_data:/data
      - caddy_config:/config
    depends_on:
      - n8n
volumes:
  caddy_data:
  caddy_config:
EOF

  cat << EOF > $N8N_DIR/Caddyfile
${DOMAIN} {
  reverse_proxy n8n:5678
}
EOF

  chown -R 1000:1000 $N8N_DIR
  chmod -R 755 $N8N_DIR
  cd $N8N_DIR
  docker-compose up -d

  gum style --foreground 10 "n8n is now installed at https://${DOMAIN}"

elif [[ "$ACTION" == "Update n8n" ]]; then
  if [ ! -f "$N8N_DIR/docker-compose.yml" ]; then
    gum style --foreground 9 "Cannot find docker-compose setup at $N8N_DIR"
    exit 1
  fi

  CURRENT_VERSION=$(docker exec -it $(docker ps --filter ancestor=$IMAGE -q) n8n -v | tr -d '\r')
  LATEST_VERSION=$(curl -s https://hub.docker.com/v2/repositories/n8nio/n8n/tags | \
    jq -r '.results[].name' | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' | sort -Vr | head -n 1)

  gum style --foreground 10 "Current version: $CURRENT_VERSION"
  gum style --foreground 10 "Latest version: $LATEST_VERSION"

  if [ "$CURRENT_VERSION" == "$LATEST_VERSION" ]; then
    gum style --foreground 10 "You're already running the latest version."
  else
    gum confirm "Update n8n from $CURRENT_VERSION to $LATEST_VERSION?" || exit 0
    gum spin --spinner dot --title "Updating n8n..." -- bash -c "
      cd $N8N_DIR &&
      docker-compose pull &&
      docker-compose down &&
      docker-compose up -d
    "
    NEW_VERSION=$(docker exec -it $(docker ps --filter ancestor=$IMAGE -q) n8n -v | tr -d '\r')
    gum style --foreground 10 "n8n has been updated to version $NEW_VERSION."
  fi

elif [[ "$ACTION" == "Show current n8n version" ]]; then
  CONTAINER_ID=$(docker ps --filter ancestor=$IMAGE -q)
  if [ -n "$CONTAINER_ID" ]; then
    VERSION=$(docker exec -it $CONTAINER_ID n8n -v | tr -d '\r')
    gum style --foreground 10 "Current n8n version: $VERSION"
  else
    gum style --foreground 9 "n8n is not running."
  fi
else
  gum style --foreground 9 "No valid action selected."
fi
