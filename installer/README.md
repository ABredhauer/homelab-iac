# Proxmox VE Automated Installation Guide

This guide provides a complete walkthrough for implementing automated, unattended Proxmox VE installations using Infrastructure as Code principles. The approach uses URL-based answer files hosted on GitHub and post-install automation scripts for a completely hands-off deployment experience.

## Table of Contents

1. [Overview](#overview)
2. [Prerequisites](#prerequisites)
3. [Architecture](#architecture)
4. [Files and Directory Structure](#files-and-directory-structure)
5. [Step-by-Step Implementation](#step-by-step-implementation)
6. [Answer File Configuration](#answer-file-configuration)
7. [ISO Creation Process](#iso-creation-process)
8. [Deployment and Testing](#deployment-and-testing)
9. [Post-Install Automation](#post-install-automation)
10. [Troubleshooting](#troubleshooting)
11. [Advanced Configuration](#advanced-configuration)
12. [References](#references)

## Overview

This automated installation system provides:

- **Zero-touch deployment** from bare metal to configured Proxmox cluster node
- **Dynamic node identification** based on hardware characteristics (MAC addresses)
- **Git-based configuration management** with all configs version controlled
- **Security-first approach** with SSH key authentication and password lockdown
- **Scalable architecture** that works for 2 nodes or 200+ nodes
- **Minimal ISO modification** - single ISO works for all nodes

### Key Benefits

- **Reproducible**: Every installation is identical and documented
- **Maintainable**: All configurations in Git, easy to track changes
- **Scalable**: Add new nodes by updating configuration files only
- **Secure**: Automated security hardening during installation
- **Flexible**: Easy to test changes without rebuilding ISOs

## Prerequisites

### Hardware Requirements

- Target systems with UEFI boot capability
- Network connectivity during installation (for fetching configs)
- Systems with unique identifiable characteristics (MAC addresses, serial numbers)
- Optional: Out-of-band management (Intel AMT, iDRAC, iLO) for remote deployment

### Software Requirements

**Development Machine (macOS/Linux):**
- Git for version control
- Text editor for configuration files
- `curl` for testing URLs
- `hdiutil` (macOS) or equivalent ISO tools

**Network Infrastructure:**
- DHCP server for initial IP assignment
- DNS resolution for GitHub access
- Internet connectivity for package downloads

### Knowledge Prerequisites

- Basic understanding of Linux system administration
- Familiarity with Git version control
- Understanding of YAML/TOML configuration formats
- Basic networking concepts (DHCP, DNS, IP addressing)

## Architecture

### High-Level Flow

```
1. Boot from modified Proxmox ISO
2. ISO fetches answer file from GitHub URL
3. Unattended installation proceeds automatically
4. System reboots and runs first-boot script
5. First-boot script identifies node and configures system
6. Ansible playbooks complete detailed configuration
7. Node is ready for cluster operations
```

### Component Interaction

```
GitHub Repository
├── Answer File (TOML) ──→ Proxmox Installer
├── First-Boot Script ──→ Systemd Service
└── Ansible Playbooks ──→ Configuration Management
```

### Security Model

- **Installation Phase**: Temporary root password for installation only
- **First-Boot Phase**: SSH keys deployed, password authentication disabled
- **Runtime Phase**: Key-based authentication only, root password locked

## Files and Directory Structure

```
installer/
├── README.md                    # This comprehensive guide
├── answer-files/
│   └── proxmox-answer.toml     # Main answer file for all nodes
├── scripts/
│   └── create-automated-iso.sh # ISO creation script
└── examples/
    ├── answer-file-examples.toml
    └── boot-parameter-examples.txt
```

## Step-by-Step Implementation

### Phase 1: Repository Setup

1. **Initialize Git Repository**
   ```bash
   mkdir homelab-iac
   cd homelab-iac
   git init
   mkdir -p installer/{answer-files,scripts,examples}
   ```

2. **Create Answer File**
   - Copy the template answer file to `installer/answer-files/proxmox-answer.toml`
   - Customize regional settings (timezone, keyboard, country)
   - Configure disk layout based on your hardware
   - Set temporary root password (will be disabled post-install)

3. **Create Bootstrap Scripts**
   - Set up `scripts/bootstrap/secure-first-boot.sh` 
   - Configure node identification logic (MAC address mapping)
   - Define post-install security hardening steps

4. **Push to GitHub**
   ```bash
   git add .
   git commit -m "Initial automated installation setup"
   git push origin main
   ```

### Phase 2: ISO Preparation

1. **Download Official Proxmox ISO**
   ```bash
   cd installer/
   wget https://enterprise.proxmox.com/iso/proxmox-ve_9.0-1.iso
   ```

2. **Verify Download**
   ```bash
   # Check file size and integrity
   ls -lh proxmox-ve_9.0-1.iso
   # Optional: verify checksum if provided by Proxmox
   ```

3. **Test Answer File Accessibility**
   ```bash
   curl -f https://raw.githubusercontent.com/yourusername/homelab-iac/main/installer/answer-files/proxmox-answer.toml
   ```

### Phase 3: ISO Modification

1. **Run ISO Creation Script**
   ```bash
   chmod +x installer/scripts/create-automated-iso.sh
   cd installer/
   ./scripts/create-automated-iso.sh
   ```

2. **Verify Modified ISO**
   ```bash
   ls -lh proxmox-ve-automated.iso
   # Test mount to verify structure
   ```

### Phase 4: Deployment

1. **Create Bootable Media**
   - USB: Use `dd` or disk imaging tool
   - Network: Set up PXE/iPXE boot
   - Remote: Use out-of-band management to mount ISO

2. **Boot Target System**
   - Power on target system
   - Select automated installation option
   - Monitor installation progress (optional)

3. **Post-Install Verification**
   - Wait for first-boot script completion
   - Verify SSH key authentication works
   - Check hostname and system identification

## Answer File Configuration

The answer file (`proxmox-answer.toml`) uses TOML format and contains several key sections:

### Global Settings Section

```toml
[global]
keyboard = "us"                    # Keyboard layout
country = "au"                     # Country for mirror selection
timezone = "Australia/Brisbane"    # System timezone
fqdn = "pve-temp.homelab.local"   # Temporary hostname
mailto = "admin@example.com"       # Alert email
root-password = "TempPassword123!" # Temporary password
```

**Key Considerations:**
- **Keyboard Layout**: Must match your physical keyboard
- **Country Code**: Affects package mirror selection and download speed
- **Timezone**: Use standard timezone identifiers
- **FQDN**: Will be changed by post-install script
- **Root Password**: Use complex temporary password, gets disabled automatically

### Network Configuration Section

```toml
[network]
source = "from-dhcp"  # Use DHCP for initial setup
```

**Options:**
- `from-dhcp`: Automatic IP assignment (recommended)
- `from-answer-file`: Manual IP configuration in answer file
- Static configuration requires additional parameters

### Disk Setup Section

```toml
[disk-setup]
filesystem = "ext4"        # Root filesystem type
disk-list = ["*"]         # Disk selection pattern
filter-match = "any"      # Matching strategy

# LVM Configuration
lvm.hdsize = 900          # Total disk usage (GB)
lvm.swapsize = 8          # Swap size (GB)
lvm.maxroot = 100         # Root volume max size (GB)
lvm.maxvz = 792          # Data volume max size (GB)
lvm.minfree = 16         # Minimum free space (GB)
```

**Filesystem Options:**
- **ext4**: Most reliable, recommended for most use cases
- **xfs**: Good performance, suitable for large files
- **zfs**: Advanced features, requires more RAM
- **btrfs**: Experimental, not recommended for production

**Disk Selection Patterns:**
- `["*"]`: Any available disk
- `["/dev/sda"]`: Specific disk by device name
- `["/dev/nvme*"]`: NVMe disks only
- `["*SAMSUNG*"]`: Filter by model name

### First-Boot Hook Section

```toml
[first-boot]
source = "from-url"
url = "https://raw.githubusercontent.com/user/repo/main/scripts/bootstrap/secure-first-boot.sh"
on-error = "continue"
```

**Error Handling Options:**
- `continue`: Boot continues even if script fails
- `abort`: Stop boot process on script failure

## ISO Creation Process

The ISO creation process involves minimal modification of the official Proxmox ISO:

### What Gets Modified

1. **Boot Menu**: Add automated installation option
2. **Boot Parameters**: Add `fetch-answer-url` parameter
3. **Default Selection**: Set automated install as default
4. **Timeout**: Reduce boot menu timeout for automation

### Boot Parameter Details

The key addition is the `fetch-answer-url` parameter:

```
fetch-answer-url=https://raw.githubusercontent.com/user/repo/main/installer/answer-files/proxmox-answer.toml
```

This tells the Proxmox installer to:
1. Download the answer file from the specified URL
2. Parse the TOML configuration
3. Proceed with unattended installation
4. Execute post-install hooks as configured

### ISO Structure After Modification

```
proxmox-ve-automated.iso
├── boot/
│   ├── grub/
│   │   └── grub.cfg          # Modified with new boot entries
│   ├── linux26              # Proxmox kernel
│   └── initrd.img           # Initial ramdisk
└── [other original files]    # Unchanged
```

## Deployment and Testing

### Testing Strategy

1. **Virtual Machine Testing**
   - Test with VMware/VirtualBox first
   - Verify answer file download works
   - Check installation completes successfully
   - Validate first-boot script execution

2. **Network Connectivity Testing**
   ```bash
   # Test from target network
   curl -v https://raw.githubusercontent.com/user/repo/main/installer/answer-files/proxmox-answer.toml
   ```

3. **Hardware-Specific Testing**
   - Test on actual target hardware
   - Verify disk detection and partitioning
   - Check network interface identification
   - Validate MAC address-based node identification

### Deployment Methods

#### USB Boot Deployment
```bash
# Create bootable USB (replace /dev/sdX with actual device)
sudo dd if=proxmox-ve-automated.iso of=/dev/sdX bs=4M status=progress
sync
```

#### Network PXE Deployment
```bash
# Extract ISO contents to TFTP root
mkdir /tftpboot/proxmox
mount -o loop proxmox-ve-automated.iso /mnt
cp -r /mnt/* /tftpboot/proxmox/
umount /mnt

# Configure PXE menu entry
cat >> /tftpboot/pxelinux.cfg/default << 'EOF'
LABEL proxmox-auto
    MENU LABEL Proxmox VE Automated Install
    KERNEL proxmox/boot/linux26
    APPEND initrd=proxmox/boot/initrd.img fetch-answer-url=https://raw.githubusercontent.com/user/repo/main/installer/answer-files/proxmox-answer.toml
EOF
```

#### Remote Management Deployment
```bash
# Intel AMT example
amttool hostname.domain power-cycle
# Mount ISO via remote management interface
# Boot from virtual media
```

## Post-Install Automation

### First-Boot Script Execution

The first-boot script (`secure-first-boot.sh`) performs critical post-install configuration:

1. **Security Configuration**
   - Deploy SSH public keys from GitHub
   - Disable password authentication
   - Lock root password account

2. **System Identification**
   - Detect hardware characteristics (MAC address)
   - Determine node identity from predefined mapping
   - Set appropriate hostname for the node

3. **Initial System Setup**
   - Update system packages
   - Install essential tools and dependencies
   - Configure timezone and regional settings

4. **Infrastructure Code Setup**
   - Clone infrastructure repository
   - Install Ansible and dependencies
   - Execute initial configuration playbooks

### Node Identification Logic

```bash
# Example MAC address-based identification
PRIMARY_MAC=$(ip link show | grep -A1 "state UP" | grep -o '[a-f0-9:]\{17\}' | head -1)

case "$PRIMARY_MAC" in
    "aa:bb:cc:dd:ee:01")
        NODE_NAME="pve-node1"
        ;;
    "aa:bb:cc:dd:ee:02") 
        NODE_NAME="pve-node2"
        ;;
    *)
        NODE_NAME="pve-unknown-$(date +%s)"
        ;;
esac
```

### Configuration Management Integration

Post-install automation integrates with Ansible for detailed configuration:

```bash
# Example Ansible execution from first-boot script
ansible-playbook -i localhost, \
    -c local \
    -e "node_hostname=$NODE_NAME" \
    -e "node_id=$NODE_ID" \
    ansible/playbooks/bootstrap.yml
```

## Troubleshooting

### Common Issues and Solutions

#### Answer File Not Found (404 Error)
**Symptoms**: Installation fails with network/download error
**Causes**: 
- GitHub repository is private
- File path is incorrect
- Network connectivity issues

**Solutions**:
```bash
# Test URL accessibility
curl -v https://raw.githubusercontent.com/user/repo/main/installer/answer-files/proxmox-answer.toml

# Check repository visibility (must be public)
# Verify file path in repository
# Test network connectivity from target system
```

#### First-Boot Script Fails
**Symptoms**: System boots but automation doesn't complete
**Causes**:
- Script has syntax errors
- Network issues during script execution
- Missing dependencies

**Solutions**:
```bash
# Check first-boot logs
tail -f /var/log/homelab-bootstrap.log

# Manually run first-boot script for debugging
bash -x /path/to/secure-first-boot.sh

# Verify script syntax
bash -n /path/to/secure-first-boot.sh
```

#### SSH Key Authentication Not Working
**Symptoms**: Cannot connect with SSH keys after installation
**Causes**:
- GitHub username incorrect in script
- SSH keys not properly deployed
- SSH daemon configuration issues

**Solutions**:
```bash
# Verify SSH key deployment
cat /root/.ssh/authorized_keys

# Check SSH daemon configuration
grep -E "(PasswordAuthentication|PubkeyAuthentication)" /etc/ssh/sshd_config

# Test GitHub key access
curl https://github.com/yourusername.keys
```

#### Disk Partitioning Issues
**Symptoms**: Installation fails during disk setup
**Causes**:
- Disk size calculations incorrect
- Disk not detected by filter
- Existing partitions interfere

**Solutions**:
```bash
# Check available disks during installation
lsblk

# Verify disk filter patterns match your hardware
# Adjust LVM size calculations in answer file
# Clear existing partitions if necessary
```

### Debug Mode Installation

For troubleshooting, you can modify the boot parameters to enable debug mode:

```
# Add to boot parameters
proxdebug console=tty0 console=ttyS0,115200
```

This provides detailed installation logs and console access.

### Log File Locations

Important log files for troubleshooting:

- **Installation logs**: `/var/log/installer/`
- **First-boot logs**: `/var/log/homelab-bootstrap.log`
- **System logs**: `/var/log/syslog`, `/var/log/messages`
- **SSH logs**: `/var/log/auth.log`

## Advanced Configuration

### Multiple Answer Files

For different hardware types or configurations:

```
installer/answer-files/
├── proxmox-answer.toml           # Standard configuration
├── proxmox-answer-zfs.toml       # ZFS configuration
└── proxmox-answer-enterprise.toml # Enterprise configuration
```

Boot parameter can specify different files:
```
fetch-answer-url=https://raw.githubusercontent.com/user/repo/main/installer/answer-files/proxmox-answer-zfs.toml
```

### Dynamic Answer File Generation

For larger deployments, generate answer files dynamically:

```python
# Example: Generate answer files from CSV inventory
import csv
import jinja2

template = jinja2.Template(open('answer-template.toml').read())

with open('node-inventory.csv') as f:
    for row in csv.DictReader(f):
        answer_content = template.render(**row)
        with open(f"proxmox-answer-{row['hostname']}.toml", 'w') as out:
            out.write(answer_content)
```

### Custom Boot Menus

Create sophisticated boot menus with multiple options:

```
menuentry "Install Node 1" {
    linux /boot/linux26 ro fetch-answer-url=https://raw.githubusercontent.com/user/repo/main/installer/answer-files/node1.toml
    initrd /boot/initrd.img
}

menuentry "Install Node 2" {
    linux /boot/linux26 ro fetch-answer-url=https://raw.githubusercontent.com/user/repo/main/installer/answer-files/node2.toml
    initrd /boot/initrd.img
}

menuentry "Install with ZFS" {
    linux /boot/linux26 ro fetch-answer-url=https://raw.githubusercontent.com/user/repo/main/installer/answer-files/proxmox-zfs.toml
    initrd /boot/initrd.img
}
```

### Integration with Configuration Management

#### Ansible Integration
```yaml
# Example: Generate and deploy answer files with Ansible
- name: Generate Proxmox answer files
  template:
    src: proxmox-answer.toml.j2
    dest: "/var/www/html/{{ inventory_hostname }}.toml"
  delegate_to: web-server

- name: Update boot configuration
  lineinfile:
    path: /tftpboot/pxelinux.cfg/01-{{ ansible_mac | replace(':','-') }}
    line: "APPEND fetch-answer-url=http://web-server/{{ inventory_hostname }}.toml"
```

#### Terraform Integration
```hcl
# Example: Generate answer files with Terraform
resource "local_file" "proxmox_answer" {
  for_each = var.proxmox_nodes
  
  filename = "installer/answer-files/proxmox-${each.key}.toml"
  content = templatefile("templates/proxmox-answer.toml.tftpl", {
    hostname = each.value.hostname
    ip_address = each.value.ip_address
    # ... other variables
  })
}
```

## References

### Official Documentation
- [Proxmox VE Automated Installation](https://pve.proxmox.com/wiki/Automated_Installation) - Official automation guide
- [Proxmox VE Installation](https://pve.proxmox.com/wiki/Installation) - General installation documentation
- [Proxmox VE Administration Guide](https://pve.proxmox.com/pve-docs/pve-admin-guide.html) - Complete administration reference

### Configuration Format References
- [TOML Specification](https://toml.io/en/) - TOML configuration format documentation
- [Systemd Unit Files](https://www.freedesktop.org/software/systemd/man/systemd.unit.html) - For first-boot service configuration
- [GRUB Configuration](https://www.gnu.org/software/grub/manual/grub/grub.html) - Boot loader configuration

### Security Best Practices
- [SSH Hardening Guide](https://www.ssh.com/academy/ssh/sshd_config) - SSH daemon security configuration
- [Linux Security Hardening](https://linux-audit.com/linux-server-hardening-most-important-steps-to-secure-a-server/) - General server hardening practices

### Infrastructure as Code
- [Ansible Documentation](https://docs.ansible.com/) - Configuration management automation
- [Git Best Practices](https://git-scm.com/book/en/v2) - Version control best practices

### Hardware Management
- [Intel AMT](https://www.intel.com/content/www/us/en/support/articles/000007916/software.html) - Out-of-band management documentation
- [PXE Boot Setup](https://wiki.syslinux.org/wiki/index.php?title=PXELINUX) - Network boot configuration

---

This comprehensive guide covers all aspects of the automated Proxmox installation system. For specific configuration examples and troubleshooting, refer to the additional files in this directory and the official Proxmox documentation.

Remember to always test configurations in a safe environment before deploying to production systems, and maintain proper backups of all configuration files and data.