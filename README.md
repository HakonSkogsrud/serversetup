# Server setup

Ansible playbooks for homelab. Currently I use Alma linux.

Run files like this
```sh
ansible-playbook -i inventory.yml --ask-vault-pass -K samba-setup.yml
```

## Setup

Playbooks require passwordless ssh to server.

```sh
brew install ansible ansible-lint

ansible-galaxy collection install ansible.posix --force
ansible-galaxy collection install community.general --force
ansible-galaxy collection install community.docker --force
```
## Development

```sh
uv venv
uv pip install -r requirements.txt
pre-commit install
````

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


## VM template

- On proxmox host, download alma cloud image into `/var/lib/vz/template/qcow`

```sh
cd /var/lib/vz/template/qcow
# wget ....
qm create 9000 --name alma-cloud-template --memory 4096 --net0 virtio,bridge=vmbr0
qm importdisk 9000 AlmaLinux-9-GenericCloud-9.5-20241120.x86_64.qcow2 local-lvm
qm set 9000 --scsihw virtio-scsi-pci --scsi0 local-lvm:vm-9000-disk-0
qm set 9000 --ide2 local-lvm:cloudinit
qm set 9000 --boot c --bootdisk scsi0
qm set 9000 --serial0 socket --vga serial0
```
Edit 9000:
- Hardware
    - Memory: Remove ballooning
    - Processors: more cpu and socket, enable Numa, cpu type: Host
    - Hard Disk: enable ssd emulation
    - Add virtiofs with tag and enable xattr for samba share
- Cloud-init:
    - set username and password
    - paste in id_rsa.pub
    - ip config -> static

## Cloning template
For all:
- `Cloud-init`. Make sure dns host is `telenor.net` and dns-server is `148.122.164.253`. Otherwise it might inherit tailscale settings from proxmox.

### Fileserver
- `Hardware` add virtiofs with tag and enable xattr for samba share.
- Set ip to 10.0.0.44/24 with gateway 10.0.0.138

### Immich server
Add virtiofs for immich dataset.
- Set ip to 10.0.0.42/24 with gateway 10.0.0.138


# Backups external harddrives

## wdred
open
```sh
cryptsetup luksOpen $(blkid -o device -t UUID="3e92926f-ec99-4907-a6e4-796f0ae035d2") wdred_encrypted
mount /dev/mapper/wdred_encrypted /mnt/wdred
```

close
```sh
umount /mnt/wdred
cryptsetup luksClose wdred_encrypted
```

backup 

```sh
rsync -aHAX --progress /storage/immich/ /mnt/wdred/immich/ 
```

restore

```sh
rsync -aHAX --progress /mnt/wdred/immich/ /storage/immich/
```