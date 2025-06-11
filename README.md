 # Secure VPS Initialization Script

This script provides a comprehensive security setup for Ubuntu LTS VPS servers, including user management, SSH hardening, firewall configuration, and more.

## Features

1. System Updates: Ensures all packages are current
2. Sudo User: Creates a new user with sudo privileges
3. SSH Hardening: Disables root login, password auth, and sets a custom port
4. UFW Firewall: Configures a stateful firewall with SSH rate-limiting
5. Fail2ban: Protects against brute-force attacks
6. auditd: Installs and configures Linux Audit Daemon
7. Automatic Updates: Enables unattended security upgrades
8. Docker & Swarm: Installs Docker Engine and initializes Swarm mode
9. Lynis: Installs security auditing tool and performs baseline scan

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
   ```

   Copy the output - you'll need to paste this when the script asks for it.

## Usage

1. Upload the script to your VPS:
   ```bash
   # On Windows (PowerShell):
   scp server.sh root@your-server-ip:/root/

   # On Linux/macOS:
   scp server.sh root@your-server-ip:/root/
   ```

2. Connect to your VPS:
   ```bash
   ssh root@your-server-ip
   ```

3. Make the script executable:
   ```bash
   chmod +x server.sh
   ```

4. Run the script:
   ```bash
   sudo ./server.sh
   ```

5. Follow the prompts to:
   - Enter a username for the new sudo user
   - Paste your SSH public key when prompted

## After Installation

- The script will show you the new SSH port and connection instructions
- Use your SSH key to connect as the new user
- Review the Lynis security report for additional hardening suggestions

## Security Notes

- Never generate SSH keys on the server - always create them on your local machine
- Keep your private key secure and never share it
- The script disables root login and password authentication for enhanced security