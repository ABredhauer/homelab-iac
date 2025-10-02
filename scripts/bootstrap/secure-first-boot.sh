#!/bin/bash
# File: scripts/bootstrap/secure-first-boot.sh
# Secure first-boot script for Proxmox nodes
# Runs after installation completes

set -euo pipefail

LOG_FILE="/var/log/homelab-bootstrap.log"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "=================================================="
echo "Starting secure bootstrap at $(date)"
echo "=================================================="

# 1. SECURITY FIRST - Set up SSH key authentication
echo "Step 1: Configuring SSH key authentication..."
mkdir -p /root/.ssh
chmod 700 /root/.ssh

# TODO: Replace 'yourusername' with your actual GitHub username
GITHUB_USER="ABredhauer"
curl -sSL "https://github.com/${GITHUB_USER}.keys" > /root/.ssh/authorized_keys
chmod 600 /root/.ssh/authorized_keys

# Disable password authentication
sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
sed -i 's/PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
systemctl reload sshd

# Lock the root password (keeps account active for SSH)
passwd -l root
echo "✓ SSH key authentication configured and password auth disabled"

# 2. NODE IDENTIFICATION - Determine which Dell this is
echo "Step 2: Identifying node..."
PRIMARY_MAC=$(ip link show | grep -A1 "state UP" | grep -o '[a-f0-9:]\{17\}' | head -1)
echo "Primary MAC address: $PRIMARY_MAC"

# TODO: Replace these MACs with your actual Dell MAC addresses
case "$PRIMARY_MAC" in
    "aa:bb:cc:dd:ee:01")  # First Dell OptiPlex MAC
        NODE_NAME="pve-node1"
        NODE_ID="1"
        ;;
    "aa:bb:cc:dd:ee:02")  # Second Dell OptiPlex MAC
        NODE_NAME="pve-node2" 
        NODE_ID="2"
        ;;
    *)
        NODE_NAME="pve-unknown-$(date +%s)"
        NODE_ID="99"
        echo "⚠️  Unknown MAC address - using default naming"
        ;;
esac

echo "✓ Node identified as: $NODE_NAME (ID: $NODE_ID)"

# 3. UPDATE SYSTEM IDENTITY
echo "Step 3: Updating system identity..."
hostnamectl set-hostname "$NODE_NAME"

# Update /etc/hosts
cp /etc/hosts /etc/hosts.backup
echo "127.0.1.1 $NODE_NAME.homelab.local $NODE_NAME" >> /etc/hosts
sed -i 's/pve-temp/'"$NODE_NAME"'/g' /etc/hosts

echo "✓ Hostname set to: $NODE_NAME.homelab.local"

# 4. BASIC SYSTEM UPDATES
echo "Step 4: Updating system packages..."
apt-get update
apt-get install -y curl wget git htop vim net-tools

# 5. CLONE INFRASTRUCTURE REPOSITORY
echo "Step 5: Setting up infrastructure automation..."
REPO_URL="https://github.com/ABredhauer/homelab-iac.git"  # TODO: Update this
REPO_DIR="/opt/homelab-iac"

if [ -d "$REPO_DIR" ]; then
    echo "Repository already exists, updating..."
    cd "$REPO_DIR" && git pull
else
    echo "Cloning infrastructure repository..."
    git clone "$REPO_URL" "$REPO_DIR"
fi

# 6. INSTALL ANSIBLE
echo "Step 6: Installing Ansible..."
apt-get install -y python3-pip
pip3 install ansible

# 7. RUN INITIAL ANSIBLE BOOTSTRAP
echo "Step 7: Running Ansible bootstrap..."
cd "$REPO_DIR"
export ANSIBLE_HOST_KEY_CHECKING=False

# Check if bootstrap playbook exists before running
if [ -f "ansible/playbooks/bootstrap.yml" ]; then
    ansible-playbook -i localhost, \
        -c local \
        -e "node_hostname=$NODE_NAME" \
        -e "node_id=$NODE_ID" \
        -e "primary_mac=$PRIMARY_MAC" \
        ansible/playbooks/bootstrap.yml
else
    echo "⚠️  Bootstrap playbook not found - skipping Ansible run"
fi

# 8. MARK COMPLETION
touch /opt/homelab-bootstrap-complete
echo "$NODE_NAME" > /opt/homelab-node-identity

echo "=================================================="
echo "✓ Bootstrap completed successfully at $(date)"
echo "✓ Node: $NODE_NAME ($NODE_ID)"
echo "✓ IP: $(hostname -I | awk '{print $1}')"
echo "✓ Proxmox UI: https://$(hostname -I | awk '{print $1}'):8006"
echo "✓ SSH: ssh root@$(hostname -I | awk '{print $1}')"
echo "=================================================="
