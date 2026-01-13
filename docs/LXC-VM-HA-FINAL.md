# LXC vs VM â€“ HA, Networking & Migration (Final Decisions)

**Date:** 2026-01-13  
**Status:** Final  

---

## Purpose

Clarify final decisions for:

- LXC vs VM usage
- HA and failover behaviour
- Live migration support
- Networking choices (bridge vs macvlan)

This feeds directly into Phase 4 and 5.

---

## LXC vs VM â€“ HA Behaviour

### Virtual Machines (VMs)

- **Live migration:** Yes (online via `qm migrate â€¦ --online`)
- **HA:** Full Proxmox HA support
- **Planned maintenance:** Zero downtime with live migration
- **Unplanned failover:** ~2 minutes (watchdog + restart)
- **Good for:** Complex stacks, anything with its own supervisor (Docker VMs, databases, media)

### LXC Containers

- **Live migration:** No (only offline migration)
- **HA:** Can be managed by HA stack but restart is cold
- **Planned maintenance:** Requires stop â†’ migrate â†’ start (~30s downtime)
- **Unplanned failover:** Similar to VMs (~2 minutes) if on shared storage and under HA
- **Good for:** Lightweight infra (DNS, reverse proxy, PBS, Prometheus)

---

## Final Placement Decision

| Service   | Type | HA Style       | Reason                                    |
|-----------|------|----------------|-------------------------------------------|
| PiHole x2 | LXC  | Active-active  | Simple DNS, low resource, no single point |
| Traefik   | LXC  | HA failover    | Reverse proxy, tolerates ~2min downtime   |
| PBS       | LXC  | Single, no HA  | Backups can tolerate cluster downtime     |
| Prometheus| LXC  | HA failover    | Metrics, not hard SLA, must be available  |
| Plex      | VM   | HA failover + live migrate | GPU passthrough, heavier load |
| Arr stack | VM   | HA failover + live migrate | Multiple services, DB, I/O heavy |
| Downloads | VM   | HA failover    | VPN + torrent stack, restarts acceptable |
| Web apps  | VM   | HA failover    | DB + web services, medium SLA needed      |

**Rationale:**

- **LXC for infrastructure:** Low overhead, simple configs, easy to manage at scale
- **VMs for applications:** Better isolation, easier to backup/restore, support live migration
- **Active-active DNS:** No single point of failure; DHCP sends both IPs to clients
- **HA failover for everything else:** Acceptable 2-minute downtime for homelab

---

## Networking Architecture

### Selected: Bridge Networking (NOT Macvlan)

Each LXC and VM gets a direct IP on the bridge network.

```text
Physical NIC (eth0)
â”œâ”€ vmbr0 (bridge, 192.168.1.0/24)
â”‚  â”œâ”€ PiHole #1: 192.168.1.192
â”‚  â”œâ”€ PiHole #2: 192.168.1.193
â”‚  â”œâ”€ Traefik: 192.168.1.194
â”‚  â”œâ”€ Plex VM: 192.168.1.210
â”‚  â”œâ”€ Arr VM: 192.168.1.211
â”‚  â”œâ”€ Downloads VM: 192.168.1.212
â”‚  â””â”€ Web Apps VM: 192.168.1.213
â””â”€ vmbr1 (bridge, 192.168.10.0/24)
   â”œâ”€ Prometheus: 192.168.10.240
   â””â”€ PBS: 192.168.10.250
```

**Inside each VM:** Docker containers use bridge/NAT (172.20.0.0/16, 172.21.0.0/16, etc.)

### Why Bridge (Not Macvlan)?

| Aspect          | Bridge | Macvlan |
|-----------------|--------|---------|
| Live migration  | âœ… Works seamlessly | âŒ Breaks (macvlan config tied to host) |
| Host â†” Container| âœ… Direct routing | âŒ Special handling needed |
| Setup complexity| âœ… Simple           | âŒ Complex (config on every host) |
| DHCP / DNS      | âœ… Normal           | âš ï¸ Potential issues with MAC spoofing |
| Failover        | âœ… Automatic        | âŒ Requires reconfiguration |

**Decision:** Use bridge networking for all LXCs and VMs.

---

## Traefik Routing (Reverse Proxy)

Traefik (192.168.1.194) routes incoming HTTPS requests to backend services:

```text
Internet (HTTPS on 443)
â””â”€ Router Port Forward 443 â†’ 192.168.1.194:443
   â””â”€ Traefik (in LXC)
      â”œâ”€ example.com â†’ 192.168.1.210:7896 (Plex)
      â”œâ”€ arr.example.com â†’ 192.168.1.211:7878 (Radarr)
      â”œâ”€ dashboard.example.com â†’ 192.168.1.213:5000 (Web app)
      â””â”€ ...
```

**Docker inside VMs** (e.g., Plex on 192.168.1.210) listens on ports and is accessible via Traefik.

---

## HA Configuration (Proxmox HA)

### Groups

Create a Proxmox HA group called `homelab`:

```bash
ha-manager groupadd homelab --nodes pve-node1,pve-node2
```

### HA Resources

Add VMs and LXCs to the group:

```bash
# VMs â€“ HA failover with live migrate
ha-manager add vm:101 --group homelab --state started
ha-manager add vm:102 --group homelab --state started
ha-manager add vm:103 --group homelab --state started
ha-manager add vm:104 --group homelab --state started

# LXCs â€“ HA failover (cold restart)
ha-manager add ct:240 --group homelab --state started  # Prometheus
```

**Not in HA:**
- PiHole #1 and #2 (active-active, no need for HA restart)
- PBS (single, no HA needed)

### HA Behaviour on Node Failure

**Scenario:** pve-node1 fails

1. Watchdog detects failure (~60 seconds)
2. Node fenced by cluster quorum
3. HA restarts all resources from that node on pve-node2
4. Total downtime: ~2â€“3 minutes

**Scenario:** Planned maintenance (e.g., Proxmox updates)

1. Migrate all VMs off node with `qm migrate â€¦ --online`
2. Shut down LXCs cleanly
3. Update node
4. Reboot node
5. Optionally rebalance workloads

---

## Live Migration (Zero Downtime)

Live migration is supported **for VMs only**, not LXCs.

### Example: Migrate Plex VM during Proxmox update

```bash
# From node1, move Plex to node2 (no downtime)
qm migrate 101 pve-node2 --online

# Monitor progress
watch -n 1 'qm status 101'

# Once done, Plex continues on node2 without disruption
```

### Not applicable for LXCs

LXC migration requires downtime:

```bash
pct stop 240    # Stop Prometheus
pct migrate 240 pve-node2
pct start 240   # Start on node2
```

---

## DNS & DHCP Strategy

### PiHole Active-Active

Both PiHole LXCs are independent and identical.

**DHCP Configuration:**

```text
DHCP server hands out:
- DNS1: 192.168.1.192 (PiHole #1)
- DNS2: 192.168.1.193 (PiHole #2)
```

**Gravity Sync:**

Keeps both PiHole databases in sync:
- Custom DNS records
- Whitelists/blacklists
- Group assignments

```bash
# On PiHole #1 (or both)
gravity-sync pull  # Pull from remote
gravity-sync push  # Push to remote
```

**Failure scenarios:**

- PiHole #1 down â†’ DNS via PiHole #2 (automatic, no action needed)
- PiHole #2 down â†’ DNS via PiHole #1 (automatic)
- Both down â†’ No DNS (but HA can restart on remaining node)

---

## Storage & HA Implications

All LXCs and VMs use **shared ZFS storage** (replicated between nodes).

**Why this matters for HA:**

- If node1 fails and node2 is still running, HA can restart VMs/LXCs because data is on the shared pool.
- Live migration works because data doesn't move, only the VM context moves.

---

## Backup Strategy

### Proxmox Backup Server (PBS)

- Runs in LXC (192.168.10.250)
- Stores backups on NAS NFS
- Backs up all VMs and LXCs daily

**Retention:**
- Daily: Keep 7 days
- Weekly: Keep 4 weeks
- Monthly: Keep 12 months

**Scheduling:**

```bash
# Via Proxmox Web UI or pvesm:
pvesm add dir backup-dir \
  --content images,rootdir \
  --path /mnt/pbs-datastore

# Backup jobs (in Proxmox):
# - All VMs: 2am daily
# - All LXCs: 3am daily
```

---

## Failover Testing (Checklist)

### Test 1: PiHole Failover

```bash
# On pve-node1, stop PiHole #1
pct stop 210

# Verify DNS still works (via PiHole #2)
nslookup google.com 192.168.1.193

# Restart PiHole #1
pct start 210
```

### Test 2: VM Live Migration

```bash
# Migrate Plex while streaming
qm migrate 101 pve-node2 --online

# From a client, verify Plex keeps playing (no interruption)
```

### Test 3: Node Failure Simulation

```bash
# On pve-node1, simulate watchdog timeout
# (Hard to do safely; instead, just monitor HA logs after a real failure)

# In Proxmox Web UI: Cluster â†’ HA Status
# Check logs for HA restart events
```

### Test 4: Manual VM Failover

```bash
# Simulate planned maintenance
ha-manager status

# See which node each resource is on
# Migrate all VMs off node1
for vmid in $(qm list | awk 'NR>1 {print $1}'); do
  qm migrate "$vmid" pve-node2 --online
done
```

---

## SLA Summary

| Service        | Downtime on Node Failure | Downtime on Planned Maintenance |
|----------------|--------------------------|--------------------------------|
| DNS (PiHole)   | None (active-active)     | None (manual migrate)           |
| Traefik        | ~2 min (HA failover)     | None (live migrate)             |
| Prometheus     | ~2 min (HA failover)     | ~1 min (cold migrate)           |
| PBS            | Acceptable (backups queue)| ~1 min (cold migrate)           |
| Plex           | ~2 min (HA failover)     | None (live migrate)             |
| Arr stack      | ~2 min (HA failover)     | None (live migrate)             |
| Downloads      | ~2 min (HA failover)     | None (live migrate)             |
| Web apps       | ~2 min (HA failover)     | None (live migrate)             |

---

## Configuration Files to Create

All decisions are implemented through:

1. **Proxmox cluster:**
   - `/etc/pve/nodes/` (auto-managed)
   - `/etc/pve/ha/` (HA config)

2. **LXC configs:**
   - `/etc/pve/lxc/210.conf` (PiHole #1)
   - `/etc/pve/lxc/211.conf` (PiHole #2)
   - etc.

3. **Gravity Sync (on PiHoles):**
   - `/etc/gravity-sync/gravity-sync.conf`

4. **Traefik (in LXC 212):**
   - `/opt/traefik/docker-compose.yml`
   - `/opt/traefik/traefik.yml`
   - `/opt/traefik/config.yml` (routers, services)

5. **Docker Compose (in VMs):**
   - `/opt/plex/docker-compose.yml`
   - `/opt/arr/docker-compose.yml`
   - etc.

---

## Summary

**Networking:** Bridge only, no macvlan.

**HA Strategy:** 
- Active-active DNS (no HA restart needed)
- HA failover for everything else (~2 min acceptable)
- Live migration for VMs during maintenance

**Placement:**
- Critical/lightweight infra â†’ LXC
- Applications/complex stacks â†’ VM

**Live migration:** VMs only (zero-downtime maintenance)

This design prioritizes **simplicity** and **reliability** over maximum uptime, which is appropriate for a homelab.

---

## Rollback / Decommission

If you want to remove HA:

```bash
ha-manager remove vm:101
ha-manager remove vm:102
ha-manager remove ct:240

ha-manager groupremove homelab
```

Services continue running but with no automatic failover.

To switch to macvlan (not recommended):

1. Reconfigure each host's network interface
2. Reconfigure each LXC/VM with macvlan
3. Re-add to HA
4. Test thoroughly
5. Accept that live migration may break

**Not worth it for homelab.**