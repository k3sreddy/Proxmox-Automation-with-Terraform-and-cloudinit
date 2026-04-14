# 🏔️ Proxmox Infrastructure: Rocky Linux 9 & RKE2 Foundation

> [!IMPORTANT]
> This guide documents the automated deployment of a **13-node High-Availability RKE2 cluster** on Proxmox 8.1.x/9.1.x. It utilizes **Terraform** for infrastructure orchestration and **Cloud-Init** for immediate post-boot configuration.

---

## 📑 Table of Contents
1.  [Cluster Architecture Overview](#-cluster-architecture-overview)
2.  [Technical Stack](#-technical-stack)
3.  [Provisioning Logic (Cloud-Init)](#-provisioning-logic-cloud-init)
4.  [Operational Guide (Terraform)](#-operational-guide-terraform)
5.  [Post-Deployment (Ansible)](#-post-deployment-ansible)
6.  [File Manifest & Project Structure](#-file-manifest--project-structure)

---

## 🏢 Cluster Architecture Overview
The foundation is built using a two-tier architecture, optimizing resources for control plane stability and worker node performance.

### 📐 Node Resource Allocation
| Node Role | Count | CPU (Cores) | RAM (GB) | Storage (NVMe/ZFS) | IP Range | Datastore |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **Control Plane** | 3 | 4 | 4 | 100 GB | `172.16.50.226 - .228` | `RAIDZ-ZFS` |
| **Worker Nodes** | 10 | 8 | 16 | 100 GB | `172.16.50.229 - .238` | `RAIDZ-ZFS` |

---

## 🛠️ Technical Stack
*   **Infrastructure as Code (IaC)**: [Terraform v1.14.8+](https://www.terraform.io/)
*   **Proxmox Provider**: [`bpg/proxmox` (v0.66.0+)](https://registry.terraform.io/providers/bpg/proxmox/latest)
*   **Operating System**: Rocky Linux 9 (GenericCloud-LVM QCOW2)
*   **Automated Provisioning**: Cloud-Init YAML Fragments
*   **Configuration Management**: Ansible-ready inventory generation

---

## 📜 Provisioning Logic (Cloud-Init)
To ensure nodes are "ready-to-join" immediately after boot, the following configurations are injected via Cloud-Init.

### 🛡️ System Hardening
| Feature | Action | Rationale |
| :--- | :--- | :--- |
| **SELinux** | `Disabled` | Required for RKE2 binary compatibility and performance. |
| **Firewalld** | `Disabled` | Managed at the network/ingress level. |
| **Swap** | `Disabled` | Mandatory for Kubelet stability. |

### ⌛ Localization & Performance
*   **Timezone**: `Asia/Kolkata`
*   **Format**: Forced 24-hour clock via `LC_TIME=en_GB.UTF-8`.
*   **Guest Agent**: Pre-installed `qemu-guest-agent` for Proxmox telemetry.
*   **Time Sync**: `chrony` enabled on first-boot.

### 💾 LVM Disk Expansion (Dynamic Resize)
Since standard Cloud-Images often default to 2GB-8GB of used space regardless of disk size, we implement an automated **LVM expansion** in the `runcmd` block:
1.  **Grow Partition**: Resize the GPT/MBR partition.
2.  **Physical Volume**: Expand the PV to fill the partition.
3.  **Logical Volume**: Extend the root LV to 100% of available space.
4.  **Filesystem**: Online resize of the XFS partition.

---

## 🔌 Operational Guide (Terraform)

### 🚀 Initial Cluster Deployment
Provision all 13 nodes (3 CP + 10 Workers) in a single operation:
```bash
terraform init
terraform apply -auto-approve
```

### 📈 Dynamic Scaling
The infrastructure is designed for elastic scaling using Terraform variables. Use these commands to adjust node counts without affecting existing state.

*   **Scale Up/Down Workers**:
    ```bash
    terraform apply -var="worker_node_count=15" -auto-approve
    ```
*   **Remove All Workers** (Maintenance Mode):
    ```bash
    terraform apply -var="worker_node_count=0" -auto-approve
    ```
*   **Targeted Re-deployment**:
    ```bash
    terraform apply -target="proxmox_virtual_environment_vm.rke2_nodes[\"rke2-worker-1\"]"
    ```

---

## 🧪 Post-Deployment (Ansible)
Terraform automatically generates a dynamic `inventory.yml` file upon completion.

### 📡 Connectivity Test
```bash
ansible -i inventory.yml all -m ping
```

### 🛠️ Batch Maintenance (Ad-hoc)
If you need to apply updates or specific fixes across all 13 nodes simultaneously:

```bash
ansible -i inventory.yml all -m shell -a "
  localectl set-locale LC_TIME=en_GB.UTF-8;
  growpart /dev/sda 4;
  pvresize /dev/sda4;
  lvextend -l +100%FREE /dev/mapper/rocky-lvroot;
  xfs_growfs /;
  hostnamectl set-hostname {{ inventory_hostname }}
" --become
```

---

## 📁 File Manifest & Project Structure

| File | Purpose |
| :--- | :--- |
| **[`main.tf`](file:///Users/kreddy/Documents/Proxmox-automation/main.tf)** | Primary resource definitions and Cloud-Init YAML logic. |
| **[`variables.tf`](file:///Users/kreddy/Documents/Proxmox-automation/variables.tf)** | Schema for cluster size, IPs, and hardware specs. |
| **[`providers.tf`](file:///Users/kreddy/Documents/Proxmox-automation/providers.tf)** | Proxmox API authentication and provider constraints. |
| **[`terraform.tfvars`](file:///Users/kreddy/Documents/Proxmox-automation/terraform.tfvars)** | Environment-specific secrets and credential mappings. |
| **[`inventory.yml`](file:///Users/kreddy/Documents/Proxmox-automation/inventory.yml)** | Generated Ansible inventory for configuration management. |

---
> [!TIP]
> **Proxmox Console Access**: While Cloud-Init handles the heavy lifting, you can monitor the boot process and disk expansion via the Proxmox "NoVNC" console for each VM.
