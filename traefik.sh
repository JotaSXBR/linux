#!/bin/bash

# Traefik Reverse Proxy Installation Script for Docker Swarm - v3 Corrected
#
# FIX:
# - Updated the command flags to be compatible with Traefik v3.
# - Removed '--providers.docker.swarmMode' and added '--providers.swarm'.
#
# It will:
# 1. Automatically fetch the latest stable Traefik version from GitHub.
# 2. Prompt for your domain name and email address.
# 3. Prompt for a username and password to secure the Traefik dashboard.
# 4. Create a shared overlay network for Traefik and other services.
# 5. Create the necessary directory and placeholder file for Let's Encrypt certificates.
# 6. Generate a 'traefik.yml' file with your custom configuration.
# 7. Deploy Traefik as a Docker Swarm stack.

# --- Pre-flight Checks ---
if ! docker info > /dev/null 2>&1; then
  echo "Error: Docker is not running or you don't have permission to use it."
  exit 1
fi
if ! command -v openssl &> /dev/null; then
    echo "Error: 'openssl' is not installed. Please install it with 'sudo apt-get install openssl'."
    exit 1
fi
if ! command -v jq &> /dev/null; then
    echo "jq is not installed. Installing it now..."
    sudo apt-get update && sudo apt-get install -y jq
fi

# --- Configuration ---
NETWORK_NAME="main-proxy"
STACK_NAME="traefik"
COMPOSE_FILE="traefik.yml"
ACME_DIR="/opt/traefik"
ACME_FILE="$ACME_DIR/acme.json"
DEFAULT_TRAEFIK_VERSION="v3.0" # Fallback version

# --- Dynamic Versioning ---
echo "### Fetching the latest stable Traefik version... ###"
LATEST_TRAEFIK_VERSION=$(curl -s "https://api.github.com/repos/traefik/traefik/releases/latest" | jq -r '.tag_name')

if [ -z "$LATEST_TRAEFIK_VERSION" ] || [[ "$LATEST_TRAEFIK_VERSION" == "null" ]]; then
    echo "Warning: Could not fetch the latest version. Using default: $DEFAULT_TRAEFIK_VERSION"
    TRAEFIK_VERSION=$DEFAULT_TRAEFIK_VERSION
else
    echo "Latest version found: $LATEST_TRAEFIK_VERSION"
    TRAEFIK_VERSION=$LATEST_TRAEFIK_VERSION
fi
echo

# --- Interactive Setup ---
echo "### Traefik Configuration Setup ###"
read -p "Enter the domain for the Traefik dashboard (e.g., traefik.yourdomain.com): " TRAEFIK_DOMAIN
read -p "Enter your email address (for Let's Encrypt SSL certificates): " LETSENCRYPT_EMAIL
read -p "Enter a username for the Traefik dashboard: " DASHBOARD_USER
read -sp "Enter a password for the dashboard: " DASHBOARD_PASS
echo
echo "----------------------------------------------------"
echo

# --- Script Execution ---

# 1. Create the common overlay network
echo "### Checking for Docker network '$NETWORK_NAME'... ###"
if ! docker network inspect "$NETWORK_NAME" >/dev/null 2>&1; then
  echo "Network '$NETWORK_NAME' not found. Creating it now..."
  docker network create --driver=overlay --attachable "$NETWORK_NAME"
else
  echo "Network '$NETWORK_NAME' already exists."
fi
echo

# 2. Create directory and acme.json for Let's Encrypt
echo "### Setting up storage for Let's Encrypt certificates... ###"
sudo mkdir -p "$ACME_DIR"
if [ ! -f "$ACME_FILE" ]; then
    sudo touch "$ACME_FILE"
    sudo chmod 600 "$ACME_FILE"
    echo "Created empty acme.json with secure permissions."
else
    echo "acme.json already exists."
fi
echo

# 3. Generate hashed password for dashboard
echo "### Generating hashed password for dashboard... ###"
HASHED_PASSWORD=$(openssl passwd -apr1 "$DASHBOARD_PASS")
echo "Password hash generated."
echo

# 4. Create the traefik.yml file
echo "### Creating Docker Compose file: $COMPOSE_FILE... ###"
cat > "$COMPOSE_FILE" <<EOF
# traefik.yml
version: '3.8'

services:
  traefik:
    image: traefik:${TRAEFIK_VERSION}
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - $ACME_DIR:/etc/traefik/acme
    networks:
      - $NETWORK_NAME
    command:
      - "--api.dashboard=true"
      - "--providers.docker=true"
      - "--providers.docker.exposedByDefault=false"
      # --- V3 SWARM PROVIDER CONFIGURATION ---
      - "--providers.swarm=true"
      - "--providers.swarm.exposedByDefault=false"
      # --- END V3 CONFIGURATION ---
      - "--entrypoints.web.address=:80"
      - "--entrypoints.web.http.redirections.entrypoint.to=websecure"
      - "--entrypoints.web.http.redirections.entrypoint.scheme=https"
      - "--entrypoints.websecure.address=:443"
      - "--certificatesresolvers.myresolver.acme.email=$LETSENCRYPT_EMAIL"
      - "--certificatesresolvers.myresolver.acme.storage=/etc/traefik/acme/acme.json"
      - "--certificatesresolvers.myresolver.acme.httpchallenge=true"
      - "--certificatesresolvers.myresolver.acme.httpchallenge.entrypoint=web"
    deploy:
      mode: replicated
      replicas: 1
      placement:
        constraints:
          - node.role == manager
      labels:
        - "traefik.enable=true"
        - "traefik.http.routers.dashboard.rule=Host(\`$TRAEFIK_DOMAIN\`)"
        - "traefik.http.routers.dashboard.service=api@internal"
        - "traefik.http.routers.dashboard.tls=true"
        - "traefik.http.routers.dashboard.tls.certresolver=myresolver"
        - "traefik.http.routers.dashboard.middlewares=auth"
        - "traefik.http.middlewares.auth.basicauth.users=$DASHBOARD_USER:$HASHED_PASSWORD"

networks:
  $NETWORK_NAME:
    external: true
EOF
echo "Compose file created."
echo

# 5. Deploy the Traefik stack
echo "### Deploying Traefik stack '$STACK_NAME'... ###"
docker stack deploy -c "$COMPOSE_FILE" "$STACK_NAME"
echo

# --- Final Instructions ---
SERVER_IP=$(hostname -I | awk '{print $1}')
echo "####################################################################"
echo "###            Traefik Deployment Initiated!                     ###"
echo "####################################################################"
echo
echo "IMPORTANT: Make sure your domain '$TRAEFIK_DOMAIN' points to this server's IP: $SERVER_IP"
echo
echo "It may take a minute for the service to be available and for the SSL certificate to be generated."
echo "You can check the status with the command: docker stack ps $STACK_NAME"
echo "If it fails again, check logs with: docker service logs ${STACK_NAME}_traefik"
echo
echo "Once running, access the Traefik dashboard at:"
echo "https://$TRAEFIK_DOMAIN"
echo