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

## Deploying Additional Applications

The `part4_portainer_setup.sh` and `part5_postgres_setup.sh` scripts serve as the template for all future applications. The pattern is:

1.  Create a new script (e.g., `partX_myapp_setup.sh`).
2.  In the script, create a dedicated Docker-managed volume for your application's persistent data (`docker volume create myapp_data`).
3.  If the application needs passwords or API keys, create Docker Secrets for them (`docker secret create ...`).
4.  Generate a `docker-compose.yml` file that includes Traefik labels for routing and tells the service to use the volumes and secrets you created.
5.  Deploy the stack with `docker stack deploy`.

## Day-to-Day Management

*   **Check Stack Status:** `docker stack ps <stack_name>` (e.g., `docker stack ps traefik`)
*   **View Service Logs:** `docker service logs <stack_name>_<service_name>`
*   **Update an Application:** To update an application's image version, edit the corresponding `partX_..._setup.sh` script, change the `image:` tag in the YAML block, and re-run the script. This ensures your Git repository always reflects the true state of your server.

This setup provides a professional-grade foundation for hosting modern containerized applications securely and reliably.