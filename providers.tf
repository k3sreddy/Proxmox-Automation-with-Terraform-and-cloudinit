terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = ">= 0.66.0"
    }
  }
}

provider "proxmox" {
  endpoint = var.proxmox_api_url
  username = var.proxmox_username
  password = var.proxmox_password
  api_token = var.proxmox_api_token
  insecure = true # Since the IP is local (172.16.50.33)
  ssh {
    agent = true
    username = "root"
  }
}
