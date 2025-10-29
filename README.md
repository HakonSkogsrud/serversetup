# Ansible playbooks for homelab.

WORK IN PROGRESS 🔨🧱🏗️

![setup](server-architecture.png)

## VMs

| Server       | IP          | User       | Services/ports.              | os  |
|--------------|-------------|------------|------------------------------|-----------|
| Services     | 10.0.0.44   | haaksk     | samba, immich,2283           | Alma 9.5  |
| Proxmox      | 10.0.0.41   | root       | Hypervisor:8006.             | Debian    |

## Setup


Playbooks require passwordless ssh to server. Setup environment.

```sh
uv venv
uv pip install -r requirements.txt
```

Add a file `.vault_pass` with vault password

# Pushover
`send_pushover` function is copied to server along with pushover_user token as environment variable.

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
    zfs create storage/smb
    ```
In Datacenter - Directory Mapping create mapping/tag for both datasets








