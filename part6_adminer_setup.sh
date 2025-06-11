#!/bin/bash

# PART 6: ADMINER DEPLOYMENT (Web-Based Database UI)
#
# This script deploys Adminer, a web UI for database management.
# It will be exposed via Traefik with a secure HTTPS connection.
# It MUST be run as the non-root 'deploy' user.

# --- Configuration ---
NETWORK_NAME="main-proxy"
STACK_NAME="adminer"
COMPOSE_FILE="adminer.yml"

# --- Pre-flight Checks ---
if ! docker info > /dev/null 2>&1; then
  echo "Error: Docker is not running or you don't have permission to use it."
  exit 1
fi

# --- Interactive Setup ---
echo "### Adminer Secure Setup ###"
read -p "Enter the domain for Adminer (e.g., db-admin.yourdomain.com): " ADMINER_DOMAIN
echo "----------------------------------------------------"
echo

# --- Script Execution ---

# 1. Create the adminer.yml file
echo "### Creating Docker Compose file: $COMPOSE_FILE... ###"
cat > "$COMPOSE_FILE" <<EOF
# adminer.yml
version: '3.8'

services:
  adminer:
    image: adminer
    networks:
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
        - "traefik.http.routers.adminer.rule=Host(\`$ADMINER_DOMAIN\`)"
        - "traefik.http.routers.adminer.tls=true"
        - "traefik.http.routers.adminer.tls.certresolver=myresolver"
        - "traefik.http.routers.adminer.entrypoints=websecure"
        # 2. The service definition, telling Traefik where to send the traffic
        - "traefik.http.routers.adminer.service=adminer-svc"
        - "traefik.http.services.adminer-svc.loadbalancer.server.port=8080"

networks:
  $NETWORK_NAME:
    external: true
EOF
echo "Compose file created."
echo

# 2. Deploy the Adminer stack
echo "### Deploying Adminer stack '$STACK_NAME'... ###"
docker stack deploy -c "$COMPOSE_FILE" "$STACK_NAME"
echo

# --- Final Instructions ---
echo "####################################################################"
echo "###          ADMINER DEPLOYMENT COMPLETE!                        ###"
echo "####################################################################"
echo
echo "Adminer is now running and accessible at: https://$ADMINER_DOMAIN"
echo
echo "To log in to your database via Adminer:"
echo "  System:   PostgreSQL"
echo "  Server:   postgres  (This is the Docker service name)"
echo "  Username: postgres"
echo "  Password: [The password you set or generated in part 5]"
echo "  Database: postgres"
echo