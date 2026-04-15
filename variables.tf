variable "proxmox_api_url" {
  description = "Proxmox API Endpoint (e.g., https://192.168.1.100:8006/api2/json)"
  type        = string
}

variable "proxmox_api_token" {
  description = "Proxmox API Token (e.g., USER@pve!TOKEN=UUID)"
  type        = string
  sensitive   = true
  default     = null
}

variable "proxmox_username" {
  description = "Proxmox Username (e.g., root@pam)"
  type        = string
  default     = "root@pam"
}

variable "proxmox_password" {
  description = "Proxmox Password"
  type        = string
  sensitive   = true
  default     = null
}

variable "target_node" {
  description = "The Proxmox node to deploy VMs to"
  type        = string
  default     = "pve"
}

variable "gateway" {
  description = "Default gateway for the VMs"
  type        = string
  default     = "172.16.50.254"
}

variable "ssh_public_key" {
  description = "Your SSH public key for Cloud-Init"
  type        = string
}

variable "image_url" {
  default = "https://download.rockylinux.org/pub/rocky/9/images/x86_64/Rocky-9-GenericCloud-LVM.latest.x86_64.qcow2"
}

variable "datastore_id" {
  description = "Datastore where the image and disks will reside"
  type        = string
  default     = "RAIDZ-ZFS"
}

variable "control_plane_count" {
  description = "Number of control plane nodes"
  type        = number
  default     = 3
}

variable "worker_node_count" {
  description = "Number of worker nodes"
  type        = number
  default     = 10
}
