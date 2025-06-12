#!/bin/bash

# PART 7: REDIS & REDISINSIGHT DEPLOYMENT (v2 - Secured)
# This script deploys a Redis database and the RedisInsight web UI.
# Redis is kept internal. RedisInsight is exposed via Traefik and
# secured with mandatory Basic Authentication middleware.
# It MUST be run as the non-root 'deploy' user.

# --- Configuration ---
NETWORK_NAME="main-proxy"
STACK_NAME="redis"
COMPOSE_FILE="redis.yml"
REDIS_DATA_VOLUME="redis_data"
REDISINSIGHT_DATA_VOLUME="redisinsight_data"
SECRET_NAME="redis_password"

# --- Pre-flight Checks ---
if ! docker info > /dev/null 2>&1; then
    echo "Error: Docker is not running or you don't have permission to use it."
    exit 1
fi

# --- Interactive Setup ---
echo "### Redis & RedisInsight Secure Setup ###"
read -p "Enter the domain for RedisInsight (e.g., redis.yourdomain.com): " REDISINSIGHT_DOMAIN
read -sp "Enter the password for the Redis database (or press Enter to generate a secure one): " REDIS_SECRET_VALUE
echo
echo
echo "### RedisInsight UI Authentication ###"
echo "You will now create login credentials to protect the web UI."
read -p "Enter a username for the RedisInsight UI: " UI_USER
read -sp "Enter a password for the RedisInsight UI: " UI_PASS
echo
echo "----------------------------------------------------"
echo

# --- Script Execution ---

# 1. Generate a Redis password if one was not provided
if [ -z "$REDIS_SECRET_VALUE" ]; then
    echo "No Redis password entered. Generating a secure 32-character password..."
    REDIS_SECRET_VALUE=$(openssl rand -hex 32)
    echo
    echo "####################################################################"
    echo "### SAVE THIS PASSWORD! This is your new Redis password:         ###"
    echo "  $REDIS_SECRET_VALUE"
    echo "####################################################################"
    echo
fi

# 2. Generate the hashed password for the UI
echo "### Generating UI password hash for Traefik... ###"
# We use printf to avoid newline characters and -stdin for security.
# The sed command correctly escapes the dollar signs in the hash for the heredoc.
HASHED_UI_PASSWORD=$(printf "%s" "$UI_PASS" | openssl passwd -apr1 -stdin | sed 's/\$/\$\$/g')
echo "Password hash created."
echo

# 3. Create Docker Managed Volumes
echo "### Creating Docker managed volumes... ###"
if ! docker volume inspect "$REDIS_DATA_VOLUME" >/dev/null 2>&1; then
    docker volume create "$REDIS_DATA_VOLUME"
else
    echo "Volume '$REDIS_DATA_VOLUME' already exists."
fi
if ! docker volume inspect "$REDISINSIGHT_DATA_VOLUME" >/dev/null 2>&1; then
    docker volume create "$REDISINSIGHT_DATA_VOLUME"
else
    echo "Volume '$REDISINSIGHT_DATA_VOLUME' already exists."
fi
echo

# 4. Create the Docker Secret for the Redis password
echo "### Creating Docker secret '$SECRET_NAME'... ###"
if docker secret inspect "$SECRET_NAME" >/dev/null 2>&1; then
    docker secret rm "$SECRET_NAME"
    echo "Removed existing secret to create a new one."
fi
printf "%s" "$REDIS_SECRET_VALUE" | docker secret create "$SECRET_NAME" -
echo "Secret created successfully."
echo

# 5. Create the redis.yml file
echo "### Creating Docker Compose file: $COMPOSE_FILE ###"
cat > "$COMPOSE_FILE" <<EOF
version: '3.8'

services:
  redis:
    image: redis:7-alpine
    environment:
      # Use the official Redis variable to read the password from the secret file
      REDIS_PASSWORD_FILE: /run/secrets/$SECRET_NAME
    networks:
      - $NETWORK_NAME
    volumes:
      - $REDIS_DATA_VOLUME:/data
    secrets:
      - $SECRET_NAME
    deploy:
      mode: replicated
      replicas: 1
      placement:
        constraints:
          - node.role == manager

  redisinsight:
    image: redis/redisinsight:latest
    networks:
      - $NETWORK_NAME
    volumes:
      - $REDISINSIGHT_DATA_VOLUME:/db
    deploy:
      mode: replicated
      replicas: 1
      placement:
        constraints:
          - node.role == manager
      labels:
        # 1. Traefik General
        - "traefik.enable=true"
        - "traefik.docker.network=$NETWORK_NAME"

        # 2. Traefik Router Definition with Middleware
        - "traefik.http.routers.redisinsight.rule=Host(\`$REDISINSIGHT_DOMAIN\`)"
        - "traefik.http.routers.redisinsight.entrypoints=websecure"
        - "traefik.http.routers.redisinsight.tls=true"
        - "traefik.http.routers.redisinsight.tls.certresolver=myresolver"
        - "traefik.http.routers.redisinsight.service=redisinsight-svc"
        - "traefik.http.routers.redisinsight.middlewares=redisinsight-auth"

        # 3. Traefik Service Definition
        - "traefik.http.services.redisinsight-svc.loadbalancer.server.port=5540"

        # 4. Middleware for Basic Authentication
        - "traefik.http.middlewares.redisinsight-auth.basicauth.users=$UI_USER:$HASHED_UI_PASSWORD"

networks:
  $NETWORK_NAME:
    external: true

volumes:
  $REDIS_DATA_VOLUME:
    external: true
  $REDISINSIGHT_DATA_VOLUME:
    external: true

secrets:
  $SECRET_NAME:
    external: true
EOF
echo "Compose file created."
echo

# 6. Deploy the Redis stack
echo "### Deploying Redis stack '$STACK_NAME' from '$COMPOSE_FILE'... ###"
docker stack deploy -c "$COMPOSE_FILE" "$STACK_NAME"
echo

# --- Final Instructions ---
echo "####################################################################"
echo "###      REDIS & REDISINSIGHT DEPLOYMENT COMPLETE!               ###"
echo "####################################################################"
echo
echo "The services have been deployed."
echo
echo "--- How to Check Status ---"
echo "To check the running state: docker stack ps $STACK_NAME"
echo
echo "--- How to Connect ---"
echo "Access RedisInsight at: https://$REDISINSIGHT_DOMAIN"
echo "You will be prompted for the UI username and password you just created."
echo
echo "Inside RedisInsight, add a new Redis Database with these details:"
echo "  Host:     redis"
echo "  Port:     6379"
echo "  Password: [The Redis password you set or generated]"
echo