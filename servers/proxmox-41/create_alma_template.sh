#! /bin/bash

VMID=9003 # Changed VMID to avoid conflict
STORAGE=local-lvm
# USER=almalinux # Set to the default AlmaLinux cloud user or your desired user
USER=haaksk # Or keep your custom user and ensure cloud-init creates it
VM_PASSWORD=$VM_PASSWORD
ALMA_IMAGE_FILENAME="AlmaLinux-9-GenericCloud-latest.x86_64.qcow2" # Example filename
ALMA_IMAGE_URL="https://repo.almalinux.org/almalinux/9/cloud/x86_64/images/${ALMA_IMAGE_FILENAME}" # Example URL

qm create $VMID --name alma-cloud-template --memory 4096 --net0 virtio,bridge=vmbr0 --agent=1
qm importdisk $VMID AlmaLinux-9-GenericCloud-9.5-20241120.x86_64.qcow2 $STORAGE
qm set $VMID --scsihw virtio-scsi-pci --scsi0 $STORAGE:vm-$VMID-disk-0
qm set $VMID --ide2 $STORAGE:cloudinit
qm set $VMID --boot c --bootdisk scsi0
qm set $VMID --serial0 socket --vga serial0