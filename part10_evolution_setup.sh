#!/bin/bash

# PART 10: EVOLUTION API DEPLOYMENT (Fully Automated)
#
# This definitive version asks for NO PASSWORDS. It automatically retrieves
# the Postgres, Redis, and S3 credentials from Docker Secrets and uses the
# proven .env file method to configure the Evolution API.
#
# It MUST be run as the non-root 'deploy' user.

set -e

# --- Configuration ---
NETWORK_NAME="main-proxy"
STACK_NAME="evolution"
COMPOSE_FILE="evolution.yml"
ENV_FILE_NAME="evolution_env_content"
CONFIG_NAME="evolution_env"
DATA_VOLUME="evolution_data"
API_KEY_SECRET="evolution_api_key"
S3_ACCESS_KEY_SECRET="evolution_s3_access_key"
S3_SECRET_KEY_SECRET="evolution_s3_secret_key"

# --- Interactive Setup ---
echo "### Evolution API Secure Setup ###"
read -p "Enter the domain for the Evolution API: " API_DOMAIN
read -p "Enter the domain for the Minio S3 API: " S3_API_DOMAIN
echo
read -sp "Enter your desired master API Key (or press Enter to generate one): " API_KEY
[ -z "$API_KEY" ] && API_KEY=$(openssl rand -hex 32) && echo && echo "Generated API Key: $API_KEY"
echo; echo
echo "----------------------------------------------------"
echo

# 1. Securely retrieve ALL existing passwords from Docker Secrets
echo "### Retrieving existing credentials from Docker Secrets... ###"
POSTGRES_PASS=$(docker run --rm --network none --secret postgres_password alpine cat /run/secrets/postgres_password)
REDIS_PASS=$(docker run --rm --network none --secret redis_password alpine cat /run/secrets/redis_password)
S3_ACCESS_KEY=$(docker run --rm --network none --secret $S3_ACCESS_KEY_SECRET alpine cat /run/secrets/$S3_ACCESS_KEY_SECRET)
S3_SECRET_KEY=$(docker run --rm --network none --secret $S3_SECRET_KEY_SECRET alpine cat /run/secrets/$S3_SECRET_KEY_SECRET)

if [ -z "$POSTGRES_PASS" ] || [ -z "$REDIS_PASS" ] || [ -z "$S3_ACCESS_KEY" ]; then
    echo "FATAL ERROR: Could not retrieve one or more required secrets." >&2
    echo "Please ensure you have successfully run the setup scripts for PostgreSQL, Redis, and Minio." >&2
    exit 1
fi
echo "All necessary credentials retrieved successfully."
echo

# 2. Create the .env file content
echo "### Creating environment file for Docker Config... ###"
cat > "$ENV_FILE_NAME" <<EOF
DATABASE_CONNECTION_URI=postgresql://postgres:${POSTGRES_PASS}@postgres:5432/evolution?sslmode=require
CACHE_REDIS_URI=redis://:${REDIS_PASS}@redis:6379/1
S3_ENDPOINT=${S3_API_DOMAIN}
S3_ACCESS_KEY=${S3_ACCESS_KEY}
S3_SECRET_KEY=${S3_SECRET_KEY}
EOF
echo "Environment file content created."
echo

# 3. Create/Update the Docker Config
docker config rm $CONFIG_NAME >/dev/null 2>&1
docker config create "$CONFIG_NAME" "$ENV_FILE_NAME"
rm "$ENV_FILE_NAME"
echo "Docker Config created and temporary file removed."
echo

# 4. Create the Docker Secret for the master API Key
docker secret rm $API_KEY_SECRET >/dev/null 2>&1
printf "%s" "$API_KEY" | docker secret create $API_KEY_SECRET -
echo "Master API Key secret created."
echo

# 5. Create the evolution.yml file
echo "### Creating Docker Compose file: $COMPOSE_FILE ###"
cat > "$COMPOSE_FILE" <<EOF
version: '3.8'
configs:
  $CONFIG_NAME: { external: true }
secrets:
  $API_KEY_SECRET: { external: true }
services:
  evolution-api:
    image: atendeai/evolution-api:v2.2.3
    volumes:
      - $DATA_VOLUME:/evolution/instances
    networks:
      - $NETWORK_NAME
    secrets:
      - $API_KEY_SECRET
    configs:
      - source: $CONFIG_NAME
        target: /evolution/.env
    environment:
      - SERVER_URL=https://$API_DOMAIN
      - DATABASE_ENABLED=true
      - DATABASE_PROVIDER=postgresql
      - CACHE_REDIS_ENABLED=true
      - S3_ENABLED=true
      - S3_BUCKET=evolution
      - S3_PORT=443
      - S3_USE_SSL=true
      - AUTHENTICATION_API_KEY_FILE=/run/secrets/$API_KEY_SECRET
    deploy:
      mode: replicated
      replicas: 1
      placement: { constraints: [node.role == manager] }
      labels:
        - "traefik.enable=true"
        - "traefik.http.routers.evolution-api.rule=Host(\`$API_DOMAIN\`)"
        - "traefik.http.routers.evolution-api.entrypoints=websecure"
        - "traefik.http.routers.evolution-api.tls=true"
        - "traefik.http.routers.evolution-api.tls.certresolver=myresolver"
        - "traefik.http.services.evolution-api-svc.loadbalancer.server.port=8080"
networks:
  $NETWORK_NAME: { external: true }
volumes:
  $DATA_VOLUME: { external: true }
EOF
echo "Compose file created."
echo

# 6. Deploy the stack
echo "### Deploying Evolution API stack '$STACK_NAME'... ###"
docker stack rm "$STACK_NAME" >/dev/null 2>&1 && sleep 5
docker volume create "$DATA_VOLUME" >/dev/null 2>&1
docker stack deploy -c "$COMPOSE_FILE" "$STACK_NAME"
echo

echo "####################################################################"
echo "###       EVOLUTION API DEPLOYMENT COMPLETE!                     ###"
echo "####################################################################"