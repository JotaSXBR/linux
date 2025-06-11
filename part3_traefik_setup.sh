#!/bin/bash

# PART 3: TRAEFIK DEPLOYMENT
#
# This script deploys Traefik using a clean configuration and
# Docker-managed named volumes to avoid permission errors.
# It MUST be run as the non-root 'deploy' user.

# --- Configuration ---
NETWORK_NAME="main-proxy"
ACME_VOLUME="traefik-acme"
LOG_VOLUME="traefik-logs"
STACK_NAME="traefik"
COMPOSE_FILE="traefik.yml"
DEFAULT_TRAEFIK_VERSION="v3.0" # Fallback version

# --- Pre-flight Checks ---
if ! docker info > /dev/null 2>&1; then
  echo "Error: Docker is not running or you don't have permission to use it."
  echo "Please ensure you are part of the 'docker' group."
  exit 1
fi

# --- Dynamic Versioning ---
echo "### Fetching the latest stable Traefik version... ###"
LATEST_TRAEFIK_VERSION=$(curl -s "https://api.github.com/repos/traefik/traefik/releases/latest" | jq -r '.tag_name')
if [ -z "$LATEST_TRAEFIK_VERSION" ] || [[ "$LATEST_TRAEFIK_VERSION" == "null" ]]; then
    TRAEFIK_VERSION=$DEFAULT_TRAEFIK_VERSION
else
    TRAEFIK_VERSION=$LATEST_TRAEFIK_VERSION
fi
echo "Using Traefik version: $TRAEFIK_VERSION"
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

# 1. Generate hashed password for dashboard
echo "### Generating hashed password for dashboard... ###"
HASHED_PASSWORD=$(openssl passwd -apr1 "$DASHBOARD_PASS" | sed 's/\$/\$\$/g')
echo "Password hash generated and escaped."
echo

# 2. Create the traefik.yml file
echo "### Creating Docker Compose file: $COMPOSE_FILE... ###"
cat > "$COMPOSE_FILE" <<EOF
# traefik.yml
version: '3.8'

services:
  traefik:
    image: traefik:${TRAEFIK_VERSION}
    ports:
      - target: 80
        published: 80
        mode: host
      - target: 443
        published: 443
        mode: host
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - $ACME_VOLUME:/etc/traefik/acme
      - $LOG_VOLUME:/var/log/traefik
    networks:
      - $NETWORK_NAME
    command:
      - "--api.dashboard=true"
      - "--providers.docker=true"
      - "--providers.docker.exposedByDefault=false"
      - "--providers.docker.network=$NETWORK_NAME"
      - "--providers.swarm=true"
      - "--entrypoints.web.address=:80"
      - "--entrypoints.web.http.redirections.entrypoint.to=websecure"
      - "--entrypoints.web.http.redirections.entrypoint.scheme=https"
      - "--entrypoints.websecure.address=:443"
      - "--certificatesresolvers.myresolver.acme.email=$LETSENCRYPT_EMAIL"
      - "--certificatesresolvers.myresolver.acme.storage=/etc/traefik/acme/acme.json"
      - "--certificatesresolvers.myresolver.acme.httpchallenge=true"
      - "--certificatesresolvers.myresolver.acme.httpchallenge.entrypoint=web"
      - "--log.level=DEBUG"
      - "--log.filePath=/var/log/traefik/traefik.log"
      - "--accesslog=true"
      - "--accesslog.filepath=/var/log/traefik/access.log"
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

volumes:
  $ACME_VOLUME:
    external: true
  $LOG_VOLUME:
    external: true
EOF
echo "Compose file created."
echo

# 3. Deploy the Traefik stack
echo "### Deploying Traefik stack '$STACK_NAME'... ###"
# Use a subshell with the new group to run docker commands
newgrp docker <<'END_DOCKER_DEPLOY'
docker stack deploy -c "$COMPOSE_FILE" "$STACK_NAME"
END_DOCKER_DEPLOY
echo

# --- Final Instructions ---
echo "####################################################################"
echo "###          PART 3 (TRAEFIK DEPLOYMENT) COMPLETE!               ###"
echo "####################################################################"
echo
echo "It may take a minute for the service to be available."
echo "You can check the status with the command: docker stack ps $STACK_NAME"
echo "If it fails, check the detailed log with: docker service logs ${STACK_NAME}_traefik"
echo
echo "Once running, access the Traefik dashboard at:"
echo "https://$TRAEFIK_DOMAIN"
echo