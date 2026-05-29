# Plan: Self-host Radicale on services VM

## Goal

Add a `radicale` Ansible role that runs Radicale (CalDAV/CardDAV server) in Docker on the services VM
using the `tomsquest/docker-radicale` image with htpasswd authentication. Expose it through the
existing Caddy reverse proxy at `/radicale`. Back up collections on a daily systemd timer. Role
structure and patterns mirror the existing `vaultwarden` role exactly.

## Decisions

- **Image**: `tomsquest/docker-radicale` (built-in htpasswd support, bcrypt hashing)
- **Auth**: htpasswd — credentials stored in `secrets.yml` (vault-encrypted), written to container by
  Ansible using `community.general.htpasswd`
- **Caddy path**: `/radicale`
- **Port**: `8200` (internal, not exposed publicly)
- **Backup**: daily systemd timer, mirrors `vaultwarden_backup` pattern, keeps last 30 snapshots
- **Data dir**: `/home/haaksk/radicale/` with subdirs `config/` and `data/`
- **Backup destination**: `/mnt/storage/smb/radicale/`
- No `meta/main.yml` needed — the role opens its own firewall port directly

---

## Phase 1 — New `radicale` role

### `roles/radicale/defaults/main.yml`

Define these variables (mirror vaultwarden defaults structure):

```yaml
radicale_port: 8200
radicale_dir: /home/haaksk/radicale

# Backup settings
radicale_backup_dir: /mnt/storage/smb/radicale
radicale_backup_script_name: radicale_backup
radicale_backup_data_dir: /home/haaksk/radicale/data
radicale_backup_uptimekuma_push_url: ""
```

### `roles/radicale/handlers/main.yml`

Single handler — identical to vaultwarden:

```yaml
- name: Reload systemd
  ansible.builtin.systemd:
    daemon_reload: true
```

### `roles/radicale/tasks/main.yml`

- Stat `{{ radicale_dir }}/data`
- Import `restore.yml` when the directory does not exist
- Always import `radicale_backup.yml` (sets up the timer)

### `roles/radicale/tasks/restore.yml`

Steps in order:

1. Create `{{ radicale_dir }}` directory (owner `{{ template.user }}`, mode `0755`)
2. Create `{{ radicale_dir }}/config` directory (same ownership)
3. Create `{{ radicale_dir }}/data` directory (same ownership)
4. Template `config.ini.j2` → `{{ radicale_dir }}/config/config` (owner `{{ template.user }}`, mode `0644`)
5. Use `community.general.htpasswd` to write `{{ radicale_dir }}/config/users`, adding user
   `{{ radicale_htpasswd_username }}` with password `{{ radicale_htpasswd_password }}` and
   `crypt_scheme: bcrypt`
6. Set ownership of `config/users` to `{{ template.user }}`
7. Template `docker-compose.yml.j2` → `{{ radicale_dir }}/docker-compose.yml`
   (owner `{{ template.user }}`, mode `0755`)
8. Open firewall port `{{ radicale_port }}/tcp` with `ansible.posix.firewalld` (permanent, immediate)
9. Start container with `community.docker.docker_compose_v2` using `project_src: {{ radicale_dir }}`

### `roles/radicale/tasks/radicale_backup.yml`

Mirror `roles/vaultwarden/tasks/vaultwarden_backup.yml` exactly, replacing variable/file name prefixes:

1. Ensure `{{ radicale_backup_dir }}` exists (owner `{{ template.user }}`)
2. Template `radicale_backup.sh.j2` → `/usr/local/bin/{{ radicale_backup_script_name }}.sh`
   (root, mode `0755`)
3. Template `radicale_backup.service.j2` → `/etc/systemd/system/radicale_backup.service`
   (root, mode `0644`) — notify `Reload systemd`
4. Template `radicale_backup.timer.j2` → `/etc/systemd/system/radicale_backup.timer`
   (root, mode `0644`) — notify `Reload systemd`
5. Enable and start `radicale_backup.timer` with `ansible.builtin.systemd`

### `roles/radicale/tasks/backup.yml`

Called from the playbook pre-task (mirrors `roles/vaultwarden/tasks/backup.yml`):

1. Stat `/usr/local/bin/{{ radicale_backup_script_name }}.sh`
2. Run the script with `ansible.builtin.command` as `become_user: {{ template.user }}` when it exists
3. Fix ownership of backup files with `chown -R` when script exists

### `roles/radicale/templates/docker-compose.yml.j2`

```yaml
services:
  radicale:
    image: tomsquest/docker-radicale:latest
    container_name: radicale
    restart: unless-stopped
    volumes:
      - ./config:/config
      - ./data:/data
    ports:
      - {{ radicale_port }}:5232
```

### `roles/radicale/templates/config.ini.j2`

```ini
[server]
hosts = 0.0.0.0:5232

[auth]
type = htpasswd
htpasswd_filename = /config/users
htpasswd_encryption = bcrypt

[storage]
filesystem_folder = /data/collections

[logging]
level = info
```

### `roles/radicale/templates/radicale_backup.sh.j2`

Mirror `roles/vaultwarden/templates/vaultwarden_backup.sh.j2`. Key logic:

- `SCRIPT_NAME="{{ radicale_backup_script_name }}"`
- `DATA_DIR="{{ radicale_backup_data_dir }}"` (i.e. `/home/haaksk/radicale/data`)
- `BACKUP_ROOT="{{ radicale_backup_dir }}"`
- `BACKUP_PATH="$BACKUP_ROOT/radicale_$(date +%Y%m%d_%H%M%S)"`
- `KEEP_COUNT=30`
- Use `cp -rp "$DATA_DIR/." "$BACKUP_PATH/"` to copy the whole data dir (no sqlite special handling)
- Log start/end with `logger -t "$SCRIPT_NAME"`
- Prune: `ls -1dt radicale_*/` keeping last 30, `xargs rm -rf`
- Conditional Uptime Kuma curl push (same `{% if radicale_backup_uptimekuma_push_url %}` pattern as
  vaultwarden)

### `roles/radicale/templates/radicale_backup.service.j2`

Mirror `roles/vaultwarden/templates/vaultwarden_backup.service.j2`:

```ini
[Unit]
Description=Radicale backup to smb share
Documentation=man:systemd.service(5)

[Service]
Type=oneshot
User={{ template.user }}
Group={{ template.user }}
ExecStart=/usr/local/bin/{{ radicale_backup_script_name }}.sh
StandardError=journal
StandardOutput=journal
SyslogIdentifier={{ radicale_backup_script_name }}

[Install]
WantedBy=multi-user.target
```

### `roles/radicale/templates/radicale_backup.timer.j2`

Mirror `roles/vaultwarden/templates/vaultwarden_backup.timer.j2`:

```ini
[Unit]
Description=Run radicale backup
Documentation=man:systemd.timer(5)

[Timer]
OnCalendar=*-*-* 02:30:00
Persistent=true
AccuracySec=1m

[Install]
WantedBy=timers.target
```

Timer is offset from vaultwarden (02:15) to avoid overlap.

---

## Phase 2 — Caddy changes

### `roles/caddy/tasks/main.yml`

Add a new `include_vars` task after the existing vaultwarden one:

```yaml
- name: read radicale vars to get port
  ansible.builtin.include_vars:
    file: "../../radicale/defaults/main.yml"
```

### `roles/caddy/templates/Caddyfile.j2`

Add a new block after the vaultwarden `handle` block. Use `handle_path` so the `/radicale` prefix is
stripped before forwarding to the container (Radicale expects requests at `/`):

```
handle_path /radicale/* {
    reverse_proxy {{ vms.services.ip }}:{{ radicale_port }}
}
```

---

## Phase 3 — Playbook wiring

### `playbooks/proxmox_primary/services.yml`

Three changes:

**1. Backup pre-task** — add after the vaultwarden backup task in the `Backup services before any
changes` play:

```yaml
- name: Take backup of radicale
  ansible.builtin.include_role:
    name: radicale
    tasks_from: backup.yml
  when: force_recreate | default(false) | bool
```

**2. Role list** — add `radicale` to the `Configure services` play roles list, next to `vaultwarden`:

```yaml
- vaultwarden
- radicale
```

**3. docker_auto_update_compose_paths** — add the radicale compose file:

```yaml
- "/home/{{ template.user }}/radicale/docker-compose.yml"
```

### `secrets.yml`

Manually add two vault-encrypted variables:

```bash
ansible-vault edit secrets.yml
```

```yaml
radicale_htpasswd_username: <your_username>
radicale_htpasswd_password: <your_password>
```

---

## Files to create

| File | Purpose |
|------|---------|
| `roles/radicale/defaults/main.yml` | Role variable defaults |
| `roles/radicale/handlers/main.yml` | Reload systemd handler |
| `roles/radicale/tasks/main.yml` | Entry point — stat, restore, backup setup |
| `roles/radicale/tasks/restore.yml` | First-run provisioning |
| `roles/radicale/tasks/radicale_backup.yml` | Install backup script + systemd timer |
| `roles/radicale/tasks/backup.yml` | Pre-task backup runner (called from playbook) |
| `roles/radicale/templates/docker-compose.yml.j2` | Container definition |
| `roles/radicale/templates/config.ini.j2` | Radicale server config |
| `roles/radicale/templates/radicale_backup.sh.j2` | Backup shell script |
| `roles/radicale/templates/radicale_backup.service.j2` | Systemd service unit |
| `roles/radicale/templates/radicale_backup.timer.j2` | Systemd timer unit |

## Files to modify

| File | Change |
|------|--------|
| `roles/caddy/tasks/main.yml` | Add `include_vars` for radicale defaults |
| `roles/caddy/templates/Caddyfile.j2` | Add `handle_path /radicale/*` reverse proxy block |
| `playbooks/proxmox_primary/services.yml` | Add backup pre-task, role, and auto-update path |
| `secrets.yml` | Add `radicale_htpasswd_username` + `radicale_htpasswd_password` (manual vault edit) |

## Out of scope

- TLS termination — handled by Caddy already
- Multi-user support beyond the initial user — add more via `community.general.htpasswd` later
- Radicale rights/permissions file — default (owner-only) is sufficient for single-user
- Restore-from-backup logic — not included in this plan (fresh install only); add later if needed

---

## Verification

1. Add credentials to secrets: `ansible-vault edit secrets.yml`
2. Dry run: `ansible-playbook playbooks/proxmox_primary/services.yml --check`
3. Full run: `ansible-playbook playbooks/proxmox_primary/services.yml`
4. On services VM: `systemctl status radicale_backup.timer` — should be active/waiting
5. On services VM: `docker ps | grep radicale` — container running
6. In browser: `https://<tailscale-host>/radicale/` — should return HTTP 401 (auth prompt)
7. With credentials: should return `200 OK`
8. Add CalDAV/CardDAV account in a client (Thunderbird, iOS, DAVx⁵) using URL
   `https://<host>/radicale/<username>/` and the vault credentials
9. Trigger backup manually: `sudo systemctl start radicale_backup.service`
   then check `ls /mnt/storage/smb/radicale/`
