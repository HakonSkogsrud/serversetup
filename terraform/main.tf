terraform {
  required_providers {
    proxmox = {
      source  = "telmate/proxmox"
      version = "3.0.1-rc6"
    }
  }
}

variable "api_token" {
  description = "API token for Proxmox authentication"
  type        = string
  sensitive   = true
}

provider "proxmox" {
  pm_api_url          = "https://10.0.0.41:8006/api2/json"
  pm_api_token_id     = "root@pam!terraform-automation"
  pm_api_token_secret = var.api_token
  pm_tls_insecure     = true
}

resource "proxmox_vm_qemu" "immich" {
  name        = "immich"
  target_node = "proxmox"
  clone       = "alma-cloud-template"
  full_clone  = true
  vmid        = 4000
  agent      = 1

  network {
    model   = "virtio"
    bridge  = "vmbr0"
    id=0
  }
}
