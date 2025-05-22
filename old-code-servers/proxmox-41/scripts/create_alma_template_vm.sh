#! /bin/bash

VMID=9003 
STORAGE=local-lvm
USER=haaksk # Or keep your custom user and ensure cloud-init creates it
VM_PASSWORD=$VM_PASSWORD
URL=https://repo.almalinux.org/almalinux/9/cloud/x86_64/images/AlmaLinux-9-GenericCloud-9.5-20241120.x86_64.qcow2
FILE=AlmaLinux-9-GenericCloud-9.5-20241120.x86_64.qcow2
IMAGE_NAME=alma-cloud-template-automated

set -x

qm destroy $VMID

# create a variable from the alma image below
if [ ! -f AlmaLinux-9-GenericCloud-9.5-20241120.x86_64.qcow2 ]; then
    wget https://repo.almalinux.org/almalinux/9/cloud/x86_64/images/AlmaLinux-9-GenericCloud-9.5-20241120.x86_64.qcow2
fi

qm create $VMID --name $IMAGE_NAME --memory 4096 --net0 virtio,bridge=vmbr0 --agent 1
qm importdisk $VMID $FILE $STORAGE -format qcow2

qm set $VMID --scsihw virtio-scsi-single
qm set $VMID --scsi0 $STORAGE:vm-$VMID-disk-0,discard=on,iothread=1,ssd=1,cache=none
qm set $VMID --ide2 $STORAGE:cloudinit
qm set $VMID --boot c --bootdisk scsi0
qm set $VMID --serial0 socket --vga serial0
qm set $VMID --cpu host
qm set $VMID --numa 1
qm set $VMID --ciuser $USER 
qm set $VMID --cipassword "$VM_PASSWORD" 
qm set $VMID --nameserver 148.122.164.253
qm set $VMID --searchdomain telenor.net
qm set $VMID --sshkeys /root/.ssh/authorized_keys # This will be applied to the ciuser
qm set $VMID --ipconfig0 ip=dhcp
qm template $VMID