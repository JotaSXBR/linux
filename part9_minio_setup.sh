#!/bin/bash

# PART 9: MINIO DEPLOYMENT (Fully Automated)
#
# This definitive script deploys Minio and automatically provisions the
# user and policy for the Evolution API. Crucially, it saves the generated
# S3 credentials as Docker Secrets for the next script to use.
#
# It MUST be run as the non-root 'deploy' user.

set -e

# --- Configuration ---
STACK_NAME="minio"
COMPOSE_FILE="minio.yml"
DATA_VOLUME="minio_data"
POLICY_NAME="evolution-policy"

# --- Interactive Setup ---
echo "### Minio Automated Setup ###"
read -p "Enter domain for Minio Console (e.g., s3.fluxie.com.br): " MINIO_CONSOLE_DOMAIN
read -p "Enter domain for Minio API (e.g., s3api.fluxie.com.br): " MINIO_API_DOMAIN
read -sp "Enter the Minio ROOT password (or press Enter to generate one): " MINIO_ROOT_PASSWORD
echo
[ -z "$MINIO_ROOT_PASSWORD" ] && MINIO_ROOT_PASSWORD=$(openssl rand -hex 32) && echo "Generated Root Password: $MINIO_ROOT_PASSWORD"

echo
echo "--- Evolution API S3 Credentials (will be generated) ---"
EVO_ACCESS_KEY="evolution_user"
EVO_SECRET_KEY=$(openssl rand -hex 40)
echo "An S3 user named '$EVO_ACCESS_KEY' will be created."
echo "Its secret key will be automatically generated and stored."
echo "----------------------------------------------------"
echo

# 1. Forcefully remove old secrets to ensure a clean state
echo "### Cleaning up old secrets... ###"
docker secret rm minio_root_password evolution_s3_access_key evolution_s3_secret_key >/dev/null 2>&1
printf "%s" "$MINIO_ROOT_PASSWORD" | docker secret create minio_root_password -
echo "Secrets created."
echo

# 2. Create the minio.yml file
echo "### Creating Docker Compose file: $COMPOSE_FILE ###"
cat > "$COMPOSE_FILE" <<EOF
version: '3.8'
services:
  minio:
    image: minio/minio:latest
    command: server /data --console-address ":9001"
    environment:
      MINIO_ROOT_USER: "root"
      MINIO_ROOT_PASSWORD_FILE: /run/secrets/minio_root_password
    volumes: ["$DATA_VOLUME:/data"]
    networks: ["main-proxy"]
    secrets: ["minio_root_password"]
    deploy:
      mode: replicated
      replicas: 1
      placement: { constraints: [node.role == manager] }
      labels:
        - "traefik.enable=true"
        - "traefik.http.routers.minio-api.rule=Host(\`$MINIO_API_DOMAIN\`)"
        - "traefik.http.routers.minio-api.entrypoints=websecure"
        - "traefik.http.routers.minio-api.tls.certresolver=myresolver"
        - "traefik.http.services.minio-api-svc.loadbalancer.server.port=9000"
        - "traefik.http.routers.minio-console.rule=Host(\`$MINIO_CONSOLE_DOMAIN\`)"
        - "traefik.http.routers.minio-console.entrypoints=websecure"
        - "traefik.http.routers.minio-console.tls=true"
        - "traefik.http.routers.minio-console.tls.certresolver=myresolver"
        - "traefik.http.services.minio-console-svc.loadbalancer.server.port=9001"
networks:
  main-proxy: { external: true }
volumes:
  $DATA_VOLUME: { external: true }
secrets:
  minio_root_password: { external: true }
EOF
echo "Compose file created."
echo

# 3. Deploy the Minio stack
echo "### Deploying Minio stack '$STACK_NAME'... ###"
docker stack rm "$STACK_NAME" >/dev/null 2>&1 && sleep 5
docker volume rm "$DATA_VOLUME" >/dev/null 2>&1
docker stack deploy -c "$COMPOSE_FILE" "$STACK_NAME"
echo

# 4. Wait for Minio to be ready
echo "### Waiting for Minio service to start... ###"
until docker service logs ${STACK_NAME}_minio 2>&1 | grep -q "API: http"; do
    echo -n "."
    sleep 2
done
echo "Minio is up!"
echo

# 5. Provision user and policy
echo "### Provisioning user and policy for Evolution API... ###"
cat > evolution_policy.json <<'EOF'
{
    "Version": "2012-10-17",
    "Statement": [
        { "Effect": "Allow", "Action": ["s3:CreateBucket", "s3:ListBucket"], "Resource": ["arn:aws:s3:::evolution"] },
        { "Effect": "Allow", "Action": ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"], "Resource": ["arn:aws:s3:::evolution/*"] }
    ]
}
EOF
CONTAINER_ID=$(docker ps --filter "name=${STACK_NAME}_minio" --format "{{.ID}}")
docker cp evolution_policy.json "${CONTAINER_ID}:/tmp/policy.json"
docker exec "$CONTAINER_ID" mc alias set local http://localhost:9000 root "$MINIO_ROOT_PASSWORD"
docker exec "$CONTAINER_ID" mc admin policy create local "$POLICY_NAME" /tmp/policy.json
docker exec "$CONTAINER_ID" mc admin user add local "$EVO_ACCESS_KEY" "$EVO_SECRET_KEY"
docker exec "$CONTAINER_ID" mc admin policy attach local "$POLICY_NAME" --user "$EVO_ACCESS_KEY"
rm evolution_policy.json
echo "User and policy provisioned successfully."
echo

# 6. Create Docker secrets for Evolution to use
echo "### Storing generated S3 credentials in Docker Secrets... ###"
printf "%s" "$EVO_ACCESS_KEY" | docker secret create evolution_s3_access_key -
printf "%s" "$EVO_SECRET_KEY" | docker secret create evolution_s3_secret_key -
echo "S3 secrets for Evolution API created successfully."
echo

echo "####################################################################"
echo "###          MINIO DEPLOYMENT COMPLETE!                          ###"
echo "####################################################################"
echo "Minio is running and the 'evolution_user' has been created."
echo "You are now ready to run the final Evolution API setup script."
echo "####################################################################"