#!/bin/bash
# Minimal first-boot script for Raspberry Pi - just enable root SSH access
# The ansible user will be created by the bootstrap playbook

set -euo pipefail
LOG_FILE="/var/log/pi-first-boot.log"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "=================================================="
echo "Pi First-Boot: $(date)"
echo "=================================================="

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
