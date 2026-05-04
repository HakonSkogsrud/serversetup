# Plan: Disk Health Monitoring via Uptime Kuma Push

## Goal

Monitor SMART health of all physical drives across Proxmox primary, Proxmox secondary, and the backup server. Uses the existing push-to-Uptime-Kuma pattern (like `mount_probe`, `pihole_health`). One alert per host; failure details in the journal, with missing pushes triggering alerts.

## Approach

New role `disk_health` installs a script + systemd timer on each host. The script runs `smartctl` on configured drives, checks key SMART attributes, logs results to journal (picked up by Alloy→Loki→Grafana), and pushes to Uptime Kuma on success. If any drive fails, push is skipped → Uptime Kuma alerts.

## Drive Inventory

| Host | Drives | Notes |
|------|--------|-------|
| Proxmox primary | 1TB NVMe, 4TB NVMe, 4TB 2.5" SSD | Always available |
| Proxmox secondary | 1 SSD (system) | Always available |
| Backup server | 1 system SSD, 2×4TB HDD | HDDs are ZFS pools (`wdred`, `sgblack`) normally exported — SMART works on block device regardless |

## Steps

### Phase 1: Role creation

1. Create `roles/disk_health/defaults/main.yml` — default thresholds and interval
2. Create `roles/disk_health/tasks/main.yml` — install smartmontools, deploy script + timer
3. Create `roles/disk_health/templates/disk_health.sh.j2` — health check script
4. Create `roles/disk_health/templates/disk-health.service.j2` — systemd service unit
5. Create `roles/disk_health/templates/disk-health.timer.j2` — systemd timer (every 6h)
6. Create `roles/disk_health/handlers/main.yml` — restart timer on config change

### Phase 2: Configuration

7. Add `disk_health_drives` variable to each host_vars (list of `/dev/` paths per host)
8. Add `disk_health_push_url` to `secrets.yml` (one per host)
9. Create 3 push monitors in Uptime Kuma (proxmox, proxmox2, backupserver) with heartbeat interval matching timer

### Phase 3: Integration

10. Include `disk_health` role in `playbooks/proxmox_primary/proxmox.yml`
11. Include `disk_health` role in `playbooks/proxmox_secondary/proxmox2.yml`
12. Include `disk_health` role in `playbooks/backupserver/backupserver.yml`

## Script Logic

```
For each drive in disk_health_drives:
  1. Detect type (NVMe vs SATA) from device path or smartctl info
  2. Run `smartctl -H /dev/X` → check overall SMART health status
  3. For NVMe: check Percentage Used, Available Spare, Temperature
  4. For SATA/HDD: check Reallocated_Sector_Ct, Current_Pending_Sector, Temperature
  5. For SATA/SSD: check reallocated sectors and temperature
  6. Compare against thresholds from defaults

If ALL pass → curl configured push URL
If ANY fail → log which drive + attribute failed, skip push
All results logged via `logger -t disk-health`
```

## Defaults

```yaml
disk_health_drives: []
disk_health_push_url: ""
disk_health_timer_on_boot_sec: "5min"
disk_health_timer_on_unit_active_sec: "6h"
disk_health_timer_accuracy_sec: "5min"

# Thresholds (fail if exceeded/below)
disk_health_temp_max: 55          # °C
disk_health_nvme_pct_used_max: 90 # %
disk_health_nvme_spare_min: 10    # %
disk_health_reallocated_max: 5    # sectors
disk_health_pending_max: 0        # sectors
```

## Relevant Files

- `roles/mount_probe/` — primary template for script + timer + push pattern
- `roles/pihole_health/` — reference for multi-check health script
- `roles/syncoid/templates/syncoid.sh.j2` — confirms backup HDDs are block-accessible even when pools exported
- `host_vars/proxmox.yml`, `host_vars/backupserver.yml` — add drive lists
- `secrets.yml` — add push URLs

## Verification

1. Run script manually on each host, confirm SMART parsing works for NVMe and SATA drives
2. Verify backup server HDDs are readable by smartctl even with pools exported
3. Simulate failure (set temp threshold to 0) → confirm push skipped and journal logs failure
4. Confirm Uptime Kuma receives push and shows green after timer fires
5. Run full playbook, confirm idempotent on second run

## Decisions

- One Uptime Kuma monitor per host (not per drive) — failure details in the journal, missing push triggers alert
- No metrics backend — pass/fail only
- SMART accessible on block devices regardless of ZFS pool state — no import needed
- Script detects drive type automatically (NVMe vs SATA HDD vs SATA SSD)
- Thresholds in role defaults, overridable per host
