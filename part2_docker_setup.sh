#!/bin/bash

# PART 2: DOCKER SETUP (v2 - Corrected)
#
# FIX: Uses an un-quoted heredoc to allow variable expansion within the
#      'newgrp' sub-shell, ensuring networks and volumes are created.
#
# This script installs Docker and prepares the Swarm environment.
# It MUST be run as the non-root 'deploy' user.

# --- Configuration ---
NETWORK_NAME="main-proxy"
ACME_VOLUME="traefik-acme"
LOG_VOLUME="traefik-logs"

# --- Script Execution ---

if [ "$(id -u)" -eq 0 ]; then
  echo "This script should be run as the non-root 'deploy' user, not as root." >&2
  exit 1
fi

echo "### Checking sudo password... ###"
if sudo -n true 2>/dev/null; then
    echo "Sudo password is already cached."
else
    echo "You need to set a password for the user '$(whoami)' to use sudo."
    sudo passwd "$(whoami)"
fi
echo "### Sudo access confirmed. ###"
echo

echo "### Installing Docker... ###"
sudo apt-get update
sudo apt-get install -y docker.io
sudo usermod -aG docker "$(whoami)"
echo "### Docker installed successfully. ###"
echo "NOTE: You may need to log out and log back in for docker group changes to apply."
echo "This script will attempt to use the new group membership immediately."
echo

# Use a subshell with the new group to run docker commands
# FIX: Use un-quoted heredoc to allow variable expansion
newgrp docker <<END_DOCKER_CMDS

echo "### Initializing Docker Swarm... ###"
if ! docker info | grep -q "Swarm: active"; then
    docker swarm init
    echo "Docker Swarm initialized."
else
    echo "Docker Swarm is already active."
fi
echo

echo "### Creating Docker managed volumes and networks... ###"
if ! docker network inspect "$NETWORK_NAME" >/dev/null 2>&1; then
  docker network create --driver=overlay --attachable "$NETWORK_NAME"
else
  echo "Network '$NETWORK_NAME' already exists."
fi
if ! docker volume inspect "$ACME_VOLUME" >/dev/null 2>&1; then
  docker volume create "$ACME_VOLUME"
else
  echo "Volume '$ACME_VOLUME' already exists."
fi
if ! docker volume inspect "$LOG_VOLUME" >/dev/null 2>&1; then
  docker volume create "$LOG_VOLUME"
else
  echo "Volume '$LOG_VOLUME' already exists."
fi
echo "### Docker environment is ready. ###"
echo

END_DOCKER_CMDS

echo "####################################################################"
echo "###          PART 2 (DOCKER SETUP) COMPLETE!                     ###"
echo "####################################################################"
echo
echo "ACTION REQUIRED:"
echo "Now, run the 'part3_traefik_setup.sh' script to deploy Traefik."
echo