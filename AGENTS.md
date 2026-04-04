# Project: Homelab Infrastructure as Code

Ansible-managed homelab running on Proxmox VE with AlmaLinux VMs. GitOps model - single repo is source of truth.

## Infrastructure Overview

### VMs

| VM | IP | Purpose |
|----|----|---------|
| services | 10.0.0.44 | Docker host (Jellyfin, CouchDB, Caddy, Vaultwarden, etc.) |
| proxmox | 10.0.0.41 | Primary Proxmox host |
| proxmox2 | 10.0.0.33 | Secondary Proxmox host |
| loki | 10.0.0.83 | Log aggregation |
| grafana | 10.0.0.84 | Dashboards |
| immich | 10.0.0.80 | Photos/videos |
| pihole | 10.0.0.77 | DNS + ad blocking |
| backupserver | 100.104.43.26 | Offsite backup (VPN) |

### Backup Strategy (3-2-1)

1. **Local**: Sanoid + ZFS snapshots (Proxmox)
2. **Offsite**: Syncoid over VPN to backupserver
3. **Offline**: Manual external drive sync

## Directory Structure

```
serversetup/
├── playbooks/           # Ansible playbooks (one per VM/role)
├── roles/               # Ansible roles
│   └── <role>/
│       ├── tasks/
│       │   ├── main.yml
│       │   └── *.yml
│       ├── templates/    # Jinja2 templates (.j2)
│       ├── defaults/     # Default variables
│       ├── handlers/     # Handlers for notify
│       └── meta/         # Dependencies
├── group_vars/          # Variables for all hosts
├── host_vars/           # Host-specific variables
├── inventory.yml         # Inventory definitions
├── secrets.yml          # Encrypted secrets
└── misc_tasks/          # Shared task snippets
```

## Role Patterns

### Standard Role Structure

```
roles/<role_name>/
├── tasks/
│   ├── main.yml          # Entry point, imports other tasks
│   ├── <role>.yml        # Main setup tasks
│   ├── backup.yml        # Backup logic (optional)
│   ├── restore.yml       # Restore logic (optional)
├── templates/            # *.j2 files
├── defaults/main.yml     # Variables with defaults
├── handlers/main.yml     # Restart handlers
└── meta/main.yml         # Dependencies (optional)
```

### Task Pattern: main.yml

```yaml
---
- name: setup role
  ansible.builtin.include_tasks: role.yml

- name: setup backup
  ansible.builtin.include_tasks: backup.yml
```

### Task Pattern: restore.yml

Check if data directory exists. If not, restore from backup.

```yaml
---
- name: check if data directory exists
  ansible.builtin.stat:
    path: "{{ role_data_dir }}"
  register: role_data_exists

- name: restore if missing
  ansible.builtin.include_tasks: restore_data.yml
  when: not role_data_exists.stat.exists
```

### Pre-play Backup Pattern

For services that need backup before VM recreation:

```yaml
- name: Backup services before any changes
  hosts: services
  become: true
  gather_facts: false
  vars_files:
    - ../../secrets.yml
  tasks:
    - name: Backup service
      ansible.builtin.include_role:
        name: <role>
        tasks_from: backup.yml
      when: force_recreate | default(false) | bool
```

### Docker Compose Role Pattern

```yaml
# tasks/<role>.yml
- name: ensure directory exists
  ansible.builtin.file:
    path: "/home/{{ template.user }}/<service>"
    state: directory
    owner: "{{ template.user }}"
    group: "{{ template.user }}"

- name: copy docker-compose.yml
  ansible.builtin.template:
    src: docker-compose.yml.j2
    dest: "/home/{{ template.user }}/<service>/docker-compose.yml"
  notify: Restart <service>

- name: start container
  ansible.builtin.shell:
    cmd: docker compose up -d
    chdir: "/home/{{ template.user }}/<service>"
```

### Systemd Timer/Service Backup Pattern

```yaml
# tasks/<backup>_backup.yml
- name: ensure backup directory exists
  ansible.builtin.file:
    path: "{{ backup_dir }}"
    state: directory

- name: copy backup script
  ansible.builtin.template:
    src: backup.sh.j2
    dest: "/usr/local/bin/{{ backup_script_name }}.sh"
    mode: "0755"

- name: copy systemd service
  ansible.builtin.template:
    src: backup.service.j2
    dest: "/etc/systemd/system/{{ backup_script_name }}.service"
  notify: Reload systemd

- name: copy systemd timer
  ansible.builtin.template:
    src: backup.timer.j2
    dest: "/etc/systemd/system/{{ backup_script_name }}.timer"
  notify: Reload systemd

- name: enable timer
  ansible.builtin.systemd:
    name: "{{ backup_script_name }}.timer"
    enabled: true
    state: started
```

### Firewalld Pattern

```yaml
- name: Configure firewalld
  ansible.posix.firewalld:
    port: "{{ port }}/tcp"
    permanent: true
    state: enabled
    immediate: true
```

Add `meta/main.yml` to ensure firewall role runs first:
```yaml
dependencies:
  - { role: firewall }
  - { role: docker }
```

## Variables

### Standard Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `template.user` | `haaksk` | SSH user on VMs |
| `vms.<name>.ip` | - | VM IP address |
| `vms.<name>.vmid` | - | Proxmox VM ID |

### Variable Naming Convention

All role variables must be prefixed with the role name:

```yaml
# Wrong
uptimekuma_push_url: "..."

# Correct
syncoid_uptimekuma_push_url: "..."
sanoid_uptimekuma_push_url: "..."
```

### Docker Auto-Update

Services tracked by `docker_auto_update_compose_paths` are checked for updates weekly.

## Proxmox-Specific

### Sanoid

- Located on Proxmox hosts
- Default timer: every 15 minutes
- Config: `/etc/sanoid/sanoid.conf`
- Post-snapshot scripts for push monitoring

### ZFS

- `tank` pool for VMs
- `storage/smb` dataset for backups
- Syncoid replicates to backupserver over VPN

## Monitoring Stack

- **Promtail**: Installed on all VMs, ships logs to Loki
- **Loki**: Log aggregation, 31-day retention
- **Grafana**: Dashboards with Loki datasource
- **UptimeKuma**: Service monitoring with push/ping/HTTP checks

### UptimeKuma v2

- Docker deployment on services VM (image: `louislam/uptime-kuma:2`)
- Port: 3001 (bound to all interfaces for access)
- Data: `/home/haaksk/uptimekuma/data`
- Backup: tar.gz to `/mnt/storage/smb/uptimekuma/` via systemd timer (daily @ 01:00)
- Backup script stops container, creates tar.gz, restarts container
- Firewalld: port 3001/tcp opened

#### Push Monitors

Services push to UptimeKuma after completing:

| Service | Role Variable | Interval |
|---------|---------------|----------|
| Sanoid | `sanoid_uptimekuma_push_url` | Every 15 min (snapshots) |
| Syncoid | `syncoid_uptimekuma_push_url` | After replication completes |

Heartbeat interval should be ~25 min (longer than Sanoid's 15 min run).

#### Restore on VM Recreation

Pre-play backs up to `/mnt/storage/smb/uptimekuma/`. Configure services play checks if data dir exists — if missing, restores from latest backup.

## Deployment Commands

```bash
# Full deploy
ansible-playbook playbooks/services.yml

# Single VM
ansible-playbook playbooks/proxmox.yml

# With backup (for VM recreation)
ansible-playbook playbooks/services.yml -e "force_recreate=true"
```

## Secrets Management

`secrets.yml` is encrypted with ansible-vault. Contains:
- Database passwords
- API keys
- Notification tokens
