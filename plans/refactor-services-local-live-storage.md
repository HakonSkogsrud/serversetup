# Refactor services VM live data to local storage

## Objective

Move hot service data on the `services` VM off `/mnt/storage/smb` so virtiofs is used only for backup and restore, not for steady-state container I/O.

Primary targets:

- Loki
- CouchDB
- EchoVault

Out of scope for this change:

- Syncthing, which already uses its own dedicated virtiofs mount
- Services that already keep live data on the VM and only use smb for backups, such as Uptime Kuma, Vaultwarden, Grafana, and Pi-hole

## Why this change

The current investigation indicates that the remaining hangs are on `/mnt/storage/smb`, even after Syncthing was moved away from that mount. The remaining known services with live data directly bound from smb-backed virtiofs are:

- Loki: `loki_storage_path: "/mnt/storage/smb/loki"`
- CouchDB: `couchdb_storage_path: "/mnt/storage/smb/couchdb"`
- EchoVault: `echovault_storage_path: "/mnt/storage/smb/echovault-data"`

That means steady-state reads and writes from those containers are still coupled to virtiofs responsiveness. The desired design is:

- live data on the VM's local disk
- backup archives on `/mnt/storage/smb`
- restore flow pulls backup data from `/mnt/storage/smb` back onto local VM storage before service start

This matches the existing repo pattern used by services like Uptime Kuma, where runtime data is local but backups are written to smb.

## Current state summary

### Already using local live storage

- Grafana stores live data under `{{ grafana_data_dir }}/data`
- Vaultwarden stores live data under `./vw-data`
- Uptime Kuma stores live data under `{{ uptimekuma_data_dir }}`
- Pi-hole stores live data under its local project directory

These services may still copy or archive data to smb, but they do not mount `/mnt/storage/smb` directly into their containers for hot runtime data.

### Still using smb for live runtime data

- Loki binds `{{ loki_storage_path }}/data:/loki`
- CouchDB binds `{{ couchdb_storage_path }}/data:/opt/couchdb/data`
- EchoVault binds `{{ echovault_storage_path }}:/data`

## Target architecture

Use separate variables for local live data and smb-backed backup storage.

For each stateful service, the role should expose:

- a local live-data path on the VM
- a backup path on `/mnt/storage/smb`
- restore logic that restores from backup storage to the local live-data path

Recommended convention:

- local live data under `/home/{{ template.user }}/<service>/data`
- backup artifacts under `/mnt/storage/smb/<service>` or `/mnt/storage/smb/<service>_backup`

Example split:

- Loki
  - local live data: `/home/{{ template.user }}/loki/data`
  - backup storage: `/mnt/storage/smb/loki`
- CouchDB
  - local live data: `/home/{{ template.user }}/couchdb/data`
  - backup storage: `/mnt/storage/smb/couchdb_backup`
- EchoVault
  - local live data: `/home/{{ template.user }}/echovault/data`
  - backup storage: `/mnt/storage/smb/echovault-backup`

The important part is not the exact directory names. The important part is that container bind mounts for runtime data no longer point at `/mnt/storage/smb`.

## Constraints and tradeoffs

- The services VM disk is currently configured at `100G`, so migration must start with a disk-capacity check.
- Moving live data local reduces exposure to virtiofs stalls, but it also means host-side storage snapshots no longer capture the live service directories directly.
- Recovery will depend on backup freshness, so the force-recreate backup path and restore procedure must be reliable before switching critical services.
- Loki may not need the same restore guarantees as CouchDB. If retention data is considered disposable, Loki can be treated as a best-effort restore candidate. Decide this explicitly before implementation.

## Implementation plan

### Phase 0: confirm local disk budget

Before changing any role defaults:

- measure current live data size for Loki, CouchDB, and EchoVault
- measure free space on the `services` VM root filesystem or target filesystem
- decide whether Loki retention must be shortened before migration

Suggested checks:

- `du -sh /mnt/storage/smb/loki /mnt/storage/smb/couchdb /mnt/storage/smb/echovault-data`
- `df -h /home /`

Exit criteria:

- enough local space exists for live data plus temporary restore or migration overhead

### Phase 1: introduce a consistent live-data versus backup split

Refactor each target role so defaults distinguish:

- local runtime path
- smb backup path

Expected file changes:

- `roles/loki/defaults/main.yml`
- `roles/loki/tasks/loki.yml`
- `roles/loki/templates/docker-compose.yml.j2`
- `roles/couchdb/defaults/main.yml`
- `roles/couchdb/tasks/restore.yml`
- `roles/couchdb/tasks/couchdb.yml`
- `roles/couchdb/tasks/couchdb_backup.yml`
- `roles/couchdb/templates/docker-compose.yml.j2`
- `roles/couchdb/templates/couchdb_backup.sh.j2`
- `roles/echovault/defaults/main.yml`
- `roles/echovault/tasks/echovault.yml`
- `roles/echovault/templates/docker-compose.yml.j2`

Implementation rules:

- local data directories must be created under the service project directory or another local VM path
- backup directories must remain on `/mnt/storage/smb`
- no target container should bind-mount `/mnt/storage/smb` for its active database or active working set

### Phase 2: migrate Loki first

Loki is the first migration target because it is the strongest current suspect for virtiofs pressure.

### Loki target design

Current Loki role behavior:

- `loki_storage_path` points at `/mnt/storage/smb/loki`
- the container bind-mounts `{{ loki_storage_path }}/data:/loki`
- the Loki config uses filesystem storage under `/loki`
- active Loki state includes at least:
  - `/loki/chunks`
  - `/loki/rules`
  - `/loki/compactor`
  - TSDB index data under `/loki`

Planned split:

- `loki_live_data_path`: `/home/{{ template.user }}/loki/data`
- `loki_backup_path`: `/mnt/storage/smb/loki`
- container bind mount: `{{ loki_live_data_path }}:/loki:Z`

Recommended restore policy:

- do not auto-restore Loki on every normal deploy
- restore when the local Loki data directory is missing or empty
- document Loki restore as best effort unless log retention is declared operationally critical

This avoids overwriting an existing local Loki dataset during ordinary playbook runs, while still repopulating a fresh instance from backup when appropriate.

### Loki role changes

Follow the existing services playbook and role conventions instead of inventing a Loki-specific backup flow.

Repo conventions to match:

- `playbooks/proxmox_primary/services.yml` calls `tasks_from: backup.yml` during the pre-change backup play when `force_recreate=true`
- roles that support restore usually import or include `restore.yml` from `tasks/main.yml`
- restore tasks commonly accept either:
  - a controller-side archive in `/tmp/<service>-backup.tar.gz`
  - or a persistent archive already present on smb

For Loki, that implies this file layout:

- `roles/loki/tasks/main.yml`: restore gate and install
- `roles/loki/tasks/backup.yml`: ad hoc backup used by the pre-change backup play in `services.yml`
- `roles/loki/tasks/restore.yml`: restore from controller or smb backup into local live data

Defaults:

- replace `loki_storage_path` with:
  - `loki_live_data_path`
  - `loki_backup_path`

Task structure:

- keep `roles/loki/tasks/main.yml` as the entry point
- update `roles/loki/tasks/loki.yml` to create the local live-data directory instead of `{{ loki_storage_path }}/data`
- add `roles/loki/tasks/backup.yml` for `services.yml` pre-recreate backups
- add `roles/loki/tasks/restore.yml`
- have `main.yml` follow the repo pattern:
  - check whether the local live-data directory already exists
  - restore only when the local live-data directory is missing or empty
  - install Loki

Compose changes:

- update `roles/loki/templates/docker-compose.yml.j2` so `/loki` is bound from `{{ loki_live_data_path }}`
- do not mount any smb path into the Loki container

Backup implementation:

- in `tasks/backup.yml`, follow the Grafana and CouchDB pre-recreate pattern:
  - archive the live data to `/tmp/loki-backup.tar.gz`
  - fetch that archive to the controller at `/tmp/loki-backup.tar.gz`
  - clean up the remote temp file

This keeps Loki aligned with the simpler pre-recreate backup flow instead of adding recurring log backup automation.

Restore implementation:

- have `restore.yml` follow the Grafana and CouchDB restore pattern:
  - check first for `/tmp/loki-backup.tar.gz` on the controller
  - otherwise check for `{{ loki_backup_path }}/loki-backup.tar.gz` on the guest
  - set a restore source fact
  - copy the chosen archive to a temp file on the guest
  - unarchive into the local live-data path
  - fix ownership
  - if the source came from the controller, copy the archive into persistent smb backup storage
  - remove the temp file
- require Loki to be stopped before extraction
- ensure ownership is reset to `{{ template.user }}` after restore

### Loki migration procedure

#### Step 1: measure data size and decide retention policy

Before changing the role:

- measure current Loki data size under `/mnt/storage/smb/loki/data`
- compare that size to free local space on the services VM
- decide whether `loki_retention_period` should be shortened before migration

Reason:

- Loki is the most likely target to consume a large fraction of the VM disk, and copying oversized historical data local is avoidable if retention can be reduced first

Exit criteria:

- local space comfortably fits the active Loki dataset plus headroom for compaction and restore

#### Step 2: add backup and restore plumbing before cutover

Implement the role changes first so the migration is reversible.

Required files:

- `roles/loki/defaults/main.yml`
- `roles/loki/tasks/main.yml`
- `roles/loki/tasks/loki.yml`
- `roles/loki/tasks/backup.yml`
- `roles/loki/tasks/restore.yml`
- `roles/loki/templates/docker-compose.yml.j2`

Recommended behavior:

- add a pre-change task in `playbooks/proxmox_primary/services.yml`:
  - `include_role: name=loki tasks_from=backup.yml`
  - guarded by `force_recreate | default(false) | bool`
- in `main.yml`, restore when the local live-data path is missing or empty
- ordinary deploys should not overwrite an existing non-empty local Loki dataset

Exit criteria:

- Loki role supports local live data and smb backups in code, even before moving existing data

#### Step 3: take a final pre-cutover backup from the current smb-backed data

Before moving paths:

- stop Loki cleanly
- produce a final known-good archive from the current `/mnt/storage/smb/loki/data`
- store that archive in `{{ loki_backup_path }}`

Reason:

- the first migration should preserve a rollback point that does not depend on the partially copied local directory

Exit criteria:

- a fresh timestamped backup exists on smb and its contents can be listed successfully

If you are keeping Loki backup intentionally minimal, it is also acceptable to rely only on the controller-side `/tmp/loki-backup.tar.gz` generated by `backup.yml` during `force_recreate` and skip recurring archive generation entirely.

#### Step 4: seed the new local live-data directory

Populate `{{ loki_live_data_path }}` from the existing data before switching the compose mount.

Preferred approach:

- create the local live-data directory with final ownership first
- copy the existing Loki data from `/mnt/storage/smb/loki/data` into the local directory while Loki is stopped
- preserve permissions and timestamps as far as practical

Alternative approach:

- restore from the fresh archive created in Step 3 instead of copying directly

Decision rule:

- direct copy is simpler for the first cutover
- archive-based restore is better if the role already has reliable restore logic by that point

Exit criteria:

- the full Loki dataset exists locally and matches the expected top-level directories used by the config

#### Step 5: switch the container bind mount to local storage

After local data is seeded:

- update the compose template to mount `{{ loki_live_data_path }}` at `/loki`
- deploy the updated compose file
- start Loki from `{{ loki_data_dir }}`

Immediate checks:

- Loki starts without schema or filesystem errors
- queries against recent logs succeed
- new writes appear under the local path rather than `/mnt/storage/smb/loki/data`

Exit criteria:

- `docker inspect` shows only the local VM path for `/loki`

#### Step 6: verify Loki independence from smb during steady-state runtime

Once Loki is running locally:

- confirm Loki remains healthy if smb is slow or temporarily unavailable
- confirm backup jobs still fail safely and visibly if smb is unavailable, without affecting the running Loki container

This is the main behavioral reason for doing the migration.

Exit criteria:

- loss of smb availability affects backup or restore only, not routine Loki reads and writes

### Loki validation checklist

- `docker inspect loki` shows `/home/{{ template.user }}/loki/data` as the source for `/loki`
- `/mnt/storage/smb` no longer appears in Loki container mounts
- Loki responds on port `3100`
- recent logs remain queryable after the restart
- compactor and retention continue to work with the local path
- the pre-recreate backup task writes a valid archive to `/tmp/loki-backup.tar.gz` on the controller
- the restore task can repopulate an empty local data directory on a test run or controlled rebuild

### Loki rollback plan

If Loki fails after cutover:

1. Stop the Loki container.
2. Revert the compose bind mount to the old smb-backed path.
3. Start Loki against `/mnt/storage/smb/loki/data`.
4. Keep the local copy for inspection until the cause is understood.
5. Do not delete the old smb data until the local-storage migration has survived normal operation and at least one backup cycle.

### Loki completion criteria

- Loki runs with local storage only
- Loki backups land on smb
- `/mnt/storage/smb` is no longer mounted into the Loki container
- `playbooks/proxmox_primary/services.yml` has a clear pre-recreate backup path for Loki if force-recreate is used
- the post-migration incident window shows that an smb virtiofs stall no longer freezes Loki runtime I/O

### Phase 3: migrate CouchDB second

CouchDB already has the most complete backup and restore workflow, so this is primarily a path refactor plus validation pass.

Work:

- move `couchdb_storage_path` to a local VM path
- keep `couchdb_backup_path` on smb
- update restore logic so backups extract into local live storage, not smb
- update the backup script so it archives the local live data path, not `/mnt/storage/smb/couchdb/data`
- verify pre-play `backup.yml` still works with the new local path

Important detail:

- today the backup script hard-codes `STORAGE_PATH="/mnt/storage/smb/couchdb/data"`; that must become the local live-data path variable

Exit criteria:

- CouchDB live data is fully local
- force-recreate backups still complete successfully
- force-recreate and restore paths still work end to end

### Phase 4: migrate EchoVault third

EchoVault is lower priority because it is a weaker suspect and appears less operationally critical, but it should follow the same pattern if it remains stateful.

Work:

- move active `/data` bind mount to a local VM path
- add backup and restore tasks if the data is worth preserving
- otherwise explicitly document that EchoVault can be recreated and leave it out of the restore workflow

Exit criteria:

- either EchoVault is migrated to the same local-plus-backup pattern
- or EchoVault is explicitly declared disposable and excluded by design

### Phase 5: update orchestration and operational checks

Adjust the broader playbook flow so backup and restore behavior remains predictable.

Expected checks:

- confirm `playbooks/proxmox_primary/services.yml` pre-flight backup stage includes every service that now needs protected local live data
- confirm restore tasks run before first container startup when appropriate
- confirm `docker_auto_update` restarts do not depend on smb availability for live-state containers
- confirm `mount_probe` can still detect smb failures even though hot paths are local

## Migration procedure for each service

Use the same sequence for each migrated role:

1. Take a fresh backup to smb.
2. Stop the container.
3. Copy or extract current data from smb into the new local data path.
4. Update the compose bind mount to the local path.
5. Start the container.
6. Verify application health.
7. Verify new writes land on local storage.
8. Verify backup job still writes to smb.
9. Remove the old smb live-data bind only after verification succeeds.

For CouchDB and Loki, prefer a one-time migration task or an explicitly documented operator procedure over ad hoc shell commands.

## Verification checklist

After each migration:

- `docker inspect` shows local VM paths, not `/mnt/storage/smb`, for active data mounts
- service health checks pass
- service restarts succeed while `/mnt/storage/smb` is intentionally unavailable, as long as a restore is not in progress
- the pre-recreate backup task or restore path can still produce and consume a valid Loki backup archive successfully
- restore procedure can rebuild local live data from smb backup on a clean path

After all in-scope migrations:

- the only remaining routine use of `/mnt/storage/smb` on the services VM is backup, restore, or explicitly non-critical access
- a new virtiofs stall on smb should not freeze Loki, CouchDB, or EchoVault runtime I/O

## Rollback plan

If a migration fails:

1. Stop the affected container.
2. Revert the compose bind mount to the previous smb-backed path.
3. Restore the latest confirmed-good backup if local data was partially migrated.
4. Start the service on the old path.
5. Capture why the local-path migration failed before retrying.

Rollback should be per-service, not all-or-nothing.

## Open questions

- Is the current `100G` services VM disk large enough once Loki, CouchDB, and EchoVault live data move local?
- Should Loki restore be treated as required, optional, or explicitly unsupported?
- Should EchoVault be backed up at all, or should it be treated as disposable cache or derived state?
- Do any other services on the `services` VM still have hidden live-state paths under `/mnt/storage/smb` that were not found in the current role scan?

## Recommended order

1. Measure disk usage and free space.
2. Migrate Loki.
3. Migrate CouchDB.
4. Decide whether EchoVault is persistent enough to migrate.
5. Re-run failure monitoring after hot paths are off smb.