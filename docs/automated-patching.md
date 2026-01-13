# Automated Patching & Update Strategy

**Date:** 2026-01-13  
**Status:** Final  
**Phase:** 4 (Monitoring & Maintenance)  

---

## Overview

Goal: Keep Proxmox hosts, LXCs, and VMs **patched with minimal manual effort** while maintaining control over restarts.

Scope:

- Proxmox nodes (OS + Proxmox packages)
- LXC containers (Debian/Ubuntu packages)
- Docker VMs (OS packages)
- Docker containers (images via Diun notifications)

---

## Strategy Summary

| Component        | Method                     | Frequency       | Reboot | Automation      |
|-----------------|----------------------------|-----------------|--------|-----------------|
| Proxmox hosts   | Rolling update script      | Monthly         | Yes    | Semi-automated  |
| LXC containers  | Ansible playbook           | Weekly (Sun 3am)| Maybe  | Fully automated |
| Docker VMs      | Ansible playbook           | Weekly (Sun 3am)| Maybe  | Fully automated |
| Docker containers | Diun + manual `pull`/`up`| As needed       | No     | Notify only     |

---

## 1. Proxmox Host Updates (Rolling)

### Manual Rolling Updates (Recommended)

Monthly procedure:

1. Migrate VMs off node1 to node2 (live)
2. Stop/migrate LXCs (cold)
3. `apt update && apt dist-upgrade -y` on node1
4. Reboot node1
5. Once healthy, rebalance or leave as-is
6. Repeat for node2

Example commands:

```bash
# On node1 â€“ migrate all VMs to node2
for vmid in $(qm list | awk 'NR>1 {print $1}'); do
  qm migrate "$vmid" pve-node2 --online
done

# LXC migrate
for ctid in $(pct list | awk 'NR>1 {print $1}'); do
  pct stop "$ctid"
  pct migrate "$ctid" pve-node2
  pct start "$ctid"
done

# Update node1
apt update && apt dist-upgrade -y
reboot
```

### Semi-automated Script (Optional)

Place at `/usr/local/bin/rolling-update.sh`:

```bash
#!/bin/bash
set -euo pipefail

NODE="${1:-}"
if [[ -z "$NODE" ]]; then
  echo "Usage: $0 <node-name>"
  exit 1
fi

echo "=== Rolling Update: $NODE ==="

# 1. Migrate VMs off this node
echo "Migrating VMs..."
TARGET_NODE=""
if [[ "$NODE" == "pve-node1" ]]; then
  TARGET_NODE="pve-node2"
else
  TARGET_NODE="pve-node1"
fi

for vmid in $(qm list | awk 'NR>1 {print $1}'); do
  CURRENT=$(qm status "$vmid" | grep node | awk '{print $2}')
  if [[ "$CURRENT" == "$NODE" ]]; then
    echo "  Migrating VM $vmid to $TARGET_NODE..."
    qm migrate "$vmid" "$TARGET_NODE" --online || true
  fi
done

# 2. Migrate LXCs
echo "Migrating LXCs..."
for ctid in $(pct list | awk 'NR>1 {print $1}'); do
  CURRENT=$(pct status "$ctid" | grep node | awk '{print $2}')
  if [[ "$CURRENT" == "$NODE" ]]; then
    echo "  Stopping CT $ctid..."
    pct stop "$ctid" || true
    echo "  Migrating CT $ctid to $TARGET_NODE..."
    pct migrate "$ctid" "$TARGET_NODE"
    echo "  Starting CT $ctid..."
    pct start "$ctid"
  fi
done

# 3. Update packages
echo "Updating packages on $NODE..."
ssh "$NODE" "apt update && apt dist-upgrade -y"

# 4. Check if reboot required
REBOOT_REQUIRED=$(ssh "$NODE" "test -f /var/run/reboot-required && echo yes || echo no")
if [[ "$REBOOT_REQUIRED" == "yes" ]]; then
  echo "Reboot required. Rebooting $NODE..."
  ssh "$NODE" "reboot"
  
  # Wait for node to come back
  echo "Waiting for $NODE to come back online..."
  sleep 60
  until ssh "$NODE" "uptime" &>/dev/null; do
    sleep 10
  done
  
  # Wait for cluster quorum
  echo "Waiting for cluster quorum..."
  sleep 30
  until pvecm status | grep -q "Quorate.*Yes"; do
    sleep 10
  done
  
  echo "$NODE is back and cluster has quorum."
else
  echo "No reboot required."
fi

echo "=== Rolling Update Complete: $NODE ==="
```

Usage:

```bash
chmod +x /usr/local/bin/rolling-update.sh
rolling-update.sh pve-node1
rolling-update.sh pve-node2
```

---

## 2. LXC Container Updates

Use `ansible/playbooks/update-lxc-containers.yml`:

```yaml
---
- name: Update LXC Containers
  hosts: lxc_containers
  become: yes

  tasks:
    - name: Update APT cache
      ansible.builtin.apt:
        update_cache: yes
        cache_valid_time: 3600

    - name: Upgrade packages
      ansible.builtin.apt:
        upgrade: dist
        autoremove: yes
        autoclean: yes
      register: apt_upgrade

    - name: Check reboot required
      ansible.builtin.stat:
        path: /var/run/reboot-required
      register: reboot_required

    - name: Reboot if needed
      ansible.builtin.reboot:
        msg: "Reboot initiated by Ansible"
      when: reboot_required.stat.exists and (auto_reboot | default(false))

    - name: Wait for container online
      ansible.builtin.wait_for_connection:
        delay: 10
        timeout: 300
      when: reboot_required.stat.exists and (auto_reboot | default(false))
```

Inventory file `ansible/inventory/lxc_containers.yml`:

```yaml
all:
  children:
    lxc_containers:
      hosts:
        pihole-1:
          ansible_host: 192.168.1.192
        pihole-2:
          ansible_host: 192.168.1.193
        traefik:
          ansible_host: 192.168.1.194
        prometheus:
          ansible_host: 192.168.10.240
        pbs:
          ansible_host: 192.168.10.250
```

Cron (on control host):

```cron
0 3 * * 0 root cd /path/to/homelab-iac && \
  ansible-playbook -i ansible/inventory/lxc_containers.yml \
    ansible/playbooks/update-lxc-containers.yml -e "auto_reboot=true" \
    >> /var/log/ansible-lxc-updates.log 2>&1
```

---

## 3. Docker VM Updates

`ansible/playbooks/update-docker-vms.yml`:

```yaml
---
- name: Update Docker VMs
  hosts: docker_vms
  become: yes
  serial: 1

  tasks:
    - name: Update APT cache
      ansible.builtin.apt:
        update_cache: yes
        cache_valid_time: 3600

    - name: Upgrade packages
      ansible.builtin.apt:
        upgrade: dist
        autoremove: yes
        autoclean: yes
      register: apt_upgrade

    - name: Check reboot required
      ansible.builtin.stat:
        path: /var/run/reboot-required
      register: reboot_required

    - name: Pause before reboot
      ansible.builtin.pause:
        seconds: 60
        prompt: "Reboot required. Press enter to continue (Ctrl+C to cancel)"
      when: reboot_required.stat.exists and (auto_reboot | default(false))

    - name: Reboot VM
      ansible.builtin.reboot:
        msg: "Reboot initiated by Ansible"
      when: reboot_required.stat.exists and (auto_reboot | default(false))

    - name: Wait for VM online
      ansible.builtin.wait_for_connection:
        delay: 10
        timeout: 300
      when: reboot_required.stat.exists and (auto_reboot | default(false))
```

Inventory file `ansible/inventory/docker_vms.yml`:

```yaml
all:
  children:
    docker_vms:
      hosts:
        plex-vm:
          ansible_host: 192.168.1.210
        arr-stack-vm:
          ansible_host: 192.168.1.211
        download-clients-vm:
          ansible_host: 192.168.1.212
        web-apps-vm:
          ansible_host: 192.168.1.213
```

Cron (on control host):

```cron
0 3 * * 0 root cd /path/to/homelab-iac && \
  ansible-playbook -i ansible/inventory/docker_vms.yml \
    ansible/playbooks/update-docker-vms.yml -e "auto_reboot=true" \
    >> /var/log/ansible-vm-updates.log 2>&1
```

---

## 4. Docker Containers (Images)

You already have Diun configured to email when new images are available.

Process:

1. Receive Diun email (e.g. new Plex image)
2. On the relevant VM:

```bash
cd /opt/plex
docker-compose pull
docker-compose up -d
```

No automation here to avoid surprise restarts.

---

## 5. Monitoring Updates

Optional: expose `apt_pending_updates` via node_exporter textfile collector and alert in Prometheus if updates pending for more than a week.

Example script `/usr/local/bin/apt-metrics.sh`:

```bash
#!/bin/bash
UPDATES=$(apt list --upgradable 2>/dev/null | grep -c upgradable)
echo "apt_pending_updates $UPDATES" > /var/lib/node_exporter/textfile_collector/apt.prom
```

Cron (daily):

```cron
0 6 * * * root /usr/local/bin/apt-metrics.sh
```

Prometheus alert:

```yaml
- alert: PendingUpdates
  expr: apt_pending_updates > 10
  for: 7d
  annotations:
    summary: "{{ $labels.instance }} has {{ $value }} pending updates"
```

---

## 6. Testing

### Proxmox Host

```bash
# Dry-run test
ssh pve-node1 "apt update && apt list --upgradable"

# Test rolling-update.sh
rolling-update.sh pve-node1
```

### LXC Containers

```bash
# Dry-run (no changes)
ansible-playbook -i ansible/inventory/lxc_containers.yml \
  ansible/playbooks/update-lxc-containers.yml \
  --check

# Live run
ansible-playbook -i ansible/inventory/lxc_containers.yml \
  ansible/playbooks/update-lxc-containers.yml \
  -e "auto_reboot=true"
```

### Docker VMs

```bash
# Dry-run
ansible-playbook -i ansible/inventory/docker_vms.yml \
  ansible/playbooks/update-docker-vms.yml \
  --check

# Live run
ansible-playbook -i ansible/inventory/docker_vms.yml \
  ansible/playbooks/update-docker-vms.yml \
  -e "auto_reboot=true"
```

---

## 7. Rollback

- If host update causes issues: boot previous kernel, or reinstall Proxmox and restore from PBS.
- If container/LXC update breaks something: restore PBS backup or revert packages with `apt install <package>=<version>`.
- For Docker, pin to a known-good tag and redeploy.

---

## 8. Security Considerations

- Always test updates in a non-production environment first (if available)
- Keep at least 2 recent PBS backups before major updates
- Review release notes for Proxmox updates (especially kernel changes)
- Monitor logs after automated updates: `/var/log/ansible-*.log`

---

## 9. Future Enhancements

- Integrate with Proxmox HA to automatically migrate VMs before host updates
- Create Ansible role for Proxmox host updates
- Add pre-update backup triggers
- Implement update windows (e.g., only update between 2am-6am)
- Add Slack/Discord notifications for update completion/failures

---

## Summary

This strategy balances automation with control:

- **Hosts:** Manual/semi-automated monthly (high risk, needs oversight)
- **LXCs/VMs:** Fully automated weekly (low risk, easy rollback)
- **Containers:** Notify only (application-level, needs testing)

All components stay patched without constant manual intervention, while maintaining the ability to control and monitor the update process.