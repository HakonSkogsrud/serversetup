# Plan: Add Uptime Kuma Push Monitors to Missing Services

## Services that should push but don't

| Timer | Role | Why it matters |
|-------|------|----------------|
| `vaultwarden_backup.timer` | `vaultwarden` | Backup failure is critical, would go unnoticed |
| `uptimekuma_backup.timer` | `uptimekuma` | UptimeKuma can monitor its own push endpoints — silent failure is still bad |
| `docker-auto-update.timer` | `docker_auto_update` | Failed updates leave containers on vulnerable images |
| `scheduled-update.timer` | `scheduled_update` | OS update failures leave systems unpatched (runs on every host!) |

## Existing pattern to follow

All other roles use this curl idiom at the end of their bash script (on success only):

```bash
HTTP_STATUS=$(curl -s -m 10 -o /dev/null -w "%{http_code}" "{{ <role>_uptimekuma_push_url }}")
```

Each role defines a default variable (empty string) and the push is conditional on it being set:

```yaml
# defaults/main.yml
<role>_uptimekuma_push_url: ""
```

```bash
# At end of script, after success
{% if <role>_uptimekuma_push_url %}
curl -s -m 10 -o /dev/null -w "%{http_code}" "{{ <role>_uptimekuma_push_url }}"
{% endif %}
```

## Implementation steps

1. **`vaultwarden`** — Add `vaultwarden_backup_uptimekuma_push_url` default, add curl to `vaultwarden_backup.sh.j2`
2. **`uptimekuma`** — Add `uptimekuma_backup_uptimekuma_push_url` default, add curl to the backup script template
3. **`docker_auto_update`** — Add `docker_auto_update_uptimekuma_push_url` default, add curl to the script template
4. **`scheduled_update`** — Add `scheduled_update_uptimekuma_push_url` default, add curl to the script template
5. **Create push monitors in Uptime Kuma** — one per host×timer combination, get the push tokens
6. **Set push URLs in secrets.yml or host_vars** — populate the actual URLs for each deployment
