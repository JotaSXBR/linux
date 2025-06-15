#!/bin/bash

# PART 9: MINIO DEPLOYMENT (Secure Edition)
#
# This script securely deploys the Minio service based on the analysis
# of your previous configuration. It uses Docker Secrets for credentials
# and adapts the networking and Traefik labels to our new architecture.

set -e

# --- Configuration ---
NETWORK_NAME="main-proxy"
STACK_NAME="minio"
COMPOSE_FILE="minio.yml"
DATA_VOLUME="minio_data"
ROOT_PASS_SECRET="minio_root_password"

# --- Interactive Setup ---
echo "### Minio Secure Setup ###"
read -p "Enter the domain for the Minio Console UI (e.g., s3.fluxie.com.br): " MINIO_CONSOLE_DOMAIN
read -p "Enter the domain for the Minio S3 API (e.g., s3api.fluxie.com.br): " MINIO_API_DOMAIN
read -sp "Enter the Minio ROOT password (or press Enter to generate one): " MINIO_ROOT_PASSWORD
echo
[ -z "$MINIO_ROOT_PASSWORD" ] && MINIO_ROOT_PASSWORD=$(openssl rand -hex 32) && echo "Generated Root Password: $MINIO_ROOT_PASSWORD"
echo "----------------------------------------------------"
echo

# --- Script Execution ---

# 1. Clean up and create the root password secret
echo "### Creating Docker secret for Minio root user... ###"
docker secret rm "$ROOT_PASS_SECRET" >/dev/null 2>&1 || true
printf "%s" "$MINIO_ROOT_PASSWORD" | docker secret create "$ROOT_PASS_SECRET" -
echo "Secret created."
echo

# 2. Create the minio.yml file
echo "### Creating Docker Compose file: $COMPOSE_FILE ###"
cat > "$COMPOSE_FILE" <<EOF
version: '3.8'
services:
  minio:
    image: minio/minio:RELEASE.2025-04-22T22-12-26Z
    command: server /data --console-address ":9001"
    environment:
      MINIO_ROOT_USER: "root"
      MINIO_ROOT_PASSWORD_FILE: /run/secrets/$ROOT_PASS_SECRET
      MINIO_SERVER_URL: "https://$MINIO_API_DOMAIN"
      MINIO_BROWSER_REDIRECT_URL: "https://$MINIO_CONSOLE_DOMAIN"
    volumes:
      - $DATA_VOLUME:/data
    networks:
      - $NETWORK_NAME
    secrets:
      - $ROOT_PASS_SECRET
    deploy:
      mode: replicated
      replicas: 1
      placement:
        constraints: [node.role == manager]
      labels:
        - "traefik.enable=true"
        - "traefik.docker.network=$NETWORK_NAME"

        # --- Router for the S3 API ($MINIO_API_DOMAIN) ---
        - "traefik.http.routers.minio-api.rule=Host(\`$MINIO_API_DOMAIN\`)"
        - "traefik.http.routers.minio-api.entrypoints=websecure"
        - "traefik.http.routers.minio-api.tls=true"
        - "traefik.http.routers.minio-api.tls.certresolver=myresolver"
        - "traefik.http.routers.minio-api.service=minio-api-svc"
        - "traefik.http.services.minio-api-svc.loadbalancer.server.port=9000"
        - "traefik.http.services.minio-api-svc.loadbalancer.passhostheader=true"

        # --- Router for the Console UI ($MINIO_CONSOLE_DOMAIN) ---
        - "traefik.http.routers.minio-console.rule=Host(\`$MINIO_CONSOLE_DOMAIN\`)"
        - "traefik.http.routers.minio-console.entrypoints=websecure"
        - "traefik.http.routers.minio-console.tls=true"
        - "traefik.http.routers.minio-console.tls.certresolver=myresolver"
        - "traefik.http.routers.minio-console.service=minio-console-svc"
        - "traefik.http.services.minio-console-svc.loadbalancer.server.port=9001"
        - "traefik.http.services.minio-console-svc.loadbalancer.passhostheader=true"

networks:
  $NETWORK_NAME: { external: true }
volumes:
  $DATA_VOLUME: { external: true }
secrets:
  $ROOT_PASS_SECRET: { external: true }
EOF
echo "Compose file created."
echo

# 3. Deploy the Minio stack
echo "### Deploying Minio stack '$STACK_NAME'... ###"
docker stack rm "$STACK_NAME" >/dev/null 2>&1 || true
sleep 5
docker volume rm "$DATA_VOLUME" >/dev/null 2>&1 || true
docker volume create "$DATA_VOLUME" >/dev/null 2>&1
docker stack deploy -c "$COMPOSE_FILE" "$STACK_NAME"
echo

echo "####################################################################"
echo "###          MINIO DEPLOYMENT COMPLETE!                          ###"
echo "####################################################################"
echo "Minio is deploying. You can log into the console to manage it."
echo "Console URL: https://$MINIO_CONSOLE_DOMAIN"
echo "Username:    root"
echo "Password:    [The password you set or was generated]"
echo
echo "What is our next step?"
echo "####################################################################"