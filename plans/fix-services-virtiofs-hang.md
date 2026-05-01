# Fix: services VM hangs on /mnt/storage/smb

## Problem

The services VM's virtiofs mount at `/mnt/storage/smb` periodically becomes completely unresponsive. Any process that touches the path enters kernel uninterruptible sleep (`D` state) on `request_wait_answer [fuse]` and cannot be killed — only a VM reboot clears it.

## Observed behaviour

- Proxmox host: `/storage/smb` is fine
- Immich VM: `/mnt/storage/smb` via virtiofs works fine
- Services VM: `/mnt/storage/smb` **hangs** — specific to this VM
- Kernel reports `INFO: task stat:… blocked for more than N seconds` with a FUSE call stack
- `timeout` cannot kill the stuck `stat` — the process is in D-state and ignores all signals including `SIGKILL`
- `systemctl stop` on a unit whose process is stuck on the mount will itself hang

## Hypothesis: Syncthing saturates virtiofsd

Working hypothesis, **not proven**. Syncthing bind-mounts `/mnt/storage/smb/Sync` into its Docker container and does continuous inotify + file I/O through the single `virtiofsd` process backing the VM's virtiofs share. This may saturate the FUSE request queue and block all other mount access.

Evidence for:
- Syncthing is the only service with continuous I/O on virtiofs
- Immich/Samba VMs (no continuous virtiofs I/O) never hang

Evidence against:
- Hang does not start immediately after Syncthing starts
- Stopping Syncthing after the hang begins does not clear the stuck mount

Do not implement the Syncthing split-mount fix until a controlled A/B test or captured host-side `virtiofsd` state confirms the hypothesis.

---

## mount_probe role

The `mount_probe` role (`roles/mount_probe/`) deploys a systemd timer + oneshot service that probes `/mnt/storage/smb` every minute and captures diagnostics on failure.

### How it works

1. `mount-probe.timer` fires every 60 seconds (`OnUnitActiveSec=1min`)
2. `mount-probe.service` runs `/usr/local/bin/mount_probe.sh`
3. The script launches `stat /mnt/storage/smb` inside a **transient systemd unit** (`systemd-run --unit mount_probe-check-<ts>-<pid>`) so the probe process is isolated from the main script
4. It polls the transient unit's `ActiveState` for up to 10 seconds
5. If the transient unit completes with exit 0 → mount is healthy, write `OK` to state file
6. If the transient unit does not complete within 10 seconds → mount is hung:
   - Kills the transient unit (`SIGKILL` + `stop --no-block`)
   - Writes `FAIL` to state file with boot ID and timestamp
   - Logs `MOUNT_PROBE_TIMEOUT` to journal (`journalctl -t mount_probe`)
   - Captures a diagnostic dump to `/var/log/mount_probe/`
   - Stops probing for the rest of the current boot (prevents stacking stuck processes)
7. On a new boot or after state file removal, probing resumes automatically
8. If the mount recovers across boots, logs `MOUNT_PROBE_RECOVERY`

### Key files on the services VM

| Path | Purpose |
|---|---|
| `/usr/local/bin/mount_probe.sh` | Probe script |
| `/etc/systemd/system/mount-probe.service` | Oneshot service unit |
| `/etc/systemd/system/mount-probe.timer` | Timer unit (1min interval) |
| `/var/lib/mount_probe/state` | State file: `OK\|FAIL <boot_id> <timestamp>` |
| `/var/log/mount_probe/` | Diagnostic dump files |

### Check that the probe is working

```bash
# Timer should be active and show a recent trigger time
systemctl status mount-probe.timer --no-pager

# Service should show recent successful completions (not stuck in "activating")
systemctl status mount-probe.service --no-pager

# State file should exist and show OK with a recent timestamp
cat /var/lib/mount_probe/state

# Journal should have recent entries (empty = probe never detected a failure, which is fine)
journalctl -t mount_probe -n 20 --no-pager

# Dump directory should be empty during normal operation
ls -lt /var/log/mount_probe/
```

If `mount-probe.service` shows `Active: activating (start)` for more than ~15 seconds, it is stuck on a wedged mount (old script version) or `systemd-run` failed to launch. After deploying the current version, the service should never stay in `activating` for more than the 10-second check timeout plus a few seconds of overhead.

### When you discover the mount is hung

#### On the services VM

Do **not** run any command that touches `/mnt/storage/smb` — it will enter D-state and become unkillable.

```bash
# Check probe state and dump
cat /var/lib/mount_probe/state
ls -lt /var/log/mount_probe/
# Read the latest dump (contains D-state stacks, docker ps, kernel log, etc.)
cat /var/log/mount_probe/$(ls -1t /var/log/mount_probe/ | head -1)

# Confirm the mount is stuck (without touching it)
findmnt --types virtiofs --output TARGET,SOURCE,FSTYPE,OPTIONS
mount | grep virtiofs

# List D-state processes and their kernel stacks
ps -eo pid,ppid,stat,wchan:32,comm,args | grep ' D '
for pid in $(ps -eo pid=,stat= | awk '$2 ~ /D/ {print $1}'); do
  echo "===== PID $pid ====="
  cat /proc/$pid/stack
done

# Recent kernel messages (hung task warnings)
journalctl -k -n 200 --no-pager

# Docker container status (to correlate with Syncthing hypothesis)
docker ps --format 'table {{.Names}}\t{{.Status}}'
```

#### On the Proxmox host (at the same time)

```bash
date --iso-8601=seconds
qm config 4001
ps -ef | grep '[v]irtiofsd'
journalctl -k -n 200 --no-pager
zpool iostat -v 1 5
```

Compare the `virtiofsd` process backing the services VM with those of other VMs. If the services VM's `virtiofsd` is stuck while the pool is otherwise healthy, that supports the virtiofs contention theory.

#### Recovery

The only reliable recovery is rebooting the services VM. D-state processes cannot be killed from userspace. After reboot, the probe will automatically resume on the new boot.

To re-arm the probe without a full reboot (only works if the mount has actually recovered):

```bash
rm -f /var/lib/mount_probe/state
systemctl start mount-probe.service
```

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
