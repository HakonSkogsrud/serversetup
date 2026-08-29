# Nextcloud personal pilot runbook

This pilot deploys Nextcloud Files, Calendar, Contacts, Notes, Text, and Nextcloud Office on a
dedicated VM. Office uses the built-in Collabora CODE server for the pilot, avoiding a separate
office container and proxy endpoint. Access is
private through the existing subnet-router, Tailscale Serve, and Caddy. The Nextcloud VM does not
join the tailnet. PostgreSQL and Redis are disposable VM state; user data,
configuration, custom applications, themes, and logical database dumps live on
`storage/nextcloud`.

## Prerequisites

Add two values of at least 16 characters to `secrets.yml` with `ansible-vault edit secrets.yml`:

```yaml
nextcloud_admin_password: replace-with-a-unique-password
nextcloud_db_password: replace-with-a-different-unique-password
```

The deployment creates `storage/nextcloud` and the Proxmox `nextcloud` directory mapping when they
do not exist. Confirm that VMID `4010` and address `10.0.0.83` are free before the first run.

## Deploy

```bash
ansible-playbook playbooks/proxmox_primary/nextcloud.yml
```

At the end of the play, obtain the subnet-router HTTPS hostname with:

```bash
ssh subnet-router tailscale serve status
```

Open `https://<subnet-router-hostname>/nextcloud/`. Log in as `nextcloud-admin`, create a separate
non-admin personal account, and use that account for all testing.

## Pilot acceptance data

Before testing recovery, create all of the following:

- a file containing a unique recovery phrase
- a calendar and event
- a contact
- a note

Run an on-demand backup and inspect its result:

```bash
ssh nextcloud sudo systemctl start nextcloud-backup.service
ssh nextcloud sudo systemctl status nextcloud-backup.service
```

## Destructive rebuild test

The recreate flow backs up the database, validates the dump and persistent config, stops the stack,
creates a ZFS snapshot, and only then permits VM destruction:

```bash
ansible-playbook playbooks/proxmox_primary/nextcloud.yml -e force_recreate=true
```

After rebuilding, verify that the file, event, contact, and note remain present and editable. Also
verify `Settings -> Administration -> Overview`, background-job status, WebDAV, and mobile CalDAV.
Do not consider the pilot successful until this rebuild has completed without manual data repair.
