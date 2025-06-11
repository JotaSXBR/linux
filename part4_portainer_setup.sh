#!/bin/bash

# PART 4: PORTAINER DEPLOYMENT (A Real-World Application Example)
#
# This script demonstrates the pattern for deploying a new service.
# It assumes parts 1, 2, and 3 are complete.
# It MUST be run as the non-root 'deploy' user.

# --- Configuration ---
NETWORK_NAME="main-proxy"
STACK_NAME="portainer"
COMPOSE_FILE="portainer.yml"
# Each new service gets its own managed volume for its data.
DATA_VOLUME="portainer_data"

# --- Pre-flight Checks ---
if ! docker info > /dev/null 2>&1; then
  echo "Error: Docker is not running or you don't have permission to use it."
  exit 1
fi

# --- Interactive Setup ---
echo "### Portainer Configuration Setup ###"
read -p "Enter the domain for Portainer (e.g., portainer.yourdomain.com): " PORTAINER_DOMAIN
echo "----------------------------------------------------"
echo

# --- Script Execution ---

# 1. Create the Docker Managed Volume for Portainer data
echo "### Creating Docker managed volume '$DATA_VOLUME'... ###"
if ! docker volume inspect "$DATA_VOLUME" >/dev/null 2>&1; then
  docker volume create "$DATA_VOLUME"
else
  echo "Volume '$DATA_VOLUME' already exists."
fi
echo

# 2. Create the portainer.yml file
echo "### Creating Docker Compose file: $COMPOSE_FILE... ###"
cat > "$COMPOSE_FILE" <<EOF
# portainer.yml
version: '3.8'

services:
  portainer:
    image: portainer/portainer-ce:latest
    volumes:
      # Mount the managed volume for persistent data
      - $DATA_VOLUME:/data
      # Mount the docker socket to allow Portainer to manage Docker
      - /var/run/docker.sock:/var/run/docker.sock
    networks:
      # Connect to the existing proxy network
      - $NETWORK_NAME
    deploy:
      mode: replicated
      replicas: 1
      placement:
        constraints:
          - node.role == manager
      labels:
        # --- Traefik Integration ---
        - "traefik.enable=true"
        # 1. The router for the domain
        - "traefik.http.routers.portainer.rule=Host(\`$PORTAINER_DOMAIN\`)"
        - "traefik.http.routers.portainer.tls=true"
        - "traefik.http.routers.portainer.tls.certresolver=myresolver"
        # 2. The service definition, telling Traefik where to send the traffic
        - "traefik.http.routers.portainer.service=portainer-svc"
        - "traefik.http.services.portainer-svc.loadbalancer.server.port=9000"
        # 3. Middleware to handle the HTTPS entrypoint for Portainer's UI
        - "traefik.http.routers.portainer.entrypoints=websecure"

networks:
  $NETWORK_NAME:
    external: true

volumes:
  $DATA_VOLUME:
    external: true
EOF
echo "Compose file created."
echo

# 3. Deploy the Portainer stack
echo "### Deploying Portainer stack '$STACK_NAME'... ###"
docker stack deploy -c "$COMPOSE_FILE" "$STACK_NAME"
echo

# --- Final Instructions ---
echo "####################################################################"
echo "###          PORTAINER DEPLOYMENT COMPLETE!                      ###"
echo "####################################################################"
echo
echo "It may take a minute for the service to be available."
echo "You can check the status with the command: docker stack ps $STACK_NAME"
echo
echo "Once running, access Portainer at:"
echo "https://$PORTAINER_DOMAIN"
echo