# Rocky Linux 9 RKE2 Cluster Deployment on Proxmox 9.1.x

This document outlines the deployment of a 13-node high-availability Kubernetes (RKE2) foundation on Rocky Linux 9 using Terraform and the **bpg/proxmox** provider.

## 1. Cluster Architecture
The cluster is divided into two distinct roles with differential resource allocation:

| Role | Nodes | CPUs | RAM | Storage | Static IP Range | Datastore |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **Control Plane** | `rke2-cp-[1-3]` | 4 | 4 GB | 100 GB | `172.16.50.226 - 228` | `RAIDZ-ZFS` |
| **Worker Node** | `rke2-worker-[1-10]` | 8 | 16 GB | 100 GB | `172.16.50.229 - 238` | `RAIDZ-ZFS` |

---

## 2. Technical Stack
*   **Infrastructure as Code**: Terraform v1.14.8+
*   **Provider**: `bpg/proxmox` (v0.66.0+)
*   **Base Image**: Rocky Linux 9 GenericCloud-LVM (QCOW2)
*   **Cloud-Init**: Custom YAML snippets for automated provisioning
*   **Post-Provisioning**: Ansible-ready inventory (`inventory.yml`)

---

## 3. Provisioning Logic (Cloud-Init)
The VMs are customized on first boot via `main.tf` to handle specific environment requirements:

### System Hardening & Settings
*   **SELinux**: Disabled via `sed` and `setenforce 0` to support RKE2 requirements.
*   **QEMU Guest Agent**: Installed and enabled to report IP/Status back to Proxmox.
*   **Time & Locale**: 
    *   Timezone: `Asia/Kolkata`
    *   24-Hour Format: Forced using `localectl set-locale LC_TIME=en_GB.UTF-8`.
*   **Utility Packages**: Installed `vim`, `git`, `wget`, `chrony`, and `net-tools` by default.

### LVM Disk Expansion (The 50GB Fix)
Since the Rocky Linux GenericCloud-LVM image defaults to a smaller partition size, we implemented an automated expansion in the `runcmd` block:
1.  **Grow Partition**: `growpart /dev/sda 4`
2.  **Resize PV**: `pvresize /dev/sda4`
3.  **Extend LV**: `lvextend -l +100%FREE /dev/mapper/rocky-lvroot`
4.  **Resize XFS**: `xfs_growfs /`

---

## 4. Operational Guide

### Initial Deployment
To provision the entire cluster:
```bash
terraform init
terraform apply -auto-approve
```

### Dynamic Scaling (Workers or Control Plane)
You can now scale or destroy specific roles dynamically using variables. This is the **preferred way** to handle role-specific operations:

*   **Destroy ONLY Worker nodes** (while keeping CP):
    ```bash
    terraform apply -var="worker_node_count=0" -auto-approve
    ```
*   **Deploy ONLY Workers** (if they were deleted):
    ```bash
    terraform apply -var="worker_node_count=10" -auto-approve
    ```
*   **Destroy ONLY Control Plane nodes**:
    ```bash
    terraform apply -var="control_plane_count=0" -auto-approve
    ```
*   **Scale to a specific number** (e.g., 5 workers):
    ```bash
    terraform apply -var="worker_node_count=5" -auto-approve
    ```

### Targeted Operations (Standard Terraform)
To work strictly on a single specific node without affecting others:
```bash
terraform apply -target="proxmox_virtual_environment_vm.rke2_nodes[\"rke2-worker-1\"]"
```

### Ansible Readiness
An **`inventory.yml`** file has been generated with all 13 nodes for post-infrastructure configuration.
**Verify connectivity:**
```bash
ansible -i inventory.yml all -m ping
```
Option 1: Fix All 13 VMs at once via Ansible
Since we already have the inventory.yml file ready, you can fix the disk space, 24h time, and hostname for all 13 VMs simultaneously without destroying them.

Run this command from your terminal:

bash
ansible -i inventory.yml all -m shell -a "
  localectl set-locale LC_TIME=en_GB.UTF-8;
  growpart /dev/sda 4;
  pvresize /dev/sda4;
  lvextend -l +100%FREE /dev/mapper/rocky-lvroot;
  xfs_growfs /;
  hostnamectl set-hostname {{ inventory_hostname }}
" --become
Option 2: Individual Fix (Manual)
If you'd like to do it manually on each VM, run these inside the SSH session:

bash
# Set 24h format
sudo localectl set-locale LC_TIME=en_GB.UTF-8
# Grow the disk space
sudo growpart /dev/sda 4
sudo pvresize /dev/sda4
sudo lvextend -l +100%FREE /dev/mapper/rocky-lvroot
sudo xfs_growfs /
# Set the hostname
sudo hostnamectl set-hostname $(curl -s http://169.254.169.254/latest/meta-data/local-hostname || echo rke2-node)

---

## 5. File Manifest
*   **[main.tf](file:///Users/kreddy/Documents/Proxmox-automation/main.tf)**: Resource definitions and Cloud-Init YAML.
*   **[providers.tf](file:///Users/kreddy/Documents/Proxmox-automation/providers.tf)**: Proxmox auth and provider settings.
*   **[variables.tf](file:///Users/kreddy/Documents/Proxmox-automation/variables.tf)**: Environment variables and node specs.
*   **[terraform.tfvars](file:///Users/kreddy/Documents/Proxmox-automation/terraform.tfvars)**: Your specific credentials and environment secrets.
*   **[inventory.yml](file:///Users/kreddy/Documents/Proxmox-automation/inventory.yml)**: Ansible inventory.
