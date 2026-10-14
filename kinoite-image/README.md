# Kinoite image experiment

Canonical image source is now [HakonSkogsrud/kionite](https://github.com/HakonSkogsrud/kionite).
The builder checks it out at `~/kionite`. This local directory is retained as the
prototype snapshot; make image changes in the GitHub repository going forward.

## Current setup

- Builder: `haaksk@10.0.0.139`, AlmaLinux 10.2, x86_64, 100 GiB disk,
  4 GiB RAM, and 4 GiB temporary swap.
- Test desktop: `haaksk@10.0.0.59`, now running the custom Fedora 44 Kinoite image.
- Registry: `10.0.0.139:5000`, unauthenticated HTTP on the trusted LAN.
- Update reference: `10.0.0.139:5000/my-kinoite:44-candidate`.
- Image definition and shell environment: this directory; remote copies are at
  `~/kinoite-image` on the builder and `~/kinoite-shell` on the test desktop.

The registry uses the Podman container `kinoite-registry`, persistent data at
`/var/lib/kinoite-registry`, and `podman-restart.service` for restart after reboot.
Temporary swap at `/var/swap-kinoite` is not configured in fstab.
Permanent hosting still needs HTTPS, authentication, signing, and scheduled builds.

Implementation plan: [custom-kinoite-homelab.md](../plans/custom-kinoite-homelab.md).

## Image and shell packages

The image contains Tailscale, Syncthing, Microsoft VS Code, Emacs PGTK, Avahi,
CUPS, Git, Zsh, OpenSSH client, man-page utilities, and Fedora's Nix packages.
Nix sees `/nix/store`; persistent `/var/nix` is bind-mounted onto `/nix` before
package tmpfiles initialization and daemon startup. SELinux remains enforcing.

Home Manager supplies eza, ripgrep, zoxide, fzf, fd, bat, lazygit, Neovim, uv,
tmux, direnv/nix-direnv, zsh-autosuggestions, and JetBrains Mono Nerd Font.
It manages `.zshrc`, `.tmux.conf`, and the lazygit configuration. The login shell
is `/usr/bin/zsh`, provided by the host image. Syncthing's user service is enabled;
lingering was not enabled. Tailscale is running but requires user authentication:

```sh
sudo tailscale up
```

The shell configuration comes from
<https://github.com/HakonSkogsrud/nixos>, revision
`a13621f39485c3ea95a11846e3543bdc6bfa16b3`, with a builtin-cd fallback,
Nix plugin-path substitution, Home Manager session variables, and a direnv hook.
It uses the real Fedora home path `/var/home/haaksk` and `/usr/bin/zsh` in tmux.
Nix GPU integration is disabled because the Nix environment currently contains
CLI tools; the editors are host RPMs. Inputs are pinned in `home/flake.lock`.

## Validated on 2026-10-13

- Built the Kinoite image on AlmaLinux and published it to the homelab registry.
- Bootc lint: 14 checks passed, 1 skipped, no warnings after runtime/cache cleanup.
- Switched the disposable Silverblue VM to Kinoite without local package layers.
- Verified the requested host RPMs, Nix bind mount, daemon, and service startup.
- Ran a cached Nix package and a local sandboxed derivation as ordinary user
  `haaksk`, with SELinux enforcing.
- Built and activated Home Manager; verified shell tools, aliases, autosuggestion
  binding, and Zoxide navigation.
- CUPS is running and discovered `Brother_HL_L2445DW`; no print job was sent.
- Updated through `bootc upgrade` to a second image digest, rebooted, rolled back
  to the first revision, and returned to the second revision.
- The Nix store/result, Home Manager profile, and nixbld group survived the update
  and rollback. No failed system services remained during those checks.

The second revision changes image version metadata, not RPM contents. This tests
registry update/staging and deployment rollback, but not Nix daemon upgrades
across versions. Physical desktop graphics, suspend, and actual printing still
need user testing. The graphical login unit is `plasmalogin.service` on this base,
not `sddm.service`.

| Revision | Registry digest |
|---|---|
| `44-first-boot` | `sha256:ef7d5755ce43d3f99988119d09c42208660322ca6f502818f73433a7249a9554` |
| `44-experiment-2` | `sha256:cef8e4b2abe00dd6c966215cac67c7de3d8980217196e1626a9902fc77cd586d` |

## Building and publishing

On the builder, from `~/kinoite-image`:

```sh
bash build.sh
PUBLISH=1 bash build.sh
```

The script pulls the latest Fedora 44 base and disables build cache so third-party
RPM updates are picked up even when the base digest is unchanged. It records image
metadata and uses a timestamped version label by default. Override `IMAGE_REF` and
`IMAGE_VERSION` as needed. Build logs and generated metadata are excluded from Git.
The first build can take several minutes: this builder's kernel causes Podman to
use a slower overlay filesystem diff mode.

Do not overwrite a release tag intended for recovery. A permanent workflow should
publish immutable candidates, validate them, then promote a stable reference.
The current candidate workflow is manual and unsigned.

## Updating, rolling back, and checking the desktop

```sh
sudo bootc status
sudo bootc upgrade
sudo systemctl reboot
```

For a rollback, inspect the target first, then:

```sh
sudo bootc rollback
sudo systemctl reboot
```

The original Silverblue deployment remains pinned. Deployment indexes change;
inspect `sudo ostree admin status` before selecting a pinned deployment. Its old
image lacks Nix and Zsh, so the personalized shell environment is only validated
on the custom Kinoite revisions.

Use `bash verify-host.sh` as an ordinary user for the basic runtime checks.
Nix state under `/var/nix` is shared: an OS rollback does not roll back Nix packages,
profiles, or the database. Back up user configuration separately.

To update the shell environment on the desktop:

```sh
cd ~/kinoite-shell
nix run .#homeConfigurations.haaksk.activationPackage
```

Inspect existing dotfile conflicts and back up files before activation on another
machine. No existing managed dotfiles were present on this disposable VM.

## Migration fix and saved state

Silverblue's old root fstab entry caused `systemd-remount-fs.service` to fail with
`overlay: No changes allowed in reconfigure` after switching to composefs Kinoite.
The root filesystem is already mounted by the initramfs using kernel root flags.
After checking those flags, the obsolete `/` fstab entry was commented out on
this VM, preserving the `/boot`, `/home`, and `/var` entries. The remount service
then succeeded. See [upstream bootc issue 971](https://github.com/bootc-dev/bootc/issues/971).
This is a per-machine migration fix, not a generic fstab replacement in the image.

Desktop evidence and backups are in `~/kinoite-experiment-backup`, including the
original deployment metadata, original fstab, activation logs, and sandbox result.
The registry's precise HTTP exception is in
`/etc/containers/registries.conf.d/90-kinoite-experiment.conf`.

The initial detached build/publish job ran as `kinoite-build-publish.service` on
the builder and completed successfully. Its journal remains available:

```sh
sudo journalctl -u kinoite-build-publish.service --no-pager
```

## Nix integration references

- [Fedora native Nix on bootc experience](https://discussion.fedoraproject.org/t/my-experience-integrating-nix-into-fedora-bootc/190809)
- [Reference implementation](https://github.com/fu5ha/winter), revision
  `0daf5c285eab9a09b2389ec3c71acd307e050e98`.

Fedora's actual Nix tmpfiles, daemon/socket, profile, and sysusers definitions were
inspected from the installed RPM layer. Additional tmpfiles rules recreate the
store directories hidden by the bind mount. Build-user UID/GID stability must be
rechecked when changing the base or package set.
