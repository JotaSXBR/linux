#!/bin/bash

# Ubuntu LTS VPS Initialization Script - Professional Live-Sourced Edition
#
# This script is interactive and performs a comprehensive security setup.
# It will prompt you for a username and your public SSH key.
#
# FEATURES:
# 1. System Updates: Ensures all packages are current.
# 2. Sudo User: Creates a new user with sudo privileges.
# 3. SSH Hardening: Disables root login, password auth, and sets a custom port.
# 4. UFW Firewall: Configures a stateful firewall with SSH rate-limiting.
# 5. Fail2ban: Protects against brute-force attacks on services.
# 6. auditd: Installs and configures the Linux Audit Daemon, pulling a best-practice
#    ruleset directly from a trusted online source.
# 7. Automatic Updates: Enables unattended security upgrades.
# 8. Docker & Swarm: Installs the latest Docker Engine and initializes Swarm mode.
# 9. Lynis: Installs the security auditing tool and performs a baseline scan.
#
# !!! IMPORTANT !!!
# 1. Run this script with sudo privileges (e.g., sudo ./setup_vps.sh).
# 2. Generate an SSH key on your LOCAL computer and have the PUBLIC key ready to paste.

# --- Configuration ---
NEW_SSH_PORT="2222" # Change to a random, non-standard port if desired
AUDITD_RULES_URL="https://raw.githubusercontent.com/neo23x0/auditd/master/audit.rules"

# --- Script Execution ---

# Ensure the script is run as root
if [ "$(id -u)" -ne 0 ]; then
  echo "This script must be run as root. Use sudo." >&2
  exit 1
fi

# Automatically determine the server's primary IP address
SERVER_IP=$(hostname -I | awk '{print $1}')

# --- Interactive Setup ---
echo "### User and SSH Key Setup ###"
read -p "Please enter the username for the new sudo user: " NEW_USER
while true; do
    read -p "Please paste your public SSH key now: " PUBLIC_SSH_KEY
    if [[ "$PUBLIC_SSH_KEY" == ssh-* ]]; then
        break
    else
        echo "Invalid key format. It should start with 'ssh-'. Please try again."
    fi
done
echo "----------------------------------------------------"
echo

# 1. System Update & Prerequisite Installation
echo "### Updating system packages and installing prerequisites... ###"
apt-get update && apt-get upgrade -y
apt-get install -y ca-certificates curl gnupg unattended-upgrades fail2ban auditd audispd-plugins
apt-get autoremove -y
echo "### System update complete. ###"
echo

# 2. Create a New Sudo User
echo "### Creating new user '$NEW_USER' with sudo privileges... ###"
if id "$NEW_USER" &>/dev/null; then
    echo "User $NEW_USER already exists. Skipping user creation."
else
    adduser --disabled-password --gecos "" "$NEW_USER"
    usermod -aG sudo "$NEW_USER"
    echo "User $NEW_USER created and added to the sudo group."
fi
echo "### New user setup complete. ###"
echo

# 3. SSH Key Authentication
echo "### Setting up SSH key authentication for $NEW_USER... ###"
mkdir -p /home/"$NEW_USER"/.ssh
echo "$PUBLIC_SSH_KEY" > /home/"$NEW_USER"/.ssh/authorized_keys
chown -R "$NEW_USER":"$NEW_USER" /home/"$NEW_USER"/.ssh
chmod 700 /home/"$NEW_USER"/.ssh
chmod 600 /home/"$NEW_USER"/.ssh/authorized_keys
echo "### SSH key added for $NEW_USER. ###"
echo

# 4. Harden SSH Configuration
echo "### Hardening SSH configuration... ###"
sed -i "s/#Port 22/Port $NEW_SSH_PORT/" /etc/ssh/sshd_config
sed -i 's/PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config
sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
sed -i 's/PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
systemctl restart sshd
echo "### SSH hardened: Port changed to $NEW_SSH_PORT, root login and password auth disabled. ###"
echo

# 5. Firewall Configuration (UFW) with SSH Rate-Limiting
echo "### Configuring UFW firewall... ###"
ufw default deny incoming
ufw default allow outgoing
ufw limit "$NEW_SSH_PORT"/tcp
ufw allow http
ufw allow https
# Docker Swarm ports (only needed if you add more nodes)
ufw allow 2377/tcp # Swarm management
ufw allow 7946/tcp # Container network discovery
ufw allow 7946/udp # Container network discovery
ufw allow 4789/udp # Overlay network traffic
ufw --force enable
echo "### UFW firewall enabled and configured. ###"
echo

# 6. Configure Fail2ban
echo "### Configuring Fail2ban... ###"
cp /etc/fail2ban/jail.conf /etc/fail2ban/jail.local
sed -i "s/bantime  = 10m/bantime  = 1h/" /etc/fail2ban/jail.local
sed -i "s/maxretry = 5/maxretry = 3/" /etc/fail2ban/jail.local
systemctl enable fail2ban && systemctl restart fail2ban
echo "### Fail2ban configured and enabled. ###"
echo

# 7. Configure auditd with Best-Practice Rules from a Live Source
echo "### Configuring auditd for system monitoring... ###"
echo "### Downloading latest auditd ruleset from $AUDITD_RULES_URL..."
if curl -sS -o /etc/audit/rules.d/99-custom.rules "$AUDITD_RULES_URL"; then
    # Make the audit configuration immutable (reboot required to change rules)
    sed -i '/^-e 2/s/^#//' /etc/audit/rules.d/99-custom.rules
    echo "### Ruleset downloaded. Loading rules..."
    augenrules --load
    systemctl enable auditd && systemctl restart auditd
    echo "### auditd configured with custom rules and enabled. ###"
else
    echo "!!! WARNING: Could not download auditd rules. Skipping auditd configuration. !!!"
fi
echo

# 8. Enable Automatic Security Updates
echo "### Enabling automatic security updates... ###"
dpkg-reconfigure -plow unattended-upgrades
echo "### Automatic security updates enabled. ###"
echo

# 9. Install Docker Engine and Dependencies
echo "### Installing Docker... ###"
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
usermod -aG docker "$NEW_USER"
echo "### Docker installed successfully. $NEW_USER added to the docker group. ###"
echo

# 10. Initialize Docker Swarm
echo "### Initializing Docker Swarm mode... ###"
docker swarm init --advertise-addr "$SERVER_IP"
echo "### Docker Swarm initialized. This node is now a manager. ###"
echo "To add a worker node, run the following on another server:"
docker swarm join-token worker | grep "docker swarm join"
echo

# 11. Install and Run Lynis Security Audit
echo "### Installing Lynis security auditing tool... ###"
curl -fsSL https://packages.cisofy.com/keys/cisofy-software-public.key | gpg --dearmor -o /etc/apt/keyrings/cisofy-software-public.gpg
echo "deb [signed-by=/etc/apt/keyrings/cisofy-software-public.gpg] https://packages.cisofy.com/community/lynis/deb/ stable main" | tee /etc/apt/sources.list.d/cisofy-lynis.list
apt-get update
apt-get install -y lynis
echo "### Lynis installed. Performing initial system audit... ###"
lynis audit system --quiet --cronjob
echo "### Lynis baseline scan complete. ###"
echo

echo "####################################################################"
echo "###            VPS Initialization Complete!                      ###"
echo "####################################################################"
echo
echo "--- Login Information ---"
echo "Log out and log back in as '$NEW_USER' on port $NEW_SSH_PORT for group changes (docker) to take effect."
echo "Use your SSH key to connect. Example:"
echo "ssh -p $NEW_SSH_PORT $NEW_USER@$SERVER_IP"
echo
echo "--- Security & Auditing ---"
echo "Root login is disabled. Use 'sudo' for administrative tasks."
echo "Docker is installed and Swarm mode is active."
echo "auditd is logging security events to /var/log/audit/audit.log."
echo "  (Use 'ausearch -k <keyname>' or 'aureport' to inspect logs)."
echo
echo "--- NEXT STEPS: Review Lynis Report ---"
echo "A security scan has been performed. Review the findings for more hardening suggestions."
echo "View the full report: sudo cat /var/log/lynis-report.dat"
echo "View suggestions only: sudo grep Suggestion /var/log/lynis.log"
echo