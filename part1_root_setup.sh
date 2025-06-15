#!/bin/bash

# PART 1: ROOT SETUP (Definitive Lynis-Hardened Edition)
#
# This script performs the initial server hardening, including user creation,
# SSH hardening, firewall setup, swap file creation, and installation of
# essential security and system tools based on a Lynis audit.
#
# It MUST be run as the 'root' user.

# --- Configuration ---
NEW_USER="deploy"
NEW_SSH_PORT="2222"
SWAP_SIZE="4G"

# --- Script Execution ---

# Ensure the script is run as root
if [ "$(id -u)" -ne 0 ]; then
  echo "This script must be run as root." >&2
  exit 1
fi

echo "### User and SSH Key Setup ###"
echo "This script will create the user '$NEW_USER'."
while true; do
    read -p "Please paste the public SSH key for the '$NEW_USER' user now: " PUBLIC_SSH_KEY
    if [[ "$PUBLIC_SSH_KEY" == ssh-* ]]; then
        break
    else
        echo "Invalid key format. It should start with 'ssh-'. Please try again."
    fi
done
echo "----------------------------------------------------"
echo

# 1. Ensure Security Repository is Active
echo "### Ensuring security repository is active... ###"
# For Ubuntu 24.04 (Noble Numbat). Adjust 'noble' for other versions.
SECURITY_REPO_LINE="deb http://security.ubuntu.com/ubuntu noble-security main restricted universe multiverse"
if ! grep -q "^deb .*noble-security" /etc/apt/sources.list /etc/apt/sources.list.d/*; then
    echo "Security repository not found. Adding it now."
    echo "$SECURITY_REPO_LINE" >> /etc/apt/sources.list
else
    echo "Security repository is already configured."
fi
echo

# 2. System Update & Prerequisite Installation
echo "### Updating system packages and installing prerequisites... ###"
apt-get update && apt-get upgrade -y
# Installs security tools recommended by Lynis
apt-get install -y ufw fail2ban auditd audispd-plugins sysstat rkhunter lynis debsums apt-listbugs apt-listchanges curl jq openssl
apt-get autoremove -y
echo "### System update complete. ###"
echo

# 3. Create and Enable Swap File
echo "### Creating and enabling a ${SWAP_SIZE} swap file... ###"
if [ -f /swapfile ]; then
    echo "Swap file already exists. Skipping creation."
else
    fallocate -l "$SWAP_SIZE" /swapfile
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile
    # Make the swap file permanent
    echo '/swapfile none swap sw 0 0' >> /etc/fstab
    echo "Swap file created and enabled."
fi
# Tune swappiness for server performance
if ! grep -q "vm.swappiness=10" /etc/sysctl.conf; then
    echo "vm.swappiness=10" >> /etc/sysctl.conf
    sysctl -p
fi
echo "### Swap configuration complete. ###"
echo

# 4. Create a New Sudo User
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

# 5. SSH Key Authentication
echo "### Setting up SSH key authentication for $NEW_USER... ###"
mkdir -p /home/"$NEW_USER"/.ssh
echo "$PUBLIC_SSH_KEY" > /home/"$NEW_USER"/.ssh/authorized_keys
chown -R "$NEW_USER":"$NEW_USER" /home/"$NEW_USER"/.ssh
chmod 700 /home/"$NEW_USER"/.ssh
chmod 600 /home/"$NEW_USER"/.ssh/authorized_keys
echo "### SSH key added for $NEW_USER. ###"
echo

# 6. Advanced SSH Hardening
echo "### Hardening SSH configuration... ###"
sed -i "s/#Port 22/Port $NEW_SSH_PORT/" /etc/ssh/sshd_config
sed -i 's/PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config
sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
sed -i 's/PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
cat <<EOF >> /etc/ssh/sshd_config
LogLevel VERBOSE
X11Forwarding no
AllowAgentForwarding no
AllowTcpForwarding no
MaxAuthTries 3
MaxSessions 2
TCPKeepAlive no
EOF
systemctl restart ssh.service
echo "### SSH hardened. ###"
echo

# 7. Firewall Configuration (UFW)
echo "### Configuring UFW firewall... ###"
ufw default deny incoming
ufw default allow outgoing
ufw limit "$NEW_SSH_PORT"/tcp
ufw allow http
ufw allow https
ufw --force enable
echo "### UFW firewall enabled and configured. ###"
echo

# 8. System Policy & Kernel Hardening
echo "### Applying system-wide policy and kernel hardening... ###"
      # Recommended for Redis to prevent issues during background saves
if ! grep -q "vm.overcommit_memory=1" /etc/sysctl.conf; then
    echo "vm.overcommit_memory=1" >> /etc/sysctl.conf
    sysctl -p
fi
# Disable core dumps
echo '* hard core 0' > /etc/security/limits.d/99-disable-coredumps.conf
# Harden login definitions
sed -i 's/^UMASK\s\+.*/UMASK           027/' /etc/login.defs
sed -i 's/^ENCRYPT_METHOD\s\+.*/ENCRYPT_METHOD SHA512/' /etc/login.defs
if ! grep -q "SHA_CRYPT_MIN_ROUNDS" /etc/login.defs; then
    echo "SHA_CRYPT_MIN_ROUNDS 500000" >> /etc/login.defs
fi
# Disable uncommon network protocols
cat > /etc/modprobe.d/99-disable-uncommon-net.conf <<EOF
install dccp /bin/true
install sctp /bin/true
install rds /bin/true
install tipc /bin/true
EOF
# Add Legal Banner
cat > /etc/issue <<EOF
*****************************************************************
*                                                               *
* This system is for the use of authorized users only.          *
* Individuals using this computer system without authority, or  *
* in excess of their authority, are subject to having all of    *
* their activities on this system monitored and recorded.       *
*                                                               *
* Anyone using this system expressly consents to such           *
* monitoring and is advised that if such monitoring reveals     *
* possible evidence of criminal activity, system personnel may  *
* provide the evidence of such monitoring to law enforcement    *
* officials.                                                    *
*                                                               *
*****************************************************************
EOF
cp /etc/issue /etc/issue.net
echo "### System policies and kernel hardened. ###"
echo

# 9. Configure and Load Auditd Rules
echo "### Configuring and loading auditd rules... ###"
cat > /etc/audit/rules.d/99-custom.rules <<EOF
# This file contains a baseline set of audit rules for a secure system.
-e 2
-b 8192
-w /etc/audit/ -p wa -k audit_rules
-w /etc/group -p wa -k identity
-w /etc/passwd -p wa -k identity
-w /etc/gshadow -p wa -k identity
-w /etc/shadow -p wa -k identity
-w /etc/security/opasswd -p wa -k identity
-w /etc/sudoers -p wa -k sudoers
-w /etc/sudoers.d/ -p wa -k sudoers
-w /etc/ssh/sshd_config -p wa -k sshd_config
-w /var/log/faillog -p wa -k logins
-w /var/log/lastlog -p wa -k logins
-w /var/log/tallylog -p wa -k logins
-a always,exit -F arch=b64 -S execve -C uid!=euid -F euid=0 -k priv_esc
-a always,exit -F arch=b32 -S execve -C uid!=euid -F euid=0 -k priv_esc
-a always,exit -F arch=b64 -S open,creat,truncate -F exit=-EACCES -F auid>=1000 -F auid!=unset -k access_denied
-a always,exit -F arch=b32 -S open,creat,truncate -F exit=-EACCES -F auid>=1000 -F auid!=unset -k access_denied
-a always,exit -F arch=b64 -S open,creat,truncate -F exit=-EPERM -F auid>=1000 -F auid!=unset -k access_denied
-a always,exit -F arch=b32 -S open,creat,truncate -F exit=-EPERM -F auid>=1000 -F auid!=unset -k access_denied
EOF
augenrules --load
# Force a restart to ensure the new rules are active.
service auditd restart
echo "### auditd configured with custom rules and enabled. ###"
echo

echo "####################################################################"
echo "###          PART 1 (ROOT SETUP) COMPLETE!                       ###"
echo "####################################################################"
echo
echo "ACTION REQUIRED:"
echo "1. Log out of this root session immediately."
echo "2. Reconnect to the server as the '$NEW_USER' user using your SSH key."
echo "   Example: ssh -p $NEW_SSH_PORT $NEW_USER@<your_vps_ip>"
echo "3. Once reconnected, run the 'part2_docker_setup.sh' script."
echo
echo "--- Security Auditing ---"
echo "To run a manual security audit at any time, use the command:"
echo "  sudo lynis audit system"
echo
echo "To run a manual rootkit scan, use the command:"
echo "  sudo rkhunter --check"
echo