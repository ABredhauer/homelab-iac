#!/bin/bash
# Bootstrap Raspberry Pi for Ansible management (mirrors Proxmox pattern)
# Execute this ON THE PI via local console or existing SSH access

set -euo pipefail
LOG_FILE="/var/log/pi-ansible-bootstrap.log"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "=================================================="
echo "Pi Ansible Bootstrap: $(date)"
echo "=================================================="

# Configuration (match your Proxmox setup)
GITHUB_USER="ABredhauer"
ANSIBLE_USER="ansible"
SEMAPHORE_SSH_KEY_URL="https://github.com/${GITHUB_USER}.keys"

# Step 1: Create ansible user
echo "[1/4] Creating ansible user..."
if ! id "${ANSIBLE_USER}" &>/dev/null; then
    useradd -m -s /bin/bash -G sudo "${ANSIBLE_USER}"
    echo "${ANSIBLE_USER} ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/99-${ANSIBLE_USER}
    chmod 440 /etc/sudoers.d/99-${ANSIBLE_USER}
    echo "✓ User ${ANSIBLE_USER} created with sudo access"
else
    echo "✓ User ${ANSIBLE_USER} already exists"
fi

# Step 2: Configure SSH keys
echo "[2/4] Configuring SSH keys..."
mkdir -p /home/${ANSIBLE_USER}/.ssh
chmod 700 /home/${ANSIBLE_USER}/.ssh

# Fetch keys from GitHub
if curl -fsSL --connect-timeout 10 "${SEMAPHORE_SSH_KEY_URL}" > /home/${ANSIBLE_USER}/.ssh/authorized_keys; then
    chmod 600 /home/${ANSIBLE_USER}/.ssh/authorized_keys
    chown -R ${ANSIBLE_USER}:${ANSIBLE_USER} /home/${ANSIBLE_USER}/.ssh
    
    keys_count=$(wc -l < /home/${ANSIBLE_USER}/.ssh/authorized_keys)
    echo "✓ SSH keys configured (${keys_count} key(s))"
else
    echo "✗ Failed to fetch SSH keys - aborting"
    exit 1
fi

# Step 3: SSH hardening (match Proxmox nodes)
echo "[3/4] Hardening SSH..."
# Backup original
cp /etc/ssh/sshd_config /etc/ssh/sshd_config.pre-ansible.bak

# Configure SSH (similar to your Proxmox first-boot script)
cat >> /etc/ssh/sshd_config <<'EOF'

# Ansible automation settings
PubkeyAuthentication yes
PasswordAuthentication no
PermitRootLogin no
MaxAuthTries 3
EOF

systemctl restart ssh
echo "✓ SSH hardened"

# Step 4: Install prerequisites
# echo "[4/4] Installing prerequisites..."
# apt update
# apt install -y corosync-qnetd iptables-persistent

# Create completion marker
cat > /opt/pi-ansible-ready <<EOF
Pi Ansible Bootstrap completed: $(date)
GitHub User: ${GITHUB_USER}
Ansible User: ${ANSIBLE_USER}
EOF

echo "=================================================="
echo "Bootstrap complete! Pi is ready for Ansible management"
echo "=================================================="
