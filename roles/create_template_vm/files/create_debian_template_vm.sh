#! /bin/bash

VMID=9001
STORAGE=local-lvm
USER=haaksk # Or keep your custom user and ensure cloud-init creates it
VM_PASSWORD=$VM_PASSWORD
URL=https://cdimage.debian.org/images/cloud/trixie/daily/latest/debian-13-generic-amd64-daily.qcow2
FILE=debian-13-generic-amd64-daily.qcow2
IMAGE_NAME=debian-trixie-cloud-image

set -x

qm destroy $VMID

# create a variable from the alma image below
if [ ! -f $FILE ]; then
    wget $URL
fi

qm create $VMID --name $IMAGE_NAME --memory 4096 --net0 virtio,bridge=vmbr0 --agent 1
qm importdisk $VMID $FILE $STORAGE -format qcow2

qm set $VMID --scsihw virtio-scsi-single
qm set $VMID --scsi0 $STORAGE:vm-$VMID-disk-0,discard=on,iothread=1,ssd=1,cache=none
qm set $VMID --ide2 $STORAGE:cloudinit
qm set $VMID --boot c --bootdisk scsi0
qm set $VMID --serial0 socket
qm set $VMID --cpu host
qm set $VMID --numa 1
qm set $VMID --ciuser $USER
qm set $VMID --cipassword "$VM_PASSWORD"
qm set $VMID --nameserver 148.122.164.253
qm set $VMID --searchdomain telenor.net
qm set $VMID --sshkeys /root/.ssh/authorized_keys # This will be applied to the ciuser
qm set $VMID --ipconfig0 ip=dhcp
qm set $VMID --keyboard no
qm template $VMID
