ARG FEDORA_VERSION=44
FROM quay.io/fedora-ostree-desktops/kinoite:${FEDORA_VERSION}

COPY repos/vscode.repo /etc/yum.repos.d/vscode.repo
RUN rpm --import https://packages.microsoft.com/keys/microsoft.asc && \
    dnf -y install tailscale syncthing code emacs-pgtk avahi avahi-tools \
      cups cups-filters git zsh openssh-clients man-db man-pages util-linux \
      nix nix-daemon && \
    dnf clean all

COPY files/ /
RUN mkdir -p /nix && \
    printf 'd /var/lib/tailscale 0700 root root - -\nd /var/cache/tailscale 0700 root root - -\n' \
      > /usr/lib/tmpfiles.d/kinoite-tailscale.conf && \
    rm -rf /run/dnf /var/cache/libdnf5 /var/lib/dnf/repos && \
    rm -f /var/cache/ldconfig/aux-cache /var/log/dnf5.log && \
    systemctl enable tailscaled.service avahi-daemon.service cups.socket \
      nix.mount nix-daemon.service && \
    bootc container lint

ARG IMAGE_VERSION=44-experiment-2
LABEL org.opencontainers.image.title="Haaksk Kinoite" \
      org.opencontainers.image.version="${IMAGE_VERSION}"
