#!/bin/bash

# PART 5: POSTGRES DEPLOYMENT (v2 - with Secure Password Generation)
#
# UPDATE: If the user does not provide a password, this script will now
#         generate a cryptographically secure one and display it.
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
# Securely prompt for the password without showing it on screen
read -sp "Enter the password for the PostgreSQL database (or press Enter to generate a secure one): " POSTGRES_SECRET_VALUE
echo
echo "----------------------------------------------------"
echo

# --- Script Execution ---

# 1. Generate a password if one was not provided
if [ -z "$POSTGRES_SECRET_VALUE" ]; then
    echo "### No password entered. Generating a secure password... ###"
    # Use openssl to generate a random, URL-safe base64 string
    POSTGRES_SECRET_VALUE=$(openssl rand -base64 32)
    echo
    echo "****************************************************************"
    echo "SAVE THIS PASSWORD! This is your new PostgreSQL password:"
    echo
    echo "  $POSTGRES_SECRET_VALUE"
    echo
    echo "****************************************************************"
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