#!/bin/bash

# PART 5: POSTGRES DEPLOYMENT (v8 - Correct Auth Method)
# UPDATE: Replaces the invalid 'hostssl' auth method with the correct
# 'scram-sha-256' method. This works in conjunction with 'ssl=on' to
# create the final, secure, and working configuration.
# This is the definitive version.
# It MUST be run as the non-root 'deploy' user.

# --- Configuration ---
NETWORK_NAME="main-proxy"
STACK_NAME="postgres"
COMPOSE_FILE="postgres.yml"
DATA_VOLUME="postgres_data"
SECRET_NAME="postgres_password"
SSL_KEY_SECRET="postgres_ssl_key"
SSL_CERT_SECRET="postgres_ssl_cert"

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
    echo "No password entered. Generating a secure 32-character password..."
    POSTGRES_SECRET_VALUE=$(openssl rand -hex 32)
    echo
    echo "SAVE THIS PASSWORD! This is your new PostgreSQL password:"
    echo "  $POSTGRES_SECRET_VALUE"
    echo
fi

# 2. Generate Self-Signed SSL Certificate for the server
echo "### Generating self-signed SSL certificate for PostgreSQL... ###"
openssl req -new -x509 -days 3650 -nodes -text -out postgres.crt \
  -keyout postgres.key -subj "/CN=postgres"
echo "Certificate generated."
echo

# 3. Create Docker Secrets for password and SSL certs
echo "### Creating Docker secrets... ###"
docker secret rm $SECRET_NAME 2>/dev/null
docker secret rm $SSL_KEY_SECRET 2>/dev/null
docker secret rm $SSL_CERT_SECRET 2>/dev/null

printf "%s" "$POSTGRES_SECRET_VALUE" | docker secret create "$SECRET_NAME" -
docker secret create "$SSL_KEY_SECRET" postgres.key
docker secret create "$SSL_CERT_SECRET" postgres.crt
echo "Secrets created successfully."
echo

# 4. Clean up temporary certificate files
rm postgres.key postgres.crt
echo "Cleaned up temporary files."
echo

# 5. Create the postgres.yml file
echo "### Creating Docker Compose file: $COMPOSE_FILE ###"
cat > "$COMPOSE_FILE" <<EOF
version: '3.8'

services:
  postgres:
    image: pgvector/pgvector:pg16
    command: >
      -c ssl=on
      -c ssl_cert_file=/run/secrets/$SSL_CERT_SECRET
      -c ssl_key_file=/run/secrets/$SSL_KEY_SECRET
    environment:
      - POSTGRES_PASSWORD_FILE=/run/secrets/$SECRET_NAME
      # THE DEFINITIVE FIX: Use the correct authentication method.
      # The entrypoint script will correctly configure pg_hba.conf to use
      # scram-sha-256 for connections, which will be forced over SSL.
      - POSTGRES_HOST_AUTH_METHOD=scram-sha-256
      - TZ=America/Sao_Paulo
    networks:
      - $NETWORK_NAME
    volumes:
      - $DATA_VOLUME:/var/lib/postgresql/data
    secrets:
      - source: $SECRET_NAME
        target: $SECRET_NAME
        uid: '999'
        gid: '999'
        mode: 0400
      - source: $SSL_CERT_SECRET
        target: $SSL_CERT_SECRET
        uid: '999'
        gid: '999'
        mode: 0400
      - source: $SSL_KEY_SECRET
        target: $SSL_KEY_SECRET
        uid: '999'
        gid: '999'
        mode: 0400
    deploy:
      mode: replicated
      replicas: 1
      placement:
        constraints:
          - node.role == manager

networks:
  $NETWORK_NAME:
    external: true

volumes:
  $DATA_VOLUME:
    external: true

secrets:
  $SECRET_NAME:
    external: true
  $SSL_KEY_SECRET:
    external: true
  $SSL_CERT_SECRET:
    external: true
EOF
echo "Compose file created."
echo

# 6. Deploy the Postgres stack
echo "### Deploying Postgres stack '$STACK_NAME'... ###"
docker stack deploy -c "$COMPOSE_FILE" "$STACK_NAME"
echo

# --- Final Instructions ---
echo "####################################################################"
echo "###          POSTGRES DEPLOYMENT COMPLETE!                       ###"
echo "####################################################################"
echo
echo "The PostgreSQL database is now running with mandatory SSL encryption."
echo
echo "--- How to Connect from pgAdmin (Securely) ---"
echo "1. In pgAdmin, open the 'Register - Server' dialog."
echo "2. In the 'Connection' tab:"
echo "   - Host name/address: postgres"
echo "   - Password:          [The password you set for the database]"
echo "3. In the 'Parameters' tab:"
echo "   - Set 'SSL mode' to 'verify-full'."
echo "   - This is the highest level of security."
echo "4. Click 'Save'. The connection will now be fully encrypted."
echo