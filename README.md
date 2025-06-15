# Secure VPS Initialization & Docker Swarm Deployment

This project provides a set of scripts to automate the provisioning and hardening of a new Ubuntu LTS server, culminating in a production-ready Docker Swarm environment managed by a secure Traefik reverse proxy.

The entire process is designed to be repeatable, secure, and based on modern Infrastructure as Code (IaC) principles.

## Core Philosophy

This setup is built on several key professional practices:

*   **Separation of Concerns:** The process is split into distinct parts. System hardening (`root` user tasks) is separate from application environment setup (`deploy` user tasks), which is separate from application deployment. This makes the system cleaner and easier to manage.
*   **Infrastructure as Code (IaC):** This Git repository is the **single source of truth**. The state of the server is defined by code, not by manual actions. This ensures consistency and enables perfect disaster recovery.
*   **Security by Default:** The scripts apply a strong security baseline from the start, including a hardened SSH configuration, a restrictive firewall, and the principle of least privilege for user accounts.
*   **Modern Docker Practices:** We use Docker-managed named volumes to avoid host-level permission issues and Docker Secrets to securely manage sensitive data like passwords, which are never stored in configuration files.

## Prerequisites

Before you begin, you will need:

1.  A fresh VPS running the latest Ubuntu LTS.
2.  An SSH key pair generated on your **local computer**.
3.  A domain name that you own.
4.  Your DNS provider configured with an **A record** pointing your domain (e.g., `traefik.yourdomain.com`) to your VPS's public IP address.

## Execution Plan

Follow these steps in order. Do not skip any steps.

### Part 1: Initial Server Hardening (as `root`)

This script performs all initial system-level security hardening and creates the non-root `deploy` user.

1.  Log into your new VPS as the `root` user.
2.  Create the script file: `nano part1_root_setup.sh`
3.  Copy the content of `part1_root_setup.sh` into the file and save it.
4.  Make the script executable: `chmod +x part1_root_setup.sh`
5.  Run the script: `./part1_root_setup.sh`
6.  The script will prompt you to paste the **public SSH key** for the `deploy` user.
7.  When the script is complete, it will give you final instructions. **Follow them immediately.**

**➡️ ACTION REQUIRED:** Log out of the `root` session.

### Part 2: Docker Environment Setup (as `deploy`)

This script installs Docker and prepares the Swarm environment, including shared networks and volumes.

1.  Log into your VPS as the new `deploy` user with your SSH key:
    ```bash
    ssh -p 2222 deploy@<your_vps_ip>
    ```
2.  Create the script file: `nano part2_docker_setup.sh`
3.  Copy the content of `part2_docker_setup.sh` into the file and save it.
4.  Make the script executable: `chmod +x part2_docker_setup.sh`
5.  Run the script: `./part2_docker_setup.sh`
6.  The script will ask you to create a password for the `deploy` user. This password is only used for `sudo` commands.
7.  The script will finish by preparing the Docker environment.

**➡️ ACTION REQUIRED:** Log out and log back in one more time. This is critical for your user's new `docker` group membership to take effect in your shell.

### Part 3: Deploy Traefik (as `deploy`)

This script deploys the main Traefik reverse proxy.

1.  Log in again as the `deploy` user. Your shell now has the correct permissions to use Docker.
2.  Create the script file: `nano part3_traefik_setup.sh`
3.  Copy the content of `part3_traefik_setup.sh` into the file and save it.
4.  Make the script executable: `chmod +x part3_traefik_setup.sh`
5.  Run the script: `./part3_traefik_setup.sh`
6.  Follow the prompts to configure your Traefik domain, email, and dashboard credentials.
7.  Once complete, Traefik will be running and accessible at the domain you provided.

### Part 4: Deploy Portainer (as `deploy`)

This script deploys the Portainer management UI.

1.  Create the script file: `nano part4_portainer_setup.sh`
2.  Copy the content of `part4_portainer_setup.sh` into the file and save it.
3.  Make the script executable: `chmod +x part4_portainer_setup.sh`
4.  Run the script: `./part4_portainer_setup.sh`
5.  Follow the prompts to configure your Portainer domain.
6.  Once complete, Portainer will be running and accessible at the domain you provided.

### Part 5: Deploy PostgreSQL (as `deploy`)

This script deploys a secure PostgreSQL database server.

1.  Create the script file: `nano part5_postgres_setup.sh`
2.  Copy the content of `part5_postgres_setup.sh` into the file and save it.
3.  Make the script executable: `chmod +x part5_postgres_setup.sh`
4.  Run the script: `./part5_postgres_setup.sh`
5.  Follow the prompts to configure your PostgreSQL credentials.
6.  The script will create a secure PostgreSQL instance with Docker secrets management.

### Part 6: Deploy Redis (as `deploy`)

This script deploys a Redis server with password protection.

1.  Create the script file: `nano part7_redis_setup.sh`
2.  Copy the content of `part7_redis_setup.sh` into the file and save it.
3.  Make the script executable: `chmod +x part7_redis_setup.sh`
4.  Run the script: `./part7_redis_setup.sh`
5.  Follow the prompts to set up Redis with password protection.
6.  The script will create a secure Redis instance with Docker secrets management.

### Part 7: Deploy PgAdmin (as `deploy`)

This script deploys PgAdmin, a web-based PostgreSQL administration tool.

1.  Create the script file: `nano part8_pgadmin_setup.sh`
2.  Copy the content of `part8_pgadmin_setup.sh` into the file and save it.
3.  Make the script executable: `chmod +x part8_pgadmin_setup.sh`
4.  Run the script: `./part8_pgadmin_setup.sh`
5.  Follow the prompts to configure your PgAdmin domain and credentials.
6.  Once complete, PgAdmin will be accessible at the domain you provided.

### Part 8: Deploy MinIO (as `deploy`)

This script deploys MinIO, an S3-compatible object storage server.

1.  Create the script file: `nano part9_minio_setup.sh`
2.  Copy the content of `part9_minio_setup.sh` into the file and save it.
3.  Make the script executable: `chmod +x part9_minio_setup.sh`
4.  Run the script: `./part9_minio_setup.sh`
5.  Follow the prompts to configure your MinIO domain and access credentials.
6.  Once complete, MinIO will be accessible at the domain you provided.

### Part 9: Deploy Evolution API (as `deploy`)

This script deploys the Evolution API with integration to PostgreSQL, Redis, and MinIO.

1.  Create the script file: `nano part10_evolution_setup.sh`
2.  Copy the content of `part10_evolution_setup.sh` into the file and save it.
3.  Make the script executable: `chmod +x part10_evolution_setup.sh`
4.  Run the script: `./part10_evolution_setup.sh`
5.  Follow the prompts to configure your Evolution API domain and credentials.
6.  The script will automatically integrate with the previously deployed services.

## Infrastructure Overview

The complete infrastructure includes:

- **Traefik**: Reverse proxy and SSL termination
- **Portainer**: Docker management UI
- **PostgreSQL**: Primary database server
- **Redis**: In-memory cache and message broker
- **PgAdmin**: PostgreSQL administration interface
- **MinIO**: S3-compatible object storage
- **Evolution API**: API service with full infrastructure integration

Each component is:
- Deployed as a Docker Swarm service
- Protected by Traefik's SSL/TLS encryption
- Configured with Docker secrets for sensitive data
- Using Docker volumes for persistent storage
- Accessible via custom domains through Traefik

## Day-to-Day Management

*   **Check Stack Status:** `docker stack ps <stack_name>` (e.g., `docker stack ps traefik`)
*   **View Service Logs:** `docker service logs <stack_name>_<service_name>`
*   **Update an Application:** To update an application's image version, edit the corresponding `partX_..._setup.sh` script, change the `image:` tag in the YAML block, and re-run the script. This ensures your Git repository always reflects the true state of your server.

## Backup Considerations

Important directories and volumes to backup:

- PostgreSQL data: `postgres_data` volume
- MinIO data: `minio_data` volume
- Evolution API instances: `evolution_data` volume
- Redis data: `redis_data` volume (if persistence is enabled)

Use Docker's volume backup capabilities or configure automated backups using the respective service's backup tools.

## Security Notes

- All services are only accessible through HTTPS
- Passwords and sensitive data are managed via Docker secrets
- Each service runs in isolation with its own network namespace
- Inter-service communication is controlled via Docker networks
- Regular updates should be performed on both the host system and containers

This setup provides a professional-grade foundation for hosting modern containerized applications securely and reliably.