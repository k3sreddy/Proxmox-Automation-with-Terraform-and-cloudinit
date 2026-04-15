output "vm_info" {
  value = {
    for vm in proxmox_virtual_environment_vm.rke2_nodes :
    vm.name => {
      ip   = vm.initialization[0].ip_config[0].ipv4[0].address
      role = contains(vm.tags, "control-plane") ? "Control Plane" : "Worker"
      specs = "${vm.cpu[0].cores} vCPU, ${vm.memory[0].dedicated / 1024} GB RAM"
    }
  }
}
