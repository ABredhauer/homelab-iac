# Homelab Master Document Index

**Version:** 2.0  
**Date:** 2026-01-13  
**Status:** Ready for Implementation  
**Project:** Andrew Homelab â€“ Proxmox 2-Node Cluster + Container Migration  

---

## Quick Start

1. **Verify cluster health:** Check README for current Phase status.
2. **Understand architecture:** Review `ARCHITECTURE.md` and `NETWORK.md`.
3. **Implement Phase 4:** Follow `PHASE4-DEFINITION.md` (monitoring, power, patching).
4. **Implement Phase 5:** Follow `PHASE5-DEFINITION.md` (container migration, HA).
5. **Operate:** Use `AUTOMATED-PATCHING.md` and `TROUBLESHOOTING.md` for ongoing maintenance.

---

## Core Documents

| Document                           | Purpose                                      | Audience          |
|-----------------------------------|----------------------------------------------|-------------------|
| `README.md`                       | Top-level overview and current status        | Everyone          |
| `docs/PHASE4-DEFINITION.md`       | Monitoring, power, patching (Phase 4)       | Implementers      |
| `docs/PHASE5-DEFINITION.md`       | Container migration & HA (Phase 5)          | Implementers      |
| `docs/AUTOMATED-PATCHING.md`      | Weekly/monthly update strategy               | Operators         |
| `docs/LXC-VM-HA-FINAL.md`         | HA & networking decisions (reference)       | Architects        |
| `docs/ARCHITECTURE.md`            | Overall design decisions                     | Architects        |
| `docs/NETWORK.md`                 | VLANs, IPs, addressing, routing              | Network admins    |
| `docs/CLUSTER-SETUP.md`           | Corosync, QDevice, cluster formation         | Implementers      |
| `docs/PHASE3-COMPLETE-FINAL.md`   | Storage & replication completion notes       | Reference         |
| `docs/PHASE-ROADMAP.md`           | Timeline, phases, and status                 | Project managers  |
| `docs/TROUBLESHOOTING.md`         | Known issues and fixes                       | Operators         |

---

## Document Overview

### README.md

**Top-level entry point.** Contains:
- Project status (Phase 3 complete, Phase 4 ready)
- Quick links to all docs
- Architecture diagram
- IP/hostname table
- Current problems & next steps

**Read this first.**

---

### docs/PHASE4-DEFINITION.md

**Monitoring, Power Management & Maintenance**

Covers Weeks 1â€“2 of implementation (28 hours):

1. **Native Monitoring** â€“ Proxmox Web UI, CLI, REST API
2. **Prometheus** â€“ Deploy in LXC 240, scrape Proxmox metrics, integrate with NAS Grafana
3. **Power Management (NUT)** â€“ Install NUT clients, configure 3-phase shutdown strategy
4. **Automated Patching** â€“ Ansible playbooks for LXC/VM updates, cron scheduling

**Success criteria:**
- Access Proxmox cluster health via Web UI and CLI
- Prometheus collecting metrics from both nodes
- NUT responding to simulated power loss
- Weekly update playbooks running automatically

**When to use:** Implement after Phase 3 is complete.

---

### docs/PHASE5-DEFINITION.md

**Container Migration & Workload Deployment**

Covers Weeks 3â€“6 of implementation (48 hours):

1. **Critical Infrastructure (LXC)**
   - PiHole x2 (active-active DNS)
   - Traefik (reverse proxy, HA failover)
   - PBS LXC (backups)

2. **Media Stack (Docker VMs)**
   - Plex with GPU passthrough
   - Arr stack (Sonarr, Radarr, etc.)
   - Downloads (VPN + Deluge/SABnzbd)
   - Web apps (MariaDB, Ombi, Organizr)

3. **HA & Testing**
   - Configure Proxmox HA groups
   - Test live migration
   - Test failover scenarios

**Success criteria:**
- All 22 containers running on cluster (not NAS)
- DNS works if either node fails
- External HTTPS access via Traefik
- HA restarts failed VMs automatically
- Live migration works without downtime

**When to use:** Implement after Phase 4 monitoring is stable.

---

### docs/AUTOMATED-PATCHING.md

**Patching & Update Strategy**

Reference for keeping cluster patched:

| Component        | Method                    | Frequency       |
|-----------------|---------------------------|-----------------|
| Proxmox hosts   | Rolling update script     | Monthly         |
| LXC containers  | Ansible playbook          | Weekly (Sun 3am)|
| Docker VMs      | Ansible playbook          | Weekly (Sun 3am)|
| Docker containers | Diun email notifications | As needed       |

Includes:
- Full rolling update script for Proxmox nodes
- Ansible playbooks for LXC and VM updates
- Cron job setup
- Testing procedures
- Rollback strategies

**When to use:** During Phase 4 implementation, then ongoing.

---

### docs/LXC-VM-HA-FINAL.md

**LXC vs VM â€“ HA, Networking & Migration**

Final architectural decisions:

**Placement:**
- **LXC:** PiHole x2, Traefik, PBS, Prometheus (lightweight infra)
- **VM:** Plex, Arr, Downloads, Web apps (complex stacks, GPU)

**Networking:**
- Bridge only (no macvlan) for simplicity + live migration
- Production VLAN: 192.168.1.0/24
- Management VLAN: 192.168.10.0/24

**HA:**
- Active-active DNS (no HA restart needed)
- HA failover (~2 min) for everything else
- Live migration (zero-downtime) for VMs during maintenance

**When to use:** Reference during Phase 5 implementation.

---

### docs/ARCHITECTURE.md

**Overall design decisions.**

Covers:
- Cluster topology (2Ã— Dell R620, shared ZFS storage, Raspberry Pi QDevice)
- NAS integration (NFS backups, media storage)
- UPS configuration (CyberPower PR1500ERT2U)
- Network topology and addressing
- HA strategy

---

### docs/NETWORK.md

**VLANs, IPs, and network addressing.**

Complete IP table:
- Management: 192.168.10.0/24
- Production: 192.168.1.0/24
- Docker internal: 172.20.0.0/16 (and per-VM subnets)

Router config:
- VLAN trunking
- Port forwarding (80, 443 to Traefik)
- DHCP ranges and DNS

---

### docs/CLUSTER-SETUP.md

**Proxmox cluster formation.**

How the cluster was built:
- Corosync configuration
- QDevice setup (Raspberry Pi)
- Quorum strategy
- Shared storage configuration
- Replication setup

**When to use:** Reference only (cluster already formed in Phase 3).

---

### docs/PHASE3-COMPLETE-FINAL.md

**Storage & Replication â€“ Completion Notes**

Recap of Phase 3 work:
- Local ZFS pools on each node
- PBS backups to NAS
- VM/LXC replication between nodes
- Snapshot strategy

**When to use:** Reference for understanding storage.

---

### docs/PHASE-ROADMAP.md

**Timeline and phase status.**

Overview of all phases:
- Phase 1â€“3: Provisioning & setup (COMPLETE)
- Phase 4: Monitoring & maintenance (READY, ~2 weeks)
- Phase 5: Container migration (READY, ~4â€“6 weeks)

Includes effort estimates and success criteria for each phase.

---

### docs/TROUBLESHOOTING.md

**Known issues and fixes.**

Common problems and solutions:
- Cluster quorum loss
- Node fence/recovery
- Storage issues
- NUT power events
- Ansible connection failures

**When to use:** When something goes wrong.

---

## Target Architecture (Visual)

```
â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”
â”‚                   Proxmox Cluster (Phase 5)                    â”‚
â”‚  â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â” â”‚
â”‚  â”‚              LXC Containers (Infrastructure)            â”‚ â”‚
â”‚  â”‚                                                          â”‚ â”‚
â”‚  â”‚  PiHole #1      PiHole #2      Traefik   Prometheus    â”‚ â”‚
â”‚  â”‚  192.168.1.192  192.168.1.193  192.168.1.194  192.168.10.240 â”‚
â”‚  â”‚  (node1)        (node2)        (node1)  (node1/2 HA)   â”‚ â”‚
â”‚  â”‚                                                          â”‚ â”‚
â”‚  â”‚              PBS (192.168.10.250, node1)                â”‚ â”‚
â”‚  â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜ â”‚
â”‚  â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â” â”‚
â”‚  â”‚         Docker VMs (Applications)                        â”‚ â”‚
â”‚  â”‚                                                          â”‚ â”‚
â”‚  â”‚  Plex VM        Arr VM          Downloads VM   Web VM   â”‚ â”‚
â”‚  â”‚  192.168.1.210  192.168.1.211   192.168.1.212  192.1.213 â”‚
â”‚  â”‚  (GPU, node1/2) (node1/2 HA)    (node1/2 HA)   (node1/2) â”‚ â”‚
â”‚  â”‚                                                          â”‚ â”‚
â”‚  â”‚  - Plex        - Sonarr         - VPN          - MariaDB  â”‚
â”‚  â”‚  - GPU /dev/dri - Radarr        - Deluge       - Ombi    â”‚
â”‚  â”‚  - Docker       - Prowlarr      - SABnzbd      - Organizrâ”‚
â”‚  â”‚                 - Bazarr        - Jackett               â”‚
â”‚  â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜ â”‚
â”‚                                                                 â”‚
â”‚  Storage: Shared ZFS (both nodes), replicated                  â”‚
â”‚  Backups: Daily via PBS to NAS                                 â”‚
â”‚  HA: Proxmox HA group "homelab" (VMs + Prometheus)            â”‚
â”‚  Networking: Bridge (vmbr0, vmbr1), no macvlan                â”‚
â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜

â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”                           â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”
â”‚   NAS        â”‚â—„â”€â”€â”€â”€â”€â”€â”€â”€ NFS â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â–ºâ”‚ PBS Datastore   â”‚
â”‚              â”‚        (backups)          â”‚ (LXC 250)       â”‚
â”‚ - Grafana    â”‚                           â”‚                 â”‚
â”‚ - NFS exportsâ”‚                           â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜
â”‚ - Media/DL   â”‚
â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜

â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”
â”‚ Raspberry Pi â”‚  UPS (CyberPower 1500VA)
â”‚ - QDevice    â”‚  - NUT server
â”‚ - NUT server â”‚  - Power monitoring
â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜
```

---

## Phase Status

### âœ… Phase 1â€“3: COMPLETE

- Proxmox cluster formed (2Ã— node)
- Corosync quorum (with QDevice)
- Shared ZFS storage configured
- PBS setup and backups working
- Replication between nodes verified

### ðŸŸ¡ Phase 4: READY (In Progress or Next)

**Monitoring, Power Management & Maintenance**

- [ ] Deploy Prometheus LXC 240
- [ ] Configure NUT clients for power management
- [ ] Create Ansible playbooks for patching
- [ ] Test all alert/failover scenarios

**Timeline:** 2 weeks (28 hours)

### ðŸŸ¡ Phase 5: READY (After Phase 4)

**Container Migration & HA**

- [ ] Migrate PiHole to LXC (x2, active-active)
- [ ] Migrate Traefik to LXC
- [ ] Migrate PBS LXC
- [ ] Migrate Plex VM with GPU passthrough
- [ ] Migrate Arr stack VM
- [ ] Migrate Download clients VM
- [ ] Migrate web apps VM
- [ ] Configure HA groups
- [ ] Test live migration and failover

**Timeline:** 4â€“6 weeks (48 hours)

---

## Implementation Roadmap

### Week 1â€“2 (Phase 4, Week 1)
- Deploy Prometheus LXC
- Configure native Proxmox monitoring
- Setup email alerts

### Week 2â€“3 (Phase 4, Week 2)
- Install NUT clients
- Configure 3-phase shutdown strategy
- Create Ansible playbooks
- Schedule cron jobs

### Week 4â€“5 (Phase 5, Week 1â€“2)
- Migrate PiHole x2
- Migrate Traefik
- Verify DNS and reverse proxy working

### Week 6â€“7 (Phase 5, Week 3â€“4)
- Migrate Plex with GPU
- Migrate Arr stack
- Configure docker-compose files

### Week 8 (Phase 5, Week 5)
- Migrate downloads and web apps
- Configure all Docker services

### Week 9 (Phase 5, Week 6)
- Configure Proxmox HA
- Test live migration
- Test failover scenarios
- Decommission NAS containers (optional)

---

## How to Use This Repo

### For New Implementation

1. Start with **README.md** â€“ understand current status
2. Read **docs/ARCHITECTURE.md** â€“ understand design
3. Follow **docs/PHASE4-DEFINITION.md** â€“ implement monitoring (2 weeks)
4. Follow **docs/PHASE5-DEFINITION.md** â€“ implement containers (4â€“6 weeks)
5. Reference **docs/AUTOMATED-PATCHING.md** â€“ setup maintenance

### For Daily Operations

- **Patching:** Follow `AUTOMATED-PATCHING.md` weekly schedule
- **Issues:** Check `TROUBLESHOOTING.md`
- **Changes:** Update `README.md` with new status
- **Backups:** Monitor `PBS` via Web UI daily

### For Planned Maintenance

- **Host update:** Use rolling-update.sh (Phase 4 doc)
- **VM maintenance:** Use `qm migrate --online` (zero downtime)
- **LXC maintenance:** Plan for ~30s downtime

---

## Key Decisions Summary

| Decision          | Choice                      | Why                           |
|-----------------|----------------------------|-------------------------------|
| LXC vs VM       | LXC for infra, VMs for apps | Simplicity + live migration  |
| Networking      | Bridge only (no macvlan)    | Simplicity + live migration  |
| HA              | Proxmox HA groups           | Native, built-in failover    |
| DNS             | PiHole x2 active-active     | No single point of failure   |
| Backups         | PBS to NAS NFS              | Off-site, easy recovery      |
| Updates         | Ansible weekly + manual/mo  | Automated but controlled     |

---

## Success Criteria (End of Phase 5)

- âœ… All 22 containers running on Proxmox (not NAS)
- âœ… DNS continues if either node fails
- âœ… Traefik routes HTTPS without downtime
- âœ… Proxmox HA restarts failed services automatically
- âœ… Live migration works for VMs (zero downtime)
- âœ… Weekly Ansible updates running without manual intervention
- âœ… Daily backups to PBS from Proxmox
- âœ… No single point of failure for critical services

---

## Maintenance Checklist (After Phase 5)

### Daily
- [ ] Check Proxmox cluster status (Web UI or `pvecm status`)
- [ ] Verify all VMs/LXCs are running
- [ ] Check PBS for backup completion

### Weekly
- [ ] Monitor Ansible update logs (`/var/log/ansible-*.log`)
- [ ] Check Prometheus metrics (Grafana)
- [ ] Verify PiHole/DNS working

### Monthly
- [ ] Run Proxmox rolling updates (script or manual)
- [ ] Review Proxmox logs for warnings
- [ ] Test one PBS restore (from backup)

### Quarterly
- [ ] Full cluster failover test
- [ ] Review and update Gravity Sync configs
- [ ] Audit Traefik routes and certificates

---

## Support & Rollback

### If Phase 4 goes wrong:

- Stop Prometheus LXC: `pct stop 240`
- Remove NUT configs: `systemctl stop nut-client && apt remove nut-client`
- Remove cron jobs: `crontab -e`
- Cluster continues operating normally

### If Phase 5 goes wrong:

- Containers continue on NAS (keep running during migration)
- Traefik/DNS can point back to NAS if cluster unstable
- HA can be disabled: `ha-manager groupremove homelab`
- Restore from PBS if data corruption

---

## Next Steps

1. **Now:** Read `README.md` for current status
2. **This week:** Review `PHASE4-DEFINITION.md` 
3. **Next week:** Start Phase 4 implementation
4. **In 2 weeks:** Begin Phase 5 container migration

Questions? Check `TROUBLESHOOTING.md` or review the relevant phase document.

---

## Document Relationships

```
README.md (start here)
â”œâ”€ ARCHITECTURE.md (understand design)
â”œâ”€ NETWORK.md (understand IPs)
â”œâ”€ CLUSTER-SETUP.md (understand how cluster built)
â”œâ”€ PHASE3-COMPLETE-FINAL.md (understand storage)
â””â”€ PHASE-ROADMAP.md (understand timeline)

Phase 4 â†’ PHASE4-DEFINITION.md
â”œâ”€ Includes: AUTOMATED-PATCHING.md
â””â”€ Enables: Phase 5

Phase 5 â†’ PHASE5-DEFINITION.md
â”œâ”€ Depends on: LXC-VM-HA-FINAL.md
â”œâ”€ Depends on: NETWORK.md
â””â”€ Results in: Full cluster with all containers

Ongoing â†’ AUTOMATED-PATCHING.md + TROUBLESHOOTING.md
```

---

## Revision History

| Version | Date       | Changes                                 |
|---------|------------|----------------------------------------|
| 1.0     | 2025-12-XX | Initial homelab setup (Phase 1â€“3)      |
| 2.0     | 2026-01-13 | Phase 4â€“5 planning, HA strategy, docs  |

---

**Last Updated:** 2026-01-13  
**Maintained by:** Andrew (Homelab Admin)  
**Repo:** https://github.com/ABredhauer/homelab-iac