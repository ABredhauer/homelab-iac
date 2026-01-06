# Homelab Infrastructure as Code

**Status:** Phase 2 Complete (Cluster Formation) | Phase 3 Next (Storage Configuration)

Automated Dell OptiPlex 7000 Micro Proxmox cluster with:
- [DONE] Unattended Proxmox Installation via answer files
- [DONE] Network Boot (iVentoy) with custom ISO serving
- [DONE] Ansible Post-Install Bootstrap (SSH hardening, package setup)
- [DONE] Dual-Link Corosync Cluster formation with external quorum (QDevice)
- [IN PROGRESS] Shared Storage (NFS from Synology)
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
|  |  Semaphore (192.168.10.50)   <- Orchestration|   |
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
|  |  Synology NAS     (192.168.1.164)   <- NFS   |   |
|  |  Kubernetes/VMs    (192.168.1.x)    <- Work  |   |
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
|   |   +-- secure-first-boot-v2.sh          <- Post-install (runs on reboot)
|   |   |   +- SSH key setup
|   |   |   +- Network validation
|   |   |   +- Semaphore API registration
|   |   +-- README-BOOTSTRAP.md
|   |
|   +-- utility/
|       +-- backup-cluster-config.sh
|       +-- verify-infrastructure.sh
|
+-- ansible/
|   +-- inventory/
|   |   +-- provisioning-nodes.yml          <- Nodes being provisioned
|   |   +-- production-cluster.yml          <- Current cluster members
|   |   +-- group_vars/
|   |       +-- all.yml                     <- Global vars
|   |       +-- proxmox_cluster_masters.yml
|   |       +-- proxmox_cluster_members.yml
|   |
|   +-- playbooks/
|   |   +-- register-host.yml               <- Register node in Semaphore
|   |   +-- bootstrap-proxmox.yml           <- Post-install system setup
|   |   +-- cluster-formation.yml           <- Create HA cluster (NEW)
|   |   +-- configure-storage.yml           <- NFS mount + Ceph (TODO)
|   |   +-- deploy-vms.yml                  <- VM provisioning (TODO)
|   |
|   +-- roles/
|   |   +-- proxmox-base/                   <- Base Proxmox config
|   |   +-- network-config/                 <- Network setup
|   |   +-- storage-mount/                  <- NFS/Ceph config
|   |   +-- vm-template/                    <- VM image preparation
|   |
|   +-- group_vars/
|       +-- all.yml
|
+-- docs/
|   +-- ARCHITECTURE.md                     <- Design decisions
|   +-- NETWORK.md                          <- Network layout
|   +-- CLUSTER-SETUP.md                    <- Cluster topology
|   +-- PHASE-ROADMAP.md                    <- Implementation timeline
|   +-- TROUBLESHOOTING.md                  <- Common issues + fixes
|   +-- HOMELAB-MASTER-DOCUMENT.md          <- Full reference
|
+-- .github/
    +-- workflows/
        +-- drift-detection.yml             <- Config drift checks (TODO)
```

---

## Quick Start

### Prerequisites

**On Control Node (Your Laptop):**
- Ansible 2.10+
- Git
- SSH client

**On Target Hardware:**
- Dell OptiPlex 7000 Micro (or similar with dual NICs)
- Two separate physical networks available
- iVentoy USB stick prepared (see installer/README-INSTALLER.md)

**Infrastructure Requirements:**
- DHCP server on management network (192.168.10.x)
- NAS with NFS export ready (Synology tested)
- QDevice node (Raspberry Pi with 2GB+ RAM)
- Semaphore automation server (will run on management VLAN)

### Phase 1-2: Node Provisioning + Cluster Formation

**Step 1: Prepare Custom ISO**

```bash
cd installer/
proxmox-auto-install-assistant prepare-iso \
  proxmox-ve_9.0-1.iso \
  --answer-file answer-files/proxmox-answer.toml
# Output: proxmox-ve_9.0-1-custom.iso
```

**Step 2: Boot Target Hardware**
- Insert iVentoy USB stick
- Select custom ISO from iVentoy menu
- Proxmox installer runs completely unattended (15-20 min)
- System reboots and runs first-boot script automatically

**Step 3: Verify Node Registration**

```bash
# Check if node appears in Semaphore inventory
curl http://semaphore.homelab.internal:3000/api/tasks | jq '.tasks[] | select(.template_id==1)'

# SSH to verify SSH key setup
ssh ansible@pve-node1.homelab.bredhauer.net
```

**Step 4: Run Cluster Formation Playbook**

```bash
# After both nodes are provisioned
ansible-playbook -i ansible/inventory/production-cluster.yml \
  ansible/playbooks/cluster-formation.yml

# Verify cluster health
ssh root@pve-node1.homelab.bredhauer.net 'pvecm status'
```

---

## Phase Roadmap

### DONE: Phase 1 - Scripting Foundations
- [X] Git repository structure
- [X] Proxmox answer file (TOML format)
- [X] iVentoy netboot workflow
- [X] First-boot script (v2.0 with retry logic)
- [X] Host registration playbook
- [X] Bootstrap playbook (Ansible user, SSH hardening, packages)
- [X] Ansible playbooks framework

**Deliverables:**
- proxmox-answer.toml - Unattended installation config
- secure-first-boot-v2.sh - Post-install automation
- register-host.yml - Inventory integration
- bootstrap-proxmox.yml - System hardening and setup

---

### DONE: Phase 2 - Cluster Formation
- [X] Dual-link Corosync cluster creation (Link 0 + Link 1)
- [X] QDevice quorum voting setup (Raspberry Pi)
- [X] Node join automation
- [X] Cluster health verification

**Deliverables:**
- cluster-formation.yml - Full cluster formation playbook
- Dual-link validation (USB primary, Built-in failover)
- QDevice registration and voting

**Status:** Tested on hardware, validated manually first, now automated

---

### IN PROGRESS: Phase 3 - Storage Configuration
**Timeline:** Jan 10-17

- [ ] NFS mount from Synology NAS (192.168.1.164)
- [ ] Storage pool creation on both nodes
- [ ] VM disk provisioning (local + shared)
- [ ] Storage failover testing
- [ ] Automated backups to NAS

**Deliverables (Next):**
- configure-storage.yml - NFS mount and storage pool setup
- storage/ role with backup scheduling

**Commands Preview:**
```bash
# Will be automated via Ansible
pvesm add dir <storage_id> --path /mnt/nfs --shared 1
```

---

### TODO: Phase 4 - Monitoring and Observability (Jan 24+)
- [ ] Prometheus scrape targets
- [ ] Grafana dashboard setup
- [ ] Alerting rules
- [ ] Log aggregation (Loki)

**Deliverables:**
- monitoring-stack.yml - Prometheus and Grafana
- Grafana dashboards as code

---

### TODO: Phase 5 - VM Templates and Workloads (Feb+)
- [ ] Base Ubuntu cloud-init templates
- [ ] Kubernetes (K3s) cluster on Proxmox
- [ ] Semaphore agent deployment
- [ ] Application provisioning

**Deliverables:**
- vm-templates/ - Cloud-init configs
- deploy-vms.yml - VM provisioning playbook

---

### TODO: Phase 6 - Configuration Drift Detection (Ongoing)
- [ ] GitHub Actions workflow (daily validation)
- [ ] Compliance scanning
- [ ] Automated remediation or alerting

**Deliverables:**
- .github/workflows/drift-detection.yml
- scripts/verify-infrastructure.sh

---

## Current Status

### Automation Complete

Component                    | Status   | Playbook
---------------------------- | -------- | --------------------------------
Proxmox Installation         | DONE     | Answer file + first-boot script
Node Bootstrap               | DONE     | bootstrap-proxmox.yml
SSH Hardening                | DONE     | bootstrap-proxmox.yml
Cluster Creation             | DONE     | cluster-formation.yml
Quorum Voting (QDevice)      | DONE     | cluster-formation.yml
NFS Storage Mount            | PROGRESS | Next playbook
Configuration Drift          | PROGRESS | Cron-based validation
VM Provisioning              | TODO     | Phase 5

### Infrastructure Verified

- [X] Dual-link corosync cluster (tested failover)
- [X] QDevice voting (3-vote quorum working)
- [X] SSH key-based access (no passwords)
- [X] All configuration in Git (IaC principle)
- [X] Ansible idempotency (safe to re-run playbooks)

---

## Usage Guide

### Running Playbooks

**First Time Setup (New Cluster):**
```bash
# Phase 1: Bootstrap nodes
ansible-playbook -i ansible/inventory/provisioning-nodes.yml \
  ansible/playbooks/bootstrap-proxmox.yml

# Phase 2: Form cluster
ansible-playbook -i ansible/inventory/production-cluster.yml \
  ansible/playbooks/cluster-formation.yml
```

**Idempotent Re-runs (Safe):**
```bash
# Playbooks check current state and skip if already configured
ansible-playbook -i ansible/inventory/production-cluster.yml \
  ansible/playbooks/cluster-formation.yml \
  -v  # Show what was skipped
```

**Targeting Specific Nodes:**
```bash
# Run only on node1
ansible-playbook -i ansible/inventory/production-cluster.yml \
  ansible/playbooks/cluster-formation.yml \
  -l pve-node1

# Run only on members (not master)
ansible-playbook -i ansible/inventory/production-cluster.yml \
  ansible/playbooks/cluster-formation.yml \
  -l proxmox_cluster_members
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

**Verify SSH Access:**
```bash
# Should work without password (key-based)
ssh ansible@pve-node1.homelab.bredhauer.net

# Check if sudo works without password (for Ansible)
ssh ansible@pve-node1.homelab.bredhauer.net 'sudo pvecm status'
```

---

## Configuration

### Inventory Setup

Edit ansible/inventory/production-cluster.yml:

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
  
  children:
    proxmox_cluster_masters:
      hosts:
        pve-node1:
    
    proxmox_cluster_members:
      hosts:
        pve-node2:
```

### Answer File Configuration

Edit installer/answer-files/proxmox-answer.toml:

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

### Node Won't Boot from ISO

**Problem:** Proxmox installer doesn't start
**Solution:** Check installer/README-INSTALLER.md for iVentoy setup

### Cluster Formation Fails

**Problem:** pvecm create fails with "already exists"
**Solution:** Playbook is idempotent--this is expected on re-runs. Check pvecm status

**Problem:** Node won't join cluster
**Solution:** Verify fingerprint matches:

```bash
# On master
pvenode cert info --output-format json | jq '.[] | select(.filename=="pve-ssl.pem") | .fingerprint'

# Should match what joining node used
```

### SSH Access Denied

**Problem:** Can't SSH with Ansible user
**Solution:**

```bash
# Verify SSH key was deployed
cat /home/ansible/.ssh/authorized_keys

# Check if ansible user has sudo access
grep ansible /etc/sudoers

# Test sudo without password
sudo -l
```

### QDevice Not Voting

**Problem:** Only 2 votes in cluster (should be 3)
**Solution:**

```bash
# Verify QDevice is running on RPi
ssh root@192.168.10.164 'systemctl status corosync-qdevice'

# Check votes from master
pvecm qdevice status
```

See docs/TROUBLESHOOTING.md for more scenarios.

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

5. **Push and Create PR:** Reference related issue

### Code Standards

- Ansible: Use ansible_builtin module names, keep tasks small and focused
- Documentation: Update README and phase docs with changes
- Testing: Always run --check mode first, then verify on test hardware
- Idempotency: Every playbook must be safe to run multiple times
- No Hardcoded Secrets: Use vault or environment variables

---

## Maintenance

### Regular Tasks

**Weekly:**
- [ ] Verify cluster quorum: pvecm status
- [ ] Check storage free space: df -h /mnt/nfs

**Monthly:**
- [ ] Run configuration drift check: scripts/verify-infrastructure.sh
- [ ] Review Ansible vault inventory for expired credentials

**Quarterly:**
- [ ] Test disaster recovery (cluster rebuild from scratch)
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

---

## References

### External Documentation
- Proxmox VE 9.0 Docs: https://pve.proxmox.com/wiki/Main_Page
- Corosync Redundancy: https://pve.proxmox.com/wiki/Clustering
- QDevice Setup: https://pve.proxmox.com/wiki/Cluster_Setup#corosync
- Ansible Best Practices: https://docs.ansible.com/ansible/latest/user_guide/playbooks_best_practices.html

### Internal Documentation
- docs/ARCHITECTURE.md - Design decisions and rationale
- docs/NETWORK.md - Network topology and addressing scheme
- docs/CLUSTER-SETUP.md - Corosync and QDevice technical details
- docs/PHASE-ROADMAP.md - Detailed timeline for remaining phases
- docs/HOMELAB-MASTER-DOCUMENT.md - Complete reference (13+ sections)

### Phase Status
- docs/PHASE-ROADMAP.md - Updated after each phase completion
- See "Phase Roadmap" section above for current progress

---

## License

[Your License Here - e.g., MIT, Apache 2.0]

## Author

Andrew Bredhauer | Brisbane, Australia | https://github.com/ABredhauer

---

## Changelog

### v2.0 (January 2026) - Phase 2 Complete
- [X] Dual-link cluster formation automated
- [X] QDevice quorum voting setup
- [X] Cluster-formation.yml playbook added
- [X] Updated documentation for production use

### v1.0 (November 2025) - Phase 1 Complete
- [X] Proxmox provisioning via answer files
- [X] First-boot automation (SSH, network)
- [X] Bootstrap playbook (user setup, hardening)
- [X] Semaphore integration

---

## Next Steps

Next: Ready for Phase 3? See docs/PHASE-ROADMAP.md for storage configuration details.

Questions? Open an issue or review docs/TROUBLESHOOTING.md.

Want to contribute? See "Contributing" section above.