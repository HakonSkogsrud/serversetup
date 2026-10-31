# Retire centralized logging

The repository no longer deploys Grafana, Loki, or Alloy. Applying normal
playbooks does not uninstall existing deployments. Local system journals remain
available with `journalctl`.

## Live cleanup still required

Do not recreate the services VM to remove these containers.

- On services, stop and remove the Grafana and Loki Compose projects in
  `/home/<template.user>/grafana` and `/home/<template.user>/loki`.
- Apply the updated services configuration to remove both projects from the
  Docker auto-update configuration.
- On proxmox, proxmox2, services, immich, nextcloud, samba, github-runner,
  subnet-router, subnet-router-secondary, and pihole-secondary: stop and disable
  `alloy.service`, uninstall the `alloy` package, and remove its dedicated
  Grafana package repository. Remove Alloy configuration/state only after
  confirming it is no longer needed.
- On services, remove dedicated firewall allowances for TCP 3000, 3100, and
  9096 after confirming they have no other consumer.
- Remove any dedicated Uptime Kuma monitors and Grafana credentials.
- Data and backups can be removed separately when no longer wanted:
  `/home/<template.user>/grafana`, `/home/<template.user>/loki`,
  `/mnt/storage/smb/grafana`, `/mnt/storage/smb/loki`, and temporary
  `grafana-backup.tar.gz` / `loki-backup.tar.gz` archives.

No live cleanup has been executed. Deletion on Proxmox 10.0.0.41 remains
prohibited by the user's instruction.

Historical diagnostic artifacts and exported architecture images may still
mention the retired stack.
