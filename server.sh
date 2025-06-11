#!/bin/bash

# Ubuntu LTS VPS Initialization Script - Professional Live-Sourced Edition (v2 - Patched)
#
# This script is interactive and performs a comprehensive security setup.
# It will prompt you for a username and your public SSH key.
#
# FIXES in this version:
# - Corrected SSH service name from 'sshd' to 'ssh' for Ubuntu compatibility.
# - Replaced external auditd rules with a safer, embedded, and more compatible ruleset.
#
# !!! IMPORTANT !!!
# 1. Run this script with sudo privileges (e.g., sudo ./server.sh).
# 2. Generate an SSH key on your LOCAL computer and have the PUBLIC key ready to paste.

# --- Configuration ---
NEW_SSH_PORT="2222" # Change to a random, non-standard port if desired

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
# FIX 1: Use the correct service name 'ssh' for Ubuntu.
systemctl restart ssh.service
echo "### SSH hardened: Port changed to $NEW_SSH_PORT, root login and password auth disabled. ###"
echo

# 5. Firewall Configuration (UFW) with SSH Rate-Limiting
echo "### Configuring UFW firewall... ###"
ufw default deny incoming
ufw default allow outgoing
ufw limit "$NEW_SSH_PORT"/tcp
ufw allow http
ufw allow https
ufw allow 2377/tcp
ufw allow 7946/tcp
ufw allow 7946/udp
ufw allow 4789/udp
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

# 7. Configure auditd with a Compatible Ruleset
echo "### Configuring auditd for system monitoring... ###"
# FIX 2: Use a safer, embedded ruleset that is compatible with base Ubuntu.
cat > /etc/audit/rules.d/99-custom.rules <<EOF
# This file contains a baseline set of audit rules for a secure system.

# Make the audit configuration immutable - reboot required to change rules
-e 2

# Increase buffer size
-b 8192

# Monitor for changes to audit rules
-w /etc/audit/ -p wa -k audit_rules

# Monitor identity and authentication files
-w /etc/group -p wa -k identity
-w /etc/passwd -p wa -k identity
-w /etc/gshadow -p wa -k identity
-w /etc/shadow -p wa -k identity
-w /etc/security/opasswd -p wa -k identity

# Monitor system configuration changes
-w /etc/sudoers -p wa -k sudoers
-w /etc/sudoers.d/ -p wa -k sudoers
-w /etc/ssh/sshd_config -p wa -k sshd_config

# Monitor login/logout events
-w /var/log/faillog -p wa -k logins
-w /var/log/lastlog -p wa -k logins
-w /var/log/tallylog -p wa -k logins

# Monitor for use of privileged commands
-a always,exit -F arch=b64 -S execve -C uid!=euid -F euid=0 -k priv_esc
-a always,exit -F arch=b32 -S execve -C uid!=euid -F euid=0 -k priv_esc

# Monitor for unauthorized file access attempts
-a always,exit -F arch=b64 -S open,creat,truncate -F exit=-EACCES -F auid>=1000 -F auid!=unset -k access_denied
-a always,exit -F arch=b32 -S open,creat,truncate -F exit=-EACCES -F auid>=1000 -F auid!=unset -k access_denied
-a always,exit -F arch=b64 -S open,creat,truncate -F exit=-EPERM -F auid>=1000 -F auid!=unset -k access_denied
-a always,exit -F arch=b32 -S open,creat,truncate -F exit=-EPERM -F auid>=1000 -F auid!=unset -k access_denied
EOF
augenrules --load
systemctl enable auditd && systemctl restart auditd
echo "### auditd configured with custom rules and enabled. ###"
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