# Plan: Monitor Scheduled Updates via Grafana/Loki Alerts

## Goal

Detect when `scheduled-update.timer` fails silently on any host. Instead of adding 11 Uptime Kuma push monitors (one per host), use the existing Loki log pipeline and Grafana alerting to catch missing or failed updates.

## Why Grafana/Loki Instead of Uptime Kuma

- `scheduled-update` runs on **all 11 hosts** — that's too many push endpoints for Uptime Kuma
- Every host already runs **Alloy → Loki** log shipping
- The `scheduled_update` script already logs success/failure to the systemd journal
- Grafana is already provisioned with Loki as its datasource

## Current State

| Component | Status |
|-----------|--------|
| Alloy log labels | `host`, `unit`, `syslog_identifier` available |
| scheduled_update logs | Tags with `scheduled_update`, logs `"Package update completed successfully"` on success, `"Package update failed"` on error |
| Grafana alerting | **Not configured** — no `provisioning/alerting/` directory exists |
| Loki ruler | Configured in loki-config.yml (`rules_directory: /loki/rules`) but no rules deployed |
| Alertmanager | URL configured in Loki (`localhost:9093`) but **not deployed** |

## Approach: Grafana-Managed Alerts

Use **Grafana-managed alert rules** (stored in Grafana's database) rather than Loki ruler rules. This avoids needing to deploy an Alertmanager instance and keeps everything in the Grafana UI.

### Alert Rule Design

**Query:** Check if each host has logged a successful update in the last 48 hours (updates run daily, 48h gives a full grace period for one missed run):

```logql
count_over_time({unit="scheduled-update.service"} |= "Package update completed successfully" [48h])
```

**Alert condition:** Fire when `count_over_time` returns **0** (or no data) for any `host` label — meaning that host hasn't had a successful update in 48 hours.

**Grouping:** Alert per `host` label so you know exactly which host stopped updating.

### Notification

Options (pick one during implementation):

1. **Grafana → Email** — simplest, use Grafana's built-in SMTP contact point
2. **Grafana → Uptime Kuma status page** — push a single "all updates healthy" heartbeat from Grafana (1 endpoint instead of 11)
3. **Grafana → Webhook** — send to any endpoint (ntfy, Slack, Discord, etc.)

## Implementation Steps

### 1. Create Grafana alert provisioning structure

Add to the Grafana role:

```
roles/grafana/
├── templates/
│   ├── provisioning/
│   │   └── alerting/
│   │       └── scheduled-update-alerts.yml.j2
```

### 2. Define the alert rule

The provisioned alert YAML should contain:

- **Alert name:** `Scheduled Update Missing`
- **Folder:** `Infrastructure`
- **Evaluation interval:** Every 6 hours (no need to check more often for a daily job)
- **For duration:** 0s (fire immediately when condition is met)
- **LogQL query:** Per-host count of successful updates over 48h window
- **Condition:** Alert when count == 0 or no data for any host
- **Labels:** `severity: warning`, `service: scheduled-update`
- **Annotations:** Include `host` label and a summary message

### 3. Configure a contact point

Add a notification contact point (email, webhook, or Uptime Kuma push) to the Grafana provisioning.

### 4. Deploy and test

```bash
# Deploy updated Grafana config
ansible-playbook playbooks/proxmox_primary/services.yml --tags grafana

# Verify in Grafana UI:
# 1. Alerting → Alert rules → check "Scheduled Update Missing" exists
# 2. Alerting → Contact points → verify notification target
# 3. Test by checking the LogQL query in Explore view
```

### 5. Validate the query works

Run in Grafana Explore to confirm data exists per host:

```logql
count_over_time({unit="scheduled-update.service"} |= "Package update completed successfully" [48h]) by (host)
```

Expected: one result per host with count ≥ 1.

## Hosts Covered

| Host | Expected update frequency |
|------|--------------------------|
| proxmox | Daily |
| proxmox2 | Daily |
| services | Daily |
| immich | Daily |
| samba | Daily |
| github-runner | Daily |
| subnet-router | Daily |
| subnet-router-secondary | Daily |
| pihole-secondary | Daily |
| backupserver | Daily |
| fedora | Daily |

## Future Extensions

- Add similar alert for `scheduled-reboot.timer` (weekly on most hosts, weekly Sunday on services) — check for reboot log entries per host within expected window
- Add alert for any `user.err` priority log from `scheduled_update` syslog identifier — catches failures even if the timer runs
- Dashboard panel showing last successful update time per host
