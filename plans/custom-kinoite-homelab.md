# Plan: Custom Fedora Kinoite image built and hosted in the homelab

## Goal

Build a personal Fedora Kinoite bootable OCI image containing Tailscale, Syncthing,
Visual Studio Code, Emacs PGTK, network printing support, and Fedora-packaged Nix.
Build images on the homelab, publish them to a homelab registry, and update desktops
from tested, signed images. Preserve atomic OS updates and rollback while allowing
Nix packages and user configuration to change independently.

The disposable prototype was implemented and validated on 2026-10-13. The Alma
builder and HTTP registry are at `10.0.0.139`; the test VM at `10.0.0.59` now runs
the custom Kinoite image and Home Manager shell environment. Build, first boot,
ordinary-user sandboxed Nix builds, image update, reboot persistence, and rollback
were exercised with SELinux enforcing. The update test changed image version
metadata, not RPM contents. Permanent HTTPS/signing, scheduled builds, and physical
hardware validation remain planned. See [the implementation runbook](../kinoite-image/README.md)
for tested digests, commands, migration fixes, and remaining limitations.

## Decisions and assumptions

- Base: Fedora Kinoite desktop image, initially Fedora 44. Verify the supported
  image reference and architecture before implementation; intended reference is
  `quay.io/fedora-ostree-desktops/kinoite:44`.
- Build definition: plain Containerfile and scripts in Git. BlueBuild is optional,
  not required for this package list.
- Builder: dedicated AlmaLinux 10 VM on Proxmox, using Podman. The recreated
  builder is `haaksk@10.0.0.139`, with 100 GiB storage and 4 GiB RAM plus 4 GiB
  temporary swap. Fedora on the builder is not required for the container build.
- Architecture: initially x86_64, subject to confirming desktop hardware. Use a
  matching native builder rather than introducing emulation.
- Hosting: CNCF Distribution registry with persistent storage, a stable hostname,
  HTTPS, and separate push and pull access where supported by the chosen auth setup.
- Scheduling: daily systemd timer and manual builds initially. An existing
  self-hosted runner can trigger builds later; do not require CI to get started.
- Nix: Fedora RPMs `nix` and `nix-daemon`, with persistent `/var/nix` bind-mounted
  onto `/nix`, following the Fedora Discussion experience report.
- First installation: stock Kinoite followed by rebase/switch to the custom image.
  A custom installer ISO is a later convenience.
- Initial promotion to desktops is manual after VM validation. Automate rebuilding
  candidates before automating production promotion or desktop rebooting.

## Phase 1: Confirm prerequisites and provision infrastructure

1. Inspect existing VM provisioning, Caddy, backup, logging, and monitoring roles
   before adding permanent infrastructure. For the disposable experiment, use the
   existing AlmaLinux template and direct SSH provisioning without Ansible.
2. Confirm desktop architecture, GPU, Secure Boot requirements, printer model, and
   current OS/update mechanism. These influence validation and any driver additions.
3. Allocate a dedicated builder VM and local container storage. Install Git, Podman,
   Skopeo, signing tooling, and VM testing tools as needed. Use rootful builds where
   required by the base image's package scripts; keep build privileges on this VM.
4. Choose the registry hostname, placement, storage quota, and access method.
   Integrate with existing Caddy only after confirming hostname routing, upload
   limits, and that registry API paths and authentication headers pass correctly.
5. Provide DNS and trusted HTTPS to the builder and desktops. A registry available
   only over Tailscale requires Tailscale access before the first desktop rebase.
   Retain a LAN or recovery access path for diagnosing VPN failures.
6. Configure registry authentication and test push/pull using distinct credentials
   where practical. Store credentials through the existing secrets mechanism.
   Make desktop pull credentials available to the OS updater, not just an
   interactive user's Podman session.

Deliverable: builder can pull Fedora's base, push a test image, and pull it back
through the same HTTPS endpoint desktops will use.

## Phase 2: Create the image repository

Suggested layout, either in a dedicated Git repository or an explicitly scoped
directory here:

```text
kinoite-image/
  Containerfile
  scripts/
    build.sh
    publish.sh
    promote.sh
  repos/
    vscode.repo
  files/
    etc/nix/nix.conf
    usr/lib/systemd/system/nix.mount
    usr/lib/systemd/system/nix-daemon.service.d/mount.conf
    usr/lib/systemd/system/nix-daemon.socket.d/mount.conf
    usr/lib/tmpfiles.d/kinoite-nix.conf
  docs/
    install.md
    recovery.md
    validation.md
```

The final unit and initialization files depend on inspection of Fedora's packages;
do not create overlapping tmpfiles rules without checking the packaged definitions.

| Component | Installation and configuration |
|---|---|
| Tailscale | Prefer Fedora's `tailscale` RPM initially; enable `tailscaled`. Authenticate each machine after boot. |
| Syncthing | Fedora `syncthing`; enable its user service per account. Enable lingering only when syncing without a login is wanted. |
| VS Code | Microsoft's documented signed RPM repository; install `code`. |
| Emacs | Fedora `emacs-pgtk`; check for conflicts with an existing Emacs variant in the base. |
| Printing | Inspect inherited packages first; ensure Avahi and CUPS support. Add printer-specific packages only if needed. |
| Nix | Fedora `nix` and `nix-daemon`, plus the persistent mount integration below. |

Install missing packages during image build, copy defaults and units, clean build
caches, and run the applicable bootc image lint checks. Preserve Fedora's desktop
and kernel configuration. Confirm upstream-base trust rather than assuming the
image's repository location alone establishes authenticity.

Do not bake Tailscale authentication, Syncthing identities, user passwords, SSH
host keys, registry credentials, or private signing keys into the image.

## Phase 3: Integrate and validate Nix

### Storage and startup

Keep the logical store path at `/nix/store` for normal nixpkgs binary-cache use.
The image contains the `/nix` mount point; runtime data lives in `/var/nix`:

```text
/var/nix  -- bind mount -->  /nix
                             store/
                             var/nix/   (database, profiles, GC roots, etc.)
```

1. Inspect the exact Fedora 44 Nix RPM dependencies, sysusers/build-user setup,
   tmpfiles rules, daemon/socket units, shell integration, and SELinux policy.
   Fedora's raw spec and README were not accessible during the initial research;
   obtain these from package sources or an installed test environment.
2. Create `/nix` during the image build. Confirm it survives deployment through the
   selected Kinoite/bootc backend; it must remain an actual directory mount point.
3. Initialize `/var/nix` before its bind mount. Mount it before any packaged Nix
   initialization that writes through `/nix`. Express the ordering through systemd
   dependencies, including the daemon socket; avoid startup sleeps and ordering
   cycles with `local-fs.target` and tmpfiles services.
4. Ensure store permissions and build users match Fedora's package expectations.
   Record UID/GID mappings and verify they remain stable across rebuilds and
   upgrades, including after local user/group changes.
5. Validate labels on both backing storage and mounted paths with SELinux enforcing.
   Add persistent labeling rules or targeted policy only if actual denials require
   them. Keep the daemon units in the RPM-managed image.
6. Enable `nix-command` and `flakes` if not already enabled by Fedora defaults.
   Preserve packaged certificate/cache settings. Do not relocate the logical store
   using the article's `store-path = /var/nix/store` example or symlink `/nix`.

### User environment

- Test ordinary users installing packages through the daemon without root.
- Keep initial VS Code and Emacs installations as RPMs in the image.
- Add Home Manager as an optional user configuration layer after the store works.
  Verify the current `targets.genericLinux` option syntax in the selected revision.
- If later installing GUI apps through Nix, validate GPU integration against the
  actual hardware; choose and test the current generic-Linux GPU module or nixGL.
- Configure store garbage collection only after establishing roots for profiles,
  Home Manager generations, and any system-linked Nix outputs.

The OS rollback does not roll back `/var/nix`. Document this independent lifecycle
and test daemon compatibility with existing store state when rolling back the OS.

## Phase 4: Build, publish, sign, and promote

1. Build manually with a fresh pull of the selected Fedora release base. Record
   its digest, Git revision, architecture, package versions, and build timestamp.
2. Publish an immutable candidate tag such as `44-<date>-<git-sha>` and record the
   pushed digest. A mutable `44-candidate` tag may point at the same image.
3. Sign the published digest. Configure and test the exact client verification
   policy and signature storage format supported by the selected updater and
   registry. Confirm an unsigned or wrongly signed image is rejected.
4. Validate in the test VM. Promote the tested digest to `44-stable`, preserving
   signatures and confirming signature verification through the stable reference.
   Promotion must not rebuild the image.
5. Add a daily systemd build timer with an exclusive lock, bounded logging,
   failure reporting, and explicit success/failure exit status. A failed build or
   validation must leave `44-stable` untouched.
6. Keep Fedora major-version changes explicit in Git. Rebuilding release 44 should
   not silently migrate desktops to the next Fedora release.

Signing establishes publisher identity; it does not replace TLS, base-image trust,
or VM validation. Back up the signing key separately and document rotation.

## Phase 5: Test the complete desktop lifecycle

Use a separate Kinoite VM first, then one physical pilot desktop for hardware checks.

- Rebase/switch from stock Kinoite using the documented mechanism appropriate to
  that installation. Choose either rpm-ostree or bootc as the update workflow and
  document it consistently; do not assume every stock installation uses bootc.
- Preserve a known-good deployment before switching. Record the return-to-stock
  procedure and registry trust bootstrap procedure.
- Verify KDE login, networking, both editors, printing discovery and a real print.
  Check firewall settings on the intended trusted LAN. mDNS discovery should not
  be assumed to traverse Tailscale or routed subnets.
- Authenticate Tailscale and initialize Syncthing separately on each machine.
- Verify `/nix` is a bind mount, persistent backing storage is writable, and a
  normal user can run a cached Nix package and build a small local derivation.
- Reboot; confirm Nix, Tailscale, and Syncthing identities and data persist.
- Publish a second candidate and update the VM. Verify Nix package/profile state,
  local `/etc` configuration, and UID/GID mappings persist.
- Roll back the OS and repeat the checks. Test returning to the newer deployment.
- Test registry outage and invalid-signature behavior: the installed OS remains
  usable and no invalid image becomes the next deployment.
- On the physical pilot, check GPU acceleration, suspend/resume, Secure Boot if
  used, and printer hardware before rolling out to other desktops.

Document successful digests and test results. Desktop automatic staging/rebooting
can be enabled after this workflow has passed.

## Phase 6: Operate and recover

- Monitor build failures, age of the last successful build, registry reachability,
  free space, and pilot update failures using existing homelab tooling.
- Retain the current stable image, previous stable images, and named recovery
  digests. Prune disposable candidates and build caches with explicit retention.
  Ensure registry garbage collection preserves referenced recovery images and
  signatures and follows the registry's concurrency requirements.
- Back up registry configuration, authentication data, image definitions, release
  metadata, and signing material. Decide whether to back up image blobs or retain
  an independent recovery copy; a rebuild may not reproduce historical RPMs.
- Back up user configuration and data independently. Decide whether the Nix store
  itself needs backup; flakes, lock files, profiles, and locally unique outputs
  are more important than easily downloaded cache contents.
- Keep a recovery path that works when the registry or Tailscale is unavailable.
- Generate a custom installer ISO or QCOW2 image later if it simplifies installs
  and test automation; it is not required for registry-delivered updates.

## Implementation deliverables

| Deliverable | Completion criterion |
|---|---|
| Builder provisioning | Repeatable AlmaLinux VM setup and successful local build |
| Registry deployment | Persistent HTTPS endpoint; authenticated push and updater pull |
| Image definition | Requested RPMs, defaults, Nix mount, and stable service identities |
| Build automation | Daily candidates with logs and failure monitoring |
| Signing and promotion | Verified signed updates; stable tag changes only after validation |
| Pilot validation | Install, reboot, update, and rollback checks pass |
| Runbooks | Bootstrap, per-machine setup, promotion, recovery, and retention documented |

## References

- [Fedora experience report: native Nix on bootc](https://discussion.fedoraproject.org/t/my-experience-integrating-nix-into-fedora-bootc/190809)
- [Fedora Nix packaging and documented limitations](https://fedoraproject.org/wiki/Changes/Nix_package_tool)
- [Fedora nix-daemon package](https://packages.fedoraproject.org/pkgs/nix/nix-daemon/)
- [bootc filesystem and arbitrary mount points](https://bootc.dev/bootc/bootc-filesystem.7.html)
- [Nix logical store paths](https://nix.dev/manual/nix/2.34/store/types/local-store.html)
- [Determinate OSTree installer implementation](https://github.com/DeterminateSystems/nix-installer/blob/main/src/planner/ostree.rs)
- [rpm-ostree bootable containers](https://github.com/coreos/rpm-ostree/blob/main/docs/container.md)
- [CNCF Distribution registry deployment](https://distribution.github.io/distribution/about/deploying/)
- [VS Code Linux RPM repository](https://code.visualstudio.com/docs/setup/linux)
- [Image builder source](https://github.com/osbuild/image-builder)

The Fedora discussion reports working deployments; it is evidence for the design,
not a substitute for validating our selected image and package versions. The
Dre Dyson article's snippets should not be used as implementation instructions.
