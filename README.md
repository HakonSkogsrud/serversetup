# My Homelab: GitOps & Resilient Self-Hosting

## Tech Stack

<img src="https://img.shields.io/badge/Proxmox-E57000?style=flat&logo=proxmox&logoColor=white" alt="Proxmox" height="25"/> <img src="https://img.shields.io/badge/AlmaLinux-000000?style=flat&logo=almalinux&logoColor=white" alt="AlmaLinux" height="25"/> <img src="https://img.shields.io/badge/ZFS-0052CC?style=flat&logo=openzfs&logoColor=white" alt="ZFS" height="25"/> <img src="https://img.shields.io/badge/GitHub-181717?style=flat&logo=github&logoColor=white" alt="GitHub" height="25"/> <img src="https://img.shields.io/badge/Ansible-EE0000?style=flat&logo=ansible&logoColor=white" alt="Ansible" height="25"/> <img src="https://img.shields.io/badge/Docker-2496ED?style=flat&logo=docker&logoColor=white" alt="Docker" height="25"/> <img src="https://img.shields.io/badge/Pi--hole-96060C?style=flat&logo=pihole&logoColor=white" alt="Pi-hole" height="25"/> <img src="https://img.shields.io/badge/Tailscale-000000?style=flat&logo=tailscale&logoColor=white" alt="Tailscale" height="25"/> <img src="https://img.shields.io/badge/Grafana-F46800?style=flat&logo=grafana&logoColor=white" alt="Grafana" height="25"/> <img src="https://img.shields.io/badge/Loki-F46800?style=flat&logo=grafana&logoColor=white" alt="Loki" height="25"/> <img src="https://img.shields.io/badge/Immich-4250AF?style=flat&logo=immich&logoColor=white" alt="Immich" height="25"/> <img src="https://img.shields.io/badge/CouchDB-E42528?style=flat&logo=apachecouchdb&logoColor=white" alt="CouchDB" height="25"/> <img src="https://img.shields.io/badge/Vaultwarden-175DDC?style=flat&logo=bitwarden&logoColor=white" alt="Vaultwarden" height="25"/> <img src="https://img.shields.io/badge/Caddy-00ADD8?style=flat&logo=caddy&logoColor=white" alt="Caddy" height="25"/> <img src="https://img.shields.io/badge/Syncthing-0891D1?style=flat&logo=syncthing&logoColor=white" alt="Syncthing" height="25"/> <img src="https://img.shields.io/badge/Ubuntu-E95420?style=flat&logo=ubuntu&logoColor=white" alt="Ubuntu" height="25"/> <img src="https://img.shields.io/badge/Samba-B10000?style=flat&logo=samba&logoColor=white" alt="Samba" height="25"/> <img src="https://img.shields.io/badge/firewalld-EE0000?style=flat&logo=firewalld&logoColor=white" alt="firewalld" height="25"/> <img src="https://img.shields.io/badge/SELinux-0066CC?style=flat&logo=linux&logoColor=white" alt="SELinux" height="25"/> <img src="https://img.shields.io/badge/UptimeKuma-5CDD8B?style=flat&logo=uptimekuma&logoColor=white" alt="UptimeKuma" height="25"/>

![setup](server-architecture.png)

---

This infrastructure is built on Proxmox, ZFS, and a **GitOps/Infrastructure as Code (IaC)** model, engineered to achieve the **3-2-1 backup rule** with dedicated redundancy.

### Automation & Maintenance

My homelab uses a strict GitOps principle where a single GitHub repository is the source of truth. All VMs are build from Alma Linux.

- **"Nuke and Pave" Pipeline:** A **`github-runner` VM** executes the CI/CD pipeline. To prevent drift, major updates involve destroying the old instance and reprovisioning a new one from the Golden Image.
- **Weekly Maintenance:** Ansible configures local **cron jobs** on VMs to handle OS updates, service restarts, and updates for Pi-hole and Docker Compose apps.
- **Monitoring:** **UptimeKuma** tracks service uptime with push/ping/HTTP checks across the infrastructure.
- **Observability:** **Loki** centralizes log aggregation from all VMs (via **Promtail**), while **Grafana** provides dashboards for error logs, internet uptime checks, and other metrics.

### Core Infrastructure & Security

- **Primary Host:** Focused on storage performance, running a ZFS **RAID 1 Mirror** (2x 4TB SSDs). Services use raw ZFS performance by mounting datasets via **virtiofs**.
- **Secondary Host:** A physical host ensuring high availability, running failover instances of the **Tailscale Subnet-Router** and **Pi-hole**.
- **Security:** All VMs have firewalls enabled and run **SELinux in enforcing mode**. Host access is restricted to **SSH Keys**.

### Network & Services

**Tailscale** provides a secure mesh backbone. Remote HTTPS access flows through **Tailscale Serve** on the subnet-router, which proxies into **Caddy** (running on the services VM) as a reverse proxy, routing requests to the appropriate internal service (CouchDB, Vaultwarden, etc.). Primary and secondary Pi-hole VMs provide content filtering and DNS resolution for the entire network via the gateway.

- **Key VMs:** **`github-runner`** (CI/CD), **`samba`** (File server/backup ingestion), **`immich`** (Photos/Video), **`loki`** (Log aggregation), **`grafana`** (Error logs/Visualization), and **`services`** (Docker host for Syncthing, CouchDB, Vaultwarden, Nebula, UptimeKuma, **Caddy**).
- **`immich`** and **`samba`** are intentionally kept on dedicated VMs. Immich is a large, complex service with its own heavy stack (ML workers, database, Redis); isolating it means photo access is unaffected when the `services` VM is being rebuilt or experimented with. Samba is the ingestion point for photos and files from phones and cameras — it needs to stay available around the clock so no transfers are lost during maintenance.
- **CouchDB** on the services VM serves as the backend for **Obsidian LiveSync**, synchronizing notes across iPhone, Android, Windows, and Linux devices with HTTPS access via Tailscale.
- **Vaultwarden** provides a self-hosted Bitwarden-compatible password manager, accessible securely over Tailscale.
- **Caddy** acts as a reverse proxy on the services VM, providing TLS termination and routing for hosted services.

### Data Protection (3-2-1 Strategy)

1.  **Local:** **Sanoid** automates the creation and pruning of local ZFS snapshots.
2.  **Offsite:** An Ubuntu Server with a ZFS pool (2x 4TB HDDs) is **housed offsite**. **Syncoid** manages the scheduled replication over VPN.
3.  **Offline:** A 4TB external drive provides the air-gapped component. It is manually synced and stored offline to protect against ransomware.

![setup](server-network.png)

---

## Repository Structure

```
serversetup/
├── playbooks/
│   ├── proxmox_primary/     # services, immich, samba, proxmox, github_runner, subnet_router
│   ├── proxmox_secondary/   # proxmox2, pihole_secondary, subnet_router_secondary
│   ├── backupserver/
│   └── local/               # fedora (local workstation)
├── roles/                   # One role per service/function
│   └── <role>/
│       ├── tasks/
│       │   ├── main.yml     # Entry point
│       │   ├── <role>.yml   # Setup tasks
│       │   ├── backup.yml   # Backup logic (optional)
│       │   └── restore.yml  # Restore logic (optional)
│       ├── templates/       # Jinja2 templates (.j2)
│       ├── defaults/        # Default variables
│       ├── handlers/        # Restart/reload handlers
│       └── meta/            # Role dependencies
├── group_vars/all.yml       # Variables shared across all hosts
├── host_vars/               # Host-specific variable overrides
├── inventory.yml            # Host definitions
├── secrets.yml              # Ansible Vault encrypted secrets
└── requirements-collections.yml  # Ansible collection dependencies
```

## Deployment

```bash
# Deploy a specific VM
ansible-playbook playbooks/proxmox_primary/services.yml
ansible-playbook playbooks/proxmox_primary/immich.yml

# Deploy with pre-play backup (for VM recreation)
ansible-playbook playbooks/proxmox_primary/services.yml -e "force_recreate=true"
```

### Backup & Restore on Deploy

Stateful services (CouchDB, Vaultwarden, UptimeKuma, Syncthing, etc.) follow a consistent pattern:

- **Backup:** When `force_recreate=true`, a pre-play runs before any VM changes and copies critical data to `/mnt/storage/smb/<service>/` on the Samba share.
- **Restore:** `main.yml` checks whether the service's data directory exists on the newly provisioned VM. If missing, it restores from the Samba share before starting the service — making full VM rebuilds non-destructive.

## Roles

| Role | | Technology | Description |
|------|---|------------|-------------|
| [caddy](roles/caddy/) | <img src="https://img.shields.io/badge/Caddy-00ADD8?style=flat&logo=caddy&logoColor=white" alt="Caddy" height="20"/> | Docker | Reverse proxy with TLS termination and Caddyfile-based routing |
| [couchdb](roles/couchdb/) | <img src="https://img.shields.io/badge/CouchDB-E42528?style=flat&logo=apachecouchdb&logoColor=white" alt="CouchDB" height="20"/> | Docker | NoSQL document database, used as Obsidian LiveSync backend |
| [create_template_vm](roles/create_template_vm/) | <img src="https://img.shields.io/badge/Proxmox-E57000?style=flat&logo=proxmox&logoColor=white" alt="Proxmox" height="20"/> | Proxmox API | Creates AlmaLinux golden image template VM on Proxmox |
| [create_vm](roles/create_vm/) | <img src="https://img.shields.io/badge/Proxmox-E57000?style=flat&logo=proxmox&logoColor=white" alt="Proxmox" height="20"/> | Proxmox API | Clones and provisions VMs from the template with network config |
| [docker](roles/docker/) | <img src="https://img.shields.io/badge/Docker-2496ED?style=flat&logo=docker&logoColor=white" alt="Docker" height="20"/> | DNF | Installs Docker CE, CLI, containerd, and docker-compose plugin |
| [docker_auto_update](roles/docker_auto_update/) | <img src="https://img.shields.io/badge/Docker-2496ED?style=flat&logo=docker&logoColor=white" alt="Docker" height="20"/> | Docker + systemd | Weekly systemd timer that pulls and restarts updated Docker images |
| [echovault](roles/echovault/) | | Docker | Self-hosted in-memory data store and cache |
| [firewall](roles/firewall/) | <img src="https://img.shields.io/badge/firewalld-EE0000?style=flat&logo=firewalld&logoColor=white" alt="firewalld" height="20"/> | firewalld | Installs and enables firewalld on VMs |
| [github_runner](roles/github_runner/) | <img src="https://img.shields.io/badge/GitHub-181717?style=flat&logo=github&logoColor=white" alt="GitHub" height="20"/> | GitHub Actions | Registers a self-hosted GitHub Actions runner with Ansible/Python environment |
| [grafana](roles/grafana/) | <img src="https://img.shields.io/badge/Grafana-F46800?style=flat&logo=grafana&logoColor=white" alt="Grafana" height="20"/> | Docker | Metrics and log visualization dashboards with Loki datasource |
| [immich](roles/immich/) | <img src="https://img.shields.io/badge/Immich-4250AF?style=flat&logo=immich&logoColor=white" alt="Immich" height="20"/> | Docker | Self-hosted photo and video backup with ML object detection |
| [internet_monitor](roles/internet_monitor/) | | systemd | Monitors internet connectivity and pushes heartbeats to UptimeKuma |
| [loki](roles/loki/) | <img src="https://img.shields.io/badge/Loki-F46800?style=flat&logo=grafana&logoColor=white" alt="Loki" height="20"/> | Docker | Centralized log aggregation for all VMs |
| [mount_virtiofs](roles/mount_virtiofs/) | <img src="https://img.shields.io/badge/Proxmox-E57000?style=flat&logo=proxmox&logoColor=white" alt="Proxmox" height="20"/> | virtiofs | Mounts a virtiofs shared filesystem from the Proxmox host into a VM |
| [nebula_sync](roles/nebula_sync/) | <img src="https://img.shields.io/badge/Pi--hole-96060C?style=flat&logo=pihole&logoColor=white" alt="Pi-hole" height="20"/> | Docker | Syncs Pi-hole gravity and DNS config across multiple instances |
| [pihole_docker](roles/pihole_docker/) | <img src="https://img.shields.io/badge/Pi--hole-96060C?style=flat&logo=pihole&logoColor=white" alt="Pi-hole" height="20"/> | Docker | DNS ad blocker and network-wide content filter |
| [pihole_health](roles/pihole_health/) | <img src="https://img.shields.io/badge/Pi--hole-96060C?style=flat&logo=pihole&logoColor=white" alt="Pi-hole" height="20"/> | systemd | Monitors Pi-hole health via DNS queries and pushes to UptimeKuma |
| [promtail](roles/promtail/) | <img src="https://img.shields.io/badge/Loki-F46800?style=flat&logo=grafana&logoColor=white" alt="Loki" height="20"/> | Binary | Ships VM logs to Loki for centralized log aggregation |
| [proxmox_config](roles/proxmox_config/) | <img src="https://img.shields.io/badge/Proxmox-E57000?style=flat&logo=proxmox&logoColor=white" alt="Proxmox" height="20"/> | systemd | Configures ZFS encrypted dataset auto-mount service on Proxmox hosts |
| [samba](roles/samba/) | <img src="https://img.shields.io/badge/Samba-B10000?style=flat&logo=samba&logoColor=white" alt="Samba" height="20"/> | Samba | File sharing server with macOS Time Machine compatibility |
| [sanoid](roles/sanoid/) | <img src="https://img.shields.io/badge/ZFS-0052CC?style=flat&logo=openzfs&logoColor=white" alt="ZFS" height="20"/> | ZFS | Automated ZFS snapshot creation and retention management |
| [scheduled_reboot](roles/scheduled_reboot/) | | systemd | Schedules automatic system reboots via systemd timer |
| [scheduled_update](roles/scheduled_update/) | <img src="https://img.shields.io/badge/AlmaLinux-000000?style=flat&logo=almalinux&logoColor=white" alt="AlmaLinux" height="20"/> | systemd | Schedules automatic OS package updates via systemd timer |
| [syncoid](roles/syncoid/) | <img src="https://img.shields.io/badge/ZFS-0052CC?style=flat&logo=openzfs&logoColor=white" alt="ZFS" height="20"/> | ZFS | Replicates ZFS snapshots to offsite backup server over VPN |
| [syncthing](roles/syncthing/) | <img src="https://img.shields.io/badge/Syncthing-0891D1?style=flat&logo=syncthing&logoColor=white" alt="Syncthing" height="20"/> | Docker | Continuous P2P file synchronization across devices |
| [tailscale_installation](roles/tailscale_installation/) | <img src="https://img.shields.io/badge/Tailscale-000000?style=flat&logo=tailscale&logoColor=white" alt="Tailscale" height="20"/> | Tailscale CLI | Installs the Tailscale VPN client on AlmaLinux or Debian |
| [tailscale_node](roles/tailscale_node/) | <img src="https://img.shields.io/badge/Tailscale-000000?style=flat&logo=tailscale&logoColor=white" alt="Tailscale" height="20"/> | Tailscale CLI | Registers a node on the Tailnet with an auth key and hostname |
| [tailscale_serve](roles/tailscale_serve/) | <img src="https://img.shields.io/badge/Tailscale-000000?style=flat&logo=tailscale&logoColor=white" alt="Tailscale" height="20"/> | Tailscale CLI | Configures Tailscale HTTPS proxy to expose local services on the Tailnet |
| [tailscale_static_route](roles/tailscale_static_route/) | <img src="https://img.shields.io/badge/Tailscale-000000?style=flat&logo=tailscale&logoColor=white" alt="Tailscale" height="20"/> | Tailscale CLI | Adds static IP routes for connectivity across Tailscale subnets |
| [tailscale_subnet_router](roles/tailscale_subnet_router/) | <img src="https://img.shields.io/badge/Tailscale-000000?style=flat&logo=tailscale&logoColor=white" alt="Tailscale" height="20"/> | Tailscale CLI | Enables Tailscale subnet routing with firewalld masquerade |
| [uptimekuma](roles/uptimekuma/) | <img src="https://img.shields.io/badge/UptimeKuma-5CDD8B?style=flat&logo=uptimekuma&logoColor=white" alt="UptimeKuma" height="20"/> | Docker | Service uptime monitoring with push, ping, and HTTP checks |
| [vaultwarden](roles/vaultwarden/) | <img src="https://img.shields.io/badge/Vaultwarden-175DDC?style=flat&logo=bitwarden&logoColor=white" alt="Vaultwarden" height="20"/> | Docker | Self-hosted Bitwarden-compatible password manager |

## Secrets

`secrets.yml` is encrypted with Ansible Vault and contains database passwords, API keys, and notification tokens. The vault password is stored in `.vault_pass` (gitignored).
