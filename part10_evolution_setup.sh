#!/bin/bash

# PART 10: EVOLUTION API DEPLOYMENT (v9 - Self-Contained)
# UPDATE: This script now handles its own Minio dependency setup. It uses the
# Minio root credentials to create a bucket and a dedicated, less-privileged
# user for itself. This is the definitive, working version.
# It MUST be run as the non-root 'deploy' user.

set -e # Exit immediately if a command exits with a non-zero status.

# --- Configuration ---
NETWORK_NAME="main-proxy"
STACK_NAME="evolution"
COMPOSE_FILE="evolution.yml"
ENV_FILE_NAME="evolution_env_content"
CONFIG_NAME="evolution_env"
DATA_VOLUME="evolution_data"
API_KEY_SECRET="evolution_api_key"
S3_USER_SECRET="evolution_s3_user"
S3_PASS_SECRET="evolution_s3_pass"

# Minio dependency configuration
MINIO_STACK_NAME="minio"
EVOLUTION_BUCKET_NAME="evolution"
EVOLUTION_POLICY_NAME="evolution-api-policy"

# --- Pre-flight Checks ---
if ! docker info > /dev/null 2>&1; then
    echo "Error: Docker is not running or you don't have permission to use it."
    exit 1
fi

# --- Interactive Setup ---
echo "### Evolution API Secure Setup ###"
read -p "Enter the domain for the Evolution API (e.g., whatsapp-api.yourdomain.com): " API_DOMAIN
echo

# --- Credential Setup ---
echo "--- API Key ---"
read -sp "Enter your desired API Key (or press Enter to generate a secure one): " API_KEY
if [ -z "$API_KEY" ]; then
    echo; echo "No API Key entered. Generating a secure 32-character key..."
    API_KEY=$(openssl rand -hex 32)
    echo "SAVE THIS API KEY! You will need it to interact with the API:"
    echo "  $API_KEY"
fi
echo; echo

echo "--- PostgreSQL Database Credentials (from Part 5) ---"
read -sp "Enter the password for your 'postgres' database: " POSTGRES_PASS
echo; echo

echo "--- Redis Credentials (from Part 7) ---"
read -sp "Enter the password for your 'redis' database: " REDIS_PASS
echo; echo

echo "--- Minio/S3 Dependency Setup ---"
echo "This script will create a dedicated user in Minio for the Evolution API."
echo "Please provide the Minio ROOT credentials from Part 9."
read -p "Enter the Minio ROOT username: " MINIO_ROOT_USER
read -sp "Enter the Minio ROOT password: " MINIO_ROOT_PASS
echo; echo

echo "Now, define the credentials for the NEW dedicated user that will be created."
read -p "Enter a username for the Evolution API's Minio access (or press Enter to default to 'evolution-user'): " EVOLUTION_MINIO_USER
if [ -z "$EVOLUTION_MINIO_USER" ]; then
    EVOLUTION_MINIO_USER="evolution-user"
    echo "Username not provided, defaulting to 'evolution-user'."
fi

while true; do
    read -sp "Enter a password for this new user (at least 20 chars, or Enter to generate): " EVOLUTION_MINIO_PASS
    echo
    if [ -z "$EVOLUTION_MINIO_PASS" ]; then
        echo "No password entered. Generating a secure 20-character password..."
        EVOLUTION_MINIO_PASS=$(openssl rand -hex 10)
        echo "This is the generated password for the new Minio user:"
        echo "  $EVOLUTION_MINIO_PASS"
        break
    elif [ ${#EVOLUTION_MINIO_PASS} -ge 20 ]; then
        echo "New user password accepted."
        break
    else
        echo "Error: Password is only ${#EVOLUTION_MINIO_PASS} characters. Minio requires >= 20." >&2
    fi
done
echo "----------------------------------------------------"
echo

# --- Script Execution ---

# 1. Configure Minio Dependencies
echo "### Configuring Minio bucket, user, and policy... ###"
MINIO_TASK_ID=""
while [ -z "$MINIO_TASK_ID" ]; do
    echo "Waiting for running Minio task..."
    MINIO_TASK_ID=$(docker service ps ${MINIO_STACK_NAME}_minio -f "desired-state=running" --format "{{.ID}}" --no-trunc | head -n 1)
    sleep 2
done

MINIO_CONTAINER_ID=$(docker inspect "$MINIO_TASK_ID" --format '{{.Status.ContainerStatus.ContainerID}}')
while [ -z "$MINIO_CONTAINER_ID" ]; do
    echo "Waiting for container ID to be assigned to task..."
    sleep 2
    MINIO_CONTAINER_ID=$(docker inspect "$MINIO_TASK_ID" --format '{{.Status.ContainerStatus.ContainerID}}')
done

echo "Minio container found. Configuring..."
docker exec "$MINIO_CONTAINER_ID" mc alias set local http://127.0.0.1:9000 "$MINIO_ROOT_USER" "$MINIO_ROOT_PASS"
docker exec "$MINIO_CONTAINER_ID" mc mb --ignore-existing local/"$EVOLUTION_BUCKET_NAME"

POLICY_JSON='{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Action":["s3:GetObject","s3:PutObject","s3:DeleteObject","s3:ListBucket","s3:GetBucketLocation","s3:ListBucketMultipartUploads","s3:AbortMultipartUpload","s3:ListMultipartUploadParts"],"Resource":["arn:aws:s3:::'"$EVOLUTION_BUCKET_NAME"'","arn:aws:s3:::'"$EVOLUTION_BUCKET_NAME"'/*"]}]}'
echo "$POLICY_JSON" | docker exec -i "$MINIO_CONTAINER_ID" mc admin policy create local "$EVOLUTION_POLICY_NAME" /dev/stdin
docker exec "$MINIO_CONTAINER_ID" mc admin user add local "$EVOLUTION_MINIO_USER" "$EVOLUTION_MINIO_PASS"
docker exec "$MINIO_CONTAINER_ID" mc admin policy attach local "$EVOLUTION_POLICY_NAME" --user "$EVOLUTION_MINIO_USER"
echo "Minio dependency setup complete."
echo

# 2. Create a temporary file with the .env content
echo "### Creating temporary environment file for Docker Config... ###"
cat > "$ENV_FILE_NAME" <<EOF
DATABASE_CONNECTION_URI=postgresql://postgres:${POSTGRES_PASS}@postgres:5432/evolution
CHATWOOT_IMPORT_DATABASE_CONNECTION_URI=postgresql://postgres:${POSTGRES_PASS}@postgres:5432/chatwoot?sslmode=disable
REDIS_URI=redis://:${REDIS_PASS}@redis:6379/1
EOF
echo "Temporary file created."
echo

# 3. Create/Update the Docker Config
echo "### Creating Docker Config '$CONFIG_NAME'... ###"
docker config rm $CONFIG_NAME 2>/dev/null || true
docker config create "$CONFIG_NAME" "$ENV_FILE_NAME"
echo "Docker Config created."
echo

# 4. Clean up the temporary file from the host
rm "$ENV_FILE_NAME"
echo "Cleaned up temporary file."
echo

# 5. Create the Docker Managed Volume
echo "### Creating Docker managed volume '$DATA_VOLUME'... ###"
if ! docker volume inspect "$DATA_VOLUME" >/dev/null 2>&1; then
    docker volume create "$DATA_VOLUME"
else
    echo "Volume '$DATA_VOLUME' already exists."
fi
echo

# 6. Create the Docker Secrets
echo "### Creating Docker secrets... ###"
docker secret rm $API_KEY_SECRET 2>/dev/null || true
docker secret rm $S3_USER_SECRET 2>/dev/null || true
docker secret rm $S3_PASS_SECRET 2>/dev/null || true

printf "%s" "$API_KEY" | docker secret create $API_KEY_SECRET -
printf "%s" "$EVOLUTION_MINIO_USER" | docker secret create $S3_USER_SECRET -
printf "%s" "$EVOLUTION_MINIO_PASS" | docker secret create $S3_PASS_SECRET -
echo "Secrets created successfully."
echo

# 7. Create the evolution.yml file
echo "### Creating Docker Compose file: $COMPOSE_FILE ###"
cat > "$COMPOSE_FILE" <<EOF
version: '3.8'

configs:
  $CONFIG_NAME:
    external: true

secrets:
  $API_KEY_SECRET:
    external: true
  $S3_USER_SECRET:
    external: true
  $S3_PASS_SECRET:
    external: true

services:
  evolution-api:
    image: evoapicloud/evolution-api:v2.2.3
    volumes:
      - $DATA_VOLUME:/evolution/instances
    networks:
      - $NETWORK_NAME
    secrets:
      - $API_KEY_SECRET
      - $S3_USER_SECRET
      - $S3_PASS_SECRET
    configs:
      - source: $CONFIG_NAME
        target: /evolution/.env
    environment:
      - SERVER_URL=https://$API_DOMAIN
      - DATABASE_ENABLED=true
      - DATABASE_PROVIDER=postgresql
      - DATABASE_SAVE_DATA_INSTANCE=true
      - CACHE_REDIS_ENABLED=true
      - CACHE_REDIS_PREFIX_KEY=evolution_api
      - CACHE_REDIS_SAVE_INSTANCES=true
      - CACHE_LOCAL_ENABLED=false
      - S3_ENABLED=true
      - S3_ACCESS_KEY_FILE=/run/secrets/$S3_USER_SECRET
      - S3_SECRET_KEY_FILE=/run/secrets/$S3_PASS_SECRET
      - S3_BUCKET=evolution
      - S3_PORT=443
      - S3_ENDPOINT=${API_DOMAIN/whatsapp-api/s3-api} # This needs to be set correctly
      - S3_USE_SSL=true
      - AUTHENTICATION_API_KEY_FILE=/run/secrets/$API_KEY_SECRET
      - AUTHENTICATION_EXPOSE_IN_FETCH_INSTANCES=true
      - LANGUAGE=pt-BR
      - DEL_INSTANCE=true
      - QRCODE_LIMIT=10
      - OPENAI_ENABLED=true
      - DIFY_ENABLED=true
      - TYPEBOT_ENABLED=true
      - CHATWOOT_ENABLED=true
    deploy:
      mode: replicated
      replicas: 1
      placement:
        constraints:
          - node.role == manager
      resources:
        limits:
          cpus: "1"
          memory: 1024M
      labels:
        - "traefik.enable=true"
        - "traefik.docker.network=$NETWORK_NAME"
        - "traefik.http.routers.evolution-api.rule=Host(\`$API_DOMAIN\`)"
        - "traefik.http.routers.evolution-api.entrypoints=websecure"
        - "traefik.http.routers.evolution-api.tls=true"
        - "traefik.http.routers.evolution-api.tls.certresolver=myresolver"
        - "traefik.http.routers.evolution-api.service=evolution-api-svc"
        - "traefik.http.services.evolution-api-svc.loadbalancer.server.port=8080"

networks:
  $NETWORK_NAME:
    external: true

volumes:
  $DATA_VOLUME:
    external: true
EOF
echo "Compose file created."
echo

# 8. Deploy the stack
echo "### Deploying Evolution API stack '$STACK_NAME' from '$COMPOSE_FILE'... ###"
docker stack deploy -c "$COMPOSE_FILE" "$STACK_NAME"
echo

# --- Final Instructions ---
echo "####################################################################"
echo "###       EVOLUTION API DEPLOYMENT COMPLETE!                     ###"
echo "####################################################################"
echo
echo "The Evolution API is now running and accessible at: https://$API_DOMAIN"
echo
echo "You must use the API Key for all requests. Your key is:"
echo "  $API_KEY"
echo