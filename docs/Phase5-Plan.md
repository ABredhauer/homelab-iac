# Phase 5: Container Migration & Workload Deployment

**Version:** 2.0  
**Date:** 2026-01-13  
**Status:** Ready for Implementation  
**Duration:** 4-6 weeks  
**Effort:** 48 hours  

---

## Overview

Phase 5 migrates **22 Docker containers** from NAS to Proxmox cluster. This is the culmination of all previous phases:

- Phase 1: Nodes provisioned âœ“
- Phase 2: Cluster formed âœ“
- Phase 3: Storage configured âœ“
- Phase 4: Monitoring + power management + patching established âœ“
- **Phase 5: Workloads deployed** â† We are here

**Why this phase matters:** This phase achieves the primary goal: **move critical services (PiHole, Traefik) to HA infrastructure and offload the NAS from running containers.**

---

## Goals

### Primary Goals

1. **Deploy Critical Infrastructure (LXC, Active-Active HA)**
   - 2x PiHole (one per node, synced via Gravity Sync)
   - 1x Traefik (single instance with Proxmox HA failover, ~2 min acceptable downtime)
   - Zero downtime for DNS, acceptable brief downtime for reverse proxy

2. **Deploy Media Stack (Docker VMs, Automatic HA Failover)**
   - Plex Server (hardware transcoding)
   - Sonarr, Radarr, Prowlarr, Bazarr (Arr stack)
   - Ombi, Organizr (user-facing apps)
   - MariaDB (database for Ombi)

3. **Deploy Download Clients (Docker VM, No HA)**
   - VPN client + Deluge (network namespace)
   - SABnzbd, Jackett

4. **Deploy Infrastructure Services**
   - Proxmox Backup Server (LXC on cluster, NFS-backed storage on NAS)
   - Semaphore (optional: migrate or keep on NAS)
   - iVentoy (optional: migrate or keep on NAS)

5. **Enable Proxmox HA**
   - All Docker VMs protected by automatic failover
   - ~2 minute downtime if node fails
   - Live migration for planned maintenance (zero downtime)

---

## Key Architecture Decisions

### LXC vs Docker VM vs Docker-in-LXC

**LXC Containers (5 total):**

| Service | Reason | HA Strategy |
|---------|--------|-------------|
| PiHole #1 | Simple DNS service, perfect for LXC | Active-active (with Gravity Sync) |
| PiHole #2 | Redundant DNS, synced | Active-active (with Gravity Sync) |
| Traefik | Reverse proxy, lightweight | HA failover (~2 min) |
| PBS | Backup server, LXC only | No HA (backups wait if cluster down) |
| Prometheus | Metrics collection | HA failover (~2 min) |

**Docker VMs (4 total):**

| VM | Services | CPU | RAM | Node | HA |
|----|----------|-----|-----|------|-----|
| VM 101 | Plex Server | 4 | 4GB | node1 | HA failover |
| VM 102 | Arr Stack | 4 | 6GB | node2 | HA failover |
| VM 103 | Download Clients | 2 | 2GB | node1 | HA failover |
| VM 104 | Web Apps | 2 | 3GB | node2 | HA failover |

**Why this split:**
- **LXC for critical DNS:** Lightweight, fast restart, direct network access
- **VMs for complex stacks:** Existing docker-compose compatibility, hardware passthrough (Plex), easier backup/restore
- **Active-active DNS:** Zero downtime for critical service
- **HA failover for rest:** 1-2 min acceptable, live migrate for maintenance

### Networking: Bridge Mode (Not Macvlan)

**Why bridge mode?**
- **PiHole:** Gets direct LXC IP (192.168.1.192, 192.168.1.193)
- **Traefik:** Gets direct LXC IP (192.168.1.194)
- **Docker containers:** NAT'd inside VMs (172.20.0.x)
- **Access pattern:** External â†’ Traefik (port forward) â†’ Container (NAT via bridge)

**Why NOT macvlan?**
- Macvlan networks don't migrate with VMs between nodes
- Would require pre-configuring identical macvlan on both Proxmox nodes
- Bridge mode is simpler and "just works" with VM migration

**Example access flow:**

```
External: https://plex.bredhauer.net (your public IP)
  â†“
Cloudflare/Route53 â†’ Your public IP
  â†“
Your router port 443 â†’ 192.168.1.194 (Traefik LXC)
  â†“
Traefik â†’ http://192.168.1.210:32400 (Plex VM IP, port forward to container)
  â†“
Plex container (NAT'd IP: 172.20.0.2)
```

---

## HA & Failover Strategy

### Active-Active HA (Zero Downtime)

**PiHole x2 (DNS):**
```
Node1: pihole-200 (192.168.1.192)
Node2: pihole-201 (192.168.1.193)

DHCP server assigns both:
  Primary DNS: 192.168.1.192
  Secondary DNS: 192.168.1.193

Gravity Sync: Syncs blocklists hourly
  - Config stored in both LXCs
  - If node1 down: All DNS queries go to node2
  - If node2 down: All DNS queries go to node1
  
Behavior:
  - Node1 fails: DNS continues (zero downtime)
  - Node2 fails: DNS continues (zero downtime)
  - Both fail: Network unreachable (outside cluster scope)
```

### Automatic Failover HA (~2 minutes downtime)

**All Docker VMs (Plex, Arr, Download, Web apps):**

```
Proxmox HA Configuration:
ha-manager groupadd homelab --nodes pve-node1,pve-node2
ha-manager add vm:101 --group homelab --state started
ha-manager add vm:102 --group homelab --state started
ha-manager add vm:103 --group homelab --state started
ha-manager add vm:104 --group homelab --state started

Failover Process:
1. Node1 fails
2. HA manager detects failure (10 seconds)
3. HA fences failed node (60 second watchdog)
4. HA acquires lock on shared storage
5. HA starts VMs on node2 (60-120 seconds)
6. Docker containers start (30-60 seconds)
7. Total downtime: ~2-3 minutes

Behavior:
  - Services restart on healthy node
  - Data preserved (VMs on shared storage)
  - Network connections reset (short reconnect delay)
  - Acceptable for homelab workloads
```

### Live Migration for Planned Maintenance (Zero Downtime)

**Docker VMs only (VMs support live migration, LXCs don't):**

```
Planned Update of Node1:
1. Run: qm migrate 101 pve-node2 --online
2. VM memory transferred to node2 (~10-30 seconds)
3. VM IP/networks maintained
4. Applications experience no downtime
5. Node1 can now reboot safely
6. Post-update: Migrate VMs back to node1 for load balance

LXC Containers:
  - No live migration (must cold restart)
  - Shutdown: pct stop 200
  - Migrate: pct migrate 200 pve-node2
  - Start: pct start 200
  - Downtime: ~30 seconds
```

---

## Implementation Plan

### Week 1-2: Critical Infrastructure (LXC Containers)

#### Step 1: Deploy PiHole LXC Containers

**Create pihole-node1 (192.168.1.192):**

```bash
# On node1
pct create 200 local:vztmpl/ubuntu-24.04-standard_24.04-2_amd64.tar.zst \
  --hostname pihole-node1 \
  --memory 512 \
  --cores 1 \
  --storage local-zfs \
  --net0 name=eth0,bridge=vmbr0,ip=192.168.1.192/24,gw=192.168.1.1 \
  --features nesting=1

pct start 200
pct enter 200

# Install PiHole
curl -sSL https://install.pi-hole.net | bash

# Configure password
pihole -a -p <your_secure_password>
```

**Create pihole-node2 (192.168.1.193):**

```bash
# On node2
pct create 201 local:vztmpl/ubuntu-24.04-standard_24.04-2_amd64.tar.zst \
  --hostname pihole-node2 \
  --memory 512 \
  --cores 1 \
  --storage local-zfs \
  --net0 name=eth0,bridge=vmbr0,ip=192.168.1.193/24,gw=192.168.1.1 \
  --features nesting=1

pct start 201
pct enter 201

curl -sSL https://install.pi-hole.net | bash
pihole -a -p <same_password>
```

**Step 2: Configure Gravity Sync**

On pihole-node1:

```bash
# Install Gravity Sync
curl -sSL https://raw.githubusercontent.com/vmstan/gs-install/main/gs-install.sh | bash

# Configure
gravity-sync config
# Remote host: 192.168.1.193
# User: root
# SSH key: /root/.ssh/id_rsa (generate if needed)
# Pull: yes

# Initial sync
gravity-sync pull

# Add hourly cron job
echo "0 * * * * /usr/local/bin/gravity-sync auto" | crontab -
```

**Step 3: Test PiHole & Gravity Sync**

```bash
# From any device
nslookup google.com 192.168.1.192  # Should resolve
nslookup google.com 192.168.1.193  # Should resolve

# Verify sync working
ssh root@192.168.1.192 'gravity-sync status'
ssh root@192.168.1.193 'gravity-sync status'

# Simulate node1 failure
ssh root@192.168.1.192 'shutdown -h now'
# Wait 2 minutes
nslookup google.com 192.168.1.193  # Should still work
# Power on node1
qm start 200
```

**Step 4: Update DHCP Server**

Configure your RV320/pfSense DHCP:
```
Primary DNS:   192.168.1.192
Secondary DNS: 192.168.1.193
```

**Step 5: Migrate DNS from NAS**

```bash
# Export current PiHole config from NAS
docker exec pihole pihole -a -t > /tmp/pihole-backup.tar.gz

# Copy to pihole-node1
scp /tmp/pihole-backup.tar.gz root@192.168.1.192:/tmp/

# Import on pihole-node1
ssh root@192.168.1.192 'pihole -a -r /tmp/pihole-backup.tar.gz'

# Let Gravity Sync push to node2
ssh root@192.168.1.192 'gravity-sync push'

# Stop PiHole on NAS
docker-compose -f /volume1/docker/infrastructure/docker-compose.yml stop pihole
```

#### Step 6: Deploy Traefik LXC

**Create traefik-node1 (192.168.1.194):**

```bash
pct create 202 local:vztmpl/ubuntu-24.04-standard_24.04-2_amd64.tar.zst \
  --hostname traefik \
  --memory 512 \
  --cores 1 \
  --storage local-zfs \
  --net0 name=eth0,bridge=vmbr0,ip=192.168.1.194/24,gw=192.168.1.1 \
  --features nesting=1

pct start 202
pct enter 202

# Install Docker
apt-get update
apt-get install -y docker.io

# Mount NAS for shared SSL certs
mkdir -p /mnt/nas-shared
mount -t nfs 192.168.1.25:/volume1/homelab-shared /mnt/nas-shared

# Copy Traefik config from NAS
cp -r /mnt/nas-shared/traefik /opt/traefik

# Create docker-compose.yml
cat > /opt/traefik/docker-compose.yml << 'EOF'
version: '3'
services:
  traefik:
    image: traefik:latest
    container_name: traefik
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - /opt/traefik/traefik.yml:/etc/traefik/traefik.yml
      - /opt/traefik/acme.json:/acme.json
    environment:
      - AWS_ACCESS_KEY_ID=<your_cloudflare_key>
      - AWS_SECRET_ACCESS_KEY=<your_cloudflare_secret>
EOF

# Start Traefik
cd /opt/traefik
docker-compose up -d
```

**Step 7: Configure External DNS**

Update your DNS records (Cloudflare/Route53):

```
bredhauer.net A <your_public_ip>  # e.g., 203.0.113.45
*.bredhauer.net CNAME bredhauer.net
```

Configure router port forwarding:
```
External Port 80 â†’ 192.168.1.194:80 (HTTP, for Let's Encrypt)
External Port 443 â†’ 192.168.1.194:443 (HTTPS)
```

**Step 8: Enable HA for Traefik (Optional)**

```bash
# If you want automatic failover for Traefik
ha-manager add ct:202 --state started --max_restart 2 --max_relocate 2

# Note: 2 min failover acceptable for Traefik
# If you want higher availability, manually restart:
pct restart 202
```

**Step 9: Migrate Traefik from NAS**

```bash
# Stop Traefik on NAS
docker-compose -f /volume1/docker/infrastructure/docker-compose.yml stop traefik

# Verify DNS/HTTPS still working
curl -k https://traefik.bredhauer.net

# Configure internal services to use Traefik cluster IP
# (You'll do this in Phase 5 when deploying VMs)
```

#### Step 10: Deploy Proxmox Backup Server (PBS)

```bash
# Create PBS LXC on node1
pct create 203 local:vztmpl/debian-12-standard_12.7-1_amd64.tar.zst \
  --hostname pbs \
  --memory 2048 \
  --cores 2 \
  --storage local-zfs \
  --net0 name=eth0,bridge=vmbr1,ip=192.168.10.250/24,gw=192.168.10.1 \
  --features nesting=1

pct start 203
pct enter 203

# Install PBS
echo "deb http://download.proxmox.com/debian/pbs bookworm pbs-no-subscription" >> /etc/apt/sources.list.d/pbs.list
wget https://enterprise.proxmox.com/debian/proxmox-release-bookworm.gpg -O /etc/apt/trusted.gpg.d/proxmox-release-bookworm.gpg
apt update
apt install -y proxmox-backup-server

# Mount NAS for backup storage
mkdir -p /mnt/pbs-datastore
mount -t nfs 192.168.1.25:/volume1/homelab-backups /mnt/pbs-datastore

# Make permanent
echo "192.168.1.25:/volume1/homelab-backups /mnt/pbs-datastore nfs defaults,_netdev 0 0" >> /etc/fstab

# Create PBS datastore
proxmox-backup-manager datastore create backups /mnt/pbs-datastore

# Configure retention
proxmox-backup-manager datastore update backups \
  --keep-last 7 \
  --keep-weekly 4 \
  --keep-monthly 6
```

**Access PBS Web UI:** https://192.168.10.250:8007

---

### Week 3-4: Media Stack (Docker VMs)

#### Step 1: Create Plex Server VM

```bash
# On node1
qm create 101 --name plex-server \
  --memory 4096 \
  --cores 4 \
  --scsihw virtio-scsi-pci \
  --scsi0 local-zfs:32 \
  --net0 virtio,bridge=vmbr0 \
  --ostype l26 \
  --ide2 local-zfs:cloudinit \
  --boot c --bootdisk scsi0 \
  --ipconfig0 ip=192.168.1.210/24,gw=192.168.1.1 \
  --nameserver 192.168.1.192 \
  --sshkeys ~/.ssh/id_rsa.pub \
  --agent enabled=1

# Import cloud-init image
wget https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img -O /tmp/ubuntu-noble.img
qm importdisk 101 /tmp/ubuntu-noble.img local-zfs

# Update disk reference
qm set 101 --scsi0 local-zfs:vm-101-disk-0

# Start VM
qm start 101

# Wait for cloud-init
sleep 60

# SSH into VM
ssh ubuntu@192.168.1.210

# Install Docker
sudo apt-get update
sudo apt-get install -y docker.io docker-compose

# Create docker-compose.yml for Plex
mkdir /opt/plex
cat > /opt/plex/docker-compose.yml << 'EOF'
version: "3"

networks:
  default:
    driver: bridge
    ipam:
      config:
        - subnet: 172.20.0.0/16

services:
  plex-server:
    container_name: plex-server
    image: plexinc/pms-docker:latest
    restart: unless-stopped
    environment:
      - PLEX_UID=1000
      - PLEX_GID=1000
      - TZ=Australia/Brisbane
    devices:
      - /dev/dri:/dev/dri  # Hardware transcoding
    volumes:
      - /opt/plex/config:/config
      - /opt/plex/transcode:/transcode
      - /mnt/media:/data
    ports:
      - "32400:32400"
EOF

# Mount NAS media
sudo mkdir -p /mnt/media
sudo mount -t nfs 192.168.1.25:/volume2/media /mnt/media
echo "192.168.1.25:/volume2/media /mnt/media nfs defaults 0 0" | sudo tee -a /etc/fstab

# Migrate Plex config from NAS
rsync -avz admin@192.168.1.25:/volume1/docker/ht-pc/config/plex/ /opt/plex/config/

# Start Plex
cd /opt/plex
docker-compose up -d

# Claim server
# Visit: http://192.168.1.210:32400
# Claim with Plex account
```

#### Step 2: Create Arr Stack VM

```bash
# On node2
qm create 102 --name arr-stack \
  --memory 6144 \
  --cores 4 \
  --scsihw virtio-scsi-pci \
  --scsi0 local-zfs:32 \
  --net0 virtio,bridge=vmbr0 \
  --ostype l26 \
  --ide2 local-zfs:cloudinit \
  --boot c --bootdisk scsi0 \
  --ipconfig0 ip=192.168.1.211/24,gw=192.168.1.1 \
  --nameserver 192.168.1.192 \
  --sshkeys ~/.ssh/id_rsa.pub \
  --agent enabled=1

# Import cloud-init image
qm importdisk 102 /tmp/ubuntu-noble.img local-zfs
qm set 102 --scsi0 local-zfs:vm-102-disk-0

# Start VM
qm start 102

# Install Docker and Arr stack
ssh ubuntu@192.168.1.211
sudo apt-get update
sudo apt-get install -y docker.io docker-compose

# Create docker-compose.yml (sonarr, radarr, prowlarr, bazarr, jackett)
mkdir /opt/arr
cat > /opt/arr/docker-compose.yml << 'EOF'
version: "3"

networks:
  default:
    driver: bridge
    ipam:
      config:
        - subnet: 172.20.0.0/16

services:
  sonarr:
    image: linuxserver/sonarr:latest
    container_name: sonarr
    ports:
      - "8989:8989"
    # ... full config from your existing compose

  radarr:
    image: linuxserver/radarr
    container_name: radarr
    ports:
      - "7878:7878"
    # ... full config

  prowlarr:
    image: lscr.io/linuxserver/prowlarr:develop
    container_name: prowlarr
    ports:
      - "9696:9696"
    # ... full config

  bazarr:
    image: linuxserver/bazarr
    container_name: bazarr
    ports:
      - "6767:6767"
    # ... full config

  jackett:
    image: linuxserver/jackett:latest
    container_name: jackett
    ports:
      - "9117:9117"
    # ... full config
EOF

# Mount NAS media and downloads
sudo mkdir -p /mnt/media /mnt/downloads
sudo mount -t nfs 192.168.1.25:/volume2/media /mnt/media
sudo mount -t nfs 192.168.1.25:/volume1/docker/ht-pc/downloads /mnt/downloads

# Add to fstab
echo "192.168.1.25:/volume2/media /mnt/media nfs defaults 0 0" | sudo tee -a /etc/fstab
echo "192.168.1.25:/volume1/docker/ht-pc/downloads /mnt/downloads nfs defaults 0 0" | sudo tee -a /etc/fstab

# Migrate configs from NAS
rsync -avz admin@192.168.1.25:/volume1/docker/ht-pc/config/ /opt/arr/config/

# Start stack
cd /opt/arr
docker-compose up -d
```

#### Step 3: Verify Plex & Arr Stack

```bash
# Test Plex
http://192.168.1.210:32400

# Test Arr apps
http://192.168.1.211:8989  # Sonarr
http://192.168.1.211:7878  # Radarr
http://192.168.1.211:9696  # Prowlarr
http://192.168.1.211:6767  # Bazarr
http://192.168.1.211:9117  # Jackett
```

---

### Week 5: Download Clients & Web Apps (Docker VMs)

#### Step 1: Create Download Clients VM

```bash
# On node1
qm create 103 --name download-clients \
  --memory 2048 \
  --cores 2 \
  --scsihw virtio-scsi-pci \
  --scsi0 local-zfs:32 \
  --net0 virtio,bridge=vmbr0 \
  --ostype l26 \
  --ide2 local-zfs:cloudinit \
  --boot c --bootdisk scsi0 \
  --ipconfig0 ip=192.168.1.212/24,gw=192.168.1.1 \
  --nameserver 192.168.1.192 \
  --sshkeys ~/.ssh/id_rsa.pub \
  --agent enabled=1

# Install Docker and deploy VPN/Deluge/SABnzbd
ssh ubuntu@192.168.1.212
sudo apt-get install -y docker.io docker-compose

# Create docker-compose.yml (vpn, deluge, sabnzbd)
mkdir /opt/downloads
cat > /opt/downloads/docker-compose.yml << 'EOF'
# Copy your existing ht-pc compose, adapt for bridge networking
version: "3"

networks:
  default:
    driver: bridge

services:
  vpn:
    image: dperson/openvpn-client:latest
    # ... full config

  deluge:
    image: linuxserver/deluge:latest
    network_mode: service:vpn
    # ... full config

  sabnzbd:
    image: linuxserver/sabnzbd
    # ... full config
EOF

# Mount downloads
sudo mkdir -p /mnt/downloads
sudo mount -t nfs 192.168.1.25:/volume1/docker/ht-pc/downloads /mnt/downloads

# Start
cd /opt/downloads
docker-compose up -d
```

#### Step 2: Create Web Apps VM

```bash
# On node2
qm create 104 --name web-apps \
  --memory 3072 \
  --cores 2 \
  --scsihw virtio-scsi-pci \
  --scsi0 local-zfs:32 \
  --net0 virtio,bridge=vmbr0 \
  --ostype l26 \
  --ide2 local-zfs:cloudinit \
  --boot c --bootdisk scsi0 \
  --ipconfig0 ip=192.168.1.213/24,gw=192.168.1.1 \
  --nameserver 192.168.1.192 \
  --sshkeys ~/.ssh/id_rsa.pub \
  --agent enabled=1

# Install Docker and deploy Ombi/Organizr/MariaDB
ssh ubuntu@192.168.1.213
sudo apt-get install -y docker.io docker-compose

mkdir /opt/web-apps
cat > /opt/web-apps/docker-compose.yml << 'EOF'
version: "3"

services:
  mariadb:
    image: linuxserver/mariadb
    container_name: mariadb
    environment:
      - MYSQL_ROOT_PASSWORD=<secure_password>
    volumes:
      - /opt/web-apps/mariadb:/config
    ports:
      - "3306:3306"

  ombi:
    image: linuxserver/ombi:development
    container_name: ombi
    depends_on:
      - mariadb
    environment:
      - PUID=1000
      - PGID=1000
      - TZ=Australia/Brisbane
    volumes:
      - /opt/web-apps/ombi:/config
    ports:
      - "3579:3579"

  organizr:
    image: organizr/organizr
    container_name: organizr
    environment:
      - PUID=1000
      - PGID=1000
      - TZ=Australia/Brisbane
    volumes:
      - /opt/web-apps/organizr:/config
    ports:
      - "8000:80"
EOF

# Migrate configs
rsync -avz admin@192.168.1.25:/volume1/docker/ht-pc/config/mariadb/ /opt/web-apps/mariadb/
rsync -avz admin@192.168.1.25:/volume1/docker/ht-pc/config/ombi/ /opt/web-apps/ombi/
rsync -avz admin@192.168.1.25:/volume1/docker/ht-pc/config/organizr/ /opt/web-apps/organizr/

# Start
cd /opt/web-apps
docker-compose up -d
```

---

### Week 6: Enable HA & Testing

#### Step 1: Enable Proxmox HA for Docker VMs

```bash
# On node1
ha-manager groupadd homelab --nodes pve-node1,pve-node2

ha-manager add vm:101 --group homelab --state started --max_restart 2 --max_relocate 2  # Plex
ha-manager add vm:102 --group homelab --state started --max_restart 2 --max_relocate 2  # Arr
ha-manager add vm:103 --group homelab --state started --max_restart 2 --max_relocate 2  # Downloads
ha-manager add vm:104 --group homelab --state started --max_restart 2 --max_relocate 2  # Web Apps

# Verify HA status
ha-manager status
```

#### Step 2: Test Live Migration (Zero Downtime)

```bash
# While VM running, migrate to other node
qm migrate 101 pve-node2 --online

# Watch migration progress
pvesh get /nodes/pve-node1/qemu/101/status/current | jq .

# Should see brief pause (<10 sec), then running on pve-node2
qm list | grep 101
```

#### Step 3: Test Failover (Planned)

```bash
# Shutdown node1 (simulated failure)
ssh root@pve-node1 'shutdown -h now'

# Watch HA restart VMs on node2
# Takes ~2-3 minutes
ha-manager status

# Verify services still accessible
# Plex, Arr, Downloads, Web Apps should restart on node2

# Power on node1
qm start 100  # Boot node1 (requires physical access or IPMI)

# Wait for cluster rejoin
pvecm status
```

#### Step 4: Configure Static DHCP Reservations

Ensure VMs always get same IPs (or use static IPs):

On your router/DHCP:
```
192.168.1.210: Plex VM (MAC address)
192.168.1.211: Arr VM (MAC address)
192.168.1.212: Download Clients VM (MAC address)
192.168.1.213: Web Apps VM (MAC address)
```

#### Step 5: Update Traefik Service Routes

In Traefik config, update backend targets:

```yaml
# Instead of:
# http://192.168.1.210:32400 (old Plex on NAS)

# Use:
# http://192.168.1.210:32400 (new Plex on cluster VM 101)

# Services automatically accessible because VMs have same IPs
```

#### Step 6: Final Testing

```bash
# Test all services accessible
curl https://plex.bredhauer.net
curl https://ombi.bredhauer.net
curl https://organizr.bredhauer.net

# Test DNS (should be zero downtime)
nslookup google.com 192.168.1.192
nslookup google.com 192.168.1.193

# Test reverse proxy
curl -k https://traefik.bredhauer.net

# Monitor Prometheus for metrics
http://192.168.1.25:3000  # Grafana

# Check PBS backups running
https://192.168.10.250:8007
```

---

## Deployment Order (Critical)

**DO NOT deviate from this order:**

1. âœ“ **PiHole first** - Establish DNS infrastructure
2. âœ“ **Traefik second** - Reverse proxy for external access
3. âœ“ **PBS third** - Backup before moving other services
4. âœ“ **Plex fourth** - Largest/most important media service
5. âœ“ **Arr stack fifth** - Depends on Plex
6. âœ“ **Download clients sixth** - Depends on Arr
7. âœ“ **Web apps last** - Least critical

**Rationale:** Ensures foundational services work before deploying dependencies.

---

## Success Criteria

All of the following must be true:

### Critical Infrastructure
- [ ] 2x PiHole running, both responsive to DNS queries
- [ ] DNS continues working if either node fails
- [ ] Gravity Sync syncing blocklists between nodes
- [ ] Traefik accessible from external network
- [ ] Reverse proxy routing correctly (internal services)

### Media Stack
- [ ] Plex accessible and streaming media
- [ ] Sonarr, Radarr, Prowlarr operational
- [ ] Bazarr downloading subtitles
- [ ] Jackett returning search results

### Download Clients
- [ ] VPN connected (if configured)
- [ ] Deluge downloading via VPN
- [ ] SABnzbd downloading usenet

### Web Applications
- [ ] Ombi accepting requests
- [ ] Organizr dashboard accessible
- [ ] MariaDB running (for Ombi)

### High Availability
- [ ] Proxmox HA enabled for all VMs
- [ ] VMs restart on node failure (<2 min downtime)
- [ ] Live migration works (zero downtime planned maintenance)
- [ ] Load balanced across nodes (VMs distributed)

### Monitoring & Backups
- [ ] Prometheus scraping cluster metrics
- [ ] Grafana dashboards showing container health
- [ ] PBS running daily backups at 2am
- [ ] Backup retention policy working (keep last 7, weekly 4, monthly 6)

### Services Migrated from NAS
- [ ] PiHole: Stopped on NAS, running on cluster
- [ ] Traefik: Stopped on NAS, running on cluster
- [ ] Media stack: Stopped on NAS, running on cluster
- [ ] Download clients: Stopped on NAS, running on cluster
- [ ] Web apps: Stopped on NAS, running on cluster
- [ ] âœ“ Still on NAS (for later migration): Semaphore, iVentoy, InfluxDB, Grafana

---

## Networking Reference

### VLANs

| VLAN | Range | Purpose | Notes |
|------|-------|---------|-------|
| VLAN1 | 192.168.1.0/24 | Production | Container services, user-facing |
| VLAN2 | 192.168.10.0/24 | Management | Proxmox nodes, Ansible, monitoring |

### Static IPs Allocated

| IP | Service | Type | Node |
|----|---------|------|------|
| 192.168.1.192 | PiHole #1 | LXC | node1 |
| 192.168.1.193 | PiHole #2 | LXC | node2 |
| 192.168.1.194 | Traefik | LXC | node1 |
| 192.168.1.210 | Plex VM | VM | node1 |
| 192.168.1.211 | Arr Stack VM | VM | node2 |
| 192.168.1.212 | Download VM | VM | node1 |
| 192.168.1.213 | Web Apps VM | VM | node2 |
| 192.168.10.240 | Prometheus | LXC | node1 |
| 192.168.10.250 | PBS | LXC | node1 |

### Container-Internal IPs (NAT'd)

| Service | Range | Purpose |
|---------|-------|---------|
| Plex VM | 172.20.0.0/16 | Docker bridge in Plex VM |
| Arr VM | 172.20.0.0/16 | Docker bridge in Arr VM |
| Download VM | 172.20.0.0/16 | Docker bridge in Download VM |
| Web Apps VM | 172.20.0.0/16 | Docker bridge in Web Apps VM |

---

## Rollback Plan

If migration fails:

1. **Keep services on NAS** - Start all containers on NAS
2. **Revert DNS** - Update DHCP to point to NAS PiHole IP
3. **Revert reverse proxy** - Update external DNS to NAS IP
4. **Delete failed VMs** - `qm destroy 101 102 103 104`
5. **Delete failed LXCs** - `pct destroy 200 201 202 203`
6. **Restore from PBS** - If needed

**All migrations are reversible with minimal downtime.**

---

## Maintenance After Phase 5

### Weekly (Automated, Sunday 3am)
- Ansible updates LXC containers
- Ansible updates Docker VM host OS
- Containers/VMs may reboot if needed

### Monthly (Manual, First Saturday)
- Rolling update Proxmox hosts
- Review Diun emails for container updates

### Daily (Automated, 2am)
- PBS backs up all LXCs and VMs
- Backups retained per policy (7 daily, 4 weekly, 6 monthly)

---

## Timeline

| Week | Task | Hours |
|------|------|-------|
| 1-2 | PiHole, Traefik, PBS | 16 |
| 3-4 | Plex, Arr Stack | 16 |
| 5 | Download Clients, Web Apps | 8 |
| 6 | HA, Testing, Verification | 8 |
| **Total** | | **48 hours** |

At 2 hours/day = 24 days (~6 weeks)

---

## Next Steps

After Phase 5 completion:
- **Phase 6:** Advanced monitoring (container metrics, log aggregation with Loki)
- **Phase 7:** Kubernetes for learning (optional, separate from this homelab)
- **Phase 8:** Windows Server deployment (for learning)

---

## References

- [Proxmox HA Manager](https://pve.proxmox.com/wiki/High_Availability)
- [PiHole Documentation](https://docs.pi-hole.net/)
- [Gravity Sync](https://github.com/vmstan/gravity-sync)
- [Traefik Documentation](https://doc.traefik.io/traefik/)
- [Proxmox Backup Server](https://pve.proxmox.com/wiki/Proxmox_Backup_Server)