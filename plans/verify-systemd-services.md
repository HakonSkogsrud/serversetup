# Plan: Verify All Systemd Services and Timers

## Goal

Create an Ansible playbook that verifies all systemd services and timers managed by this repository are enabled and running (or active for timers).

## Approach

A single verification playbook that runs against all hosts, checking the expected services/timers per host. Uses `ansible.builtin.systemd` with `status` or `ansible.builtin.command` with `systemctl` to assert state.

## Expected Services/Timers Per Host

### proxmox (Proxmox primary)

| Unit | Type | Expected State |
|------|------|----------------|
| `alloy.service` | service | enabled + running |
| `create-template-vm.timer` | timer | enabled + active |
| `sanoid.timer` | timer | enabled + active |
| `syncoid.timer` | timer | enabled + active |
| `scheduled-update.timer` | timer | enabled + active |
| `zfs-load-key.service` | service | enabled |

### proxmox2 (Proxmox secondary)

| Unit | Type | Expected State |
|------|------|----------------|
| `alloy.service` | service | enabled + running |
| `create-template-vm.timer` | timer | enabled + active |
| `scheduled-update.timer` | timer | enabled + active |

### services

| Unit | Type | Expected State |
|------|------|----------------|
| `alloy.service` | service | enabled + running |
| `docker.service` | service | enabled + running |
| `scheduled-update.timer` | timer | enabled + active |
| `scheduled-reboot.timer` | timer | enabled + active |
| `docker-auto-update.timer` | timer | enabled + active |
| `couchdb-backup.timer` | timer | enabled + active |
| `pihole-health.timer` | timer | enabled + active |
| `mount-probe.timer` | timer | enabled + active |
| `uptimekuma_backup.timer` | timer | enabled + active |
| `vaultwarden_backup.timer` | timer | enabled + active |
| `firewalld.service` | service | enabled + running |

### immich

| Unit | Type | Expected State |
|------|------|----------------|
| `alloy.service` | service | enabled + running |
| `docker.service` | service | enabled + running |
| `scheduled-update.timer` | timer | enabled + active |
| `scheduled-reboot.timer` | timer | enabled + active |
| `immich-backup.timer` | timer | enabled + active |
| `docker-auto-update.timer` | timer | enabled + active |

### samba

| Unit | Type | Expected State |
|------|------|----------------|
| `alloy.service` | service | enabled + running |
| `smb.service` | service | enabled + running |
| `nmb.service` | service | enabled + running |
| `scheduled-update.timer` | timer | enabled + active |
| `scheduled-reboot.timer` | timer | enabled + active |

### github-runner

| Unit | Type | Expected State |
|------|------|----------------|
| `alloy.service` | service | enabled + running |
| `github-runner.service` | service | enabled + running |
| `firewalld.service` | service | enabled + running |
| `scheduled-update.timer` | timer | enabled + active |
| `scheduled-reboot.timer` | timer | enabled + active |

### subnet-router

| Unit | Type | Expected State |
|------|------|----------------|
| `alloy.service` | service | enabled + running |
| `tailscaled.service` | service | enabled + running |
| `firewalld.service` | service | enabled + running |
| `scheduled-update.timer` | timer | enabled + active |
| `scheduled-reboot.timer` | timer | enabled + active |

### subnet-router-secondary

| Unit | Type | Expected State |
|------|------|----------------|
| `alloy.service` | service | enabled + running |
| `tailscaled.service` | service | enabled + running |
| `firewalld.service` | service | enabled + running |
| `scheduled-update.timer` | timer | enabled + active |
| `scheduled-reboot.timer` | timer | enabled + active |

### pihole-secondary

| Unit | Type | Expected State |
|------|------|----------------|
| `alloy.service` | service | enabled + running |
| `docker.service` | service | enabled + running |
| `scheduled-update.timer` | timer | enabled + active |
| `scheduled-reboot.timer` | timer | enabled + active |
| `internet-monitor.timer` | timer | enabled + active |

### backupserver

| Unit | Type | Expected State |
|------|------|----------------|
| `tailscaled.service` | service | enabled + running |
| `scheduled-update.timer` | timer | enabled + active |
| `scheduled-reboot.timer` | timer | enabled + active |

### fedora (local)

| Unit | Type | Expected State |
|------|------|----------------|
| `scheduled-update.timer` | timer | enabled + active |

---

## Implementation: Verification Playbook

Create `playbooks/verify_services.yml` — run with:

```bash
ansible-playbook playbooks/verify_services.yml --vault-password-file=<vault-file>
```

The playbook uses `ansible.builtin.systemd_service` info gathering and asserts on the `status` and `enabled` fields per host.

### Key Design Decisions

1. **Per-host variable lists** — each host gets a list of `expected_services` (enabled+running) and `expected_timers` (enabled+active).
2. **Fail fast with clear output** — uses `assert` module to produce human-readable failure messages showing which unit failed and on which host.
3. **No changes made** — purely read-only verification (check mode not even needed, no state changes).
4. **Handles oneshot services** — for timer-triggered `.service` units, we only check the `.timer` is active (the service itself is inactive between runs, which is correct).

---

## Script Alternative (for ad-hoc SSH checking)

For quick verification without running the full playbook, a bash script that SSHs into each host:

```bash
scripts/verify-systemd.sh
```

Uses a config map of host→units and runs `systemctl is-enabled` + `systemctl is-active` over SSH, producing a colored pass/fail report.

---

## Uptime Kuma Push Monitor Gaps

The following timer-driven services **do NOT** push a heartbeat to Uptime Kuma but **probably should**, since they are periodic tasks where silent failure would go unnoticed:

| Service/Timer | Role | Recommendation |
|---------------|------|----------------|
| `vaultwarden_backup.timer` | `vaultwarden` | **Should push** — backup failure is critical and wouldn't be noticed otherwise |
| `uptimekuma_backup.timer` | `uptimekuma` | **Should push** — even though it backs up UptimeKuma itself, a separate push monitor would catch failures (UptimeKuma can monitor its own push endpoints) |
| `docker-auto-update.timer` | `docker_auto_update` | **Should push** — silent update failures could leave containers on old/vulnerable images |
| `scheduled-update.timer` | `scheduled_update` | **Should push** — OS update failures leave systems unpatched; particularly important since this runs on every host |

The following do NOT need push monitors:

| Service/Timer | Role | Why not |
|---------------|------|---------|
| `mount-probe.timer` | `mount_probe` | Already monitored via Alloy metrics; its purpose is to detect mount hangs for alerting |
| `scheduled-reboot.timer` | `scheduled_reboot` | A reboot kills the machine anyway — Uptime Kuma HTTP/ping monitors already detect if a host doesn't come back up |
| `github-runner.service` | `github_runner` | Long-running daemon — monitored by Uptime Kuma HTTP check or GitHub's own runner status |
| `zfs-load-key.service` | `proxmox_config` | Boot-time oneshot — if it fails, ZFS pools won't mount and everything downstream fails visibly |
