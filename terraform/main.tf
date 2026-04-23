terraform {
  required_version = ">= 1.5.0"

  required_providers {
    vsphere = {
      source  = "vmware/vsphere"
      version = ">= 2.6.0"
    }
  }
}

# =============================================================================
# Provider
# =============================================================================

provider "vsphere" {
  user                 = var.vsphere_user
  password             = var.vsphere_password
  vsphere_server       = var.vsphere_server
  allow_unverified_ssl = true
}

# =============================================================================
# Data Sources
# =============================================================================

data "vsphere_datacenter" "dc" {
  name = var.vsphere_datacenter
}

data "vsphere_compute_cluster" "cluster" {
  name          = var.vsphere_cluster
  datacenter_id = data.vsphere_datacenter.dc.id
}

data "vsphere_datastore" "datastore" {
  name          = var.vsphere_datastore
  datacenter_id = data.vsphere_datacenter.dc.id
}

data "vsphere_network" "network" {
  name          = var.vsphere_network
  datacenter_id = data.vsphere_datacenter.dc.id
}

data "vsphere_virtual_machine" "template" {
  name          = var.vm_template
  datacenter_id = data.vsphere_datacenter.dc.id
}

data "vsphere_resource_pool" "pool" {
  name          = var.vsphere_resource_pool != "" ? var.vsphere_resource_pool : "${var.vsphere_cluster}/Resources"
  datacenter_id = data.vsphere_datacenter.dc.id
}

# =============================================================================
# Tag Category & Tags
# =============================================================================

resource "vsphere_tag_category" "role" {
  name        = "${var.vm_name_prefix}-role"
  description = "Role category for ${var.vm_name_prefix} VMs"
  cardinality = "SINGLE"

  associable_types = ["VirtualMachine"]
}

resource "vsphere_tag" "vm_role" {
  name        = var.is_rancher_node ? "rke2-node" : "standalone"
  description = var.is_rancher_node ? "RKE2/Rancher cluster node" : "Standalone Linux VM"
  category_id = vsphere_tag_category.role.id
}

# =============================================================================
# Cloud-Init
# =============================================================================

locals {
  hostname_prefix = var.vm_hostname_prefix != "" ? var.vm_hostname_prefix : var.vm_name_prefix

  cloud_init_configs = [
    for i in range(var.vm_count) : templatefile("${path.module}/templates/cloud-init.yaml.tpl", {
      hostname        = "${local.hostname_prefix}-${i + 1}"
      ssh_user        = var.ssh_user
      ssh_public_key  = var.ssh_public_key
      ip_address      = var.vm_ips[i]
      gateway         = var.gateway
      netmask         = var.netmask
      dns_servers     = var.dns_servers
      domain          = var.domain
      is_rancher_node = var.is_rancher_node
    })
  ]
}

# =============================================================================
# Virtual Machines
# =============================================================================

resource "vsphere_virtual_machine" "vm" {
  count = var.vm_count

  name             = "${var.vm_name_prefix}-${count.index + 1}"
  resource_pool_id = data.vsphere_resource_pool.pool.id
  datastore_id     = data.vsphere_datastore.datastore.id
  firmware         = var.vm_firmware
  guest_id         = data.vsphere_virtual_machine.template.guest_id
  num_cpus         = var.vm_cpus
  memory           = var.vm_memory_mb
  tags             = [vsphere_tag.vm_role.id]

  network_interface {
    network_id   = data.vsphere_network.network.id
    adapter_type = data.vsphere_virtual_machine.template.network_interface_types[0]
  }

  disk {
    label            = "disk0"
    size             = var.vm_disk_size_gb
    thin_provisioned = data.vsphere_virtual_machine.template.disks[0].thin_provisioned
  }

  clone {
    template_uuid = data.vsphere_virtual_machine.template.id
  }

  # Cloud-init via guestinfo
  extra_config = {
    "guestinfo.userdata"          = base64encode(local.cloud_init_configs[count.index])
    "guestinfo.userdata.encoding" = "base64"
  }

  lifecycle {
    ignore_changes = [
      extra_config, # Prevent drift on cloud-init after first boot
    ]
  }
}

# =============================================================================
# Ansible Integration (optional submodule)
# =============================================================================

module "ansible" {
  source = "./ansible-integration"
  count  = var.enable_ansible_inventory ? 1 : 0

  vm_names        = vsphere_virtual_machine.vm[*].name
  vm_ips          = var.vm_ips
  ssh_user        = var.ssh_user
  is_rancher_node = var.is_rancher_node

  ansible_hardening_playbook_path = var.ansible_hardening_playbook_path
  run_ansible_on_provision        = var.run_ansible_on_provision
}
