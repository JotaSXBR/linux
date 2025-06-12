#!/bin/bash

# PART 9: MINIO DEPLOYMENT (v12 - Simplified)
# This script now has only ONE responsibility: to deploy a clean
# Minio server with a secure root user. All application-specific setup
# has been moved to the application's own script.
# It MUST be run as the non-root 'deploy' user.

set -e # Exit immediately if a command exits with a non-zero status.

# --- Configuration ---
NETWORK_NAME="main-proxy"
STACK_NAME="minio"
COMPOSE_FILE="minio.yml"
DATA_VOLUME="minio_data"
ROOT_USER_SECRET="minio_root_user"
ROOT_PASS_SECRET="minio_root_password"
MINIO_IMAGE_TAG="RELEASE.2025-04-22T22-12-26Z"

# --- Pre-flight Checks ---
if ! docker info > /dev/null 2>&1; then
    echo "Error: Docker is not running or you don't have permission to use it."
    exit 1
fi

# --- Interactive Setup ---
echo "### Minio Secure Setup ###"
read -p "Enter the domain for the Minio API (e.g., s3-api.yourdomain.com): " MINIO_API_DOMAIN
read -p "Enter the domain for the Minio Console (e.g., s3.yourdomain.com): " MINIO_CONSOLE_DOMAIN
echo

read -p "Enter the ROOT username for Minio (or press Enter to default to 'admin'): " MINIO_ROOT_USER
if [ -z "$MINIO_ROOT_USER" ]; then
    MINIO_ROOT_USER="admin"
    echo "Username not provided, defaulting to 'admin'."
fi

while true; do
    read -sp "Enter the ROOT password for Minio (at least 20 chars, or Enter to generate): " MINIO_ROOT_PASS
    echo
    if [ -z "$MINIO_ROOT_PASS" ]; then
        echo "No password entered. Generating a secure 20-character password..."
        MINIO_ROOT_PASS=$(openssl rand -hex 10)
        echo "SAVE THIS ROOT PASSWORD! You will need it for Minio administration and for other setup scripts."
        echo "  $MINIO_ROOT_PASS"
        break
    elif [ ${#MINIO_ROOT_PASS} -ge 20 ]; then
        echo "Root password accepted."
        break
    else
        echo "Error: Password is only ${#MINIO_ROOT_PASS} characters. Minio requires >= 20." >&2
    fi
done
echo "----------------------------------------------------"
echo

# --- Script Execution ---

# 1. Create the Docker Managed Volume
echo "### Creating Docker managed volume '$DATA_VOLUME'... ###"
if ! docker volume inspect "$DATA_VOLUME" >/dev/null 2>&1; then
    docker volume create "$DATA_VOLUME"
else
    echo "Volume '$DATA_VOLUME' already exists."
fi
echo

# 2. Create the Docker Secrets for the Minio ROOT credentials
echo "### Creating Docker secrets for Minio ROOT credentials... ###"
docker secret rm $ROOT_USER_SECRET 2>/dev/null || true
docker secret rm $ROOT_PASS_SECRET 2>/dev/null || true

printf "%s" "$MINIO_ROOT_USER" | docker secret create "$ROOT_USER_SECRET" -
printf "%s" "$MINIO_ROOT_PASS" | docker secret create "$ROOT_PASS_SECRET" -
echo "Root secrets created successfully."
echo

# 3. Create the minio.yml file
echo "### Creating Docker Compose file: $COMPOSE_FILE ###"
cat > "$COMPOSE_FILE" <<EOF
version: '3.8'
services:
  minio:
    image: minio/minio:$MINIO_IMAGE_TAG
    command: server /data --console-address ":9001"
    environment:
      MINIO_ROOT_USER_FILE: /run/secrets/$ROOT_USER_SECRET
      MINIO_ROOT_PASSWORD_FILE: /run/secrets/$ROOT_PASS_SECRET
      MINIO_SERVER_URL: "https://$MINIO_API_DOMAIN"
      MINIO_BROWSER_REDIRECT_URL: "https://$MINIO_CONSOLE_DOMAIN"
    networks:
      - $NETWORK_NAME
    volumes:
      - $DATA_VOLUME:/data
    secrets:
      - $ROOT_USER_SECRET
      - $ROOT_PASS_SECRET
    deploy:
      mode: replicated
      replicas: 1
      placement:
        constraints:
          - node.role == manager
      labels:
        - "traefik.enable=true"
        - "traefik.docker.network=$NETWORK_NAME"
        - "traefik.http.routers.minio-api.rule=Host(\`$MINIO_API_DOMAIN\`)"
        - "traefik.http.routers.minio-api.entrypoints=websecure"
        - "traefik.http.routers.minio-api.tls=true"
        - "traefik.http.routers.minio-api.tls.certresolver=myresolver"
        - "traefik.http.routers.minio-api.service=minio-api-svc"
        - "traefik.http.services.minio-api-svc.loadbalancer.server.port=9000"
        - "traefik.http.routers.minio-console.rule=Host(\`$MINIO_CONSOLE_DOMAIN\`)"
        - "traefik.http.routers.minio-console.entrypoints=websecure"
        - "traefik.http.routers.minio-console.tls=true"
        - "traefik.http.routers.minio-console.tls.certresolver=myresolver"
        - "traefik.http.routers.minio-console.service=minio-console-svc"
        - "traefik.http.services.minio-console-svc.loadbalancer.server.port=9001"
networks:
  $NETWORK_NAME:
    external: true
volumes:
  $DATA_VOLUME:
    external: true
secrets:
  $ROOT_USER_SECRET:
    external: true
  $ROOT_PASS_SECRET:
    external: true
EOF
echo "Compose file created."
echo

# 4. Deploy the Minio stack
echo "### Deploying Minio stack '$STACK_NAME' from '$COMPOSE_FILE'... ###"
docker stack deploy -c "$COMPOSE_FILE" "$STACK_NAME"
echo

# --- Final Instructions ---
echo "####################################################################"
echo "###          MINIO DEPLOYMENT COMPLETE!                          ###"
echo "####################################################################"
echo
echo "Minio is now running. Please wait a minute for it to fully initialize."
echo "The next script you run will ask for the Minio root credentials to configure its dependencies."
echo
echo "  - Minio Root User:     $MINIO_ROOT_USER"
echo "  - Minio Root Password: [the password you set or generated]"
echo