# Plan: Verify ZFS Backups on backupserver

## Goal

Verify that Syncoid backups replicated from proxmox to backupserver are:

- present on the expected backup pool
- up to date with the latest source snapshots
- mountable and readable
- usable for a restore

This plan is focused on proving restoreability, not just confirming that the timer or heartbeat fired.

## Background

The current backup flow is:

- `sanoid` creates snapshots for:
  - `storage/smb`
  - `storage/syncthing`
- `syncoid` runs weekly on proxmox
- replicated datasets are sent to backupserver as:
  - `POOL/backup/smb`
  - `POOL/backup/syncthing`
- the Syncoid script checks pools in this order:
  - `wdred`
  - `sgblack`

Important limitation: a successful `syncoid.service` run does not fully prove a usable backup exists. A pool import can fail, be skipped, and still leave the overall job looking healthy enough in monitoring.

## Verification levels

### Level 1: Job-level verification

Confirms that the backup job ran and reported success.

### Level 2: Snapshot-level verification

Confirms that destination snapshots exist and are as recent as the source snapshots.

### Level 3: Restore smoke test

Confirms that the backup can actually be mounted or cloned and read on backupserver.

This plan should use all three levels.

## Recommendation on dataset size

Do not begin with a full 1.8 TB restore drill.

Use this order:

1. First validate with a smaller ZFS dataset if you have one.
2. Then run a mount or clone smoke test against one real replicated production dataset.
3. Only do a full large restore drill when you specifically want to measure recovery time and operational risk.

Reason:

- a mount test does not copy 1.8 TB, so dataset size is not the main problem
- a ZFS clone test is also lightweight because it is copy-on-write
- a full restore to another dataset or disk is where the 1.8 TB size becomes expensive in time and space

So yes: if you have a smaller replicated dataset, use that first for process validation. But you do not need a small dataset just to test whether mount or clone works.

## Preconditions

Before starting:

- SSH access to `proxmox`
- SSH access to `backupserver`
- root or equivalent privileges on both hosts
- knowledge of which backup pool should currently hold the replicated datasets
- enough free space if performing a real restore test beyond mount or clone verification

## Step 1: Verify the backup job ran on proxmox

SSH to proxmox and check the timer and recent logs.

### Commands

```bash
systemctl list-timers syncoid.timer --all
systemctl status syncoid.service --no-pager
journalctl -u syncoid.service -n 200 --no-pager
```

### What to confirm

- `syncoid.timer` has a recent last run time
- `syncoid.service` did not fail
- logs show replication attempts for:
  - `smb`
  - `syncthing`
- logs show which pool was actually used:
  - `wdred`
  - `sgblack`

### Notes

This step only verifies sender-side execution. It does not prove the destination is readable or recoverable.

## Step 2: Verify source snapshots on proxmox

List the latest snapshots on the source datasets.

### Commands

```bash
zfs list -t snapshot -o name,creation -s creation storage/smb | tail -20
zfs list -t snapshot -o name,creation -s creation storage/syncthing | tail -20
```

### What to confirm

- recent snapshots exist for both datasets
- the latest snapshot names are the ones you expect Syncoid to replicate

## Step 3: Import the backup pool on backupserver

SSH to backupserver and import the target pool without mounting everything automatically.

Try the pool you expect first. If unsure, check both.

### Commands

```bash
zpool import -N -d /dev/disk/by-uuid/ wdred
zfs load-key -r wdred
```

If `wdred` is not the active backup pool, export it and try `sgblack`:

```bash
zpool export wdred
zpool import -N -d /dev/disk/by-uuid/ sgblack
zfs load-key -r sgblack
```

### What to confirm

- the pool imports cleanly
- the encryption key loads cleanly
- no pool errors prevent access to the backup datasets

## Step 4: Verify the replicated datasets exist

After importing the pool, list the replicated datasets.

### Commands

```bash
zfs list -r wdred/backup
```

or:

```bash
zfs list -r sgblack/backup
```

### What to confirm

- the backup root exists
- these datasets exist:
  - `POOL/backup/smb`
  - `POOL/backup/syncthing`

## Step 5: Compare destination snapshots with source snapshots

List snapshots on the destination and compare them with the source snapshots from Step 2.

### Commands

```bash
zfs list -t snapshot -o name,creation -s creation wdred/backup/smb | tail -20
zfs list -t snapshot -o name,creation -s creation wdred/backup/syncthing | tail -20
```

or:

```bash
zfs list -t snapshot -o name,creation -s creation sgblack/backup/smb | tail -20
zfs list -t snapshot -o name,creation -s creation sgblack/backup/syncthing | tail -20
```

### What to confirm

- latest destination snapshot names match the source
- snapshot creation times are recent enough for the backup schedule
- no dataset is missing or obviously stale

## Step 6: Perform a restore smoke test with a mount

This is the routine verification path.

Mount one replicated dataset and verify expected content is readable.

### Commands

For `wdred`:

```bash
zfs mount wdred/backup/smb
find /wdred/backup/smb -maxdepth 2 | head -50
du -sh /wdred/backup/smb
zfs unmount wdred/backup/smb
```

For `sgblack`, replace the pool name accordingly.

### What to confirm

- the dataset mounts successfully
- directory contents are readable
- top-level folders look correct
- no I/O or permission errors occur while reading

### Good candidates to inspect

Pick content that is recognizable and stable:

- known top-level directories
- expected application data folders
- a few representative files

Do not rely only on `ls`; read a few files or inspect enough structure to prove the filesystem is usable.

## Step 7: Perform a deeper restore smoke test with a temporary ZFS clone

Use this less often, but it is a stronger check than a mount.

### 7a. Find the latest snapshot

```bash
zfs list -t snapshot -o name -s creation wdred/backup/smb | tail -1
```

### 7b. Create a temporary clone

Replace `SNAPNAME` with the actual latest snapshot name.

```bash
zfs clone wdred/backup/smb@SNAPNAME wdred/backup/verify-smb
```

### 7c. Inspect the clone

```bash
ls -la /wdred/backup/verify-smb | head
find /wdred/backup/verify-smb -maxdepth 2 | head -50
du -sh /wdred/backup/verify-smb
```

### 7d. Clean up

```bash
zfs destroy wdred/backup/verify-smb
```

### What to confirm

- the snapshot can be materialized as a clone
- the clone is readable
- cleanup succeeds cleanly

## Step 8: Export the pool

Do not leave the backup pool imported after verification.

### Commands

```bash
zpool export wdred
```

or:

```bash
zpool export sgblack
```

### What to confirm

- the pool exports successfully
- no test clone or temporary mount remains behind

## Step 9: Define pass or fail criteria

The verification passes only if all of the following are true:

- Syncoid ran recently on proxmox
- source snapshots exist for the datasets being protected
- backupserver pool imports successfully
- backup datasets exist on the destination
- destination snapshots are current
- at least one replicated dataset can be mounted and read
- occasional clone-based restore smoke test succeeds
- pool exports cleanly afterward

The verification fails if any of the following occur:

- no recent Syncoid run
- destination dataset missing
- destination snapshots are stale
- pool import fails
- key load fails
- dataset mount fails
- clone creation fails
- filesystem contents are unreadable or clearly incomplete

## Suggested operating cadence

### After major backup changes

Run the full procedure:

- job verification
- snapshot comparison
- mount smoke test
- clone smoke test

### Routine checks

Run:

- job verification
- snapshot comparison
- mount smoke test on one dataset

### Periodic deeper validation

Monthly or quarterly:

- run the clone smoke test
- optionally perform a real restore into a temporary recovery dataset

## Optional future improvement

Add a dedicated verification playbook or script that:

- checks the latest source and destination snapshot names
- imports the backup pool without mounting everything automatically
- performs a temporary mount or clone verification
- fails loudly if no pool was actually backed up
