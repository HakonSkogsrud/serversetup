# Ansible playbooks for homelab.

WORK IN PROGRESS 🔨🧱🏗️

![setup](setup.png)

## VMs

| Server       | IP          | User       | Services/ports  | os  |
|--------------|-------------|------------|-----------------|-----------|
| Services     | 10.0.0.44   | haaksk     | samba           | Alma 9.5  |
| Immich       | 10.0.0.42   | haaksk     | Immich:2283     | Alma 9.5  |
| Proxmox      | 10.0.0.41   | root       | Hypervisor:8006 | Debian    |
| Workmachine2 | 10.0.0.21   | haaksk     |                 |Fedora 42  |

## Setup

Install ansible with extensions on machine you run ansible on.
```sh
brew install ansible ansible-lint

ansible-galaxy collection install ansible.posix --force
ansible-galaxy collection install community.general --force
ansible-galaxy collection install community.docker --force
```

Playbooks require passwordless ssh to server. I configure this automatically in the template I clone.

```sh
uv venv
uv pip install -r requirements.txt
pre-commit install
```

Before commit run

```sh
pre-commit run --all-files
```

Add a file `.vault_pass` with vault password

# Proxmox

## First setup

- Change repos to non-subscription
- Upgrade and update
- Create vm template, see below
- Create zfs datasets, see below
- Something with snippets?
- Install `vim` and `wget`

## IGPU passthrough
Create a resource mapping in datacenter for the igpu. Add as pcie to vm. make sure immou, vt-d etc are enabled in bios on host. 

## ZFS

- Create a zfs pool `storage`
  ```sh
  zpool create storage /dev/sdX
  ```
- Create a dataset `immich` and `smb`
    ```sh
    zfs create storage/immich
    zfs create storage/smb
    ```
In Datacenter - Directory Mapping create mapping/tag for both datasets


#### Immich restore

script for Immich restore
```sh
cd /home/haaksk/immich-app
docker compose down -v
docker compose pull
docker compose create
docker start immich_postgres
sleep 10
sudo gunzip --stdout "$(sudo ls /mnt/storage/immich/library/backups/immich-db-backup-*.sql.gz | sort -V | tail -n 1)" | sed "s/SELECT pg_catalog.set_config('search_path', '', false);/SELECT pg_catalog.set_config('search_path', 'public, pg_catalog', true);/g" | docker exec -i immich_postgres psql --dbname=postgres --username=postgres
docker compose up -d
```

# Backups external harddrives

create encrypted pools like this for ssds
```sh
zpool create \
    -o ashift=12 \
    -o autotrim=on \
    -O encryption=on \
    -O keyformat=passphrase \
    -O keylocation=prompt \
    -O compression=lz4 \
    -O acltype=posixacl \
    -O xattr=sa \
    -O dnodesize=auto \
    -O normalization=formD \
    -O relatime=on \
    -O mountpoint=/wdred \
    wdred /dev/sda1
```

mount external zpool
```sh
zpool import wdred
zfs load-key -r wdred
```

unmount
```sh
zfs unmount -a wdred
zpool export wdred
```

## Restore

List most recent snapshot
```sh
zfs list -t snapshot -o name,creation -s creation | tail -n 2
```

## sanoid

[Managed by `servers/proxmox-41/sanoid-setup.yml`](servers/proxmox-41/sanoid-setup.yml)

# Remote desktop
- install xrdp
- force layout *414 in xrdp.ini

```sh
sudo dnf install xrdp -y
sudo systemctl enable xrdp
sudo systemctl start xrdp
sudo firewall-cmd --permanent --add-port=3389/tcp
sudo firewall-cmd --reload
sudo chcon --type=bin_t /usr/sbin/xrdp
sudo chcon --type=bin_t /usr/sbin/xrdp-sesman
```
