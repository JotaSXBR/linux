#!/bin/bash

# PART 5: POSTGRES DEPLOYMENT (v3 - with Safe Password Generation)
#
# UPDATE: Uses 'openssl rand -hex' to generate a universally safe password
#         that contains no special characters, preventing issues with web UIs
#         like Adminer.
#
# This script deploys a PostgreSQL database using Docker Secrets.
# It MUST be run as the non-root 'deploy' user.

# --- Configuration ---
NETWORK_NAME="main-proxy"
STACK_NAME="postgres"
COMPOSE_FILE="postgres.yml"
DATA_VOLUME="postgres_data"
SECRET_NAME="postgres_password"

# --- Pre-flight Checks ---
if ! docker info > /dev/null 2>&1; then
  echo "Error: Docker is not running or you don't have permission to use it."
  exit 1
fi

# --- Interactive Setup ---
echo "### PostgreSQL Secure Setup ###"
read -sp "Enter the password for the PostgreSQL database (or press Enter to generate a secure one): " POSTGRES_SECRET_VALUE
echo
echo "----------------------------------------------------"
echo

# --- Script Execution ---

# 1. Generate a password if one was not provided
if [ -z "$POSTGRES_SECRET_VALUE" ]; then
    echo "### No password entered. Generating a secure, URL-safe password... ###"
    # FIX: Use 'openssl rand -hex' to generate a password with only 0-9 and a-f.
    # This is universally safe for web forms and connection strings.
    POSTGRES_SECRET_VALUE=$(openssl rand -hex 32)
    echo
    echo "******************************************************************"
    echo "SAVE THIS PASSWORD! This is your new PostgreSQL password:"
    echo
    echo "  $POSTGRES_SECRET_VALUE"
    echo
    echo "******************************************************************"
    echo
fi

# 2. Create the Docker Managed Volume for Postgres data
echo "### Creating Docker managed volume '$DATA_VOLUME'... ###"
if ! docker volume inspect "$DATA_VOLUME" >/dev/null 2>&1; then
  docker volume create "$DATA_VOLUME"
else
  echo "Volume '$DATA_VOLUME' already exists."
fi
echo

# 3. Create the Docker Secret for the password
echo "### Creating Docker secret '$SECRET_NAME'... ###"
if docker secret inspect "$SECRET_NAME" >/dev/null 2>&1; then
  docker secret rm "$SECRET_NAME"
  echo "Removed existing secret to create a new one."
fi
printf "%s" "$POSTGRES_SECRET_VALUE" | docker secret create "$SECRET_NAME" -
echo "Secret created successfully."
echo

# 4. Create the postgres.yml file
echo "### Creating Docker Compose file: $COMPOSE_FILE... ###"
cat > "$COMPOSE_FILE" <<EOF
# postgres.yml
version: '3.8'

services:
  postgres:
    image: pgvector/pgvector:pg16
    environment:
      - POSTGRES_PASSWORD_FILE=/run/secrets/$SECRET_NAME
      - TZ=America/Sao_Paulo
    networks:
      - $NETWORK_NAME
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U postgres"]
      interval: 10s
      timeout: 5s
      retries: 10
    volumes:
      - $DATA_VOLUME:/var/lib/postgresql/data
    secrets:
      - $SECRET_NAME
    deploy:
      mode: replicated
      replicas: 1
      placement:
        constraints:
          - node.role == manager
      resources:
        limits:
          cpus: "1"
          memory: 4096M

networks:
  $NETWORK_NAME:
    external: true

volumes:
  $DATA_VOLUME:
    external: true

secrets:
  $SECRET_NAME:
    external: true
EOF
echo "Compose file created."
echo

# 5. Deploy the Postgres stack
echo "### Deploying Postgres stack '$STACK_NAME'... ###"
docker stack deploy -c "$COMPOSE_FILE" "$STACK_NAME"
echo

# --- Final Instructions ---
echo "####################################################################"
echo "###          POSTGRES DEPLOYMENT COMPLETE!                       ###"
echo "####################################################################"
echo
echo "The PostgreSQL database is now running securely."
echo "Other services on the '$NETWORK_NAME' network can connect to it using the hostname: 'postgres'"
echo