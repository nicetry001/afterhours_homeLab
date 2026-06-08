# 🏠 AfterHours HomeLab

> Infrastructure-as-code homelab running on Proxmox VE, managed entirely with Terraform.

---

## 📋 Table of Contents

- [Architecture Overview](#️-architecture-overview)
- [Infrastructure Layers](#-infrastructure-layers)
- [Docker Services Reference](#-docker-services-reference)
- [Network Topology](#-network-topology)
- [Getting Started](#-getting-started)
- [Secret Management](#-secret-management)
- [Adding New Stacks](#-adding-new-stacks)
- [Repository Structure](#-repository-structure)
- [Security Notes](#️-security-notes)
- [Tech Stack Summary](#️-tech-stack-summary)

---

## 🏗️ Architecture Overview

```text
┌────────────────────────────────────────────────────────────────────────────┐
│                        PROXMOX VE HYPERVISOR (sproxmox01)                  │
│                                                                            │
│  ┌─────────────────┐             ┌──────────────────┐                      │
│  │   Home Router   │────────────►│      vmbr0       │                      │
│  │  192.168.1.1    │             │  (192.168.1.169) │                      │
│  └─────────────────┘             └────────┼─────────┘                      │
│                                           │                                │
│  ┌────────────────────────────────────────▼─────────────────────────────┐  │
│  │ Proxmox SDN zone: backend | vnet0 Subnet: 10.6.7.0/24 | GW: 10.6.7.1 │  │
│  └────────┬──────────────────────┬──────────────────────┬───────────────┘  │
│           │                      │                      │                  │
│  ┌────────▼─────────┐   ┌────────▼─────────┐   ┌────────▼─────────┐        │
│  │  lxc-pihole01    │   │ lxc-tailscale01  │   │   vm-hermes01    │        │
│  │  ID: 200 (LXC)   │   │ ID: 201 (LXC)    │   │   ID: 100 (VM)   │        │
│  │  192.168.1.171   │   │ 192.168.1.172    │   │   192.168.1.173  │        │
│  │  10.6.7.171      │   │ 10.6.7.172       │   │   10.6.7.173     │        │
│  └──────────────────┘   └────────┼─────────┘   └──────────────────┘        │
│                                  │                                         │
│  ┌───────────────────────────────▼──────────────────────────────────────┐  │
│  │ vm-docker01 (ID 101) | 192.168.1.170 / 10.6.7.170                    │  │
│  │ 8 vCPU / 16 GB RAM / Ubuntu 26.04 Server (AMD iGPU Passthrough)      │  │
│  ├──────────────────────────────────────────────────────────────────────┤  │
│  │  DOCKER ENGINE RUNTIME CONTAINER STACKS                              │  │
│  │                                                                      │  │
│  │  [ AI & LLM PLATFORMS ]     [ MEDIA SERVER (ARR) ]  [ OBSERVABILITY ]│  │
│  │  • Dify Web / API / Worker   • Jellyfin Media Server • Prometheus    │  │
│  │  • Langfuse API / Worker     • Sonarr / Radarr / qBit• Grafana       │  │
│  │  • Flowise Visual Builder   • Prowlarr / Bazarr     • cAdvisor       │  │
│  │  • Headless Browserless      • Seerr / Suggestarr    • Node Exporter │  │
│  │                                                                      │  │
│  │  [ WORKFLOW AUTOMATION ]     [ SECURE ACCESS ]       [ MANAGEMENT ]  │  │
│  │  • n8n Engine                • Cloudflared Tunnel    • Portainer CE  │  │
│  │                                                      • NocoDB Engine │  │
│  └──────────────────────────────────────────────────────────────────────┘  │
└────────────────────────────────────────────────────────────────────────────┘

```

---

## 🧱 Infrastructure Layers

The homelab is organized into numbered Terraform modules that must be applied in order.

### Layer 01 — Core Network
**File:** `terraform/01-core-network/`

Provisions the Proxmox SDN isolated zone (`backend`) with a custom subnet so containers and VMs can talk to each other without polluting the main LAN.

```text
  SDN Zone       backend  (simple zone)
  vNET           vnet0
  Subnet         10.6.7.0/24
  Gateway        10.6.7.1
  DHCP Pool      10.6.7.100 – 10.6.7.200
  SNAT           Enabled
```

---

### Layer 02 — Docker Node
**File:** `terraform/02-docker-nodes/`

Provisions the primary compute VM from an Ubuntu 26.04 cloud image.

```text
  VM Name        vm-docker01
  VM ID          101
  IP (LAN)       192.168.1.170/24
  IP (SDN)       10.6.7.170/24
  vCPU           8  (host passthrough)
  RAM            16 GB
  Disk           100 GB  (local-lvm, raw)
  GPU            AMD iGPU passthrough  (Jellyfin HW encode)
  Boot           Starts on boot, auto Docker install
```

---

### Layer 03 — Pi-hole LXC
**File:** `terraform/03-pihole-lxc/`

Debian 13 LXC running Pi-hole for network-wide ad blocking and DNS filtering.

```text
  Container      lxc-pihole01
  VM ID          200
  IP (LAN)       192.168.1.171/24
  IP (SDN)       10.6.7.171/24
  vCPU           1
  RAM            512 MB + 512 MB swap
  Disk           8 GB

  Features:
    • Unprivileged LXC (kernel boundary isolation)
    • Pre-seeded unattended install
    • Gold-standard blocklists (HaGeZi Pro, Steven Black)
    • NTP sync disabled (Proxmox handles time)
```

---

### Layer 04 — Tailscale LXC
**File:** `terraform/04-tailscale-lxc/`

Debian 13 LXC running Tailscale as a subnet router, advertising home LAN routes for secure remote access.

```text
  Container      lxc-tailscale01
  VM ID          201
  IP (LAN)       192.168.1.172/24
  IP (SDN)       10.6.7.172/24
  vCPU           1
  RAM            512 MB + 512 MB swap
  Disk           4 GB

  Features:
    • Advertises 192.168.1.0/24 and 10.6.7.0/24 routes
    • Kernel IP forwarding in container namespace
    • Waits for /dev/net/tun (linked manually on Proxmox host)
```

---

### Layer 05 — Docker Stacks
**File:** `terraform/05-docker-stacks/`

The main application layer. All containers run on `vm-docker01` with a **3-tier Docker network architecture**:

```text
  net-frontend   →  User-facing services
  net-backend    →  Internal service-to-service
  net-database   →  Database-tier isolation
```

---

### Layer 06 — Hermes Agent
**File:** `terraform/06-hermes-agent/`

Dedicated VM for the native Hermes Agent — your AI assistant that lives inside this homelab.

```text
  VM Name        vm-hermes01
  VM ID          100
  IP (LAN)       192.168.1.173/24
  IP (SDN)       10.6.7.173/24
  vCPU           4
  RAM            4 GB
  Disk           50 GB
```

---

## 🐳 Docker Services Reference

### AI & LLM Services

```text
  Service            Container          Port   Image
  ─────────────────  ────────────────  ─────  ─────────────────────────────────────
  Dify Web           dify-web           3000   langgenius/dify-web
  Dify API           dify-api           5001   langgenius/dify-api
  Dify Worker        dify-worker         —      langgenius/dify-api
  Plugin Daemon      dify-plugin-daemon  5002   langgenius/dify-plugin-daemon
  Langfuse           langfuse-api        3003   langfuse/langfuse:3
  Langfuse Worker    langfuse-worker     —      langfuse/langfuse-worker:3
  Flowise            flowise             3004   flowiseai/flowise
  Browserless        browserless         3005   ghcr.io/browserless/chromium

  Dify backing:  dify-db (Postgres 15 :5432)
                 dify-redis (Redis 6)
                 dify-qdrant (Qdrant :6333)

  Langfuse backing:  langfuse-db (Postgres 16)
                     langfuse-redis (Redis 7)
                     langfuse-clickhouse (ClickHouse)
                     langfuse-minio (MinIO S3)
```

---

### Automation

```text
  Service            Container          Port   Image
  ─────────────────  ────────────────  ─────  ─────────────────────────────────────
  n8n                n8n                5678   docker.n8n.io/n8nio/n8n
```

---

### Media Server Stack (Arr)

```text
  Service            Container          Port   Image
  ─────────────────  ────────────────  ─────  ─────────────────────────────────────
  Prowlarr           prowlarr           9696   linuxserver/prowlarr
  Sonarr             sonarr             8989   linuxserver/sonarr
  Radarr             radarr             7878   linuxserver/radarr
  Bazarr             bazarr             6767   linuxserver/bazarr
  qBittorrent        qbittorrent        8090   linuxserver/qbittorrent
  FlareSolverr       flaresolverr       8191   flaresolverr/flaresolverr
  Unpackerr          unpackerr           —      golift/unpackerr
  Jellyfin           jellyfin           8096   linuxserver/jellyfin  (+ AMD HW encode)
  Seerr              seerr              5055   seerr/seerr
  Suggestarr         suggestarr         5000   ciuse99/suggestarr
  Recyclarr          recyclarr           —      recyclarr/recyclarr
  Maintainerr        maintainerr        6246   maintainerr/maintainerr
  Decluttarr         decluttarr          —      manimatter/decluttarr
```

---

### Observability

```text
  Service            Container          Port   Image
  ─────────────────  ────────────────  ─────  ─────────────────────────────────────
  Prometheus         prometheus         9090   prom/prometheus
  Grafana            grafana            3002   grafana/grafana
  Node Exporter      node-exporter       —      prom/node-exporter
  cAdvisor           cadvisor            —      gcr.io/cadvisor/cadvisor

  Config:  terraform/05-docker-stacks/prometheus.tpl  →  rendered to prometheus.yml
```

---

### Management & Databases

```text
  Service            Container          Port   Image
  ─────────────────  ────────────────  ─────  ─────────────────────────────────────
  Portainer          portainer          9000   portainer/portainer-ce:lts
                                                  9443  (HTTPS)
  NocoDB             nocodb             8081   nocodb/nocodb
```

---

### Access & Tunnels

```text
  Service            Container          Port   Image
  ─────────────────  ────────────────  ─────  ─────────────────────────────────────
  Cloudflared        cloudflared         —      cloudflare/cloudflared
```

---

### Shared Storage

All media/download containers mount a **CIFS/SMB volume** backed by the Proxmox USB datastore:
`//192.168.1.169/Proxmox-USB`

This keeps media files off the Docker node's thin-provisioned disk.

```text
  Container          Mount Point        Purpose
  ─────────────────  ──────────────────  ──────────────────────────────
  qBittorrent        /data               Downloads + completed torrents
  Sonarr             /data               TV library
  Radarr             /data               Movie library
  Jellyfin           /data               Media playback
  Bazarr             /data               Subtitles storage
  Unpackerr          /data               Archived media
  Decluttarr         /data               Library cleanup
```

---

## 🌐 Network Topology

```text
        ┌────────────────────────────────────────┐
        │             192.168.1.0/24             │
        │                Home LAN                │
        │          Gateway: 192.168.1.1          │
        └───────────────────┬────────────────────┘
                            │
   ┌────────────────────────▼────────────────────────┐
   │    PROXMOX VE HYPERVISOR HOST (sproxmox01)      │
   │  • vmbr0 Bridge (LAN Interface): 192.168.1.169  │
   │  • vnet0 Switch (SDN Interface): 10.6.7.1       │
   └────────────────────────┬────────────────────────┘
                            │ (Internal Routing / SNAT)
   ┌────────────────────────▼────────────────────────┐
   │          10.6.7.0/24 (Proxmox SDN vnet0)        │
   │                                                 │
   │  • .170 → vm-docker01 (Compute Host Node)       │
   │  • .171 → lxc-pihole01 (DNS Blocklist Server)   │
   │  • .172 → lxc-tailscale01 (Mesh Subnet Router)  │
   │  • .173 → vm-hermes01 (Dedicated AI Agent VM)   │
   └─────────────────────────────────────────────────┘
```

---

## 🚀 Getting Started

### Prerequisites

1. **Proxmox VE** node named `sproxmox01` accessible at `192.168.1.X:8006`
2. **SSH key** at `~/.ssh/id_ed25519` (ed25519 format)
3. **Terraform** + **Terraform Proxmox Provider** installed locally
4. **Debian 13 LXC template** at Proxmox `local` storage: `debian-13-standard_13.1-2_amd64.tar.zst`
5. A **Proxmox API token** with sufficient permissions

### Clone & Configure

```bash
git clone https://github.com/nicetry001/afterhours_homeLab.git
cd afterhours_homeLab

# Copy the example vars file and fill in your secrets
cp terraform.tfvars.example terraform.tfvars
```

#### terraform.tfvars

Your local `terraform.tfvars` (gitignored) needs at minimum:

```hcl
proxmox_api_url   = "https://192.168.1.X:8006/api2/json"
proxmox_api_token = "terraform-prov@pve!deploy-token=YOUR-SECRET-TOKEN"
afterhours_pub_key = "ssh-ed25519 AAAA... your-key-here"
```

Additional variables are listed in `terraform/05-docker-stacks/variables.tf`.

### Deploy in Order

```bash
# 01 — SDN network
cd terraform/01-core-network && terraform init && terraform apply

# 02 — Docker VM
cd ../02-docker-nodes && terraform init && terraform apply

# 03 — Pi-hole LXC
cd ../03-pihole-lxc && terraform init && terraform apply

# 04 — Tailscale LXC
cd ../04-tailscale-lxc && terraform init && terraform apply

# 05 — Docker stacks (all containers)
cd ../05-docker-stacks && terraform init && terraform apply

# 06 — Hermes Agent VM
cd ../06-hermes-agent && terraform init && terraform apply
```

> **One layer at a time.** Confirm each layer is healthy before moving to the next.

---

## 🔐 Secret Management

**This repository never contains real secrets.**

All sensitive values live in `terraform.tfvars` — gitignored, kept locally only.

```text
  Variable                  Used By          Purpose
  ────────────────────────  ───────────────  ──────────────────────────────────
  proxmox_api_token         All layers       Proxmox API authentication
  afterhours_pub_key        All layers       SSH access to VMs/LXCs
  pihole_password           Pi-hole LXC      Admin web UI password
  tailscale_auth_key        Tailscale LXC    Mesh join auth key
  usb_samba_password        Docker stacks    SMB mount for shared storage
  qbit_password             Docker stacks    qBittorrent WebUI password
  nocodb_jwt_secret         NocoDB           JWT signing secret
  dify_db_pass              Dify             PostgreSQL master password
  dify_secret_key           Dify             Session/cookie encryption key
  dify_plugin_token         Dify             Plugin daemon auth token
  flowise_password          Flowise          Basic auth password
  cloudflare_tunnel_token   Cloudflared      Tunnel edge auth
  browserless_token         Browserless      API auth token
  grafana_admin_password    Grafana          Admin login password
  langfuse_db_password      Langfuse         Postgres password
  langfuse_nextauth_secret  Langfuse         Session signing secret
  langfuse_salt             Langfuse         Encryption salt
  minio_root_user           Langfuse         MinIO root user
  minio_root_password       Langfuse         MinIO root password
  minio_s3_access_key       Langfuse         App-level S3 access key
  minio_s3_secret_key       Langfuse         App-level S3 secret key
```

**Example template (no real values):**

```hcl
# terraform.tfvars.example
proxmox_api_url   = "https://192.168.1.X:8006/api2/json"
proxmox_api_token = "terraform-prov@pve!deploy-token=YOUR-SECRET-TOKEN"
```

---

## ➕ Adding New Stacks

New Docker services follow a strict convention:

1. **One file per stack** under `terraform/05-docker-stacks/` — e.g. `stack_mynewthing.tf`
2. **No docker-compose on the host** — everything is native Terraform `docker_container` / `docker_volume` resources
3. **Use existing networks** — attach to `net-frontend` and/or `net-backend` as needed
4. **Add `null_resource` scaffolding** if you need to create directories on the Docker node
5. **SSH target:** `afterhours@192.168.1.170` with `~/.ssh/id_ed25519`
6. **Add variable declarations** to `variables.tf` (with `sensitive = true` for secrets)
7. **Keep ports 80 and 8080 free** for future Nginx reverse proxy planning
8. **Add one stack at a time** — apply, verify, then move to the next

---

## 📁 Repository Structure

```text
afterhours_homeLab/
├── .env.example                 # Global application layer schema templates
├── terraform.tfvars.example     # Reference structure for local configuration fields
├── afterhours_homeLab.code-workspace
├── docker/
│   ├── .env                    # Active host runtime container mappings
│   └── media/
│       └── compose.yaml        # Native storage link maps
├── terraform/
│   ├── 01-core-network/        # Isolated Proxmox SDN integration logic
│   ├── 02-docker-nodes/        # Main compute instance definitions
│   ├── 03-pihole-lxc/          # Perimeter security and caching nameservers
│   ├── 04-tailscale-lxc/       # Inbound wireguard mesh endpoints
│   ├── 05-docker-stacks/       # Core service topologies (*.tf configs)
│   └── 06-hermes-agent/        # Core localized AI runtime systems
└── .gitignore                 # Enforces zero-leak policies
```

---

## 🛡️ Security Notes

```text
- SSH keypairs referenced by local path (`~/.ssh/id_ed25519`) — never checked into git
- Terraform state files (`.tfstate`) contain resource IDs and are gitignored
- All service passwords, API tokens, and JWT secrets live in `terraform.tfvars` (gitignored)
- Pi-hole, NocoDB, Flowise, and Grafana each have their own auth layer
- Tailscale provides encrypted mesh VPN — no router port forwarding required
- Cloudflared creates an authenticated tunnel to Cloudflare edge — no public exposure
- USB datastore mount (`//192.168.1.169/Proxmox-USB`) authenticated via Samba credentials
- This repository leverages a strict zero-secrets validation footprint. All sensitive parameters are strictly decoupled from the code tree into local-only variables handled safely by .gitignore policies.
    - ggshield secret scan path -r .
```

---

## 🛠️ Tech Stack Summary

```text
  Layer              Technology
  ─────────────────  ─────────────────────────────────────────────
  Hypervisor         Proxmox VE
  IaC Provisioning   Terraform + Proxmox Provider
  VM OS              Ubuntu 26.04 Server (cloud image)
  LXC OS             Debian 13 (trixie) standard template
  Container Runtime  Docker Engine
  DNS / Ad-blocking  Pi-hole + HaGeZi Pro + Steven Black lists
  VPN / Remote       Tailscale (subnet router) + Cloudflare Tunnel
  Media Stack        Sonarr, Radarr, Bazarr, Prowlarr, Jellyfin,
                     qBittorrent, Seerr, Suggestarr, Stirling PDF
  AI Platforms       Dify, Langfuse, Flowise, Browserless
  Automation         n8n
  Observability      Prometheus, Grafana, cAdvisor, Node Exporter
  Databases          PostgreSQL, Redis, Qdrant, ClickHouse,
                     MinIO, SQLite
  Management         Portainer, NocoDB
  AI Agent           Hermes Agent (native VM deployment)
```
