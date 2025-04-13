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

## VM template

- On host, download alma cloud image into /var/lib/vz/template/qcow

```sh
cd /var/lib/vz/template/qcow
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
    - Processors: more cpu and socket, enable Numa,  type: Host
    - Hard Disk: enable ssd emulation
- Cloud-init:
    - set username and password
    - paste in id_rsa.pub
    - ip config -> dhcp


## Proxmox click-ops

- Change repos to non-subscription
- Create a zfs pool on /storage
- Create two datasets, immich and smb
- in Datacenter - Directory Mapping create mapping/tag for both datasets
