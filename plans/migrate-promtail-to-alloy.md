# Migrate Promtail to Grafana Alloy

## Why

Promtail is deprecated. Grafana removed the Promtail binary from Loki releases starting at v3.7 (the current role pins v3.6.2 for this reason). Grafana Alloy is the official replacement — it uses a component-based config language and covers the same log collection use cases.

## Current Promtail deployment

Promtail runs as a native binary + systemd service on **9 hosts**. Two variants exist based on the `promtail_docker_installed` variable:

| Host | Docker logs | Notes |
|---|---|---|
| services | yes | Also runs Loki (receiver) |
| immich | yes | |
| proxmox | no | Hypervisor (not a VM) |
| proxmox2 | no | Secondary hypervisor |
| samba | no | |
| subnet-router | no | |
| subnet-router-secondary | no | |
| pihole-secondary | no | |
| github-runner | no | |

### What Promtail currently collects

1. **systemd-journal** — all journal entries (max_age 12h), labels: `job`, `host`, `unit`, `syslog_identifier`, `comm`
2. **system** — `/var/log/messages`
3. **auth** — `/var/log/secure`
4. **varlog** — all `*.log` files in `/var/log/`
5. **docker** (conditional) — Docker container logs via `/var/run/docker.sock` service discovery

All logs push to `http://<services_ip>:3100/loki/api/v1/push`.

### Current role files

| File | Purpose |
|---|---|
| `roles/promtail/defaults/main.yml` | Variables (version, loki url, port, paths, docker flag) |
| `roles/promtail/tasks/promtail.yml` | Download binary, deploy config + systemd unit |
| `roles/promtail/handlers/main.yml` | Restart handler |
| `roles/promtail/templates/promtail-config.yml.j2` | YAML config with scrape jobs |
| `roles/promtail/templates/promtail.service.j2` | systemd unit |

### Cross-references to update

| File | Reference |
|---|---|
| `playbooks/proxmox_primary/services.yml` | `promtail_docker_installed: true`, role inclusion |
| `playbooks/proxmox_primary/immich.yml` | `promtail_docker_installed: true`, role inclusion |
| `playbooks/proxmox_primary/proxmox.yml` | role inclusion |
| `playbooks/proxmox_primary/samba.yml` | role inclusion |
| `playbooks/proxmox_primary/subnet_router.yml` | role inclusion |
| `playbooks/proxmox_primary/github_runner.yml` | role inclusion |
| `playbooks/proxmox_secondary/proxmox2.yml` | role inclusion |
| `playbooks/proxmox_secondary/subnet_router_secondary.yml` | role inclusion |
| `playbooks/proxmox_secondary/pihole_secondary.yml` | role inclusion |
| `README.md` | Promtail role description in table |

## Alloy equivalents

Alloy uses a component-based config language (`.alloy` files) instead of YAML. The Promtail scrape jobs map to:

| Promtail job | Alloy component |
|---|---|
| systemd-journal | `loki.source.journal` |
| system (`/var/log/messages`) | `local.file_match` + `loki.source.file` |
| auth (`/var/log/secure`) | `local.file_match` + `loki.source.file` |
| varlog (`/var/log/*.log`) | `local.file_match` + `loki.source.file` |
| docker | `discovery.docker` + `loki.source.docker` |
| push to Loki | `loki.write` |

### Alloy config template (non-Docker hosts)

```alloy
// Push logs to Loki
loki.write "default" {
  endpoint {
    url = "http://{{ alloy_loki_url }}/loki/api/v1/push"
  }
}

// Relabel journal fields to match current Promtail labels
loki.relabel "journal" {
  forward_to = []

  rule {
    source_labels = ["__journal__systemd_unit"]
    target_label  = "unit"
  }
  rule {
    source_labels = ["__journal_syslog_identifier"]
    target_label  = "syslog_identifier"
  }
  rule {
    source_labels = ["__journal__comm"]
    target_label  = "comm"
  }
}

// systemd journal
loki.source.journal "default" {
  forward_to    = [loki.write.default.receiver]
  relabel_rules = loki.relabel.journal.rules
  max_age       = "12h"
  labels        = {
    job  = "systemd-journal",
    host = constants.hostname,
  }
}

// /var/log/messages
local.file_match "syslog" {
  path_targets = [{ __path__ = "/var/log/messages" }]
}
loki.source.file "syslog" {
  targets    = local.file_match.syslog.targets
  forward_to = [loki.write.default.receiver]

  tail_from_end = true
}

// /var/log/secure
local.file_match "auth" {
  path_targets = [{ __path__ = "/var/log/secure" }]
}
loki.source.file "auth" {
  targets    = local.file_match.auth.targets
  forward_to = [loki.write.default.receiver]

  tail_from_end = true
}

// /var/log/*.log
local.file_match "varlog" {
  path_targets = [{ __path__ = "/var/log/*.log" }]
}
loki.source.file "varlog" {
  targets    = local.file_match.varlog.targets
  forward_to = [loki.write.default.receiver]

  tail_from_end = true
}
```

### Additional Docker block (services + immich)

```alloy
// Docker container discovery
discovery.docker "containers" {
  host = "unix:///var/run/docker.sock"
  refresh_interval = "30s"
}

// Docker log collection
loki.source.docker "default" {
  host       = "unix:///var/run/docker.sock"
  targets    = discovery.docker.containers.targets
  forward_to = [loki.write.default.receiver]
  labels     = { host = constants.hostname }
}
```

## Installation method

Alloy is installed via the Grafana RPM/DEB repository and runs as a systemd service (`alloy.service`). No binary download needed.

- **AlmaLinux (VMs)**: `dnf install alloy` after adding the Grafana repo
- **Debian (Proxmox)**: `apt install alloy` after adding the Grafana repo
- Config file: `/etc/alloy/config.alloy`
- Environment file: `/etc/sysconfig/alloy` (RHEL) or `/etc/default/alloy` (Debian)
- Storage path: `/var/lib/alloy`
- User: `alloy` (must be in `adm` and `systemd-journal` groups; for Docker hosts, also `docker`)

## Ansible changes

### New role: `roles/alloy/`

| File | Purpose |
|---|---|
| `defaults/main.yml` | Variables: `alloy_loki_url`, `alloy_docker_installed` |
| `tasks/main.yml` | Import tasks |
| `tasks/alloy.yml` | Add Grafana repo, install alloy, deploy config, add user to groups, enable service |
| `handlers/main.yml` | Restart alloy handler |
| `templates/config.alloy.j2` | Alloy config template (conditionally includes Docker block) |

### Playbook changes

In every playbook that currently includes `promtail`:

1. Replace `- promtail` with `- alloy` in the roles list
2. Rename `promtail_docker_installed` to `alloy_docker_installed` where set

### Cleanup tasks (add to alloy role or run once)

On each host, the old Promtail installation needs removal:

```yaml
- name: Stop and disable promtail
  ansible.builtin.systemd:
    name: promtail
    state: stopped
    enabled: false
  ignore_errors: true

- name: Remove promtail binary
  ansible.builtin.file:
    path: /usr/local/bin/promtail
    state: absent

- name: Remove promtail config
  ansible.builtin.file:
    path: /etc/promtail
    state: absent

- name: Remove promtail service unit
  ansible.builtin.file:
    path: /etc/systemd/system/promtail.service
    state: absent
  notify: Reload systemd

- name: Remove promtail positions
  ansible.builtin.file:
    path: /var/lib/promtail
    state: absent
```

### README.md

Update the role table: replace the Promtail row with Alloy.

## Rollout order

Roll out one host at a time. Verify logs appear in Grafana before proceeding.

1. **services** — most complex (Docker + Loki receiver on same host), validates the full pipeline
2. **immich** — second Docker host
3. **proxmox** — Debian-based, tests the apt install path
4. **proxmox2** — confirms secondary hypervisor
5. **Remaining VMs** — samba, subnet-router, subnet-router-secondary, pihole-secondary, github-runner

### Verification per host

```bash
# Alloy is running
systemctl status alloy

# Alloy can reach Loki
journalctl -u alloy -n 50 --no-pager | grep -i error

# Logs appear in Grafana
# Query: {host="<hostname>"} in Loki/Grafana and confirm recent entries
```

## Post-deploy verification (all hosts)

After running `deploy-to-homelab`, verify the full fleet in one pass:

```bash
# 1. Check alloy is active on all hosts
ansible all -b -m command -a "systemctl is-active alloy"

# 2. Check for errors in alloy logs (last 20 lines)
ansible all -b -m shell -a "journalctl -u alloy -n 20 --no-pager | grep -i error || echo OK"

# 3. Confirm every host is delivering logs to Loki (query from services VM)
for host in services immich samba subnet-router subnet-router-secondary pihole-secondary github-runner proxmox proxmox2; do
  echo -n "$host: "
  ansible services -b -m shell -a "curl -sG 'http://localhost:3100/loki/api/v1/query_range' \
    --data-urlencode 'query={host=\"$host\"}' \
    --data-urlencode 'limit=1' \
    --data-urlencode 'since=5m'" 2>/dev/null | grep -q '"result":\[{' && echo "OK" || echo "NO LOGS"
done

# 4. Verify Docker hosts have container logs
ansible services -b -m shell -a "curl -sG 'http://localhost:3100/loki/api/v1/query_range' \
  --data-urlencode 'query={host=\"services\", source=\"docker\"}' \
  --data-urlencode 'limit=1' --data-urlencode 'since=10m'"

# 5. Open Grafana and confirm dashboards still work (label compat)
#    - Explore → Loki → {job="systemd-journal"} should show all hosts
#    - Any alerts/dashboards filtering on unit, syslog_identifier, comm should still resolve
```

## Label compatibility

The current Promtail config attaches these labels: `job`, `host`, `unit`, `syslog_identifier`, `comm`, `container_name`. Any Grafana dashboards or alert rules that filter on these labels must continue to work.

The Alloy config template above preserves all of these labels through `loki.relabel` rules and explicit `labels` blocks. After migration, verify existing Grafana dashboard queries still return results.

## Lessons learned (from samba + services migration)

### Architecture decisions

- **Dropped file tailing entirely** — On AlmaLinux 9, `/var/log/messages` and `/var/log/secure` are just rsyslog copies of journal data. Tailing them causes double-ingestion with different labels. Same for `/var/log/*.log` (dnf, cloud-init). The idiomatic Alloy setup is **journal + Docker only**.
- **No root override needed** — Without file tailing, the `alloy` user just needs `systemd-journal` group for journal access and `docker` group for Docker socket access. No need to run as root.

### Pitfalls encountered

1. **`constants.hostname` gives FQDN** — On these VMs, `constants.hostname` resolves to `samba.local` not `samba`. This breaks label compatibility with old Promtail which used `{{ ansible_hostname }}`. Fix: use `{{ inventory_hostname }}` in the Jinja2 template (always available, doesn't need fact gathering).

2. **Data directory ownership after root→alloy switch** — If alloy ever ran as root (even briefly), `/var/lib/alloy/data/` will be owned by root. The `alloy` user then can't write positions files. The role now includes a `chown -R alloy:alloy /var/lib/alloy` task to fix this idempotently.

3. **`ansible_hostname` is undefined without fact gathering** — When deploying via `ansible <host> -m include_role`, facts aren't gathered. Use `inventory_hostname` instead (always defined).

4. **Duplicate Jinja2 conditional blocks** — The template must have exactly one Docker block inside `{% if alloy_docker_installed %}`. A duplicate causes Alloy to fail with "block already declared".

5. **Loki readiness delays** — After Loki restarts (e.g., health-check triggered), it reports "Ingester not ready: waiting for 15s". During this time alloy may batch and retry. Don't panic if logs don't appear immediately — wait ~30s.

6. **SELinux and firewall** — VMs run SELinux and firewalld. The Grafana RPM package sets correct SELinux contexts for `/usr/bin/alloy` and `/etc/alloy/`. The journal is accessible via group membership without SELinux issues. Docker socket access works with the `docker` group. No firewall rules needed since alloy only makes outbound connections to Loki.

7. **Proxmox hosts are Debian 13 (trixie)** — `apt-key` is removed. Must use `get_url` to download GPG key + `gpg --dearmor` to `/usr/share/keyrings/grafana.gpg`, then reference it in the apt source with `[signed-by=/usr/share/keyrings/grafana.gpg]`. The role now handles this automatically via `ansible_os_family` conditionals.

8. **Fact gathering required** — The role uses `ansible_os_family` to branch between RPM/Debian install paths. A `setup` task with `gather_subset: os_family` is included at the top of the role tasks to ensure this fact is available even in ad-hoc mode.

### Deployment checklist per VM

```bash
# 1. Deploy
ansible <host> -b -m include_role -a name=alloy -e @secrets.yml [-e alloy_docker_installed=true]

# 2. Verify service running (no errors)
ansible <host> -b -m shell -a 'systemctl status alloy --no-pager -l | head -20'

# 3. Generate test log and verify in Loki (wait ~12s for batch)
ansible <host> -b -m shell -a 'logger -t alloy-test "verify-$(date +%s)"'
# Then query Loki: {host="<inventory_hostname>"} |= "alloy-test"

# 4. Stop promtail
ansible <host> -b -m systemd -a 'name=promtail state=stopped enabled=false'

# 5. Update playbook: replace `- promtail` with `- alloy`
```

## Delete old role

After all hosts are migrated and verified:

1. Delete `roles/promtail/`
2. Remove any remaining `promtail_*` variables from `group_vars/` or `host_vars/`
3. Commit
