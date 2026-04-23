output "vm_names" {
  description = "Names of the provisioned VMs"
  value       = vsphere_virtual_machine.vm[*].name
}

output "vm_ips" {
  description = "Static IPs assigned to each VM"
  value       = var.vm_ips
}

output "vm_ids" {
  description = "vSphere managed object IDs for each VM"
  value       = vsphere_virtual_machine.vm[*].id
}

output "ansible_inventory_content" {
  description = "Rendered Ansible inventory content"
  value       = var.enable_ansible_inventory ? module.ansible[0].inventory_content : ""
}

output "ssh_command_examples" {
  description = "Example SSH commands to connect to each VM"
  value = [
    for i in range(var.vm_count) :
    "ssh ${var.ssh_user}@${var.vm_ips[i]}"
  ]
}
