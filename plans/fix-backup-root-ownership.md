# Fix: Backup scripts creating root-owned files on SMB share

## Root Cause

Ansible deploy plays run with `become: true` (root). When backup tasks run scripts or native
shell commands during a deploy, files are created as root. Scheduled systemd timers for some
services explicitly set `User=root`. This causes a mismatch: files written as root cannot be
overwritten by timers running as `haaksk`, breaking scheduled backups silently.

## Confirmed state (checked 2026-04-29)

| Role | Timer `User=` | Deploy backup runs as | Non-timestamped file overwritten? | Status |
|---|---|---|---|---|
| **couchdb** | `haaksk` | root (become: true) | Yes — `couchdb-backup.tar.gz` | ✗ BROKEN |
| **uptimekuma** | `root` (explicit) | root (become: true) | No (timestamped dirs) | ⚠ Functional, unnecessarily privileged |
| **vaultwarden** | `root` (explicit) | root (become: true) | No (timestamped dirs) | ⚠ Functional, unnecessarily privileged |
| **grafana** | No timer (deploy-only) | root (become: true) | Yes — `grafana-backup.tar.gz` | ℹ Deploy-only, no timer contention |
| **pihole** | No timer (deploy-only) | root (become: true) | No (timestamped) | ✓ Fine |
| **syncthing** | No timer (deploy-only) | root (become: true) | Yes — `config.xml` | ℹ Deploy-only, no timer contention |

## Fixes

### Priority 1 — Fix broken scheduled backup (couchdb)

**`roles/couchdb/tasks/backup.yml`** — add `become_user` so deploy backup matches timer ownership:
```yaml
- name: run script
  ansible.builtin.command:
    cmd: "/usr/local/bin/{{ couchdb_backup_script_name }}.sh"
  become_user: "{{ template.user }}"
```

### Priority 2 — Stop running backup timers as root unnecessarily

**`roles/uptimekuma/templates/uptimekuma_backup.service.j2`**:
```ini
# Change:
User=root
Group=root
# To:
User={{ template.user }}
Group={{ template.user }}
```

**`roles/vaultwarden/templates/vaultwarden_backup.service.j2`**:
```ini
# Change:
User=root
Group=root
# To:
User={{ template.user }}
Group={{ template.user }}
```

Also fix deploy-time backup.yml for both to match:

**`roles/vaultwarden/tasks/backup.yml`** — add `become_user`:
```yaml
- name: run script
  ansible.builtin.command:
    cmd: "/usr/local/bin/{{ vaultwarden_backup_script_name }}.sh"
  become_user: "{{ template.user }}"
```

**`roles/uptimekuma/tasks/backup.yml`** — add `become_user` to shell tasks in the block.

### Priority 3 — Consistency (deploy-only, no timer contention)

**`roles/grafana/tasks/restore.yml`** — "Copy backup to persistent storage" task:
add `owner: "{{ template.user }}" group: "{{ template.user }}"` to the copy task.

## Immediate server-side fix (run now, before next scheduled backup)

```bash
sudo chown haaksk:haaksk \
  /mnt/storage/smb/couchdb_backup/couchdb-backup.tar.gz \
  /mnt/storage/smb/couchdb_backup/couchdb-backup-20260411_215459.tar.gz \
  /mnt/storage/smb/couchdb_backup/couchdb-backup-20260416_144818.tar.gz \
  /mnt/storage/smb/grafana/grafana-backup.tar.gz
```

Note: uptimekuma/vaultwarden/pihole root-owned files do NOT need chowning — those timers
run as root consistently so they can manage their own files fine for now.
