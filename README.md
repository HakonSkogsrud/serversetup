# My Homelab Architecture: A GitOps Approach to Resilient Self-Hosting

WORK IN PROGRESS 🔨🧱🏗️

![setup](server-architecture.png)

---

Written by AI.

This high-reliability, low-maintenance infrastructure is built on Proxmox, ZFS for data integrity, and a **full GitOps/Infrastructure as Code (IaC)** model. The architecture is engineered to achieve the **3-2-1 backup rule** and utilize dedicated host redundancy for critical service continuity.

## I. Infrastructure as Code (IaC) and Automation

My homelab adheres to a strict **GitOps principle**, where a single GitHub repository's configuration files serve as the immutable source of truth.

### 1. The Automated Pipeline: "Nuke and Pave" Deployment

A self-hosted CI/CD pipeline ensures system state consistency across the infrastructure:

*   **Execution Engine:** The specialized **`github-runner` VM** pulls the latest repo and runs all necessary automation tasks.
*   **Provisioning Strategy:** To prevent configuration drift, all services are managed by a "nuke and pave" deployment: a major VM update or config change involves **destroying the old instance** and **re-cloning and reprovisioning a new one** from the Golden Image.
*   **Maintenance Automation:** Weekly scheduled scripts created by Ansible run full VM OS updates, restart services, and perform automatic updates for both Pi-hole and all Docker Compose applications.
*   **System Alerts:** Scripts provide immediate feedback, logging activity and instantly delivering alerts (success/failure) to my phone via **Pushover**.


### 2. Maintenance Automation & Reporting
All systems benefit from weekly maintenance automation, configured directly via Ansible roles:

*   **Weekly Refresh:** The Ansible provisioner ensures local **cron jobs** are created and scheduled on the individual VMs to perform weekly, recurring maintenance, including: VM OS updates, service restarts, automated Pi-hole updates, and updating all deployed Docker Compose applications.
*   **System Alerts:** Scripts executed by these cron jobs provide instant operational feedback, logging their activity and immediately delivering alerts (success/failure) to my phone via **Pushover**.

## II. Core Infrastructure and Security

### 1. The Primary Server (Proxmox)
The core virtualization host, focused on storage performance and low-latency access.

*   **Storage:** A high-speed, resilient ZFS pool runs on a **RAID 1 Mirror** across two 4TB SSDs.
*   **Storage Access:** Services utilize raw ZFS performance by mounting **ZFS Datasets** into VMs via **virtiofs**.

### 2. The Redundant Host (Proxmox Secondary)
A dedicated physical host ensuring high-availability for core services.

*   This host runs failover instances of key services: the secondary **Tailscale Subnet-Router** and a secondary **Pi-hole**.
*   All VMs here are managed by the exact same centralized GitOps workflow.

### Security Posture
A strict zero-trust security policy is enforced system-wide:

*   **VM Hardening:** All virtual machines have firewalls enabled and run with **SELinux in enforcing mode** by default.
*   **Host Access:** Administrative access to the underlying Proxmox hosts is restricted to **SSH Keys**, with password authentication disabled.

## III. Network and Production Services

### Network and DNS Topology
**Tailscale** provides the secure, full-mesh network backbone with **Subnet-Router** instances enabling secure LAN access remotely. Both the primary and secondary Pi-hole VMs are configured **on the physical router** to serve as the redundant DNS resolvers for the entire network, ensuring all VMs use the **gateway** and automatically inherit the resilient, filtered DNS setup.

### Key Virtual Machines

*   **`github-runner`:** The self-hosted execution engine for the automated **CI/CD** and "nuke-and-pave" pipeline.
*   **`pihole` (Primary/Secondary):** These two VMs provide network-wide content filtering and resilient DNS resolution.
*   **`samba`:** The main file server and ingestion point for automated remote photo/media backups.
*   **`immich`:** Dedicated platform for self-hosted photo and video management.
*   **`services`:** A centralized, containerized VM (Docker/etc.) hosting miscellaneous applications like Jellyfin (Media Server), Syncthing, Nebula, and other utility micro-services.

## IV. Data Protection Strategy

The backup architecture achieves the necessary redundancy of the **3-2-1 rule** for comprehensive resilience.

### 1. Local Protection (ZFS Snapshots)
*   **Sanoid** automates the creation and intelligent pruning of local ZFS snapshots for instant recovery capability.

### 2. Scheduled Offsite Backup (Backupserver)
*   The remote machine is an **Ubuntu Server** with a high-capacity ZFS backup pool comprised of **two 4TB spinning hard drives**, securely housed **offsite**.
*   **Syncoid** securely manages the scheduled, incremental ZFS replication stream over the encrypted **Tailscale VPN**—this serves as the critical defense against a local site disaster.

### 3. Air-Gapped Offline Backup
*   A 4TB external drive provides the crucial air-gapped component. It is manually plugged in periodically for a final, consistent **ZFS snapshot sync** and then immediately returned to its secure, offline location, protecting the system from ransomware or catastrophic logical data corruption.
