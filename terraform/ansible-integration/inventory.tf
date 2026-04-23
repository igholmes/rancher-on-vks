variable "vm_names" {
  description = "List of VM names from parent module"
  type        = list(string)
}

variable "vm_ips" {
  description = "List of VM IPs from parent module"
  type        = list(string)
}

variable "ssh_user" {
  description = "SSH user for Ansible connections"
  type        = string
}

variable "is_rancher_node" {
  description = "Whether VMs are RKE2/Rancher nodes"
  type        = bool
}

variable "ansible_hardening_playbook_path" {
  description = "Path to Ansible hardening playbook"
  type        = string
  default     = ""
}

variable "run_ansible_on_provision" {
  description = "Run Ansible playbook after VM provisioning"
  type        = bool
  default     = false
}

locals {
  inventory_content = templatefile("${path.module}/templates/inventory.ini.tpl", {
    vm_names        = var.vm_names
    vm_ips          = var.vm_ips
    ssh_user        = var.ssh_user
    is_rancher_node = var.is_rancher_node
  })
}

resource "local_file" "ansible_inventory" {
  content  = local.inventory_content
  filename = "${path.module}/generated-inventory.ini"

  file_permission      = "0644"
  directory_permission = "0755"
}

resource "null_resource" "run_ansible" {
  count = var.run_ansible_on_provision && var.ansible_hardening_playbook_path != "" ? 1 : 0

  depends_on = [local_file.ansible_inventory]

  provisioner "local-exec" {
    command = "ansible-playbook -i ${local_file.ansible_inventory.filename} ${var.ansible_hardening_playbook_path}"
  }

  triggers = {
    inventory = local.inventory_content
  }
}

output "inventory_content" {
  description = "Rendered Ansible inventory"
  value       = local.inventory_content
}

output "inventory_file_path" {
  description = "Path to the generated Ansible inventory file"
  value       = local_file.ansible_inventory.filename
}
