# Safe VM replacement plan

## Goal

Replace one VM at a time with a fresh AlmaLinux 10 VM. Build and test the
replacement at a temporary VMID and IP, move the production IP only after it
passes, and retain the old VM, powered off, for a rollback window. Destroy the
old VM only after the replacement has run successfully and a fresh backup has
been verified.

## Current constraints

- `roles/create_vm/tasks/create_vm.yml` destroys the current VMID when
  `force_recreate=true`. Never use that flag for this workflow.
- Production playbooks hard-code several VMIDs and use `vms.*.ip` from
  `group_vars/all.yml`. The existing playbooks must not be run against a
  temporary VM by changing that shared production IP prematurely.
- The clone role sets `ipconfig0` only when the VM is created. Changing an IP
  variable later does not update an existing VM's network configuration.
- VirtioFS mounts and some backup targets are shared with the old VM. Two
  running copies can corrupt state or process the same jobs twice.
- Several integrations use literal IPs, especially `10.0.0.44` for services
  and `10.0.0.79` for Samba. A temporary address must be checked against
  these, as well as DNS, Tailscale, Caddy, firewall rules, and clients.

## Implement the deployment path first

1. Add an explicit candidate inventory entry per VM with a free temporary IP
   and new VMID. Keep the production inventory entry and IP unchanged. Record
   the old VMID, old IP, candidate VMID, candidate IP, Proxmox node, storage,
   VirtioFS mappings, and service owner in a per-VM worksheet.
2. Split each production playbook into reusable **create**, **configure**, and
   **verify** stages, or add a candidate playbook that calls the same roles
   with candidate host and VMID. Make creation target only the candidate VM.
   Make service roles accept a candidate address where they currently read the
   production address. Do not disable SSH host-key checking to hide a changed
   host identity; manage the candidate and production keys explicitly.
3. Add a cutover command or playbook that first checks both VMIDs, their
   actual `qm` network settings, and IP reachability. It must stop the old VM
   and confirm the production IP is free before assigning that IP to the new
   VM. It must never issue `qm destroy` during cutover.
4. Add verification for SSH, OS version, mounts, service processes, a real
   application request, and a write/read test where safe. Record test results
   and backup timestamps. Test the procedure on a low-risk VM before using it
   on the services or Nextcloud VM.

## Per-VM runbook

### 1. Prepare

- Confirm free capacity, VMID, temporary IP, and expected template (v3 on
  primary Proxmox, v2 on secondary). Capture `qm config` and a backup or
  snapshot of the old VM. Verify the application backup exists and can be
  restored; a file's presence alone is insufficient.
- List dependencies and external clients. For example, Nextcloud uses Caddy,
  the services IP, a persistent VirtioFS dataset, and database dumps. The
  services VM contains DNS, proxy, monitoring, and several data stores. A
  subnet router also owns a Tailscale identity and advertised routes.
- Define a maintenance window, an owner for the go/no-go decision, health
  checks, a rollback deadline, and a maximum permitted data loss. Decide
  whether this VM can run safely beside the old one. If it shares writable
  storage, a database, scheduled jobs, DNS records, or an external identity,
  stage it with those parts disabled or isolated.

### 2. Stage and test the candidate

- Clone the AlmaLinux 10 template to the new VMID and temporary IP. Apply
  resources and mounts, but keep production-facing services, timers, backup
  jobs, Tailscale route advertisements, and writes to shared data disabled
  until cutover. Use a copy or snapshot of data where a full test needs writes.
- Configure it with the candidate inventory entry. Check OS/kernel, package
  updates, SSH, storage, permissions, firewall, logs, and local service health.
  Test application access through the temporary IP or a test hostname. Record
  exactly which tests could not be run before cutover.
- A staged candidate is ready only when it has passed its isolated tests and
  the remaining cutover-only checks are written down.

### 3. Freeze data and cut over

- Stop writes to the old application. Disable relevant timers and jobs; drain
  or stop the old service. Take a final consistent backup or snapshot and note
  its timestamp. Transfer or restore the final data delta to the candidate.
  Verify counts or checksums and application-level integrity where possible.
- Shut down the old VM and verify it is stopped. Keep it intact. Remove its
  production IP from the network before assigning that IP to the candidate.
  Set the candidate's `ipconfig0` to the production IP, reboot if required,
  and confirm there is exactly one responder. Refresh stale ARP or neighbor
  entries if connectivity does not recover promptly.
- Move any identities that cannot coexist, such as Tailscale registration or
  route advertisement. Enable the candidate's services, timers, and writers.
  Reapply configuration that binds to the IP. Run the normal production
  playbook only once its VMID points at the candidate and its inventory host
  resolves to the production IP; otherwise it may target or recreate the old
  VMID. Update the production VMID in the playbook or `group_vars` as part of
  the reviewed cutover change.
- Check the real client path: DNS, SSH, SMB, HTTPS via Tailscale Serve/Caddy,
  Nextcloud/Immich login and data, monitoring, backups, and scheduled jobs as
  applicable. Watch logs and alerting during the maintenance window.

### 4. Roll back if checks fail

- Stop the candidate and its writers. Restore the old VM's production IP and
  boot it, then verify the same client path. Reverse any identity or routing
  change. Never run both VMs with the production IP or against the same
  writable state.
- If the candidate accepted writes, assess and export those writes before
  rollback. The old snapshot may now be stale; do not silently discard data.
  Keep the final backup and the failed candidate available for diagnosis.

### 5. Finish and retire

- Keep the old VM powered off through the agreed rollback window. Confirm a
  fresh backup from the new VM, a restore test, normal monitoring, and no
  unexpected jobs on the old VM. Then remove the old VMID and its stale SSH
  host key entry, temporary IP, candidate inventory entry, and migration-only
  overrides. Destroy the old VM only in this final step, after recording its
  backup/snapshot and the explicit go-ahead for that specific VM.

## Suggested order

Start with a low-risk stateless VM, then Samba or the secondary Pi-hole, then
Immich and Nextcloud, then the services VM. Handle subnet routers separately:
preserve one working route and DNS path throughout. Do not migrate both
members of a redundant pair in one maintenance window.
