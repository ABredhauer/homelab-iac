# Phase 3 Clean Rebuild Verification Checklist

**Objective:** Rebuild both Proxmox nodes from scratch and verify all Phase 3 functionality works correctly.

**Timeline:** Estimate 2-3 hours total

**Prerequisite:** All playbooks and configurations are committed to Git and documented.

---

## Pre-Rebuild: Preparation

- [ ] **Backup current state**
  ```bash
  ./scripts/backup-cluster-config.sh
  git log --oneline | head -20  # Record current commits
  ```

- [ ] **Document current configuration**
  ```bash
  ssh root@pve-node1 'pvecm status' > /tmp/cluster-status-backup.txt
  ssh root@pve-node1 'zfs list' > /tmp/zfs-backup.txt
  ssh root@pve-node1 'pvesm status' > /tmp/storage-backup.txt
  ```

- [ ] **Verify all playbooks are in Git**
  ```bash
  git status
  # Should show clean working directory
  ```

- [ ] **Print this checklist** (for reference during rebuild)

---

## Phase 1: Node Provisioning

### Node 1: pve-node1 (192.168.10.230)

- [ ] **Boot from iVentoy**
  - Reboot node with iVentoy USB or PXE
  - Select custom Proxmox ISO from menu
  - Let installer run completely unattended (15-20 min)

- [ ] **Post-Install Verification**
  ```bash
  ssh root@192.168.10.230 'hostname -f'
  # Expected: pve-node1.homelab.bredhauer.net
  
  ssh root@192.168.10.230 'ip addr show eth0'
  # Expected: 192.168.10.230/24
  ```

- [ ] **Wait for first-boot script to complete**
  - Check `/opt/proxmox-install-complete` exists
  ```bash
  ssh root@192.168.10.230 'ls -l /opt/proxmox-install-complete'
  ```

### Node 2: pve-node2 (192.168.10.232)

- [ ] **Boot from iVentoy**
  - Same process as Node 1
  - Select custom Proxmox ISO

- [ ] **Post-Install Verification**
  ```bash
  ssh root@192.168.10.232 'hostname -f'
  # Expected: pve-node2.homelab.bredhauer.net
  
  ssh root@192.168.10.232 'ip addr show eth0'
  # Expected: 192.168.10.232/24
  ```

- [ ] **Wait for first-boot script**
  ```bash
  ssh root@192.168.10.232 'ls -l /opt/proxmox-install-complete'
  ```

---

## Phase 2: Cluster Formation

### QDevice (Raspberry Pi) - Bootstrap

- [ ] **SSH to QDevice and run first-boot script**
  ```bash
  ssh root@192.168.10.164
  sudo bash /tmp/bootstrap-pi-for-ansible.sh
  ```

- [ ] **Verify Pi is ready for Ansible**
  ```bash
  ssh -i ~/.ssh/id_rsa root@192.168.10.164 'whoami'
  # Should return: root (with key-based auth)
  ```

### Run Playbooks (via Semaphore or CLI)

- [ ] **Phase 2a: Bootstrap QDevice**
  ```bash
  ansible-playbook -i ansible/inventory/production-cluster.yml \
    ansible/playbooks/bootstrap-qdevice.yml \
    --user root \
    -e "PI_ROOT_PASSWORD=$PI_ROOT_PASS" \
    -e "SEMAPHORE_SSH_PUBLIC_KEY='$(cat ~/.ssh/id_semaphore.pub)'" \
    -vv
  
  # Expected: ok=X changed=Y failed=0
  # Check: /opt/pi-bootstrap-complete exists
  ```

- [ ] **Phase 2b: Cluster Formation**
  ```bash
  ansible-playbook -i ansible/inventory/production-cluster.yml \
    ansible/playbooks/cluster-formation.yml -vv
  
  # Expected: ok=X changed=Y failed=0 on both nodes
  ```

- [ ] **Verify cluster is formed**
  ```bash
  ssh root@pve-node1 'pvecm status'
  # Expected output:
  #   Cluster name: proxmox_cluster
  #   Config version: N
  #   Status: Quorate
  #   Nodes: 2
  #   Node 1: pve-node1 (local)
  #   Node 2: pve-node2
  
  ssh root@pve-node1 'pvecm nodes'
  # Should list both nodes
  ```

- [ ] **Verify cluster votes (3 total)**
  ```bash
  ssh root@pve-node1 'pvecm qdevice status'
  # Expected: votes=3 (node1=1, node2=1, qdevice=1)
  ```

- [ ] **Phase 2c: QDevice Security Cleanup**
  ```bash
  ansible-playbook -i ansible/inventory/production-cluster.yml \
    ansible/playbooks/disable-qdevice-root.yml -l qdevice -vv
  
  # Expected: ok=X changed=Y failed=0
  ```

- [ ] **Verify root SSH is disabled on Pi**
  ```bash
  ssh root@192.168.10.164 'whoami' 2>&1
  # Expected: Permission denied (publickey) or similar error
  
  ssh ansible@192.168.10.164 'whoami'
  # Expected: ansible (works)
  ```

---

## Phase 3: Storage Configuration

### Deploy Storage Playbook

- [ ] **Run configure-storage.yml**
  ```bash
  ansible-playbook -i ansible/inventory/production-cluster.yml \
    ansible/playbooks/configure-storage.yml -vv
  
  # Expected: 
  #   pve-node1: ok=61 changed=12 failed=0
  #   pve-node2: ok=25 changed=3 failed=0
  ```

- [ ] **Wait for completion** (~2-3 min)
  - Monitor playbook output
  - Watch for "Phase 3 Storage Configuration Complete!" message

### Verify NFS Mounts

- [ ] **Check mounts on node1**
  ```bash
  ssh root@pve-node1 'df -h | grep nas'
  # Expected 3 mounts:
  #   192.168.1.25:/volume1/backups       on /mnt/pve/nas-backup
  #   192.168.1.25:/volume1/homelab-shared on /mnt/pve/nas-shared
  #   192.168.1.25:/volume1/homelab-data   on /mnt/pve/nas-vm-storage
  ```

- [ ] **Check mounts on node2**
  ```bash
  ssh root@pve-node2 'df -h | grep nas'
  # Should show same 3 mounts
  ```

- [ ] **Verify mount accessibility**
  ```bash
  ssh root@pve-node1 'ls -la /mnt/pve/nas-backup'
  # Expected: Directory listing (mount is accessible)
  ```

### Verify Proxmox Storage Registration

- [ ] **List storage on node1**
  ```bash
  ssh root@pve-node1 'pvesm status'
  # Expected: All storage online
  #   nas-backup   nfs     active
  #   nas-shared   nfs     active
  #   nas-vm-storage nfs   active
  #   local-zfs    dir     active
  ```

- [ ] **List storage on node2**
  ```bash
  ssh root@pve-node2 'pvesm status'
  # Should show same storage
  ```

### Verify ZFS Replication Setup

- [ ] **Check test VM exists on node1**
  ```bash
  ssh root@pve-node1 'qm list | grep 900'
  # Expected: VMID 900, replication-test, 512MB RAM
  ```

- [ ] **Check replication job exists**
  ```bash
  ssh root@pve-node1 'pvesr list'
  # Expected output:
  #   JobID    Enabled  Target              ...
  #   900-0    Yes      local/pve-node2     ...
  ```

- [ ] **Check replication status**
  ```bash
  ssh root@pve-node1 'pvesr status --guest 900'
  # Expected: State=OK, FailCount=0
  ```

- [ ] **Verify initial snapshot created on node1**
  ```bash
  ssh root@pve-node1 'zfs list -t snapshot | grep vm-900'
  # Expected: At least one @__replicate_900-0_... snapshot
  ```

- [ ] **Verify disk synced to node2**
  ```bash
  ssh root@pve-node2 'zfs list | grep vm-900-disk-0'
  # Expected: rpool/data/vm-900-disk-0  56K  857G  56K  -
  ```

- [ ] **Verify snapshots synced to node2**
  ```bash
  ssh root@pve-node2 'zfs list -t snapshot | grep vm-900'
  # Expected: Same snapshots as node1
  ```

- [ ] **Wait for first scheduled sync (5 minutes)**
  ```bash
  # Wait 5+ minutes for automatic sync
  sleep 300
  
  # Check snapshot timestamp updated
  ssh root@pve-node1 'zfs list -t snapshot | grep vm-900'
  # Should have newer timestamp
  ```

### Verify Backup Schedule

- [ ] **Check backup job exists**
  ```bash
  ssh root@pve-node1 'pvesh get /cluster/backup'
  # Expected: Backup job configured for Sunday 2AM
  ```

- [ ] **Verify backup storage**
  ```bash
  ssh root@pve-node1 'pvesm list nas-backup'
  # Expected: Backup storage shown as accessible
  ```

### Verify Memory Monitoring

- [ ] **Check monitoring script installed**
  ```bash
  ssh root@pve-node1 'ls -la /usr/local/bin/check-memory-pressure.sh'
  # Expected: Script exists and executable
  ```

- [ ] **Check cron job scheduled**
  ```bash
  ssh root@pve-node1 'crontab -l | grep memory'
  # Expected: */5 * * * * /usr/local/bin/check-memory-pressure.sh
  ```

- [ ] **Test memory check manually**
  ```bash
  ssh root@pve-node1 '/usr/local/bin/check-memory-pressure.sh'
  # Expected: No errors, silent if under 90%
  ```

---

## Final Verification

### Cluster Health Check

- [ ] **Verify quorum**
  ```bash
  ssh root@pve-node1 'pvecm status | grep Quorate'
  # Expected: Quorate: Yes
  ```

- [ ] **Verify corosync links**
  ```bash
  ssh root@pve-node1 'corosync-cfgtool -s'
  # Expected: Link 0 and Link 1 both ACTIVE
  ```

- [ ] **Verify no errors**
  ```bash
  ssh root@pve-node1 'journalctl -u corosync -n 20'
  # Expected: No critical errors, normal operation messages
  ```

### Idempotency Test

**Run all Phase 3 playbooks again to verify idempotency:**

- [ ] **Re-run QDevice bootstrap**
  ```bash
  ansible-playbook -i ansible/inventory/production-cluster.yml \
    ansible/playbooks/bootstrap-qdevice.yml \
    --user ansible -vv
  
  # Expected: changed=0 (no changes needed, all "ok")
  ```

- [ ] **Re-run cluster formation**
  ```bash
  ansible-playbook -i ansible/inventory/production-cluster.yml \
    ansible/playbooks/cluster-formation.yml -vv
  
  # Expected: changed=0 (no changes)
  ```

- [ ] **Re-run storage configuration**
  ```bash
  ansible-playbook -i ansible/inventory/production-cluster.yml \
    ansible/playbooks/configure-storage.yml -vv
  
  # Expected: changed=0 (no changes)
  # All tasks should show "ok"
  ```

### Stress Test (Optional)

- [ ] **Trigger manual replication sync**
  ```bash
  ssh root@pve-node1 'pvesr run --id 900-0'
  # Should complete without errors
  
  # Wait for sync
  sleep 10
  
  # Verify status
  ssh root@pve-node1 'pvesr status --guest 900'
  ```

- [ ] **Test NFS failover** (optional)
  ```bash
  # Unmount NAS shares on node1
  ssh root@pve-node1 'umount /mnt/pve/nas-*'
  
  # Verify mounts on node2 still work
  ssh root@pve-node2 'ls /mnt/pve/nas-backup'
  
  # Remount on node1
  ssh root@pve-node1 'mount -a'
  ```

---

## Documentation

- [ ] **Record rebuild results**
  ```bash
  cat > rebuild-results-$(date +%Y%m%d).txt << EOF
  Clean Rebuild Date: $(date)
  Node 1 Hostname: $(ssh root@pve-node1 'hostname -f')
  Node 2 Hostname: $(ssh root@pve-node2 'hostname -f')
  Cluster Status: $(ssh root@pve-node1 'pvecm status | grep Status')
  Replication Status: $(ssh root@pve-node1 'pvesr status --guest 900 | head -1')
  Storage Mounts: $(ssh root@pve-node1 'df -h | grep nas | wc -l') shares
  Build Date: $(date)
  EOF
  ```

- [ ] **Commit rebuild notes to Git**
  ```bash
  git add rebuild-results-*.txt
  git commit -m "Clean rebuild verification: Phase 3 complete

  - Both nodes rebuilt from scratch via iVentoy
  - All Phase 2 playbooks executed and verified
  - All Phase 3 playbooks executed and verified
  - Cluster formed with QDevice quorum
  - Storage replicated and backups scheduled
  - Idempotency verified (all playbooks run twice)
  
  Cluster Status: Quorate, 3 votes (node1=1, node2=1, qdevice=1)
  Replication: Active, State=OK, FailCount=0
  Storage: 3 NFS shares mounted, all accessible
  "
  ```

---

## Troubleshooting During Rebuild

### If iVentoy boot fails:

```bash
# Check DHCP is pointing to iVentoy
# Verify iVentoy server is running
# Ensure custom ISO is in data directory
# Try PXE boot from BIOS
```

### If cluster formation fails:

```bash
# Check SSH key trust
ssh root@pve-node1 'ssh root@192.168.10.232 hostname'

# Check cluster state
ssh root@pve-node1 'pvecm status'

# Re-run cluster formation playbook
ansible-playbook ... cluster-formation.yml
```

### If storage doesn't mount:

```bash
# Verify NAS is reachable
ping 192.168.1.25

# Check NFS exports on NAS
ssh admin@192.168.1.25 'exportfs -v'

# Re-run storage playbook
ansible-playbook ... configure-storage.yml
```

### If replication doesn't start:

```bash
# Check for old snapshots blocking replication
ssh root@pve-node2 'zfs list -t snapshot | grep vm-900'

# If old snapshots exist, delete them
ssh root@pve-node2 'zfs destroy rpool/data/vm-900-disk-0@__OLD_SNAPSHOT__'

# Delete replication job and recreate
ssh root@pve-node1 'pvesr delete 900-0 --force'

# Re-run storage playbook (recreates job)
ansible-playbook ... configure-storage.yml
```

---

## Success Criteria

All of the following must be true:

- [X] Both nodes boot from iVentoy and complete installation unattended
- [X] Cluster forms with 3 votes (node1=1, node2=1, qdevice=1)
- [X] Cluster status shows "Quorate: Yes"
- [X] QDevice is voting (pvecm qdevice status shows active)
- [X] Root SSH disabled on Pi after QDevice setup
- [X] All 3 NFS shares mounted on both nodes
- [X] Proxmox shows all storage online (pvesm status)
- [X] Test VM 900 created on node1
- [X] Replication job 900-0 created and active
- [X] Replication status shows "State=OK, FailCount=0"
- [X] VM disk replicated to node2
- [X] Snapshots synced to node2
- [X] First automatic sync occurs at 5-minute interval
- [X] Backup schedule configured for Sunday 2AM
- [X] Memory monitoring enabled with 5-minute checks
- [X] All playbooks run twice with changed=0 on second run

**If all criteria are met: PHASE 3 REBUILD VERIFIED SUCCESS** âœ“

---

## Post-Rebuild Actions

1. **Commit rebuild success to Git**
2. **Update CHANGELOG with rebuild date**
3. **Archive old backup** (from before rebuild)
4. **Proceed to Phase 4: Monitoring & Observability**

---

## Estimated Timeline

| Phase | Task | Duration |
|-------|------|----------|
| Setup | Preparation & backup | 10 min |
| Node1 | iVentoy boot + install | 20 min |
| Node2 | iVentoy boot + install | 20 min |
| Wait | First-boot scripts | 5 min |
| Phase2a | QDevice bootstrap | 5 min |
| Phase2b | Cluster formation | 10 min |
| Phase2c | QDevice security cleanup | 2 min |
| Phase3 | Storage configuration | 3 min |
| Verify | Replication sync + tests | 10 min |
| Idempotency | Re-run playbooks | 20 min |
| **TOTAL** | | **105 min (1.75 hours)** |

**Actual time may vary based on network and hardware speed.**
