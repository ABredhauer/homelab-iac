#!/bin/bash
# Minimal first-boot script for Raspberry Pi - just enable root SSH access
# The ansible user will be created by the bootstrap playbook

set -euo pipefail
LOG_FILE="/var/log/pi-first-boot.log"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "=================================================="
echo "Pi First-Boot: $(date)"
echo "=================================================="

GITHUB_USER="ABredhauer"
SSH_KEY_DIR="/root/.ssh"

# Step 1: Configure SSH for Ansible access
echo "[2/3] Configuring SSH access..."
mkdir -p "${SSH_KEY_DIR}"
chmod 700 "${SSH_KEY_DIR}"

# Fetch SSH keys from GitHub
if curl -fsSL --connect-timeout 10 --max-time 30 "https://github.com/${GITHUB_USER}.keys" > "${SSH_KEY_DIR}/authorized_keys"; then
    chmod 600 "${SSH_KEY_DIR}/authorized_keys"
    
    # Verify keys were actually downloaded
    if [[ -s "${SSH_KEY_DIR}/authorized_keys" ]]; then
        keys_count=$(wc -l < "${SSH_KEY_DIR}/authorized_keys")
        echo "✓ SSH keys configured (${keys_count} key(s))"
    else
        echo "✗ SSH keys file is empty"
        exit 1
    fi
else
    echo "✗ Failed to fetch SSH keys - aborting"
    exit 1
fi

# Step 1: Enable SSH
echo "[1/2] Enabling SSH..."
systemctl enable --now ssh
echo "✓ SSH enabled"

# Step 2: SSH hardening (basic config, will be refined by bootstrap playbook)
echo "[2/2] Configuring SSH..."
if ! grep -q "# Minimal Pi SSH config" /etc/ssh/sshd_config; then
    cat >> /etc/ssh/sshd_config <<'EOF'

# Minimal Pi SSH config
PubkeyAuthentication yes
EOF
fi

systemctl reload ssh
echo "✓ SSH ready for bootstrap playbook"

echo "=================================================="
echo "First-boot complete - ready for Ansible bootstrap"
echo "=================================================="
