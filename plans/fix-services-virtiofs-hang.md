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

### Captured incidents

| # | Hang detected | Boot age | Uptime-kuma | Syncthing | D-state stack | Load |
|---|---|---|---|---|---|---|
| 1 | 2026-05-01 17:44 | ~39 min | unhealthy | Up 39 min (healthy) | `request_wait_answer → fuse_simple_request` | low |
| 2 | 2026-05-02 19:16 | ~18 h | unhealthy | Up 18 h (healthy) | `request_wait_answer → fuse_simple_request → fuse_do_getattr → vfs_statx` | 0.01 |
| 3 | 2026-05-05 03:22:38 Europe/Oslo | after Syncthing split-mount deploy | unhealthy | Moved to `/mnt/storage/syncthing` | `request_wait_answer → fuse_simple_request → fuse_do_getattr → vfs_statx` | low |

**Pattern:** All captured incidents show the same FUSE deadlock — `request_wait_answer` with no response from `virtiofsd`. System is idle (low load, plenty of RAM). Hang time after boot varies widely, ruling out a simple startup race.

## Historical hypothesis: Syncthing saturates virtiofsd

Original working hypothesis. Syncthing bind-mounted `/mnt/storage/smb/Sync` into its Docker container and did continuous inotify + file I/O through the single `virtiofsd` process backing the VM's virtiofs share. This was the best explanation for the first two incidents.

Evidence for:
- Syncthing is the only service with continuous I/O on virtiofs
- Immich/Samba VMs (no continuous virtiofs I/O) never hang
- Both captured incidents show Syncthing running and healthy at time of hang
- Identical FUSE call stack in both incidents (`request_wait_answer`)
- System is idle in both cases — not a resource exhaustion issue

Evidence against:
- Hang does not start immediately after Syncthing starts (39 min in one case, 18 h in another)
- Stopping Syncthing after the hang begins does not clear the stuck mount

## Current hypothesis: another smb-backed container is the remaining live trigger

The Syncthing-specific hypothesis is now materially weaker. The split-mount fix was implemented and the live Syncthing config was verified to use `/mnt/storage/syncthing/Sync`, but `/mnt/storage/smb` still hung afterward.

Current leading candidates are the remaining containers that still bind directly into `/mnt/storage/smb`:
- Loki: `/mnt/storage/smb/loki/data`
- CouchDB: `/mnt/storage/smb/couchdb/data`
- Echovault: `/mnt/storage/smb/echovault-data`

Current ranking:
- Loki is now the strongest application-level suspect because it receives continuous log writes and keeps hot state on `/mnt/storage/smb/loki/data`
- CouchDB is a secondary suspect because Obsidian LiveSync can generate bursts of small document writes, but it is more user-driven than constant
- Echovault is currently the weakest suspect because it is barely used in practice

Evidence for:
- The post-fix incident still affected only `/mnt/storage/smb`, not `/mnt/storage/syncthing`
- Live Syncthing config no longer referenced `/mnt/storage/smb/Sync`
- Current container inspection shows Loki, CouchDB, and Echovault still mounted on smb-backed paths
- Host-side Proxmox checks still show no obvious `virtiofsd` or ZFS failure in the correlated journal window

Evidence against / still unknown:
- No single service has yet been isolated by A/B testing
- Guest-side dumps so far only captured the probe's own stuck `stat`, not another blocked worker process
- Proxmox logs remain quiet, so this could still be a guest/kernel-side virtiofs issue rather than one specific application

## Monitoring (done)

- **Uptime Kuma push monitor** added to `mount_probe` — pushes on each successful probe (every 60s). When the mount hangs, pushes stop and Uptime Kuma alerts after 120s heartbeat timeout.
- Push URL configured in `roles/mount_probe/defaults/main.yml`

## Decision: proceed with the split-mount fix

The A/B test suggested in the original plan is impractical — the hang is intermittent (39 min to 18 h) and the only recovery is a reboot. Two captured incidents with identical signatures plus the Syncthing correlation are sufficient to act.

If the hang still occurs after isolating Syncthing to its own virtiofsd, the hypothesis is disproven and we look at other causes (kernel FUSE bug, virtiofsd memory leak, etc.).

## Status update: what has been done

Completed:
- Added `mount_probe` monitoring and guest-side dump capture for `/mnt/storage/smb`
- Added dedicated `virtiofs1` / `syncthing` share for the services VM
- Moved the Syncthing container bind mount to `/mnt/storage/syncthing`
- Updated the repo so Syncthing config path migration is automated during deploy
- Verified the live Syncthing `config.xml` no longer points at `/mnt/storage/smb/Sync`
- Added a cross-host forensic collector playbook at `playbooks/local/collect_virtiofs_failure.yml`
- Captured correlated guest/host artifacts under `artifacts/virtiofs-failure/`

What the new evidence says:
- The split-mount implementation worked, but it did **not** stop the smb hang
- `/mnt/storage/smb` is still the mount that wedges
- Proxmox host checks around the failure timestamp still show healthy ZFS and no obvious `virtiofsd` error
- The remaining active smb consumers are Loki, CouchDB, and Echovault
- Based on observed usage, Loki should be isolated or tested before CouchDB, and CouchDB before Echovault

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

#### From the repo (preferred now)

Use the collector playbook to capture both sides into local artifacts:

```bash
ansible-playbook playbooks/local/collect_virtiofs_failure.yml
```

If the services VM is already unreachable but you know the alert time, pass it explicitly:

```bash
ansible-playbook playbooks/local/collect_virtiofs_failure.yml -e 'virtiofs_failure_timestamp_hint=2026-05-05T03:22:38+02:00'
```

Artifacts are written under `artifacts/virtiofs-failure/<timestamp>/`.

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

| Layer | Current | New |
|---|---|---|
| Proxmox ZFS dataset | `storage/smb` | `storage/syncthing` |
| virtiofs tag | `smb` (virtiofs0) | `syncthing` (virtiofs1) |
| Services VM mount point | `/mnt/storage/smb` | `/mnt/storage/syncthing` |
| Syncthing container volume | `/mnt/storage/smb/Sync:/mnt/storage/smb/Sync` | `/mnt/storage/syncthing:/mnt/storage/syncthing` |

---

## Step 1: Manual — Proxmox host (do before Ansible)

### 1a. Create ZFS dataset

```bash
# Inherits encryption from parent 'storage' pool automatically
zfs create storage/syncthing
```

### 1b. Move existing Syncthing data

```bash
# Stop the services VM first (or at least stop Syncthing container inside it)
# Then move data on the Proxmox host:
mv /storage/smb/Sync/* /storage/syncthing/
# Verify
ls -la /storage/syncthing/
```

### 1c. Register virtiofs share in Proxmox

Add a virtiofs-capable storage entry for `syncthing`. Either:

**Option A: Edit `/etc/pve/storage.cfg`** — add a block mirroring the existing `smb` entry but pointing at `/storage/syncthing` with tag `syncthing`.

**Option B: Proxmox GUI** → Datacenter → Storage → Add → Directory:
- ID: `syncthing`
- Directory: `/storage/syncthing`
- Content: (none needed, used only for virtiofs)
- Enable: yes

### 1d. Attach virtiofs1 to services VM

```bash
qm set 4001 --virtiofs1 'syncthing,expose-xattr=1'
```

Reboot the services VM after this step.

---

## Step 2: Ansible changes

### 2a. `group_vars/all.yml` — add virtiofs tag

```yaml
virtiofs_tags:
  smb: smb
  syncthing: syncthing    # <-- add this line
```

### 2b. `roles/create_vm/tasks/create_vm.yml` — add virtiofs1 support

Add a new task after the existing `Set virtiofs0 configuration` task:

```yaml
- name: Set virtiofs1 configuration
  ansible.builtin.command:
    cmd: "qm set '{{ create_vm_newid }}' --virtiofs1 '{{ create_vm_virtiofs1_tag }},expose-xattr=1'"
  vars:
    current_virtiofs: "{{ (create_vm_config_json.stdout | from_json).virtiofs1 | default('') }}"
  when:
    - create_vm_virtiofs1_tag is defined
    - create_vm_virtiofs1_tag | length > 0
    - create_vm_virtiofs1_tag not in current_virtiofs
  notify: "reboot vm"
  changed_when: true
```

Add to `roles/create_vm/vars/main.yml`:

```yaml
create_vm_virtiofs1_tag: ""
```

### 2c. `playbooks/proxmox_primary/services.yml` — pass virtiofs1 tag to create_vm

In the `Create services VM` play, add the var:

```yaml
create_vm_virtiofs1_tag: "{{ virtiofs_tags.syncthing }}"
```

### 2d. `roles/syncthing/meta/main.yml` — mount the new virtiofs share

Change from:

```yaml
dependencies:
  - { role: mount_virtiofs }
  - { role: docker }
```

To:

```yaml
dependencies:
  - role: mount_virtiofs
    vars:
      mount_virtiofs_tag: "{{ virtiofs_tags.syncthing }}"
      mount_virtiofs_path: "/mnt/storage/syncthing"
  - { role: docker }
```

### 2e. `roles/syncthing/templates/docker-compose.yml.j2` — update volume path

Change:

```yaml
    volumes:
      - ./config:/var/syncthing/config
      - /mnt/storage/smb/Sync:/mnt/storage/smb/Sync
```

To:

```yaml
    volumes:
      - ./config:/var/syncthing/config
      - /mnt/storage/syncthing:/mnt/storage/syncthing
```

**Note:** After deploying, update the Syncthing GUI folder paths from `/mnt/storage/smb/Sync/...` to `/mnt/storage/syncthing/...` for each synced folder.

### 2f. `roles/sanoid/tasks/sanoid.yml` — snapshot the new dataset

Change the `block:` in the blockinfile task from:

```ini
[storage/smb]
    use_template = production
    recursive = yes
```

To:

```ini
[storage/smb]
    use_template = production
    recursive = yes

[storage/syncthing]
    use_template = production
    recursive = yes
```

### 2g. `roles/syncoid/templates/syncoid.sh.j2` — replicate the new dataset

Change:

```bash
DATASETS_TO_BACKUP=("smb")
```

To:

```bash
DATASETS_TO_BACKUP=("smb" "syncthing")
```

This replicates `storage/syncthing` to the backup server alongside `storage/smb`.

---

## Step 3: Deploy and verify

```bash
# Deploy all Ansible changes
ansible-playbook playbooks/proxmox_primary/services.yml

# Verify mount on services VM
ansible services -m shell -a "findmnt --types virtiofs"
# Should show both /mnt/storage/smb (smb) and /mnt/storage/syncthing (syncthing)

# Verify Syncthing sees its data
ansible services -m shell -a "docker exec syncthing ls /mnt/storage/syncthing"

# Verify sanoid snapshots the new dataset (on proxmox)
ansible proxmox -b -m shell -a "sanoid --configcheck"

# Trigger a syncoid run and check it backs up both datasets
ansible proxmox -b -m shell -a "systemctl start syncoid.service"
```

Status: completed. The split mount exists on the services VM and live Syncthing config now points to `/mnt/storage/syncthing/Sync`.

## Step 4: Post-deploy — update Syncthing folder paths

In Syncthing web UI (`http://10.0.0.44:8384`), edit each synced folder and update the path from `/mnt/storage/smb/Sync/<folder>` to `/mnt/storage/syncthing/<folder>`.

Status: no longer a manual-only step. The repo now automates migration of existing Syncthing folder paths during deploy, though the live system was also manually verified.

## Next steps

1. Keep the collector playbook as the standard incident procedure and run it immediately after each alert, with a timestamp hint if needed.
2. Prioritize Loki as the next suspect, then CouchDB, then Echovault.
3. Do a controlled isolation test: stop Loki after reboot, wait for the next incident window, and compare whether `/mnt/storage/smb` still hangs.
4. If the hang still occurs with Loki stopped, repeat the same test with CouchDB stopped.
5. Only test Echovault if Loki and CouchDB are ruled out, since Echovault is barely used.
6. If one service correlates strongly, split that service onto its own virtiofs share or move its hot data off the shared smb mount.
7. If hangs continue after isolating all active smb-backed containers, escalate the investigation toward a guest/kernel/virtiofs bug rather than an application-specific workload issue.
