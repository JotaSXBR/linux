 # VPS Setup and Configuration Scripts

This repository contains a set of modular scripts for setting up and configuring a secure Ubuntu LTS VPS with Docker, Traefik, and Portainer.

## Available Scripts

The setup is divided into four parts that should be run in sequence:

### 1. Root Server Setup (`part1_root_setup.sh`)

Initial server security setup and user configuration.

#### Features:
1. System Updates: Ensures all packages are current
2. Sudo User: Creates a new user with sudo privileges
3. SSH Hardening: Disables root login, password auth, and sets a custom port
4. UFW Firewall: Configures a stateful firewall with SSH rate-limiting
5. Fail2ban: Protects against brute-force attacks
6. auditd: Installs and configures Linux Audit Daemon
7. Automatic Updates: Enables unattended security upgrades

### 2. Docker Setup (`part2_docker_setup.sh`)

Installs and configures Docker with Swarm mode.

#### Features:
1. Docker Engine installation
2. Docker Compose plugin installation
3. Docker Swarm initialization
4. Security best practices configuration
5. User group permissions setup

### 3. Traefik Setup (`part3_traefik_setup.sh`)

Sets up Traefik v3 as a secure reverse proxy.

#### Features:
1. Automatic HTTPS with Let's Encrypt
2. Secure Traefik dashboard with authentication
3. Docker Swarm network configuration
4. Best practices from Docker Swarm Rocks
5. Custom domain and email configuration

### 4. Portainer Setup (`part4_portainer_setup.sh`)

Deploys Portainer for Docker management.

#### Features:
1. Portainer CE installation
2. Secure web interface setup
3. Docker Swarm integration
4. Automatic HTTPS via Traefik
5. Container management interface

## Prerequisites

Before running the script, you must:

1. Generate an SSH key pair on your **local** machine:

   ```bash
   # On Windows (PowerShell):
   ssh-keygen -t ed25519 -f "$env:USERPROFILE\.ssh\id_ed25519"

   # On Linux/macOS:
   ssh-keygen -t ed25519
   ```

2. Get your public key:

   ```bash
   # On Windows (PowerShell):
   Get-Content "$env:USERPROFILE\.ssh\id_ed25519.pub"

   # On Linux/macOS:
   cat ~/.ssh/id_ed25519.pub
   ```   Copy the output - you'll need to paste this when the script asks for it.

## Getting Started

### 1. Get the Scripts

First, get the scripts onto your VPS using one of these methods:

#### Method 1: Clone from GitHub (Recommended)

1. Connect to your VPS:
   ```bash
   ssh root@your-server-ip
   ```

2. Install git:
   ```bash
   apt update && apt install git -y
   ```

3. Clone this repository:
   ```bash
   git clone https://github.com/JotaSXBR/linux.git
   cd linux
   ```

4. Make scripts executable:
   ```bash
   chmod +x *.sh
   ```

#### Method 2: Manual Upload

If you prefer to upload the scripts manually:

1. Upload the scripts to your VPS:
   ```bash
   # On Windows (PowerShell):
   scp *.sh root@your-server-ip:/root/

   # On Linux/macOS:
   scp *.sh root@your-server-ip:/root/
   ```

### 2. Run the Scripts

Run the scripts in sequence:

1. Root Setup:
   ```bash
   sudo ./part1_root_setup.sh
   ```
   Follow the prompts to:
   - Enter a username for the new sudo user
   - Paste your SSH public key when prompted

2. Reconnect with your new user and run Docker setup:
   ```bash
   ./part2_docker_setup.sh
   ```

3. Configure Traefik:
   ```bash
   ./part3_traefik_setup.sh
   ```
   Follow the prompts to:
   - Enter your domain name
   - Provide your email for Let's Encrypt
   - Set up dashboard credentials

4. Deploy Portainer:
   ```bash
   ./part4_portainer_setup.sh
   ```
   Follow the prompts to:
   - Configure initial admin password
   - Set up Portainer domain

## After Installation

- The script will show you the new SSH port and connection instructions
- Use your SSH key to connect as the new user
- Review the Lynis security report for additional hardening suggestions

## Security Notes

- Never generate SSH keys on the server - always create them on your local machine
- Keep your private key secure and never share it
- The script disables root login and password authentication for enhanced security