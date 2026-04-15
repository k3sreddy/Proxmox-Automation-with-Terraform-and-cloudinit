locals {
  # Dynamically generate nodes based on variables
  nodes = concat(
    # Control Plane Nodes
    [
      for i in range(var.control_plane_count) : {
        name      = "rke2-cp-${i + 1}"
        role      = "control-plane"
        cpu       = 4
        ram       = 4096
        ip        = "172.16.50.${226 + i}"
        vmid      = 200 + i
        datastore = var.datastore_id
      }
    ],
    # Worker Nodes
    [
      for i in range(var.worker_node_count) : {
        name      = "rke2-worker-${i + 1}"
        role      = "worker"
        cpu       = 8
        ram       = 16384
        ip        = "172.16.50.${226 + var.control_plane_count + i}"
        vmid      = 200 + var.control_plane_count + i
        datastore = var.datastore_id
      }
    ]
  )
}

# 1. Download the Rocky Linux Image (Direct-to-Host Download)
resource "proxmox_virtual_environment_download_file" "rocky_linux_image" {
  content_type = "iso"
  datastore_id = "local"
  node_name    = var.target_node
  url          = var.image_url
  file_name    = "rocky9-cloud.img"

  # Prevents Terraform from overwriting the file if it already exists,
  # but on 'destroy' it may still try to delete it unless targeted.
  overwrite = false

  lifecycle {
    prevent_destroy = true
  }
}

# 2. Define Cloud-Init Configuration (as snippets)
resource "proxmox_virtual_environment_file" "cloud_config" {
  for_each     = { for node in local.nodes : node.name => node }
  content_type = "snippets"
  datastore_id = "local"
  node_name    = var.target_node

  source_raw {
    data      = <<EOF
#cloud-config
hostname: ${each.value.name}
preserve_hostname: false
timezone: Asia/Kolkata
users:
  - name: root
    ssh_authorized_keys:
      - ${var.ssh_public_key}
  - name: rocky
    groups: sudo
    shell: /bin/bash
    sudo: ALL=(ALL) NOPASSWD:ALL
    ssh_authorized_keys:
      - ${var.ssh_public_key}
chpasswd:
  list: |
    root:unroot
    rocky:unroot
  expire: False
  
ssh_pwauth: true

package_update: true
package_upgrade: true
packages:
  - qemu-guest-agent
  - curl
  - chrony
  - wget
  - vim
  - git
  - net-tools
  - cloud-utils-growpart
  - gdisk

runcmd:
  # 0. Allow Root SSH Login
  - sed -i 's/^#PermitRootLogin.*/PermitRootLogin yes/g' /etc/ssh/sshd_config
  - systemctl restart sshd
  # 1. Disable SELinux (Required if not using rke2-selinux package)
  - setenforce 0 || true
  - sed -i 's/^SELINUX=.*/SELINUX=disabled/g' /etc/selinux/config
  # 2. Enable QEMU Guest Agent
  - systemctl enable --now qemu-guest-agent
  # 3. Fix 24-Hour Time (Use en_GB for ISO/24h format)
  - localectl set-locale LC_TIME=en_GB.UTF-8
  - hostnamectl set-hostname ${each.value.name}
  # 4. Load Kernel Modules for RKE2
  - echo -e "overlay\nbr_netfilter" > /etc/modules-load.d/rke2.conf
  - modprobe overlay || true
  - modprobe br_netfilter || true
  # 5. Kernel Tuning (sysctl) - using echo to avoid nested heredoc conflicts
  - echo "net.ipv4.ip_forward = 1" > /etc/sysctl.d/90-rke2.conf
  - echo "net.bridge.bridge-nf-call-iptables = 1" >> /etc/sysctl.d/90-rke2.conf
  - echo "net.bridge.bridge-nf-call-ip6tables = 1" >> /etc/sysctl.d/90-rke2.conf
  - echo "fs.inotify.max_user_watches = 524288" >> /etc/sysctl.d/90-rke2.conf
  - echo "fs.inotify.max_user_instances = 512" >> /etc/sysctl.d/90-rke2.conf
  - sysctl --system
  # 6. Fix NetworkManager (Prevent interference with CNI) - using printf to avoid nested heredoc
  - mkdir -p /etc/NetworkManager/conf.d
  - printf "[keyfile]\nunmanaged-devices=interface-name:flannel*;interface-name:cali*;interface-name:tunl*;interface-name:vxlan.calico\n" > /etc/NetworkManager/conf.d/rke2-canal.conf
  - systemctl reload NetworkManager || true
  # 7. Expand LVM Partition
  - growpart /dev/sda 4 || true
  - pvresize /dev/sda4 || true
  - lvextend -l +100%FREE /dev/mapper/rocky-lvroot || true
  - xfs_growfs / || true
  # 8. Disable firewalld (Conflicts with RKE2)
  - systemctl disable --now firewalld || true
  # 9. Final Reboot to apply all kernel/selinux changes
  - reboot
EOF
    file_name = "cloud-config-${each.value.name}.yaml"
  }
}

# 3. Create the VMs
resource "proxmox_virtual_environment_vm" "rke2_nodes" {
  for_each = { for node in local.nodes : node.name => node }

  name          = each.value.name
  description   = "RKE2 ${each.value.role} Node Managed by Terraform"
  tags          = ["rke2", each.value.role, "rocky9"]
  node_name     = var.target_node
  vm_id         = each.value.vmid
  machine       = "q35"
  on_boot       = true
  scsi_hardware = "virtio-scsi-single"
  hotplug       = "network,disk,cpu,memory"

  operating_system {
    type = "l26"
  }

  cpu {
    cores = each.value.cpu
    type  = "x86-64-v2-AES"
    numa  = true
  }

  memory {
    dedicated = each.value.ram
  }

  agent {
    enabled = true
  }

  network_device {
    bridge = "vmbr0"
  }

  disk {
    datastore_id = each.value.datastore
    file_id      = proxmox_virtual_environment_download_file.rocky_linux_image.id
    interface    = "scsi0"
    size         = 100
    discard      = "on"
    ssd          = true
  }

  initialization {
    datastore_id = each.value.datastore
    ip_config {
      ipv4 {
        address = "${each.value.ip}/24"
        gateway = var.gateway
      }
    }

    user_data_file_id = proxmox_virtual_environment_file.cloud_config[each.key].id
  }
}
