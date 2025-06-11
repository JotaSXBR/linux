#!/bin/bash

# PART 3: TRAEFIK DEPLOYMENT (v5 - TCP Enabled)
#
# UPDATE: Adds a new TCP entrypoint for PostgreSQL on port 5432.
#
# This script deploys Traefik using a clean configuration.
# It MUST be run as the non-root 'deploy' user.

# --- Configuration ---
NETWORK_NAME="main-proxy"
ACME_VOLUME="traefik-acme"
LOG_VOLUME="traefik-logs"
STACK_NAME="traefik"
COMPOSE_FILE="traefik.yml"
DEFAULT_TRAEFIK_VERSION="v3.0"

# --- Pre-flight Checks ---
if ! docker info > /dev/null 2>&1; then
  echo "Error: Docker is not running or you don't have permission to use it."
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
HASHED_PASSWORD=$(openssl passwd -apr1 "$DASHBOARD_PASS" | sed 's/\$/\$\$/g')
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
      # Expose the Postgres port
      - target: 5432
        published: 5432
        mode: host
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - $ACME_VOLUME:/etc/traefik/acme
      - $LOG_VOLUME:/var/log/traefik
    networks:
      - $NETWORK_NAME
    command:
      - "--api.dashboard=true"
      - "--providers.swarm=true"
      - "--providers.swarm.exposedByDefault=false"
      - "--entrypoints.web.address=:80"
      - "--entrypoints.websecure.address=:443"
      # --- NEW: Define the Postgres TCP Entrypoint ---
      - "--entrypoints.postgres.address=:5432"
      - "--entrypoints.web.http.redirections.entrypoint.to=websecure"
      - "--entrypoints.web.http.redirections.entrypoint.scheme=https"
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

echo "### Deploying Traefik stack '$STACK_NAME'... ###"
docker stack deploy -c "$COMPOSE_FILE" "$STACK_NAME"
echo "### Traefik deployment complete. ###"