# Fix: services VM hangs on /mnt/storage/smb

## Confirmed context
- Proxmox host: `/storage/smb` is fine
- Immich VM: `/mnt/storage/smb` via virtiofs works fine
- Services VM: `/mnt/storage/smb` **hangs** — specific to this VM
- Evidence: `couchdb-backup.service` logs "Starting CouchDB Backup to SMB Share..." then hangs immediately on its first `mkdir -p /mnt/storage/smb/couchdb_backup`

## Root Cause

**Syncthing's Docker container has a live bind-mount on the virtiofs path:**

```yaml
# roles/syncthing/templates/docker-compose.yml.j2
volumes:
  - ./config:/var/syncthing/config
  - /mnt/storage/smb/Sync:/mnt/storage/smb/Sync   ← THIS IS THE PROBLEM
```

Syncthing continuously watches and syncs files through `/mnt/storage/smb/Sync`.
Every file event, inotify watch, and file I/O goes through the virtiofs FUSE driver
→ the `virtiofsd` daemon on Proxmox (one per VM) becomes saturated.

When any process tries to access `/mnt/storage/smb`, the kernel queues the operation
behind Syncthing's pending FUSE requests → **hangs indefinitely**.

This explains why:
- Immich works fine — only accesses virtiofs during scheduled backups, never continuously
- Samba VM works fine — no inotify/continuous I/O loop on the mount
- It's "almost always" a hang — because Syncthing is always running

## Fix: Separate virtiofs mount for Syncthing

Proxmox supports multiple virtiofs shares per VM (virtiofs0, virtiofs1…), each backed by its
own `virtiofsd` process on the host. Currently the services VM only has `virtiofs0 → /storage/smb`.

Add `virtiofs1` pointing to a dedicated `/storage/syncthing` ZFS dataset.
- Syncthing's continuous I/O goes through its own `virtiofsd` (virtiofs1)
- The main `smb` virtiofsd (virtiofs0) stays free for low-frequency backup/restore I/O
- Data still lives on ZFS → sanoid/syncoid coverage unchanged

### Path mapping

| Layer | Path |
|---|---|
| Proxmox ZFS dataset | `/storage/syncthing` |
| virtiofs tag | `syncthing` |
| Services VM mount point | `/mnt/storage/syncthing` |
| Syncthing container volume (host→container) | `/mnt/storage/syncthing:/mnt/storage/syncthing` |

## Manual steps on Proxmox host (do these before running the playbook)

### 1. Create the ZFS dataset
```bash
# Inherits encryption from the parent 'storage' pool automatically
zfs create storage/syncthing
```

### 2. Register the virtiofs share in Proxmox
The `smb` tag maps to a Proxmox storage entry. Add a matching one for `syncthing`
pointing at `/storage/syncthing`. Mirror the existing `smb` virtiofs entry in
`/etc/pve/storage.cfg` or add it via Proxmox GUI → Datacenter → Storage → Add.

## Ansible changes

| File | Change |
|---|---|
| `group_vars/all.yml` | Add `syncthing: syncthing` under `virtiofs_tags` |
| `roles/create_vm/tasks/create_vm.yml` | Add optional `virtiofs1` block (var: `create_vm_virtiofs1_tag`) |
| `playbooks/proxmox_primary/services.yml` | Pass `create_vm_virtiofs1_tag: "{{ virtiofs_tags.syncthing }}"` |
| `roles/syncthing/meta/main.yml` | Mount `syncthing` virtiofs tag at `/mnt/storage/syncthing` |
| `roles/syncthing/templates/docker-compose.yml.j2` | Change volume to `/mnt/storage/syncthing:/mnt/storage/syncthing` |
| `roles/sanoid/tasks/sanoid.yml` | Add `[storage/syncthing]` block to `sanoid.conf` |
| `roles/syncoid/templates/syncoid.sh.j2` | Add `syncthing` to `DATASETS_TO_BACKUP` array |

### sanoid — add to `sanoid.conf` blockinfile block
```ini
[storage/syncthing]
    use_template = production
```
Reuses existing `template_production` (daily/weekly/monthly/yearly snapshots).

### syncoid — update `DATASETS_TO_BACKUP`
```bash
DATASETS_TO_BACKUP=("smb" "syncthing")
```
Replicates `storage/syncthing` to the backup server alongside `storage/smb`.
