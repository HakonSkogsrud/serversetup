# Proxmox setup notes

## after installation
- remove subscription repositories and add no-subsciption. Upgrade system
- add zfs pool, see below
- download iso vm image for alma linux

## zfs
- create a zfs pool `storage`.
- create datasets `immich` and `smb`
- on Datacenter, create mapping /storage/smb with tag `smb`
- show locations of dataset with `zfs list`

## creating vms
- add hardware virtiofs with tag `smb` to make dataset available
