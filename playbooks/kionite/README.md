# Kionite builder

The existing builder is VM 103 at 10.0.0.139. Apply provisioning separately from
OS configuration:

```sh
ansible-playbook playbooks/proxmox_primary/kionite_builder.yml
ansible-playbook playbooks/kionite/builder.yml
```

The Proxmox playbook adopts the expected `builder` VM and grows disks only. It
refuses `force_recreate` and requires `kionite_builder_create=true` to clone a
missing VM from the existing template. It does not shut down an active builder.
CPU/memory changes need a controlled shutdown/start; disk expansion also requires
guest partition/filesystem growth. Keep the DHCP reservation stable when adopting
103; the creation path configures the specified static address.

The OS role installs EPEL/CRB packages, creates `kionite-build` with KVM access,
allocates subordinate IDs, enables lingering, checks out public image source, and
checks rootless Podman. It also installs libvirt/QEMU for session-owned disk-backed tests. It does not give the build account sudo or infrastructure
credentials. Its state lives under `/var/lib/kionite-builder`.

The source checkout is initially cloned but not reset/updated by Ansible on later
runs. The pipeline owns per-run revision checkout and locking. The nightly build
timer is enabled for this host; no laptop update policy is installed. GHCR authentication is optional
and enabled for this host through `host_vars/kionite-builder.yml`. The role loads
`secrets.yml` into a namespace and reads its `atomic-homelab-builder` key. Only the
publisher credential is written to the build account's auth file, mode 0600;
Vault input/output and diffs are suppressed. The auth directory is mode 0700.
No image publication is triggered by this role.

The image build script supports an explicit `PODMAN_ROOTLESS=1` mode in the new
pipeline. The published pipeline uses this mode for builds and verification. Images must be built,
tested and published from one account's storage. A first test can pull the existing
prototype image from the temporary trusted-LAN HTTP registry using an explicit
`--tls-verify=false`; permanent GHCR pulls use normal HTTPS verification.

Acceptance: repeat Ansible with no changes, reboot and recheck KVM/user Podman,
then boot the existing image with `bcvk ephemeral` and collect its guest status.
This initial VM experiment is not the full graphical/update/rollback test suite.

The EPEL bcvk 0.10 package cannot bootstrap TCP SSH for this image in its disk
installer. The role installs upstream bcvk 0.21 in `/usr/local/bin` from an immutable
OCI artifact digest, verifies the manifest digest/version and retains the packaged
binary as a fallback. Use `/usr/local/bin/bcvk` explicitly: sudo’s secure PATH can otherwise select `/usr/bin/bcvk` 0.10. No moving `latest` artifact is used during provisioning.

bcvk ephemeral mode disables SELinux and uses temporary `/var`; it is a boot
experiment, not the release gate. Disk-backed tests use `qemu:///session` without
system-wide libvirt access. Test-only `systemd.wants=sshd.service` starts TCP SSH.
Initial UEFI tests disable Secure Boot and TPM; hardware-specific coverage remains
separate. The build user's source and state should not be reset by provisioning.

The session QEMU config uses `max_core = 0`, avoiding attempts to raise an
unprivileged hard core limit. A session daemon already running before this setting
was applied needs a controlled restart while tests are stopped; new sessions read
it automatically.

## Scheduled publication

Ansible installs `kionite-build.service` and `kionite-build.timer` under the build
account's `~/.config/systemd/user/`. The existing linger setting keeps its manager
running after logout and reboot. These are user units so Podman and libvirt run in
the normal account session; no SELinux service-domain override is installed.

The timer defaults off. Set `kionite_builder_timer_enabled: true` in this host's
variables after a manual pipeline run completes with `published_reference` recorded
in `last-success.json`; the role asserts this before enabling the timer. Schedule:
03:00 Europe/Oslo, up to 10 minutes jitter, with missed-run catch-up.

As the build user, use `systemctl --user start kionite-build.service`,
`systemctl --user list-timers kionite-build.timer`, and
`journalctl --user -u kionite-build.service`. Administrators can use
`sudo -iu kionite-build env XDG_RUNTIME_DIR=/run/user/1001 systemctl --user ...`
for the current UID; derive the UID with `id -u kionite-build` on recreated hosts.
The source repository's `scripts/check-status.sh` reports failures or success older
than 48 hours. Pipeline logs, release records and last/latest status remain under
`/var/lib/kionite-builder`. Kuma success monitoring is configured for this host as described below.

For first publication, GHCR defaults to private. Change the package to public in
its settings, then use `scripts/pipeline.sh --resume <build-id>` to promote the
already-tested release. The publisher verifies anonymous access and matching
release/stable digests. No desktop update timer is installed by this role.

## Kuma success monitoring

This host enables `kionite_builder_monitor_enabled`. The endpoint is stored in
encrypted `secrets.yml` under `atomic_homelab_builder_success_push_url`, then
installed as a mode-0600 environment file owned by the build user. The image
repository contains only generic notification code. No endpoint credential is
embedded in the image or public source.

A heartbeat is sent after successful verified publication; failed builds send
no up heartbeat. Monitor delivery failure logs a warning without reverting the
published release. Set Kuma's push interval to 26 hours to cover daily builds,
jitter and installation time. The first success heartbeat was accepted.

The complete pipeline passed on 2026-10-14. Its basic gate checks boot, DNS,
KWin/Plasma startup and Klassy/Smooth Swipe files. Build subprocesses use umask
022 so guest services can traverse image directories; private pipeline state
and credentials retain restrictive permissions.
