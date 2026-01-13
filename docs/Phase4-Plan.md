# Phase 4: Monitoring, Power Management & Maintenance

**Version:** 2.0  
**Date:** 2026-01-13  
**Status:** Ready for Implementation  
**Duration:** 2 weeks  
**Effort:** 28 hours  

---

## Overview

Phase 4 establishes **observability, resilience, and automated maintenance** for the Proxmox cluster. The goals are:

1. **Native Monitoring** - Know cluster health (Proxmox Web UI, CLI, alerts)
2. **Prometheus Metrics** - Historical data beyond 24 hours
3. **Power Management** - Graceful shutdown on UPS failure (NUT integration)
4. **Automated Patching** - Keep cluster and containers patched automatically

**Why this phase matters:** Before deploying 22 production containers, you need to understand cluster health, handle power failures gracefully, and maintain security patches automatically.

---

## Goals

### Primary Goals

#### 1. Native Monitoring Setup
- Document Proxmox's built-in monitoring capabilities
- Configure email alerts for critical events (quorum loss, node failure)
- Verify you can check cluster health via Web UI, CLI, and REST API

#### 2. Prometheus for Historical Metrics
- Deploy Prometheus LXC on cluster (scrapes Proxmox API)
- Integrate with existing Grafana on NAS
- Maintain 15-30 day metric history
- Create dashboards for trend analysis

#### 3. Power Management (NUT Integration)
- Install NUT clients on both Proxmox nodes
- Configure graceful shutdown on power loss
- Implement 3-phase shutdown strategy:
  - Phase 1 (0-5 min): Keep both nodes running
  - Phase 2 (5-15 min): Shutdown node2, keep node1
  - Phase 3 (15+ min): Graceful shutdown of node1

#### 4. Automated Patching Strategy
- Proxmox hosts: Manual rolling updates monthly
- LXC containers: Ansible playbook weekly
- Docker VMs: Ansible playbook weekly
- Docker containers: Diun notifications (you update manually)

### Secondary Goals (Optional)

- Slack/Discord alerts (instead of email)
- Prometheus alert rules (threshold-based alerts)
- Container-level resource monitoring (defer to Phase 6)

---

## Success Criteria

All of the following must be true:

### Monitoring
- [ ] Access Proxmox Web UI and see cluster status
- [ ] Run `pvecm status` and understand output
- [ ] View 24-hour graphs in Web UI
- [ ] Receive email alert when quorum lost (tested)
- [ ] Receive email alert when node offline (tested)

### Prometheus & Grafana
- [ ] Prometheus scraping Proxmox API (both nodes showing as "UP")
- [ ] Grafana connected to Prometheus data source
- [ ] Historical CPU/RAM/disk graphs available
- [ ] Can answer: "What was cluster CPU at 3pm yesterday?"
- [ ] Grafana dashboard displays cluster health

### Power Management
- [ ] NUT clients installed on both nodes
- [ ] Nodes respond to UPS power loss signal (simulated test)
- [ ] Node2 shuts down before Node1 (verified in logs)
- [ ] Cluster rejoins cleanly after power restored
- [ ] Shutdown scripts working correctly

### Automated Patching
- [ ] Ansible playbooks created for LXC and VM updates
- [ ] Rolling update script for Proxmox hosts created
- [ ] Cron jobs scheduled (weekly Sunday 3am)
- [ ] Test run shows containers updating without errors
- [ ] Email received from Diun about available container updates

---

## Architecture

### Monitoring Stack

```
Proxmox Cluster (node1, node2)
â”œâ”€ Native: Web UI, CLI, API (24-hour history)
â””â”€ Prometheus (LXC on node1)
   â””â”€ Scrapes: /api2/prometheus/metrics (both nodes)
   â””â”€ Stores: Time-series data (15-30 day history)

NAS (External Monitoring)
â””â”€ Grafana (existing, port 3000)
   â””â”€ Data source: Prometheus http://192.168.10.240:9090
   â””â”€ Displays: Custom dashboards, historical graphs

Raspberry Pi (UPS Monitor)
â””â”€ NUT server (192.168.10.164)
   â””â”€ Monitors: CyberPower PR1500ERT2U
   â””â”€ Broadcasts: Power events to NUT clients

Both Proxmox Nodes
â”œâ”€ NUT client (192.168.10.164:3493)
â”œâ”€ Listens for power loss signals
â”œâ”€ Executes 3-phase shutdown strategy
â””â”€ Logs all power events

Ansible Control (Semaphore or Semaphore UI on NAS)
â””â”€ Scheduled playbooks (cron):
   â”œâ”€ Weekly Sunday 3am: Update LXC containers
   â”œâ”€ Weekly Sunday 3am: Update Docker VMs
   â””â”€ Manual: Proxmox host rolling updates (monthly)
```

### UPS Runtime Calculation

**CyberPower PR1500ERT2U:**
- Capacity: 1500VA / 1350W
- Current load without nodes: ~81W (6% of UPS)
- Dell R620 per node: ~120W idle, ~200W loaded

**Total cluster power:**
- Both nodes idle: 81W + 240W = 321W (24% of UPS)
- Both nodes loaded: 81W + 400W = 481W (36% of UPS)

**UPS runtime estimate:**
- At 36% load: 20-30 minutes on battery
- After node2 shutdown: 40-60 minutes on battery (sufficient for graceful node1 shutdown)

---

## Implementation Plan

### Week 1: Native Monitoring & Prometheus

#### Days 1-2: Document Native Monitoring

**Deliverable:** `docs/native-monitoring-guide.md`

Create comprehensive guide covering:

```bash
# Web UI Access
https://192.168.10.230:8006
- Datacenter â†’ Summary (cluster quorum, node count)
- Nodes â†’ <node> â†’ Status (CPU, RAM, uptime, kernel)
- Cluster Logs (Proxmox events)
- Backups (PBS jobs)

# CLI Monitoring
pvecm status          # Cluster quorum info
pvesh get /nodes/pve-node1/status
pvesh get /cluster/resources  # All resources
pvesm status          # Storage status
pvesr status          # Replication status

# REST API (for automation)
curl -k -b /tmp/cookie https://192.168.10.230:8006/api2/json/cluster/resources
```

Document what each metric means and how to interpret it.

#### Days 3-4: Email Alerts Configuration

Configure Proxmox email notifications:

```bash
# Edit /etc/pve/user.cfg
user:root@pam:1:0::andrew@bredhauer.net::

# Test email delivery
echo "Test" | mail -s "Test Alert" andrew@bredhauer.net

# Proxmox will email on:
# - Node offline
# - Quorum lost
# - Storage full (>90%)
# - Backup failed
# - Replication failed
```

**Test:** Simulate quorum loss on node2, verify email received.

#### Days 5-7: Prometheus Deployment

Create Prometheus LXC on node1:

```bash
pct create 240 local:vztmpl/ubuntu-24.04-standard_24.04-2_amd64.tar.zst \
  --hostname prometheus \
  --memory 2048 \
  --cores 2 \
  --storage local-zfs \
  --net0 name=eth0,bridge=vmbr1,ip=192.168.10.240/24,gw=192.168.10.1 \
  --features nesting=1

pct start 240
pct enter 240

# Install Prometheus
apt-get update
apt-get install -y prometheus

# Configure /etc/prometheus/prometheus.yml
scrape_configs:
  - job_name: 'proxmox'
    static_configs:
      - targets:
        - '192.168.10.230:9090'  # node1
        - '192.168.10.232:9090'  # node2
    metrics_path: '/api2/prometheus/metrics'
    scheme: https
    tls_config:
      insecure_skip_verify: true
    params:
      format: ['prometheus']

systemctl restart prometheus
systemctl enable prometheus
```

**Verify:** Access http://192.168.10.240:9090, check Targets page (both showing "UP").

#### Days 8-10: Grafana Integration

Integrate Prometheus with existing Grafana on NAS:

```bash
# Login to Grafana: http://192.168.1.25:3000

# Configuration â†’ Data Sources â†’ New
Name: Proxmox
Type: Prometheus
URL: http://192.168.10.240:9090
Save & Test

# Dashboards â†’ Import
ID: 10048 (Proxmox cluster dashboard)
Data source: Proxmox (Prometheus)
Import

# Or create custom dashboard:
# Add panels: CPU usage, RAM usage, Storage, Network
```

**Verify:** Dashboard shows cluster metrics with historical data.

#### Days 11-14: Power Management Setup

Install NUT clients and configure graceful shutdown:

```bash
# On both nodes
apt-get install nut-client

# Configure /etc/nut/upsmon.conf
MONITOR ups@192.168.10.164 1 upsmon PASSWORD slave
SHUTDOWNCMD "/sbin/shutdown -h +2"
NOTIFYCMD /usr/local/bin/ups-notify.sh

# Create /usr/local/bin/ups-notify.sh
#!/bin/bash
NOTIFYTYPE="$1"
NODE=$(hostname)

case "$NOTIFYTYPE" in
  ONBATT)
    echo "$(date): UPS on battery" >> /var/log/ups-events.log
    ;;
  LOWBATT)
    echo "$(date): UPS low battery" >> /var/log/ups-events.log
    if [[ "$NODE" == "pve-node2" ]]; then
      # Secondary node: shutdown immediately
      /sbin/shutdown -h +2 "UPS battery low, shutting down"
    fi
    ;;
  FSD)
    # Forced shutdown
    /sbin/shutdown -h now "UPS critical"
    ;;
  ONLINE)
    echo "$(date): UPS online" >> /var/log/ups-events.log
    ;;
esac

chmod +x /usr/local/bin/ups-notify.sh

# Start NUT client
systemctl enable nut-client
systemctl start nut-client

# Test with simulated power loss on Pi
# upsmon -c fsd
```

**Test:** Simulate power loss, verify both nodes shutdown gracefully.

---

### Week 2: Automated Patching & Final Testing

#### Days 15-18: Ansible Playbooks Setup

Create Ansible playbooks for automated updates.

**Playbook 1: Update LXC Containers** (`ansible/playbooks/update-lxc-containers.yml`):

```yaml
---
- name: Update LXC Containers
  hosts: lxc_containers
  become: yes
  
  tasks:
    - name: Update APT cache
      apt:
        update_cache: yes
        cache_valid_time: 3600
      
    - name: Upgrade packages
      apt:
        upgrade: dist
        autoremove: yes
        autoclean: yes
      register: apt_upgrade
      
    - name: Check reboot required
      stat:
        path: /var/run/reboot-required
      register: reboot_required
      
    - name: Reboot if needed
      reboot:
        msg: "Reboot initiated by Ansible"
      when: reboot_required.stat.exists and auto_reboot | default(false)
      
    - name: Wait for container online
      wait_for_connection:
        delay: 10
        timeout: 300
      when: reboot_required.stat.exists and auto_reboot | default(false)
```

**Playbook 2: Update Docker VMs** (`ansible/playbooks/update-docker-vms.yml`):

```yaml
---
- name: Update Docker VMs
  hosts: docker_vms
  become: yes
  serial: 1  # One at a time for HA
  
  tasks:
    - name: Update APT cache
      apt:
        update_cache: yes
        cache_valid_time: 3600
      
    - name: Upgrade packages
      apt:
        upgrade: dist
        autoremove: yes
        autoclean: yes
      register: apt_upgrade
      
    - name: Check reboot required
      stat:
        path: /var/run/reboot-required
      register: reboot_required
      
    - name: Pause before reboot (allow manual cancel)
      pause:
        seconds: 60
        prompt: "Reboot required. Press enter to continue (Ctrl+C to cancel)"
      when: reboot_required.stat.exists and auto_reboot | default(false)
      
    - name: Reboot VM
      reboot:
        msg: "Reboot initiated by Ansible"
      when: reboot_required.stat.exists and auto_reboot | default(false)
      
    - name: Wait for VM online
      wait_for_connection:
        delay: 10
        timeout: 300
      when: reboot_required.stat.exists and auto_reboot | default(false)
```

**Inventory files:**

```yaml
# ansible/inventory/lxc_containers.yml
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

# ansible/inventory/docker_vms.yml
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

#### Days 19-22: Rolling Update Script for Proxmox Hosts

Create `/usr/local/bin/rolling-update.sh` (see AUTOMATED-PATCHING.md for full script).

This script:
1. Migrates all VMs off target node
2. Updates packages on target node
3. Reboots if needed
4. Waits for cluster rejoin
5. Repeats for second node

**Usage:**
```bash
./rolling-update.sh pve-node1  # Update node1
# ... verify ...
./rolling-update.sh pve-node2  # Update node2
```

#### Days 23-24: Schedule & Test

Create cron jobs for automated updates:

```bash
# /etc/cron.d/ansible-updates
0 3 * * 0 root cd /volume1/docker/infrastructure/config/ansible-control/homelab-iac && ansible-playbook -i inventory/lxc_containers.yml playbooks/update-lxc-containers.yml -e "auto_reboot=true" >> /var/log/ansible-updates.log 2>&1

# Same for Docker VMs (serial execution)
0 3 * * 0 root cd /volume1/docker/infrastructure/config/ansible-control/homelab-iac && ansible-playbook -i inventory/docker_vms.yml playbooks/update-docker-vms.yml -e "auto_reboot=true" >> /var/log/ansible-updates.log 2>&1
```

**Test:** Run playbooks manually once to verify:
```bash
ansible-playbook -i ansible/inventory/lxc_containers.yml ansible/playbooks/update-lxc-containers.yml

ansible-playbook -i ansible/inventory/docker_vms.yml ansible/playbooks/update-docker-vms.yml
```

---

## Configuration Files

All provided in detailed sections above. Key files:

1. `docs/native-monitoring-guide.md` - Understanding Proxmox monitoring
2. `/etc/prometheus/prometheus.yml` - Prometheus configuration
3. `/etc/nut/upsmon.conf` - UPS client configuration
4. `/usr/local/bin/ups-notify.sh` - Power failure handler
5. `/usr/local/bin/rolling-update.sh` - Host update script
6. `ansible/playbooks/update-lxc-containers.yml` - LXC update playbook
7. `ansible/playbooks/update-docker-vms.yml` - VM update playbook

---

## Testing Plan

### Test 1: Native Monitoring (Day 2)

```bash
# Verify Web UI access
https://192.168.10.230:8006

# Verify CLI access
ssh root@pve-node1 'pvecm status'
ssh root@pve-node2 'pvecm status'

# Verify email alerts
# Simulate quorum loss on node2
ssh root@pve-node2 'systemctl stop corosync'
# Wait 2 minutes
# Verify email received
ssh root@pve-node2 'systemctl start corosync'
```

### Test 2: Prometheus (Day 10)

```bash
# Verify Prometheus access
curl -s http://192.168.10.240:9090/api/v1/query?query=up | jq .

# Verify Grafana integration
# Add Prometheus data source in Grafana
# Import dashboard 10048
# Verify graphs show data
```

### Test 3: Power Management (Day 14)

```bash
# Verify NUT client sees UPS
upsc ups@192.168.10.164

# Simulate power loss on Pi (NUT server)
ssh root@192.168.10.164 'upsmon -c fsd'

# Watch nodes shutdown
# Verify node2 shuts down before node1
# Check logs: tail -f /var/log/ups-events.log

# Power nodes back on
# Verify cluster rejoin
ssh root@pve-node1 'pvecm status'
```

### Test 4: Automated Patching (Day 22)

```bash
# Test LXC updates (manually)
ansible-playbook -i ansible/inventory/lxc_containers.yml \
  ansible/playbooks/update-lxc-containers.yml

# Verify all LXCs updated
ansible lxc_containers -i ansible/inventory/lxc_containers.yml \
  -m shell -a "apt list --upgradable | wc -l"

# Test Docker VM updates
ansible-playbook -i ansible/inventory/docker_vms.yml \
  ansible/playbooks/update-docker-vms.yml

# Verify all VMs updated
ansible docker_vms -i ansible/inventory/docker_vms.yml \
  -m shell -a "apt list --upgradable | wc -l"

# Test Proxmox rolling update (on non-production)
/usr/local/bin/rolling-update.sh pve-node1
```

---

## Timeline

| Days | Task | Duration | Notes |
|------|------|----------|-------|
| 1-2 | Document native monitoring | 4 hrs | Create guide, test Web UI/CLI |
| 3-4 | Email alerts | 3 hrs | Configure postfix, test alerts |
| 5-7 | Prometheus deployment | 4 hrs | Create LXC, install, configure |
| 8-10 | Grafana integration | 3 hrs | Add data source, import dashboard |
| 11-14 | Power management | 5 hrs | Install NUT, create scripts, test |
| 15-18 | Ansible playbooks | 6 hrs | Write playbooks, create inventory |
| 19-22 | Rolling update script | 4 hrs | Write script, test migration |
| 23-24 | Schedule & verify | 2 hrs | Cron jobs, final testing |
| **Total** | | **31 hours** | At 2 hrs/day = 16 days (~2.5 weeks) |

---

## Rollback Plan

### If Prometheus Fails
- Delete Prometheus LXC: `pct destroy 240`
- Remove from Grafana data sources
- Cluster still monitored via native tools
- No impact on cluster

### If Alerts Fail
- Edit `/etc/pve/user.cfg`, remove email
- Cluster still functions
- No impact on cluster

### If NUT Fails
- Uninstall: `apt-get remove nut-client`
- Remove config: `rm /etc/nut/upsmon.conf /usr/local/bin/ups-notify.sh`
- Cluster still functions (just no automatic shutdown on power loss)
- Manual shutdown required

### If Ansible Playbooks Fail
- Edit cron jobs: `crontab -e`
- Comment out failing jobs
- Revert to manual updates
- No impact on cluster

**All Phase 4 components are non-destructive add-ons with full rollback capability.**

---

## Maintenance Schedule (After Phase 4)

### Weekly (Automated, Sunday 3am)
- Ansible updates all LXC containers
- Ansible updates all Docker VM host OS
- Total downtime: ~2-5 minutes per service

### Monthly (Manual, First Saturday)
- Run rolling update script for Proxmox hosts
- Manually update Docker container images (via Diun notifications)
- Total time: ~1 hour

### As Needed
- Monitor Diun emails for container updates
- Update containers when convenient
- Most updates don't require VM restart

---

## Dependencies

### Phase 3 Must Be Complete
- Cluster operational and quorate
- Storage configured and replicating
- All nodes can reach each other

### External Services Required
- NUT server on Pi (192.168.10.164) - for UPS monitoring
- NAS with Grafana running (192.168.1.25:3000) - for dashboards
- Email relay configured - for alert delivery
- Ansible control host (on NAS via Semaphore) - for playbooks

### Network Requirements
- Both nodes can reach: 192.168.10.164 (NUT server)
- Both nodes can reach: 192.168.1.25 (NAS for Grafana)
- NAS can reach: 192.168.10.240 (Prometheus)

---

## Deliverables

### Documentation
- `docs/native-monitoring-guide.md` - Proxmox monitoring explained
- `docs/prometheus-setup.md` - Prometheus deployment steps
- `docs/power-management-setup.md` - NUT configuration guide
- `docs/automated-patching-guide.md` - Update strategy explained

### Configuration Files
- `/etc/prometheus/prometheus.yml` - Prometheus config
- `/etc/nut/upsmon.conf` - NUT client config (both nodes)
- `/usr/local/bin/ups-notify.sh` - Power failure handler (both nodes)
- `/usr/local/bin/rolling-update.sh` - Host update script (both nodes)

### Ansible Playbooks
- `ansible/playbooks/update-lxc-containers.yml`
- `ansible/playbooks/update-docker-vms.yml`
- `ansible/playbooks/weekly-updates.yml` (master playbook)
- `ansible/inventory/lxc_containers.yml`
- `ansible/inventory/docker_vms.yml`

### Cron Jobs
- `/etc/cron.d/ansible-updates` - Weekly updates (Sunday 3am)

### Test Reports
- Monitoring test results (native, Prometheus, Grafana)
- Power management test results (simulated failure)
- Update test results (playbook runs)
- Email alert verification

---

## Next Steps

After Phase 4 completion:
- **Phase 5:** Deploy containers (PiHole, Traefik, media stack)
- **Phase 6:** Advanced monitoring (container metrics, log aggregation)
- **Phase 7:** Backup automation (PBS daily backup jobs)

---

## Notes

- Prometheus retention: 15-30 days (adjust as needed via prometheus.yml)
- UPS runtime: 20-30 min both nodes, 40-60 min after node2 shutdown
- Ansible updates: Can adjust frequency, disable auto-reboot, run manually
- Monitoring is non-blocking: Can skip Prometheus and rely on native tools
- All components are optional: Implement what matches your needs

---

## References

- [Proxmox Monitoring Documentation](https://pve.proxmox.com/wiki/Monitoring)
- [Prometheus Proxmox Exporter](https://github.com/prometheus-pve/prometheus-pve-exporter)
- [Grafana Proxmox Dashboard](https://grafana.com/grafana/dashboards/10048)
- [NUT Documentation](https://networkupstools.org/docs/user-manual.chunked/)
- [Ansible Best Practices](https://docs.ansible.com/ansible/latest/user_guide/playbooks_best_practices.html)