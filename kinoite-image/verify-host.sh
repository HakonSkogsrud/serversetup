#!/usr/bin/env bash
set -euo pipefail

echo 'OS and required host packages'
cat /etc/os-release
rpm -q tailscale syncthing code emacs-pgtk avahi cups git zsh nix nix-daemon

echo 'Nix storage and service state'
findmnt --mountpoint /nix
test "$(stat -c %d:%i /nix)" = "$(stat -c %d:%i /var/nix)"
systemctl is-active nix.mount nix-daemon.service tailscaled.service avahi-daemon.service
systemctl is-active cups.socket
getenforce

echo 'Ordinary-user Nix access'
test "$(id -u)" != 0
nix --version
nix run nixpkgs#hello

echo 'Login shell'
getent passwd "$(id -un)"
