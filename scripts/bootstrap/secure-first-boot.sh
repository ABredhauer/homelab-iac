#!/bin/bash
# Minimal first-boot script - just enable Ansible access and call Semaphore

LOG_FILE="/var/log/homelab-first-boot.log"
set -euo pipefail
exec > >(tee -a "$LOG_FILE") 2>&1

echo "=================================================="
echo "First-boot initialization: $(date)"
echo "=================================================="

# Semaphore Configuration
SEMAPHORE_URL="http://192.168.1.196:3000"
SEMAPHORE_API_TOKEN="nrpjao4qhnegcri4ns5sxvt4m07uwt-it4jm9pqj2-o="
SEMAPHORE_PROJECT_ID="1"
REGISTER_TEMPLATE_ID="3"
BOOTSTRAP_TEMPLATE_ID="1"
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

# Enable SSH and configure
systemctl enable --now ssh

# Check if settings already exist before appending
if ! grep -q "# Ansible automation settings" /etc/ssh/sshd_config; then
    cat >> /etc/ssh/sshd_config <<'EOF'

# Ansible automation settings
PubkeyAuthentication yes
PasswordAuthentication no
PermitRootLogin prohibit-password
MaxAuthTries 3
EOF
fi

if systemctl reload sshd; then
    echo "✓ SSH configured for key-based authentication"
else
    echo "⚠️ SSH reload failed but continuing..."
fi

# Step 2: Register with Semaphore
echo "[3/3] Registering with Semaphore..."

# Get host details
HOSTNAME=$(hostname)
HOST_IP=$(hostname -I | awk '{print $1}')
ACTIVE_IF=$(ip route get 8.8.8.8 | awk 'NR==1 {print $5}')
PRIMARY_MAC=$(ip link show "$ACTIVE_IF" | grep -o '[a-f0-9:]\{17\}' | head -1)

echo "  Hostname: $HOSTNAME"
echo "  IP: $HOST_IP"
echo "  Interface: $ACTIVE_IF"
echo "  MAC: $PRIMARY_MAC"

# Build JSON payload for registration (using proper jq syntax)
ENV_JSON="{\"primary_mac\": \"${PRIMARY_MAC}\", \"temp_ip\": \"${HOST_IP}\", \"bootstrap_template_id\": \"${BOOTSTRAP_TEMPLATE_ID}\"}"

echo "  Environment JSON: $ENV_JSON"

# Escape for Semaphore environment parameter
ENV_ESCAPED=$(echo "$ENV_JSON" | sed 's/"/\\"/g')

echo "  Escaped Environment JSON: $ENV_ESCAPED"

# Call Semaphore registration API
echo "  Calling Semaphore registration API..."
REG_RESPONSE=$(curl -s -w "\nHTTP_STATUS:%{http_code}" -X POST \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${SEMAPHORE_API_TOKEN}" \
  -d "{
    \"template_id\": ${REGISTER_TEMPLATE_ID},
    \"message\": \"Register MAC ${PRIMARY_MAC}\",
    \"environment\": \"${ENV_ESCAPED}\"
  }" \
  "${SEMAPHORE_URL}/api/project/${SEMAPHORE_PROJECT_ID}/tasks")

# Parse response
HTTP_STATUS=$(echo "$REG_RESPONSE" | grep "HTTP_STATUS:" | cut -d':' -f2)
RESPONSE_BODY=$(echo "$REG_RESPONSE" | sed '/HTTP_STATUS:/d')

if [ "$HTTP_STATUS" = "201" ]; then
    REG_TASK_ID=$(echo "$RESPONSE_BODY" | grep -o '"id":[0-9]*' | head -1 | cut -d':' -f2)
    echo "  ✓ Registration started (Task ID: ${REG_TASK_ID})"
    echo "  ✓ View at: ${SEMAPHORE_URL}/project/${SEMAPHORE_PROJECT_ID}/history?t=${REG_TASK_ID}"
else
    echo "  ✗ Registration failed (HTTP ${HTTP_STATUS})"
    echo "  Response: ${RESPONSE_BODY}"
    exit 1
fi

# Create completion marker with details
cat > /opt/first-boot-complete <<EOF
First-boot completed: $(date)
Hostname: ${HOSTNAME}
IP: ${HOST_IP}
MAC: ${PRIMARY_MAC}
Registration Task: ${REG_TASK_ID}
Semaphore URL: ${SEMAPHORE_URL}
EOF

chmod 644 /opt/first-boot-complete

# Mark first-boot complete
echo ""
echo "=================================================="
echo "First-boot complete - Ansible will handle the rest"
echo "Monitor progress: ${SEMAPHORE_URL}"
echo "Completion details saved to /opt/first-boot-complete"
echo "=================================================="
