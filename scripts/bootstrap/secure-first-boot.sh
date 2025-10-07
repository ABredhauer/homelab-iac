#!/bin/bash

# ----------- Configuration Variables -----------
LOG_FILE="/var/log/homelab-bootstrap.log"
GITHUB_USER="ABredhauer"
REPO_URL="https://github.com/ABredhauer/homelab-iac.git"
REPO_DIR="/opt/homelab-iac"

# Static node info (update with actual MACs and IPs)
NODE_MAC_1="aa:bb:cc:dd:ee:01"
NODE_NAME_1="pve-node1"
NODE_ID_1="1"
NODE_IP_1="192.168.1.11"

NODE_MAC_2="aa:bb:cc:dd:ee:02"
NODE_NAME_2="pve-node2"
NODE_ID_2="2"
NODE_IP_2="192.168.1.12"

DEFAULT_NODE_NAME="pve-unknown"
DEFAULT_NODE_ID="99"

# ----------- End Variables -----------

set -euo pipefail
exec > >(tee -a "$LOG_FILE") 2>&1

echo "=================================================="
echo "Starting secure bootstrap at $(date)"
echo "Node: $(hostname)"
echo "IP: $(hostname -I | awk '{print $1}')"
echo "=================================================="

# Step 1: Setup SSH key authentication
echo "Step 1: Configuring SSH key authentication..."
mkdir -p /root/.ssh
chmod 700 /root/.ssh

echo "Fetching SSH keys for GitHub user: $GITHUB_USER"
if curl -fsSL --connect-timeout 10 --max-time 30 "https://github.com/${GITHUB_USER}.keys" > /root/.ssh/authorized_keys; then
    chmod 600 /root/.ssh/authorized_keys
    if [[ -s /root/.ssh/authorized_keys ]]; then
        keys_count=$(wc -l < /root/.ssh/authorized_keys)
        echo "✓ Found $keys_count SSH key(s)"
        DISABLE_PASSWORD_AUTH=true
    else
        echo "⚠️ Warning: No SSH keys found"
        KEEP_PASSWORD_AUTH=true
    fi
else
    echo "⚠️ Failed to fetch GitHub keys - keeping password auth enabled"
    KEEP_PASSWORD_AUTH=true
fi

# Configure SSH daemon security options
echo "Configuring SSH daemon security..."
cp /etc/ssh/sshd_config "/etc/ssh/sshd_config.backup.$(date +%Y%m%d-%H%M%S)"

if [[ "${KEEP_PASSWORD_AUTH:-false}" != "true" ]]; then
    sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
    sed -i 's/PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
    passwd -l root
else
    echo "Password authentication remains enabled for emergency access"
fi

cat >> /etc/ssh/sshd_config <<EOF

# Additional security settings
PubkeyAuthentication yes
MaxAuthTries 3
ClientAliveInterval 300
ClientAliveCountMax 2
PermitEmptyPasswords no
X11Forwarding no
EOF

if systemctl reload sshd; then
    echo "✓ SSH service reloaded with updated configuration"
else
    echo "⚠️ SSH service reload failed - manual intervention may be required"
fi

# Step 2: Identify node based on MAC address
echo "Step 2: Identifying node..."
ACTIVE_IF=$(ip route get 8.8.8.8 | awk 'NR==1 {print $5}')
PRIMARY_MAC=$(ip link show "$ACTIVE_IF" | grep -o '[a-f0-9:]\{17\}' | head -1)

echo "Active interface: $ACTIVE_IF"
echo "Primary MAC address: $PRIMARY_MAC"

case "$PRIMARY_MAC" in
    "$NODE_MAC_1")
        NODE_NAME="$NODE_NAME_1"
        NODE_ID="$NODE_ID_1"
        NODE_IP="$NODE_IP_1"
        ;;
    "$NODE_MAC_2")
        NODE_NAME="$NODE_NAME_2"
        NODE_ID="$NODE_ID_2"
        NODE_IP="$NODE_IP_2"
        ;;
    *)
        NODE_NAME="${DEFAULT_NODE_NAME}-$(date +%s)"
        NODE_ID="$DEFAULT_NODE_ID"
        NODE_IP=""
        echo "⚠️ Unknown MAC address; using fallback node name: $NODE_NAME"
        ;;
esac

echo " ✓ Node identified as: $NODE_NAME (ID: $NODE_ID)"

# Step 3: Update system identity (hostname and hosts file)
echo "Step 3: Updating system identity..."
hostnamectl set-hostname "$NODE_NAME"

cp /etc/hosts "/etc/hosts.backup.$(date +%Y%m%d-%H%M%S)"
sed -i '/pve-temp/d' /etc/hosts
echo "127.0.1.1 $NODE_NAME.homelab.local $NODE_NAME" >> /etc/hosts

cat >> /etc/hosts <<EOF
# Proxmox cluster nodes (uncomment as cluster forms)
# $NODE_IP_1 $NODE_NAME_1.homelab.local $NODE_NAME_1
# $NODE_IP_2 $NODE_NAME_2.homelab.local $NODE_NAME_2
EOF

echo "✓ Hostname set to: $NODE_NAME.homelab.local"

# Step 4: System update & package installation
echo "Step 4: Configuring repositories and system packages..."

# Disable enterprise repo and enable no-subscription repo
echo "Configuring Proxmox package repositories..."
if [ -f /etc/apt/sources.list.d/pve-enterprise.list ]; then
  mv /etc/apt/sources.list.d/pve-enterprise.list /etc/apt/sources.list.d/pve-enterprise.list.disabled
  echo "Enterprise repo disabled"
fi
echo "deb http://download.proxmox.com/debian/pve bookworm pve-no-subscription" > /etc/apt/sources.list.d/pve-no-subscription.list
echo "No-subscription repo enabled"

apt-get update

ESSENTIAL_PKGS=(
    curl wget git htop vim net-tools tree rsync screen python3-pip
    fail2ban ufw
    nut-client
)

apt-get install -y "${ESSENTIAL_PKGS[@]}"

# Step 5: Remove subscription nag
echo "Step 5: Removing Proxmox subscription nag from Web UI..."
JS="/usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js"
if [ -f "$JS" ] && ! grep -q NoMoreNagging "$JS"; then
  sed -i -e "/data\.status/ s/!//" -e "/data\.status/ s/active/NoMoreNagging/" "$JS"
  echo "Subscription nag suppressed"
else
  echo "Subscription nag patch not required"
fi

# Step 6: Enable HA-related services
echo "Step 6: Enabling high availability services..."
systemctl enable --now pve-ha-lrm pve-ha-crm corosync

# Step 7: Clone or update infrastructure repository
echo "Step 7: Setting up infrastructure automation..."
if [ -d "$REPO_DIR" ]; then
    cd "$REPO_DIR"
    if git pull; then
        echo "✓ Repository updated"
    else
        echo "⚠️ Failed to update repository"
    fi
else
    if git clone "$REPO_URL" "$REPO_DIR"; then
        echo "✓ Repository cloned"
    else
        echo "⚠️ Failed to clone repository"
    fi
fi

# Step 8: Install Ansible
echo "Step 8: Installing Ansible..."
pip3 install --upgrade pip
pip3 install ansible

# Step 9: Run Ansible bootstrap playbook if available
echo "Step 9: Running Ansible bootstrap..."
if [[ -f "$REPO_DIR/ansible/playbooks/bootstrap.yml" ]]; then
    cd "$REPO_DIR"
    export ANSIBLE_HOST_KEY_CHECKING=False
    ansible-playbook -i localhost, -c local -e "node_hostname=$NODE_NAME" -e "node_id=$NODE_ID" -e "primary_mac=$PRIMARY_MAC" ansible/playbooks/bootstrap.yml
else
    echo "⚠️ Bootstrap playbook not found; skipping Ansible run"
fi

# Step 10: System full upgrade and reboot
echo "Step 10: Performing full system upgrade..."
apt-get update && apt-get -y dist-upgrade

echo "Rebooting system now to complete updates..."
sleep 3
reboot

# Mark completion (won't be reached due to reboot)
echo "Step 11: Finalizing bootstrap..." 
cat > /opt/homelab-bootstrap-complete <<EOF
Bootstrap completed: $(date)
Node name: $NODE_NAME
Node ID: $NODE_ID
MAC address: $PRIMARY_MAC
IP address: $(hostname -I | awk '{print $1}')
SSH keys: $(if [[ "${KEEP_PASSWORD_AUTH:-false}" != "true" ]]; then echo "enabled"; else echo "password fallback"; fi)
Repository: $REPO_URL
EOF

echo "$NODE_NAME" > /opt/homelab-node-identity
