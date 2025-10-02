#!/bin/bash
# File: scripts/create-automated-iso.sh
# Simple script to create URL-based automated Proxmox ISO

set -euo pipefail

ISO_FILE="proxmox-ve_9.0-1.iso"
OUTPUT_ISO="proxmox-ve-automated.iso"
ANSWER_URL="https://raw.githubusercontent.com/ABredhauer/homelab-iac/main/installer/answer-files/proxmox-answer.toml"

echo "Creating automated Proxmox ISO..."

# Check if original ISO exists
if [[ ! -f "$ISO_FILE" ]]; then
    echo "Error: $ISO_FILE not found"
    echo "Download it first: wget https://enterprise.proxmox.com/iso/proxmox-ve_9.0-1.iso"
    exit 1
fi

# Create temp directory
WORK_DIR=$(mktemp -d)
MOUNT_POINT="$WORK_DIR/mount"

cleanup() {
    hdiutil detach "$MOUNT_POINT" 2>/dev/null || true
    rm -rf "$WORK_DIR"
}
trap cleanup EXIT

# Mount and copy
echo "Mounting original ISO..."
mkdir -p "$MOUNT_POINT"
hdiutil attach "$ISO_FILE" -mountpoint "$MOUNT_POINT" -nobrowse

echo "Copying ISO contents..."
cp -R "$MOUNT_POINT"/* "$WORK_DIR"/

# Modify GRUB config
echo "Modifying boot configuration..."
GRUB_CFG="$WORK_DIR/boot/grub/grub.cfg"

if [[ -f "$GRUB_CFG" ]]; then
    # Backup original
    cp "$GRUB_CFG" "$GRUB_CFG.backup"
    
    # Add automated install entry
    sed -i.bak '/menuentry.*Install Proxmox VE.*Graphical/ {
        a\
\
menuentry "Install Proxmox VE (Automated)" {\
    set gfxpayload=keep\
    linux /boot/linux26 ro ramdisk_size=16777216 rw quiet splash=verbose proxdebug fetch-answer-url='"$ANSWER_URL"'\
    initrd /boot/initrd.img\
}
    }' "$GRUB_CFG"
    
    # Set automated as default
    sed -i.bak 's/set default=.*/set default="Install Proxmox VE (Automated)"/' "$GRUB_CFG"
    sed -i.bak 's/set timeout=.*/set timeout=10/' "$GRUB_CFG"
    
    echo "✓ Boot configuration modified"
else
    echo "Warning: GRUB config not found at expected location"
fi

# Create new ISO
echo "Creating new ISO..."
cd "$WORK_DIR"
hdiutil makehybrid -o "$OLDPWD/$OUTPUT_ISO" . \
    -joliet \
    -iso \
    -default-volume-name "Proxmox VE Automated"

cd "$OLDPWD"
echo "✓ Created: $OUTPUT_ISO ($(ls -lh $OUTPUT_ISO | awk '{print $5}'))"

# Test the answer file URL
echo "Testing answer file URL..."
if curl -f -s "$ANSWER_URL" >/dev/null; then
    echo "✓ Answer file accessible at GitHub"
else
    echo "⚠️  Answer file not accessible - check GitHub repo"
fi

echo ""
echo "Ready to boot! The ISO will:"
echo "1. Boot automatically in 10 seconds"
echo "2. Fetch answer file from GitHub"
echo "3. Install Proxmox unattended"
echo "4. Run first-boot script on startup"
