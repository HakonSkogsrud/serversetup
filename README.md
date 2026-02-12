# My Homelab: GitOps & Resilient Self-Hosting

## Tech Stack

<img src="https://img.shields.io/badge/Proxmox-E57000?style=flat&logo=proxmox&logoColor=white" alt="Proxmox" height="25"/> <img src="https://img.shields.io/badge/AlmaLinux-000000?style=flat&logo=almalinux&logoColor=white" alt="AlmaLinux" height="25"/> <img src="https://img.shields.io/badge/ZFS-0052CC?style=flat&logo=openzfs&logoColor=white" alt="ZFS" height="25"/> <img src="https://img.shields.io/badge/GitHub-181717?style=flat&logo=github&logoColor=white" alt="GitHub" height="25"/> <img src="https://img.shields.io/badge/Ansible-EE0000?style=flat&logo=ansible&logoColor=white" alt="Ansible" height="25"/> <img src="https://img.shields.io/badge/Docker-2496ED?style=flat&logo=docker&logoColor=white" alt="Docker" height="25"/> <img src="https://img.shields.io/badge/Pi--hole-96060C?style=flat&logo=pihole&logoColor=white" alt="Pi-hole" height="25"/> <img src="https://img.shields.io/badge/Tailscale-000000?style=flat&logo=tailscale&logoColor=white" alt="Tailscale" height="25"/> <img src="https://img.shields.io/badge/Grafana-F46800?style=flat&logo=grafana&logoColor=white" alt="Grafana" height="25"/> <img src="https://img.shields.io/badge/Loki-F46800?style=flat&logo=grafana&logoColor=white" alt="Loki" height="25"/> <img src="https://img.shields.io/badge/Immich-4250AF?style=flat&logo=immich&logoColor=white" alt="Immich" height="25"/> <img src="https://img.shields.io/badge/CouchDB-E42528?style=flat&logo=apachecouchdb&logoColor=white" alt="CouchDB" height="25"/> <img src="https://img.shields.io/badge/Jellyfin-00A4DC?style=flat&logo=jellyfin&logoColor=white" alt="Jellyfin" height="25"/> <img src="https://img.shields.io/badge/Syncthing-0891D1?style=flat&logo=syncthing&logoColor=white" alt="Syncthing" height="25"/> <img src="https://img.shields.io/badge/Ubuntu-E95420?style=flat&logo=ubuntu&logoColor=white" alt="Ubuntu" height="25"/> <img src="https://img.shields.io/badge/Samba-B10000?style=flat&logo=samba&logoColor=white" alt="Samba" height="25"/> <img src="https://img.shields.io/badge/firewalld-EE0000?style=flat&logo=firewalld&logoColor=white" alt="firewalld" height="25"/> <img src="https://img.shields.io/badge/SELinux-0066CC?style=flat&logo=linux&logoColor=white" alt="SELinux" height="25"/>

![setup](server-architecture.png)

---

This infrastructure is built on Proxmox, ZFS, and a **GitOps/Infrastructure as Code (IaC)** model, engineered to achieve the **3-2-1 backup rule** with dedicated redundancy.

### Automation & Maintenance

My homelab uses a strict GitOps principle where a single GitHub repository is the source of truth. All VMs are build from Alma Linux.

- **"Nuke and Pave" Pipeline:** A **`github-runner` VM** executes the CI/CD pipeline. To prevent drift, major updates involve destroying the old instance and reprovisioning a new one from the Golden Image.
- **Weekly Maintenance:** Ansible configures local **cron jobs** on VMs to handle OS updates, service restarts, and updates for Pi-hole and Docker Compose apps.
- **Alerting:** Scripts log activity and provide instant feedback (success/failure) to my phone via **Pushover**.
- **Observability:** **Loki** centralizes log aggregation from all VMs (via **Promtail**), while **Grafana** provides visualization and monitoring dashboards for the entire infrastructure.

### Core Infrastructure & Security

- **Primary Host:** Focused on storage performance, running a ZFS **RAID 1 Mirror** (2x 4TB SSDs). Services use raw ZFS performance by mounting datasets via **virtiofs**.
- **Secondary Host:** A physical host ensuring high availability, running failover instances of the **Tailscale Subnet-Router** and **Pi-hole**.
- **Security:** All VMs have firewalls enabled and run **SELinux in enforcing mode**. Host access is restricted to **SSH Keys**.

### Network & Services

**Tailscale** provides a secure mesh backbone with HTTPS access via **Tailscale Serve** proxying through the subnet-router for mobile clients. Primary and secondary Pi-hole VMs provide content filtering and DNS resolution for the entire network via the gateway.

- **Key VMs:** **`github-runner`** (CI/CD), **`samba`** (File server/backup ingestion), **`immich`** (Photos/Video), **`loki`** (Log aggregation), **`grafana`** (Monitoring/Visualization), and **`services`** (Docker host for Jellyfin, Syncthing, CouchDB, Nebula).
- **CouchDB** on services VM provides self-hosted Obsidian LiveSync for notes synchronization across iPhone, Android, Windows, and Linux devices with HTTPS access via Tailscale.

### Data Protection (3-2-1 Strategy)

1.  **Local:** **Sanoid** automates the creation and pruning of local ZFS snapshots.
2.  **Offsite:** An Ubuntu Server with a ZFS pool (2x 4TB HDDs) is **housed offsite**. **Syncoid** manages the scheduled replication over VPN.
3.  **Offline:** A 4TB external drive provides the air-gapped component. It is manually synced and stored offline to protect against ransomware.

![setup](server-network.png)
