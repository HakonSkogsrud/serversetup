# Secondary Proxmox Cleanup Plan

This backlog covers the six highest-priority cleanup items identified for
`proxmox2` and its AlmaLinux 10 guests. Work should remain scoped to the
secondary Proxmox environment unless a shared-role change is explicitly made
backward-compatible with the primary environment.

## 1. Manage Pi-hole with systemd or Podman Quadlet

### Problem

Pi-hole is started with an ad-hoc `podman-compose up -d` command. There is no
enabled systemd or Quadlet unit that clearly owns the container lifecycle, so
restart behavior after a VM reboot is not sufficiently explicit or testable.

### Planned work

- Replace the direct `podman-compose` invocation with a Podman Quadlet or a
  dedicated systemd service.
- Enable the unit at boot and make Ansible restart it only when its
  configuration changes.
- Keep the container running with host networking and the existing persistent
  data directory unless testing identifies a reason to change them.
- Remove the duplicate `podman-compose up` task/handler behavior.

### Acceptance criteria

- Pi-hole starts automatically after rebooting `pihole-secondary`.
- `systemctl` clearly reports whether the Pi-hole workload is healthy.
- A second playbook run is idempotent.
- DNS queries succeed after both deployment and reboot.

### Relevant files

- `roles/pihole_podman/tasks/main.yml`
- `roles/pihole_podman/handlers/main.yml`
- `roles/pihole_podman/templates/docker-compose.yml.j2`
- `roles/pihole_podman/defaults/main.yml`

## 2. Remove or gate obsolete Docker migration actions

### Problem

The Pi-hole role always attempts `docker compose down` and disables Docker,
even on a clean AlmaLinux 10 VM where Docker is not installed. Failures are
suppressed, and the task produces noisy or misleading change results.

### Planned work

- Remove the Docker shutdown and disable tasks if the Docker migration is
  considered complete.
- Alternatively, put them behind an explicit, default-off variable such as
  `pihole_podman_migrate_from_docker` for one-time migrations.
- Remove any remaining secondary-only Docker assumptions after confirming
  Podman owns the Pi-hole workload.

### Acceptance criteria

- A normal Pi-hole deployment never invokes the Docker CLI.
- Docker is not installed as an indirect dependency.
- Repeated deployments do not report changes for nonexistent Docker services.

### Relevant files

- `roles/pihole_podman/tasks/main.yml`
- `roles/pihole_podman/defaults/main.yml`
- `roles/pihole_podman/meta/main.yml`

## 3. Replace the Tailscale installation script

### Problem

The downloaded Tailscale installer identifies AlmaLinux 10 as Fedora and has
generated a `fedora//` repository URL. On the v2 AlmaLinux image, installation
also encountered an `iptables-libs`/`iptables-nft` dependency mismatch and
only succeeded after blindly rerunning the same script.

### Planned work

- Configure Tailscale's RPM repository directly with Ansible.
- Install Tailscale using the package module rather than a downloaded shell
  script.
- Determine whether a normal package upgrade or `dnf distro-sync` is needed
  before installation to keep AlmaLinux v2 packages aligned.
- Remove the unconditional retry and any temporary installer artifacts.
- Preserve compatibility with the operating systems that legitimately share
  this role, or split the AlmaLinux 10 implementation into a dedicated task
  file.

### Acceptance criteria

- A fresh AlmaLinux 10 v2 VM installs Tailscale on the first run.
- No `fedora//` repository is created.
- A second run is idempotent and does not download or execute an installer
  script.
- `tailscaled` is enabled, active, and usable by the subnet-router role.

### Relevant files

- `roles/tailscale_installation/tasks/alma.yml`
- `roles/tailscale_installation/tasks/main.yml`
- `roles/tailscale_installation/handlers/main.yml`

## 4. Protect credentials rendered into files

### Problem

The Pi-hole API password is rendered into its compose configuration, and the
cloud-template password is embedded in the generated template creation
script. File permissions and secret placement should not expose these values
to unprivileged users on the host.

### Planned work

- Set restrictive ownership and permissions on every generated file that
  contains a credential.
- Prefer a root-owned environment or secrets file for Pi-hole instead of
  embedding its password in a generally readable compose file.
- Investigate removing the cloud-template password entirely in favor of SSH
  keys and cloud-init configuration.
- Keep secret values in Ansible Vault and ensure they are not printed in task
  output; apply `no_log` where needed.
- Review Uptime Kuma push tokens in secondary role defaults and playbooks as
  part of the same secret-handling pass.

### Acceptance criteria

- Unprivileged users on proxmox2 and `pihole-secondary` cannot read deployed
  credentials.
- Secrets remain Vault-backed in the repository.
- Ansible output and diffs do not reveal secret values.
- VM creation and Pi-hole authentication continue to work.

### Relevant files

- `roles/pihole_podman/templates/docker-compose.yml.j2`
- `roles/pihole_podman/tasks/main.yml`
- `roles/create_template_vm/templates/create_template_vm.sh.j2`
- `roles/create_template_vm/tasks/deploy_script.yml`
- `playbooks/proxmox_secondary/proxmox2.yml`

## 5. Make disk-health failures fail visibly

### Problem

The disk-health script records failed checks but can still exit successfully.
That makes the systemd service appear healthy and does not provide a reliable
failure signal to monitoring.

### Planned work

- Exit nonzero whenever any configured disk fails a health check.
- Send an explicit failure/down result to Uptime Kuma as well as the existing
  success heartbeat.
- Treat curl failures and non-2xx HTTP responses as failed pushes.
- Review brittle SMART text parsing and use `smartctl` JSON output if supported
  by the MacBook's installed smartmontools version.
- Preserve useful journal messages while avoiding false-positive `PASSED` or
  `OK` matches.

### Acceptance criteria

- A simulated unhealthy result makes the systemd service fail.
- Healthy disks produce a successful service run and monitoring heartbeat.
- A failed monitoring push is visible in the journal.
- The actual secondary disks are parsed correctly.

### Relevant files

- `roles/disk_health/templates/disk_health.sh.j2`
- `roles/disk_health/templates/disk-health.service.j2`
- `roles/disk_health/defaults/main.yml`
- `playbooks/proxmox_secondary/proxmox2.yml`

## 6. Make secondary template updates failure-safe

### Problem

The template updater destroys the existing Proxmox template before the new
template has been fully imported and configured. A failed import or `qm set`
operation can therefore leave proxmox2 without a usable deployment template.
The checksum cache can also suppress reconstruction when the cached checksum
matches but the template itself is missing.

### Planned work

- Download and verify the image before modifying the active template.
- Build the replacement using a temporary VMID and validate its configuration.
- Replace or promote the active template only after the temporary build has
  succeeded.
- Check that the expected VMID exists even when the cached checksum matches.
- Add `set -euo pipefail`, use `curl --fail`, and handle each Proxmox operation
  explicitly.
- Ensure failure of the AlmaLinux 9 entry cannot prevent maintenance of the
  AlmaLinux 10 v2 template on proxmox2; preferably make proxmox2's template
  list AlmaLinux-10-only in a separate cleanup.
- Clean up failed temporary VMs and downloads without destroying the last
  working template.

### Acceptance criteria

- A forced download, import, or configuration failure leaves VMID 9001 intact
  and clonable.
- A missing VMID 9001 is rebuilt even if its checksum cache is current.
- A successful update produces the expected AlmaLinux 10 x86-64-v2 template.
- The updater reports failure to systemd and monitoring.
- No primary-Proxmox template behavior changes unintentionally.

### Relevant files

- `roles/create_template_vm/templates/create_template_vm.sh.j2`
- `roles/create_template_vm/defaults/main.yml`
- `roles/create_template_vm/tasks/deploy_script.yml`
- `host_vars/proxmox2.yml`

## Suggested execution order

1. Protect credentials.
2. Add reliable Pi-hole lifecycle management.
3. Remove the obsolete Docker migration path.
4. Replace the Tailscale installer.
5. Correct disk-health failure reporting.
6. Redesign template replacement and test its failure paths.

Before completing each item, run the affected playbook only against the
secondary environment and extend `playbooks/local/verify_services.yml` with
the relevant regression check.
