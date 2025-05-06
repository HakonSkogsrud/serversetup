#! /bin/bash

VMID=9002
STORAGE=local-lvm
USER=haaksk
VM_PASSWORD=$VM_PASSWORD

set -x
# Check if the image already exists
if [ ! -f noble-server-cloudimg-amd64.img ]; then
    wget -q https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img
else
    echo "Image already exists. Skipping download."
fi
qemu-img resize noble-server-cloudimg-amd64.img 8G
qm destroy $VMID
qm create $VMID --name "ubuntu-noble-template" --memory 4024 --balloon 0 --agent 1 
qm importdisk $VMID noble-server-cloudimg-amd64.img $STORAGE
qm set $VMID --scsihw virtio-scsi-pci --scsi0 $STORAGE:vm-$VMID-disk-0
qm set $VMID --scsi1 $STORAGE:cloudinit
qm set $VMID --boot c --bootdisk scsi0
qm set $VMID --serial0 socket --vga std
qm set $VMID --net0 virtio,bridge=vmbr0

cat << EOF | tee /var/lib/vz/snippets/ubuntu.yaml
#cloud-config

package_update: true
package_upgrade: true
packages:
  - qemu-guest-agent
  - vim 

# --- KEYBOARD CONFIGURATION ---
keyboard:
  layout: "no"
 
runcmd:
    - systemctl enable ssh
EOF

qm set $VMID --cicustom "vendor=local:snippets/ubuntu.yaml"
qm set $VMID --ciuser $USER
qm set $VMID --cipassword $VM_PASSWORD
qm set $VMID --nameserver 148.122.164.253
qm set $VMID --searchdomain telenor.net
qm set $VMID --sshkeys /root/.ssh/authorized_keys
qm set $VMID --ipconfig0 ip=dhcp
qm template $VMID
