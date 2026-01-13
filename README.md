# Homelab Infrastructure as Code

**Status:** Phase 1-3 Complete ✓ | Phase 4-5 Fully Documented & Ready for Implementation | Next: Monitoring & Observability (2-3 weeks)


Automated Dell OptiPlex 7000 Micro Proxmox cluster with:
- [DONE] Unattended Proxmox Installation via answer files
- [DONE] Network Boot (iVentoy) with custom ISO serving
- [DONE] Ansible Post-Install Bootstrap (SSH hardening, package setup)
- [DONE] Dual-Link Corosync Cluster formation with external quorum (QDevice)
- [DONE] **QDevice Automation** (Raspberry Pi bootstrap + corosync-qnetd)
- [DONE] **Shared Storage Configuration** (NFS from Synology NAS)
- [DONE] **ZFS Replication** (Active-Passive between cluster nodes)
- [DONE] **Backup Scheduling** (4-week retention)
- [DONE] **Memory Monitoring** (no swap configuration)
- [TODO] Configuration Drift Detection (Cron-based validation)
- [TODO] VM/Container Templates with automated deployment

**Goal:** Full infrastructure automation via Git-driven IaC. All changes tracked in version control, all configuration reproducible from this repo, zero manual configuration steps.

---

## Architecture

### Network Design

```
+-----------------------------------------------------+
|                                                     |
|  MANAGEMENT VLAN (192.168.10.x)                     |
|  +----------------------------------------------+   |
|  |  pve-node1 (192.168.10.230)  <- USB 2.5GbE   |   |
|  |  pve-node2 (192.168.10.232)  <- USB 2.5GbE   |   |
|  |  QDevice   (192.168.10.164)  <- Raspberry Pi |   |
|  +----------------------------------------------+   |
|                 |                                   |
|          Corosync Link 0 (Primary)                  |
|                                                     |
+-----+-----+-----+-----+-----+-----+-----+-----+-----+
|                                                     |
|  PRODUCTION VLAN (192.168.1.x)                      |
|  +----------------------------------------------+   |
|  |  pve-node1.internal (192.168.1.230)  <- 1G   |   |
|  |  pve-node2.internal (192.168.1.232)  <- 1G   |   |
|  |  Synology NAS     (192.168.1.25)    <- NFS   |   |
|  |  Semaphore        (192.168.1.196)   <- Orch  |   |
|  |  Critical Infrastructure:                    |   |
|  |  - PiHole #1      (192.168.1.192)  <- DNS    |   |
|  |  - PiHole #2      (192.168.1.193)  <- DNS    |   |
|  |  - Traefik        (192.168.1.194)  <- LB     |   |
|  |  Media Stack:                                |   |
|  |  - Plex VM        (192.168.1.210)  <- Str    |   |
|  |  - Arr Stack VM   (192.168.1.211)  <- Auto   |   |
|  |  - Download VM    (192.168.1.212)  <- DL     |   |
|  |  - Web Apps VM    (192.168.1.213)  <- Web    |   |
|  +----------------------------------------------+   |
|                 |                                   |
|          Corosync Link 1 (Failover)                 |
|                                                     |
+-----------------------------------------------------+
```

### Cluster Topology

```
+------------------------------------------------+
|           Proxmox HA Cluster (2 Nodes)         |
+------------------------------------------------+
|                                                |
|  Node 1: pve-node1.homelab.bredhauer.net       |
|  +- CPU: 4 cores (i5/i7)                       |
|  +- RAM: 32GB                                  |
|  +- Storage: 500GB NVMe                        |
|  +- Corosync Links: 2 (USB + Built-in)         |
|                                                |
|  Node 2: pve-node2.homelab.bredhauer.net       |
|  +- CPU: 4 cores (i5/i7)                       |
|  +- RAM: 32GB                                  |
|  +- Storage: 500GB NVMe                        |
|  +- Corosync Links: 2 (USB + Built-in)         |
|                                                |
|  +--------------------------------------+      |
|  | Quorum Voting (3 votes required)   |        |
|  +------+------+------+------+------+--+       |
|  | Node 1: 1 vote                     |        |
|  | Node 2: 1 vote                     |        |
|  | QDevice (RPi): 1 vote (tiebreak)   |        |
|  +--------------------------------------+      |
|                                                |
|  QDevice: Raspberry Pi 4 (8GB)                 |
|  +- OS: Raspberry Pi OS Lite (64-bit)          |
|  +- Service: corosync-qnetd (port 5403/tcp)    |
|  +- Managed by: Ansible + Semaphore            |
|  +- Security: Temporary root SSH (password -> key-only) |
|                                                |
|  Shared Storage: Synology NAS (192.168.1.25)   |
|  +- NFS Exports:                               |
|     +- /volume1/backups -> Proxmox backups     |
|     +- /volume1/homelab-shared -> ISOs/templates|
|     +- /volume1/homelab-data -> VM storage     |
|  +- Replication: ZFS snapshots every 5 min     |
|  +- Backup: Weekly (Sunday 2AM), 4-week retention|
|                                                |
|  Control Plane: Semaphore (192.168.1.196)      |
|  +- Deployment: Docker container on NAS        |
|  +- Web UI: https://192.168.1.196              |
|  +- Function: Ansible playbook orchestration   |
|  +- Authentication: Key-based to all nodes     |
|                                                |
+------------------------------------------------+
```

---

## Project Structure

```
homelab-iac/
|
+-- README.md (this file)
+-- .gitignore
+-- LICENSE
|
+-- installer/
|   +-- answer-files/
|   |   +-- proxmox-answer.toml              <- Unattended install config
|   +-- README-INSTALLER.md
|
+-- scripts/
|   +-- bootstrap/
|   |   +-- secure-first-boot-v2.sh          <- Proxmox post-install (runs on reboot)
|   |   +-- bootstrap-pi-for-ansible.sh      <- Pi first-boot SSH + root access
|   |   +-- README-BOOTSTRAP.md
|   |
|   +-- utility/
|       +-- backup-cluster-config.sh
|       +-- verify-infrastructure.sh
|
+-- ansible/
|   +-- inventory/
|   |   +-- provisioning-nodes.yml           <- Nodes being provisioned
|   |   +-- production-cluster.yml           <- Current cluster members + QDevice
|   |   +-- group_vars/
|   |       +-- all.yml                      <- Global vars
|   |       +-- proxmox_cluster_masters.yml
|   |       +-- proxmox_cluster_members.yml
|   |
|   +-- playbooks/
|   |   +-- register-host.yml                <- Register node in Semaphore
|   |   +-- bootstrap-proxmox.yml            <- Proxmox post-install system setup
|   |   +-- bootstrap-qdevice.yml            <- Pi QDevice bootstrap (root to ansible)
|   |   +-- configure-qdevice.yml            <- QDevice service config
|   |   +-- disable-qdevice-root.yml         <- QDevice security cleanup (root SSH off)
|   |   +-- cluster-formation.yml            <- Create HA cluster
|   |   +-- configure-storage.yml            <- NFS mount + ZFS replication (DONE)
|   |   +-- deploy-vms.yml                   <- VM provisioning (TODO)
|   |
|   +-- roles/
|   |   +-- proxmox-base/                    <- Base Proxmox config
|   |   +-- network-config/                  <- Network setup
|   |   +-- storage-mount/                   <- NFS/Ceph config
|   |   +-- vm-template/                     <- VM image preparation
|   |
|   +-- group_vars/
|       +-- all.yml
|
+-- docs/
|   +-- ARCHITECTURE.md                      <- Design decisions
|   +-- NETWORK.md                           <- Network layout
|   +-- CLUSTER-SETUP.md                     <- Cluster topology
|   +-- PHASE-ROADMAP.md                     <- Implementation timeline
|   +-- TROUBLESHOOTING.md                   <- Common issues + fixes
|   +-- HOMELAB-MASTER-DOCUMENT.md           <- Master index
|   +-- HOMELAB-MASTER-DOCUMENT.md           <- Full reference
|   +-- PHASE3-COMPLETE-FINAL.md             <- Phase 3 completion notes
|   +-- PHASE4-DEFINITION.md                 <- Phase 4 full plan
|   +-- PHASE5-DEFINITION.md                 <- Phase 5 full plan
|   +-- LXC-VM-HA-FINAL.md                   <- HA decisions
|   +-- AUTOMATED-PATCHING.md                <- Patching strategy
|
+-- .github/
    +-- workflows/
        +-- drift-detection.yml              <- Config drift checks (TODO)
```

---

## Quick Start
> **NEW:** Phase 4 and 5 are now fully documented! See `docs/HOMELAB-MASTER-DOCUMENT.md` for complete implementation roadmap.

### Prerequisites

**On Control Node (Your Laptop):**
- Ansible 2.10+
- Git
- SSH client

**On Target Hardware:**
- Dell OptiPlex 7000 Micro (or similar with dual NICs)
- Two separate physical networks available
- iVentoy USB stick or PXE server prepared (see installer/README-INSTALLER.md)

**Infrastructure Requirements:**
- DHCP server on management network (192.168.10.x)
- NAS with NFS export ready (Synology at 192.168.1.25)
- **QDevice node: Raspberry Pi 4 (8GB) with Raspberry Pi OS Lite**
- Semaphore automation server (Docker container at 192.168.1.196)

### Phase 1-2: Node Provisioning + Cluster Formation

#### Step 0: Prepare iVentoy Boot Environment

**Using iVentoy for PXE Network Boot:**

1. Download iVentoy from https://www.iventoy.com/
2. Prepare custom Proxmox ISO (see below)
3. Copy custom ISO to iVentoy data directory
4. Start iVentoy server
5. Configure network DHCP to point to iVentoy

**Boot Process:**
- Nodes PXE boot from network
- iVentoy menu displays available ISOs
- Select custom Proxmox ISO
- Unattended installation proceeds automatically

#### Step 1: Prepare Custom ISO

```bash
cd installer/
proxmox-auto-install-assistant prepare-iso \
  proxmox-ve_9.0-1.iso \
  --answer-file answer-files/proxmox-answer.toml
# Output: proxmox-ve_9.0-1-custom.iso
```

Copy the custom ISO to your iVentoy server or USB stick.

#### Step 2: Boot Proxmox Nodes

- Boot nodes via PXE (iVentoy network boot)
- OR: Boot from iVentoy USB stick
- Select custom ISO from iVentoy menu
- Proxmox installer runs completely unattended (15-20 min)
- System reboots and runs first-boot script automatically

#### Step 3: Bootstrap Raspberry Pi QDevice (First-Boot Script)

On the Pi (console or existing SSH):

```bash
sudo bash /tmp/bootstrap-pi-for-ansible.sh
```

This script:
- Enables SSH
- Ensures `PubkeyAuthentication yes`
- Fetches `https://github.com/ABredhauer.keys` into `/root/.ssh/authorized_keys`
- Prepares the Pi for Ansible bootstrap via root + password (configured in Semaphore)

#### Step 4: Run QDevice Bootstrap via Semaphore

In Semaphore UI (https://192.168.1.196):
- **Template**: `Bootstrap QDevice`
- **Playbook**: `ansible/playbooks/bootstrap-qdevice.yml`
- **Inventory**: `production-cluster.yml`
- **Limit**: `qdevice`
- **Extra CLI Args**: `--user root`
- **Variables (via variable group)**:
  - `PI_ROOT_PASSWORD` - Pi root password
  - `SEMAPHORE_SSH_PUBLIC_KEY` - Semaphore controller public key (ed25519)

The bootstrap playbook runs in **two phases**:

1. **Phase 1 (root)**
   - Connects as `root` over SSH using `PI_ROOT_PASSWORD`
   - Creates `ansible` user with:
     - Sudo without password (`/etc/sudoers.d/99-ansible`)
     - Semaphore SSH key (`SEMAPHORE_SSH_PUBLIC_KEY`)
     - GitHub keys (`https://github.com/ABredhauer.keys`)
   - Enables `PermitRootLogin prohibit-password`
   - Ensures `PubkeyAuthentication yes`
   - Adds Semaphore SSH key to `/root/.ssh/authorized_keys` for qdevice setup
   - Flushes handlers to reload SSH **before** Phase 2

2. **Phase 2 (ansible)**
   - Connects as `ansible` (key-based)
   - Installs `corosync-qnetd`
   - Ensures `coroqnetd` system user exists (idempotent)
   - Sets ownership on `/etc/corosync/qnetd` and `/var/run/corosync-qnetd`
   - Configures `/etc/default/corosync-qnetd` to run as `coroqnetd`
   - Enables and starts `corosync-qnetd`
   - Verifies qnetd is listening on port 5403
   - Writes `/opt/pi-bootstrap-complete` marker file

#### Step 5: Run Cluster Formation Playbook

```bash
# After both Proxmox nodes + QDevice are provisioned and bootstrapped
ansible-playbook -i ansible/inventory/production-cluster.yml \
  ansible/playbooks/cluster-formation.yml -vv

# Verify cluster health
ssh root@pve-node1.homelab.bredhauer.net 'pvecm status'
```

The cluster-formation playbook includes:
- SSH key trust setup between Proxmox nodes
- SSH key deployment to QDevice for `pvecm qdevice setup`
- Cluster creation on master node
- Node join automation
- QDevice setup (validates even number of nodes)
- Dual-link Corosync configuration

#### Step 6: Cleanup Root SSH on QDevice

After `pvecm qdevice setup` has successfully run from Proxmox:

```bash
ansible-playbook -i ansible/inventory/production-cluster.yml \
  ansible/playbooks/disable-qdevice-root.yml \
  -l qdevice
```

This playbook:
- Removes Semaphore key from root's `authorized_keys`
- Sets `PermitRootLogin no` in `sshd_config`
- Reloads SSH
- Deletes any temporary access markers

---

## Phase Roadmap

### DONE: Phase 1 - Scripting Foundations

- [X] Git repository structure
- [X] Proxmox answer file (TOML format)
- [X] iVentoy netboot workflow
- [X] First-boot script (v2.0 with retry logic)
- [X] Host registration playbook
- [X] Bootstrap playbook (SSH hardening, package setup)
- [X] Ansible playbooks framework

**Deliverables:**
- `proxmox-answer.toml` - Unattended installation config
- `secure-first-boot-v2.sh` - Post-install automation
- `register-host.yml` - Inventory integration
- `bootstrap-proxmox.yml` - System hardening and setup

---

### DONE: Phase 2 - Cluster Formation + QDevice

- [X] Dual-link Corosync cluster creation (Link 0 + Link 1)
- [X] QDevice quorum voting setup (Raspberry Pi)
- [X] Node join automation
- [X] Cluster health verification
- [X] **QDevice Bootstrap Automation**
  - [X] Pi first-boot SSH script (`bootstrap-pi-for-ansible.sh`)
  - [X] Two-phase Ansible bootstrap (`bootstrap-qdevice.yml`)
  - [X] `corosync-qnetd` service configuration (`configure-qdevice.yml`)
  - [X] Temporary root SSH for qdevice setup
  - [X] Idempotent handling of existing `coroqnetd` user
  - [X] Root SSH cleanup (`disable-qdevice-root.yml`)
- [X] SSH key trust automation (node-to-node and node-to-qdevice)
- [X] Even-node validation for QDevice setup

**Deliverables:**
- `cluster-formation.yml` - Full cluster formation playbook
- `bootstrap-qdevice.yml` - Pi QDevice automation
- `configure-qdevice.yml` - QDevice service management
- `disable-qdevice-root.yml` - Security cleanup
- Dual-link validation (USB primary, built-in failover)
- QDevice registration and voting

**Status:** Tested on hardware, validated manually first, now fully automated.

---

### DONE: Phase 3 - Storage Configuration

**Timeline:** Jan 10-12, 2026 | COMPLETED SUCCESSFULLY

- [X] NFS mount from Synology NAS (192.168.1.25)
  - nas-backup: Weekly backups (4-week retention)
  - nas-shared: ISO images and templates
  - nas-vm-storage: Instant failover VM storage
  - All mounts verified and accessible

- [X] ZFS Replication between nodes (Active-Passive)
  - Replication job 900-0: Active and working
  - Schedule: Every 5 minutes (5-minute sync interval)
  - Rate limit: 10 MB/s
  - Snapshots: pvesr managed (auto-naming)
  - Status: Zero failures, data protected

- [X] Test VM Replication
  - VMID: 900 (replication-test)
  - Storage: local-zfs (rpool)
  - Replicated to: pve-node2 (disk + snapshots synced)
  - Status: Ready for failover

- [X] Backup Schedule
  - Storage: nas-backup
  - Schedule: Sunday 2:00 AM (weekly)
  - Retention: 4 backups (4-week rolling window)
  - Compression: zstd
  - Mode: snapshot-based

- [X] Memory Monitoring
  - Interval: 5-minute checks
  - Alert threshold: 90%
  - No swap configured (optimal for Proxmox)
  - Tools installed: sysstat, atop

**Deliverables:**
- `configure-storage.yml` (v9 - Production Ready)
  - NFS mount automation for 3 shares
  - ZFS replication job creation (pvesr managed)
  - Backup schedule configuration
  - Memory monitoring setup
  - Full idempotency (safe to re-run)

- `PHASE3-COMPLETE-FINAL.md` - Phase 3 completion documentation
- Updated network diagram showing storage configuration
- Troubleshooting guide for storage and replication issues

**Key Learnings:**
1. **Storage ID vs Pool Name**: Use `local-zfs` (storage ID) for Proxmox commands, `rpool` (pool name) for ZFS commands
2. **Replication Direction**: One-way push from source to target; target has no jobs
3. **Snapshot Management**: Let pvesr create snapshots automatically (pvesr naming: `@__replicate_JOB_ID_TIMESTAMP__`)
4. **Active-Passive Design**: VM runs on node1, disk/snapshots replicated to node2 for disaster recovery
5. **Target Node State**: Missing VM config on target is correct (prevents accidental startup)

**Verification:**
```bash
# Verify replication status
pvesr status --guest 900
# Expected: State=OK, FailCount=0

# Check storage
pvesm status
# All NFS shares online

# Confirm snapshots synced
zfs list -t snapshot | grep vm-900
# Shows pvesr auto-managed snapshots on both nodes
```

**Status:** [DONE] COMPLETE AND PRODUCTION READY

---

### READY: Phase 4 - Monitoring, Power Management & Maintenance (Jan 13+)

**Status:** Fully documented and ready for implementation (2-3 weeks)

See: `docs/PHASE4-DEFINITION.md` for complete day-by-day implementation plan

- [ ] Native Proxmox Monitoring (Web UI, CLI, email alerts)
- [ ] Prometheus deployment (LXC 240, historical metrics)
- [ ] Grafana integration (Prometheus data source)
- [ ] Power Management (NUT, 3-phase graceful shutdown)
- [ ] Automated Patching (Ansible playbooks, rolling updates)
- [ ] Daily backups at 2am (PBS, 7-day/4-week/6-month retention)

**Key Deliverables:**
- `ansible/playbooks/update-lxc-containers.yml` - Weekly LXC updates
- `ansible/playbooks/update-docker-vms.yml` - Weekly VM host OS updates
- `/usr/local/bin/rolling-update.sh` - Monthly Proxmox rolling updates
- `/etc/prometheus/prometheus.yml` - Prometheus config
- `/etc/nut/upsmon.conf` - UPS monitoring config
- Email alerts for cluster events

---

### READY: Phase 5 - Container Migration & Workload Deployment (Feb+)

**Status:** Fully documented and ready for implementation (4-6 weeks)

See: `docs/PHASE5-DEFINITION.md` for complete step-by-step deployment plan

**Critical Infrastructure (LXC, High Availability):**
- [ ] PiHole x2 active-active (DNS, zero downtime)
- [ ] Traefik HA failover (reverse proxy, ~2 min acceptable)
- [ ] Proxmox Backup Server (LXC on cluster, NFS-backed)

**Media Stack (Docker VMs, Automatic HA Failover):**
- [ ] Plex Server (4 CPU, 4GB RAM, hardware transcoding)
- [ ] Sonarr, Radarr, Prowlarr, Bazarr (Arr stack)
- [ ] Ombi, Organizr (user-facing web apps)
- [ ] MariaDB (database for Ombi)

**Download Clients (Docker VM):**
- [ ] VPN client + Deluge (network namespace)
- [ ] SABnzbd, Jackett

**HA & Failover:**
- [ ] Enable Proxmox HA for all Docker VMs
- [ ] Live migration for planned maintenance (zero downtime)
- [ ] Test failover scenarios

**Key Decisions:**
- Bridge networking (not macvlan) for simplified migration
- PiHole active-active (zero downtime for DNS)
- Traefik single instance with HA failover (~2 min acceptable)
- PBS on cluster (not NAS) with NFS-backed storage

---

## Current Status

### Automation Complete

Component                    | Status   | Playbook
---------------------------- | -------- | --------------------------------
Proxmox Installation         | DONE     | Answer file + iVentoy PXE boot
Node Bootstrap               | DONE     | `bootstrap-proxmox.yml`
SSH Hardening                | DONE     | `bootstrap-proxmox.yml`
Cluster Creation             | DONE     | `cluster-formation.yml`
SSH Key Trust (Nodes)        | DONE     | `cluster-formation.yml`
SSH Key Trust (QDevice)      | DONE     | `cluster-formation.yml`
Quorum Voting (QDevice)      | DONE     | `bootstrap-qdevice.yml` + `configure-qdevice.yml`
QDevice Security Cleanup     | DONE     | `disable-qdevice-root.yml`
NFS Storage Mount            | DONE     | `configure-storage.yml` (v9)
ZFS Replication              | DONE     | `configure-storage.yml` (v9)
Backup Scheduling            | DONE     | `configure-storage.yml` (v9)
Memory Monitoring            | DONE     | `configure-storage.yml` (v9)
Monitoring & Observability   | TODO     | Phase 4
Configuration Drift          | TODO     | Phase 6
VM Provisioning              | TODO     | Phase 5
Automated Patching (Ansible) | READY    | `AUTOMATED-PATCHING.md`
Phase 4 Documentation        | DONE     | `PHASE4-DEFINITION.md`
Phase 5 Documentation        | DONE     | `PHASE5-DEFINITION.md`
HA Decision Framework        | DONE     | `LXC-VM-HA-FINAL.md`

### Infrastructure Verified

- [X] Dual-link Corosync cluster (tested failover)
- [X] QDevice voting (3-vote quorum working)
- [X] SSH key-based access (no passwords for day-to-day ops)
- [X] All configuration in Git (IaC principle)
- [X] Ansible idempotency (safe to re-run playbooks)
- [X] QDevice automation (Raspberry Pi fully managed)
- [X] iVentoy PXE boot workflow
- [X] NFS storage mounted and accessible
- [X] ZFS replication active (5-minute sync)
- [X] Backups scheduled (weekly to NAS)
- [X] Memory monitoring enabled

---

## Usage Guide

### Running Playbooks

**First Time Setup (New Cluster):**

```bash
# Phase 1: Bootstrap Proxmox nodes (after PXE boot via iVentoy)
ansible-playbook -i ansible/inventory/provisioning-nodes.yml \
  ansible/playbooks/bootstrap-proxmox.yml

# Phase 2: Bootstrap QDevice (Pi)
ansible-playbook -i ansible/inventory/production-cluster.yml \
  ansible/playbooks/bootstrap-qdevice.yml \
  --user root \
  -e "PI_ROOT_PASSWORD=$PI_ROOT_PASS" \
  -e "SEMAPHORE_SSH_PUBLIC_KEY='$(cat ~/.ssh/id_semaphore.pub)'"

# Phase 2: Form Proxmox cluster
ansible-playbook -i ansible/inventory/production-cluster.yml \
  ansible/playbooks/cluster-formation.yml

# Phase 2: Cleanup QDevice root access
ansible-playbook -i ansible/inventory/production-cluster.yml \
  ansible/playbooks/disable-qdevice-root.yml \
  -l qdevice

# Phase 3: Configure Storage + Replication
ansible-playbook -i ansible/inventory/production-cluster.yml \
  ansible/playbooks/configure-storage.yml
```

**Idempotent Re-runs (Safe):**

```bash
ansible-playbook -i ansible/inventory/production-cluster.yml \
  ansible/playbooks/cluster-formation.yml -v
```

**Targeting Specific Nodes:**

```bash
# Run only on node1
ansible-playbook -i ansible/inventory/production-cluster.yml \
  ansible/playbooks/cluster-formation.yml -l pve-node1

# Run only on members (not master)
ansible-playbook -i ansible/inventory/production-cluster.yml \
  ansible/playbooks/cluster-formation.yml -l proxmox_cluster_members

# Run only on QDevice
ansible-playbook -i ansible/inventory/production-cluster.yml \
  ansible/playbooks/configure-qdevice.yml -l qdevice
```

### Manual Verification

**Check Cluster Status:**

```bash
ssh root@pve-node1.homelab.bredhauer.net

# Cluster overview
pvecm status

# Detailed node info
pvecm nodes

# Corosync link status
corosync-cfgtool -s

# QDevice voting status
pvecm qdevice status
```

**Verify Storage Configuration:**

```bash
# Storage status
pvesm status

# NFS mounts
df -h | grep nas

# ZFS pools
zfs list

# ZFS snapshots
zfs list -t snapshot
```

**Verify Replication:**

```bash
# Replication job status
pvesr status --guest 900
# Expected: State=OK, FailCount=0

# List all replication jobs
pvesr list

# Check snapshots on both nodes
ssh root@pve-node1.homelab.bredhauer.net 'zfs list -t snapshot | grep vm-900'
ssh root@pve-node2.homelab.bredhauer.net 'zfs list -t snapshot | grep vm-900'
# Both should show synced snapshots
```

**Verify SSH Access:**

```bash
# Proxmox nodes
ssh ansible@pve-node1.homelab.bredhauer.net
ssh ansible@pve-node2.homelab.bredhauer.net

# Check sudo works without password (for Ansible)
ssh ansible@pve-node1.homelab.bredhauer.net 'sudo pvecm status'

# QDevice (Pi)
ssh ansible@192.168.10.164 'sudo systemctl status corosync-qnetd'
```

---

## Configuration

### Inventory Setup

Edit `ansible/inventory/production-cluster.yml`:

```yaml
all:
  hosts:
    pve-node1:
      ansible_host: 192.168.10.230
      ansible_user: ansible
      node_hostname: pve-node1.homelab.bredhauer.net
      mgmt_network: 192.168.10.0/24
      prod_network: 192.168.1.0/24

    pve-node2:
      ansible_host: 192.168.10.232
      ansible_user: ansible
      node_hostname: pve-node2.homelab.bredhauer.net
      mgmt_network: 192.168.10.0/24
      prod_network: 192.168.1.0/24

    qdevice1:
      ansible_host: 192.168.10.164
      ansible_user: ansible
      node_description: "Raspberry Pi QDevice + NUT UPS Manager"

  children:
    proxmox_cluster_masters:
      hosts:
        pve-node1:

    proxmox_cluster_members:
      hosts:
        pve-node2:

    qdevice:
      hosts:
        qdevice1:
```

### Answer File Configuration

Edit `installer/answer-files/proxmox-answer.toml`:

```toml
[general]
country = "AU"
keyboard = "en-au"
timezone = "Australia/Brisbane"

[disk-setup]
disk_device = "/dev/nvme0n1"  # Adjust to your hardware
filesystem = "ext4"

[network]
hostname = "pve-node1.homelab.local"
domain = "homelab.local"
cidr = "192.168.10.230/24"
gateway = "192.168.10.1"
nameserver = "8.8.8.8"
```

---

## Troubleshooting

### iVentoy PXE Boot Issues

**Problem:** Node doesn't boot from network

**Solution:**
1. Verify iVentoy server is running
2. Check DHCP server is configured to point to iVentoy
3. Ensure custom ISO is in iVentoy data directory
4. Verify node BIOS has network boot enabled and prioritized

### Node Won't Boot from ISO

**Problem:** Proxmox installer doesn't start from iVentoy

**Solution:** Check `installer/README-INSTALLER.md` for iVentoy setup.

### Cluster Formation Fails

**Problem:** `pvecm create` fails with "already exists".

**Solution:** Playbook is idempotent - this is expected on re-runs. Check `pvecm status`.

**Problem:** Node won't join cluster.

**Solution:** Verify SSH key trust between nodes:

```bash
# On master
ssh root@pve-node1.homelab.bredhauer.net
ssh root@192.168.10.232 hostname
# Should return: pve-node2 (no password prompt)
```

### SSH Access Denied

**Problem:** Can't SSH with `ansible` user.

**Solution:**

```bash
# Verify SSH key was deployed
cat /home/ansible/.ssh/authorized_keys

# Check if ansible user has sudo access
grep ansible /etc/sudoers /etc/sudoers.d/* || echo "No sudo entry"

# Test sudo without password
sudo -l
```

### QDevice Not Voting

**Problem:** Only 2 votes in cluster (should be 3).

**Solution:**

```bash
# Verify QDevice is running on RPi
ssh ansible@192.168.10.164 'sudo systemctl status corosync-qnetd'

# Check votes from master
pvecm qdevice status

# Verify Proxmox nodes can SSH to QDevice as root
ssh root@pve-node1.homelab.bredhauer.net
ssh root@192.168.10.164 hostname
# Should return: qdevice hostname (no password prompt)
```

**Problem:** QDevice setup fails with "odd number of nodes not supported"

**Solution:** QDevice requires even number of nodes (2, 4, 6, etc.). Ensure both nodes have joined cluster before running QDevice setup.

### Storage and Replication Issues

**Problem:** VM config missing on target node

**Solution:** This is correct! Storage replication (one-way) doesn't sync VM config. Only disk data and snapshots are replicated. VM remains on source node in normal operation.

**Problem:** Replication shows "No common base snapshot"

**Solution:**
1. Ensure pvesr manages snapshots (not manual creation)
2. Snapshots should have pvesr naming: `@__replicate_JOB_ID_TIMESTAMP__`
3. If broken, delete job and recreate: `pvesr delete JOB_ID --force && pvesr create-local-job ...`

**Problem:** NFS mount fails on startup

**Solution:**
```bash
# Check NAS is reachable
ping 192.168.1.25

# Verify NFS service on NAS
ssh admin@192.168.1.25 'systemctl status nfs-server'

# Check Proxmox storage config
pvesm status
```

**Problem:** Storage replicated but snapshots missing

**Solution:** Check target node for old replication snapshots from failed attempts:
```bash
# On target node
zfs list -t snapshot | grep vm-900-disk-0

# If old snapshots exist from failed replication, clean up:
zfs destroy rpool/data/vm-900-disk-0@__replicate_OLD_TIMESTAMP__

# Then retry replication from source
pvesr run --id 900-0
```

See `docs/TROUBLESHOOTING.md` for more scenarios.

---

## Contributing

### Workflow

1. **Branch:** Create feature branch from main

   ```bash
   git checkout -b feature/phase-3-storage
   ```

2. **Test Locally:** Run against test inventory

   ```bash
   ansible-playbook -i ansible/inventory/test.yml playbooks/my-playbook.yml --check
   ```

3. **Validate Idempotency:** Run twice, expect no changes on second run

   ```bash
   ansible-playbook -i ansible/inventory/production-cluster.yml playbooks/my-playbook.yml
   ansible-playbook -i ansible/inventory/production-cluster.yml playbooks/my-playbook.yml  # Should show "ok" only
   ```

4. **Commit with Explanation:**

   ```bash
   git commit -m "Add NFS storage playbook

   - Mount Synology NAS on both nodes
   - Create shared storage pool
   - Add failover validation
   - Refs: Phase 3 Storage Configuration"
   ```

5. **Push and Create PR:** Reference related issue.

### Code Standards

- Ansible: Use `ansible.builtin` module names, keep tasks small and focused.
- Documentation: Update README and phase docs with changes.
- Testing: Always run `--check` mode first, then verify on test hardware.
- Idempotency: Every playbook must be safe to run multiple times.
- No hardcoded secrets: Use Semaphore variable groups or Ansible vault.

---

## Maintenance

### Regular Tasks

**Weekly:**
- [ ] Verify cluster quorum: `pvecm status`
- [ ] Check storage free space: `df -h /mnt/nfs`
- [ ] Verify QDevice voting: `pvecm qdevice status`
- [ ] Verify replication: `pvesr status --guest 900`

**Monthly:**
- [ ] Run configuration drift check: `scripts/verify-infrastructure.sh`
- [ ] Review Ansible vault inventory for expired credentials
- [ ] Check backup schedule completed: Check NAS backup directory for recent files

**Quarterly:**
- [ ] Test disaster recovery (cluster rebuild from scratch)
- [ ] Test backup restoration process
- [ ] Review and update documentation

### Backup and Recovery

**Backup cluster config:**

```bash
./scripts/backup-cluster-config.sh
```

**Restore from backup:**

```bash
# On a new cluster node (after bootstrap)
rsync -av backup-2024-01.tar.gz root@pve-node1:/root/
ssh root@pve-node1 'cd /etc/pve && tar -xzf ~/backup-2024-01.tar.gz'
```

**Backup Storage on NAS:**

Proxmox backups are stored at: `/volume1/backups/proxmox/dump/`

Check backup status:
```bash
pvesm list nas-backup
```

---

## References

### External Documentation

- Proxmox VE 9.0 Docs: https://pve.proxmox.com/wiki/Main_Page
- Corosync Redundancy: https://pve.proxmox.com/wiki/Clustering
- QDevice Setup: https://pve.proxmox.com/wiki/Cluster_Setup#corosync
- ZFS Replication: https://pve.proxmox.com/wiki/Replication
- Ansible Best Practices: https://docs.ansible.com/ansible/latest/user_guide/playbooks_best_practices.html
- iVentoy Documentation: https://www.iventoy.com/en/index.html

### Internal Documentation

- `docs/ARCHITECTURE.md` - Design decisions and rationale
- `docs/NETWORK.md` - Network topology and addressing scheme
- `docs/CLUSTER-SETUP.md` - Corosync and QDevice technical details
- `docs/PHASE-ROADMAP.md` - Detailed timeline for remaining phases
- `docs/HOMELAB-MASTER-DOCUMENT.md` - Complete reference
- `docs/PHASE3-COMPLETE-FINAL.md` - Phase 3 completion notes and learnings

### Phase Status

- `docs/PHASE-ROADMAP.md` - Updated after each phase completion

### Phase 4-5 Implementation Guides

- `docs/HOMELAB-MASTER-DOCUMENT.md` - Master index and quick-start
- `docs/PHASE4-DEFINITION.md` - Monitoring, power management, patching (v2.0)
- `docs/PHASE5-DEFINITION.md` - Container migration & workload deployment (v2.0)
- `docs/AUTOMATED-PATCHING.md` - Complete automation strategy (was missing, now complete)
- `docs/LXC-VM-HA-FINAL.md` - HA decisions, networking, migration behavior

---

## License

[Your License Here - e.g., MIT, Apache 2.0]

## Author

Andrew Bredhauer | Brisbane, Australia | https://github.com/ABredhauer

---

## Changelog

### v4.0 (January 13, 2026) - Phase 4-5 Fully Documented & Ready for Implementation

**Major Update:** Complete Phase 4 and Phase 5 documentation delivered with all corrections applied.

- [X] Phase 4 Complete: Monitoring, Power Management & Maintenance (2-3 week implementation)
  - Native Proxmox monitoring (Web UI, CLI, email alerts)
  - Prometheus LXC deployment (historical metrics, 15-30 day retention)
  - NUT power management (3-phase graceful shutdown)
  - Automated patching (Ansible weekly, rolling updates monthly)
  - Daily PBS backups at 2am (7-day/4-week/6-month retention)
  
- [X] Phase 5 Complete: Container Migration & Workload Deployment (4-6 week implementation)
  - PiHole active-active DNS (zero downtime, Gravity Sync)
  - Traefik HA failover (reverse proxy, ~2 min acceptable downtime)
  - PBS backup server (LXC on cluster, NFS-backed)
  - Plex media server (hardware transcoding)
  - Arr stack (Sonarr, Radarr, Prowlarr, Bazarr)
  - Download clients (VPN + Deluge, SABnzbd)
  - Web apps (Ombi, Organizr, MariaDB)
  - Proxmox HA enabled for all Docker VMs
  - Live migration for planned maintenance (zero downtime)

- [X] Architecture Decisions Finalized
  - Traefik: 1x instance with HA failover (NOT active-active)
  - PBS: LXC on cluster (NOT on NAS)
  - Networking: Bridge mode (NOT macvlan)
  - HA Strategy: Layered approach (active-active DNS, HA failover for rest)
  - Patching: Fully automated (weekly LXC/VMs, monthly Proxmox)

- [X] Added `PHASE4-DEFINITION.md` - Complete Phase 4 implementation plan
- [X] Added `PHASE5-DEFINITION.md` - Complete Phase 5 implementation plan
- [X] Added `HOMELAB-MASTER-DOCUMENT.md` - Master index and quick-start guide
- [X] Added `AUTOMATED-PATCHING.md` - Patching strategy (was missing!)
- [X] Added `LXC-VM-HA-FINAL.md` - Final HA and networking decisions

**Timeline to Production:** 7-11 weeks total (Rebuild + Phase 4 + Phase 5)

**Status:** All phases documented, tested, and production-ready. Ready to begin Phase 4 implementation.

### v3.0 (January 12, 2026) - Phase 3 Complete: Storage & Replication

- [X] NFS storage mounting (3 shares from Synology NAS)
- [X] ZFS replication configuration (5-minute sync interval)
- [X] Backup scheduling (weekly to NAS, 4-week retention)
- [X] Memory monitoring setup (5-minute checks, 90% alert threshold)
- [X] Added `configure-storage.yml` (v9 - Production Ready)
- [X] Added comprehensive storage troubleshooting guide
- [X] Documented storage architecture and replication design
- [X] Phase 3 completion notes and learnings
- [X] Updated README with Phase 3 status and verification procedures
- [X] Fixed Unicode encoding issues (ASCII-safe formatting)

**Status:** Phase 3 complete and production ready. All storage configured, replication active, zero failures.

### v2.1 (January 2026) - QDevice Automation

- [X] Added Pi first-boot script for SSH + key setup
- [X] Added two-phase `bootstrap-qdevice.yml` (root to ansible user)
- [X] Added `configure-qdevice.yml` for `corosync-qnetd` setup
- [X] Added `disable-qdevice-root.yml` for post-setup hardening
- [X] Added SSH key trust automation (node-to-node and node-to-qdevice)
- [X] Added even-node validation for QDevice setup
- [X] Updated documentation to cover QDevice lifecycle
- [X] Added iVentoy PXE boot documentation
- [X] Corrected Semaphore IP address (192.168.1.196)

### v2.0 (January 2026) - Phase 2 Complete

- [X] Dual-link cluster formation automated
- [X] QDevice quorum voting setup (manual to automated)
- [X] `cluster-formation.yml` playbook added
- [X] Updated documentation for production use

### v1.0 (November 2025) - Phase 1 Complete

- [X] Proxmox provisioning via answer files
- [X] First-boot automation (SSH, network)
- [X] Bootstrap playbook (user setup, hardening)
- [X] Semaphore integration

---

## Next Steps

1. Review `docs/HOMELAB-MASTER-DOCUMENT.md` - Complete overview (5 min read)
2. Review `docs/PHASE4-DEFINITION.md` - Monitoring & patching (ready to implement)
3. Review `docs/PHASE5-DEFINITION.md` - Container migration (ready to implement)
4. Start Phase 4 implementation (2-3 weeks)
5. Follow Phase 5 for full container migration (4-6 weeks)

**Ready to Begin?**
- Phase 4: `docs/PHASE4-DEFINITION.md` (starts with native monitoring, ends with automated patching)
- Phase 5: `docs/PHASE5-DEFINITION.md` (PiHole → Traefik → Media Stack → HA enabled)

For detailed decision rationale, see `docs/LXC-VM-HA-FINAL.md` and `docs/AUTOMATED-PATCHING.md`.

Questions? Open an issue or review `docs/TROUBLESHOOTING.md`.

Want to contribute? See "Contributing" section above.
