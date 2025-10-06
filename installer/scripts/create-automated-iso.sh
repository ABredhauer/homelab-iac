#!/bin/bash
# File: installer/scripts/create-automated-iso.sh
# Final fixed version: ensures correct ownership & permissions

set -euo pipefail

ISO_FILE="proxmox-ve_9.0-1.iso"
OUTPUT_ISO="proxmox-ve-automated.iso"
ANSWER_URL="https://raw.githubusercontent.com/ABredhauer/homelab-iac/main/installer/answer-files/proxmox-answer.toml"

echo "==============================================="
echo "==> Starting Proxmox Automated ISO Creation"
echo "==============================================="

# Verify original ISO exists
if [[ ! -f "$ISO_FILE" ]]; then
  echo "Error: $ISO_FILE not found in $(pwd)"
  exit 1
fi

# Setup temp directories under $TMPDIR
WORK_DIR="$(mktemp -d)"
MOUNT_DIR="$WORK_DIR/iso-mount"
COPY_DIR="$WORK_DIR/Proxmox-AIS"
mkdir -p "$MOUNT_DIR" "$COPY_DIR"

trap 'echo "Cleaning up..."; set +x; hdiutil detach "$MOUNT_DIR" 2>/dev/null || true; chmod -R u+w,u+rX "$WORK_DIR" 2>/dev/null || true; rm -rf "$WORK_DIR"; echo "Cleanup complete."' EXIT

# Mount original ISO
echo "Mounting original ISO at $MOUNT_DIR..."
hdiutil attach "$ISO_FILE" -mountpoint "$MOUNT_DIR" -nobrowse -readonly

# Copy contents
echo "Copying contents to $COPY_DIR..."
cp -R "$MOUNT_DIR/." "$COPY_DIR/"

# Detach original ISO
echo "Detaching original ISO..."
hdiutil detach "$MOUNT_DIR"

# Fix ownership & permissions on copied files
echo "Adjusting ownership and permissions in $COPY_DIR..."
sudo chown -R "$(whoami)" "$COPY_DIR"
chmod -R u+w,u+rX "$COPY_DIR"

# Modify GRUB configuration

GRUB_CFG="$COPY_DIR/boot/grub/grub.cfg"

echo "Patching GRUB config at $GRUB_CFG..."

if [[ -f "$GRUB_CFG" ]]; then
  # Backup
  cp "$GRUB_CFG" "$GRUB_CFG.bak"

  # 1) Append automated menu entry at end of file
  cat >> "$GRUB_CFG" << EOF

menuentry "Install Proxmox VE (Automated)" {
    set gfxpayload=keep
    linux /boot/linux26 ro ramdisk_size=16777216 rw quiet splash=verbose proxdebug fetch-answer-url=$ANSWER_URL
    initrd /boot/initrd.img
}
EOF

  # 2) Update default and timeout
  sed -i.bak 's|^set default=.*|set default="Install Proxmox VE (Automated)"|' "$GRUB_CFG"
  sed -i.bak 's|^set timeout=.*|set timeout=10|' "$GRUB_CFG"

  echo "GRUB config patched."
else
  echo "Warning: $GRUB_CFG not found; skipping patch."
fi

# Build new ISO
echo "Building new ISO $OUTPUT_ISO..."
pushd "$COPY_DIR"

mkisofs -v -o "$OLDPWD/$OUTPUT_ISO" \
    -V "Proxmox VE Automated" \
    -J -iso-level 3 -joliet-long \
    -r \
    -b boot/grub/i386-pc/eltorito.img \
    -no-emul-boot \
    -boot-load-size 4 \
    -boot-info-table \
    -eltorito-alt-boot \
    -eltorito-platform efi \
    -b boot/grub/x86_64-efi/efiboot.img \
    -no-emul-boot \
    .

popd

# Verify ISO creation
if [[ -f "$OUTPUT_ISO" ]]; then
  echo "✓ Created $OUTPUT_ISO ($(ls -lh $OUTPUT_ISO | awk '{print $5}'))"
  file "$OUTPUT_ISO"
else
  echo "✗ Failed to create $OUTPUT_ISO"
  exit 1
fi

# Test answer file URL
echo "Testing answer file URL..."
if curl -sf "$ANSWER_URL" >/dev/null; then
  echo "✓ Answer file reachable"
else
  echo "⚠️ Answer file not reachable"
fi

echo "==============================================="
echo "==> ISO Creation Complete"
echo "==============================================="
