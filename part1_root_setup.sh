#!/bin/bash

# PART 1: ROOT SETUP
#
# This script performs the initial server hardening.
# It MUST be run as the 'root' user.

# --- Configuration ---
NEW_USER="deploy"
NEW_SSH_PORT="2222"

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

# 1. System Update & Prerequisite Installation
echo "### Updating system packages and installing prerequisites... ###"
apt-get update && apt-get upgrade -y
apt-get install -y ufw fail2ban auditd audispd-plugins sysstat rkhunter curl jq openssl
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

# 4. Advanced SSH Hardening
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

# 5. Firewall Configuration (UFW)
echo "### Configuring UFW firewall... ###"
ufw default deny incoming
ufw default allow outgoing
ufw limit "$NEW_SSH_PORT"/tcp
ufw allow http
ufw allow https
ufw --force enable
echo "### UFW firewall enabled and configured. ###"
echo

# 6. System Policy & Kernel Hardening
echo "### Applying system-wide policy and kernel hardening... ###"
# Disable core dumps
echo '* hard core 0' > /etc/security/limits.d/99-disable-coredumps.conf
# Harden login definitions
sed -i 's/^UMASK\s\+.*/UMASK           027/' /etc/login.defs
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
* This system is for the use of authorized users only.          *
*****************************************************************
EOF
cp /etc/issue /etc/issue.net
echo "### System policies and kernel hardened. ###"
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