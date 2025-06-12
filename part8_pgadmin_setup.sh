#!/bin/bash

# PART 8: PGADMIN DEPLOYMENT (v1 - Secured)
# This script deploys pgAdmin, a web UI for PostgreSQL management.
# It is exposed via Traefik with a secure HTTPS connection.
# It uses Docker Secrets to manage the default admin password.
# It MUST be run as the non-root 'deploy' user.

# --- Configuration ---
NETWORK_NAME="main-proxy"
STACK_NAME="pgadmin"
COMPOSE_FILE="pgadmin.yml"
DATA_VOLUME="pgadmin_data"
SECRET_NAME="pgadmin_default_password"

# --- Pre-flight Checks ---
if ! docker info > /dev/null 2>&1; then
    echo "Error: Docker is not running or you don't have permission to use it."
    exit 1
fi

# --- Interactive Setup ---
echo "### pgAdmin Secure Setup ###"
read -p "Enter the domain for pgAdmin (e.g., pgadmin.yourdomain.com): " PGADMIN_DOMAIN
read -p "Enter the default email for the pgAdmin login: " PGADMIN_EMAIL
read -sp "Enter the default password for the pgAdmin login: " PGADMIN_PASSWORD
echo
echo "----------------------------------------------------"
echo

# --- Script Execution ---

# 1. Create the Docker Managed Volume for pgAdmin data
echo "### Creating Docker managed volume '$DATA_VOLUME'... ###"
if ! docker volume inspect "$DATA_VOLUME" >/dev/null 2>&1; then
    docker volume create "$DATA_VOLUME"
else
    echo "Volume '$DATA_VOLUME' already exists."
fi
echo

# 2. Create the Docker Secret for the pgAdmin password
echo "### Creating Docker secret '$SECRET_NAME'... ###"
# Remove the secret if it exists to ensure the new password is used
if docker secret inspect "$SECRET_NAME" >/dev/null 2>&1; then
    docker secret rm "$SECRET_NAME"
    echo "Removed existing secret to create a new one."
fi
printf "%s" "$PGADMIN_PASSWORD" | docker secret create "$SECRET_NAME" -
echo "Secret created successfully."
echo

# 3. Create the pgadmin.yml file
echo "### Creating Docker Compose file: $COMPOSE_FILE ###"
cat > "$COMPOSE_FILE" <<EOF
version: '3.8'

services:
  pgadmin:
    image: elestio/pgadmin:latest
    environment:
      # The login email for the web UI
      PGADMIN_DEFAULT_EMAIL: "$PGADMIN_EMAIL"
      # The pgAdmin image knows to read the password from this file
      PGADMIN_DEFAULT_PASSWORD_FILE: /run/secrets/$SECRET_NAME
      # Disables the "Master Password" prompt on first login for simplicity
      PGADMIN_SETUP_MASTER_PASSWORD_FILE: /run/secrets/$SECRET_NAME
    volumes:
      - $DATA_VOLUME:/var/lib/pgadmin
    networks:
      - $NETWORK_NAME
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
          cpus: '0.5'
          memory: 1024M
      labels:
        # 1. Traefik General
        - "traefik.enable=true"
        - "traefik.docker.network=$NETWORK_NAME"

        # 2. Traefik Router Definition
        - "traefik.http.routers.pgadmin.rule=Host(\`$PGADMIN_DOMAIN\`)"
        - "traefik.http.routers.pgadmin.entrypoints=websecure"
        - "traefik.http.routers.pgadmin.tls=true"
        - "traefik.http.routers.pgadmin.tls.certresolver=myresolver"
        - "traefik.http.routers.pgadmin.service=pgadmin-svc"

        # 3. Traefik Service Definition
        - "traefik.http.services.pgadmin-svc.loadbalancer.server.port=80"

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

# 4. Deploy the pgAdmin stack
echo "### Deploying pgAdmin stack '$STACK_NAME' from '$COMPOSE_FILE'... ###"
docker stack deploy -c "$COMPOSE_FILE" "$STACK_NAME"
echo

# --- Final Instructions ---
echo "####################################################################"
echo "###          PGADMIN DEPLOYMENT COMPLETE!                        ###"
echo "####################################################################"
echo
echo "pgAdmin is now running and accessible at: https://$PGADMIN_DOMAIN"
echo
echo "Log in using the credentials you provided:"
echo "  Username: $PGADMIN_EMAIL"
echo "  Password: [The password you set during setup]"
echo
echo "--- How to Connect to Your Database ---"
echo "1. Once logged into pgAdmin, click 'Add New Server'."
echo "2. In the 'General' tab, give it a name (e.g., 'Docker Postgres')."
echo "3. In the 'Connection' tab, use the following details:"
echo "   - Host name/address: postgres"
echo "   - Port:              5432"
echo "   - Maintenance DB:    postgres"
echo "   - Username:          postgres"
echo "   - Password:          [The password you set in part5_postgres_setup.sh]"
echo "4. Click 'Save'."
echo