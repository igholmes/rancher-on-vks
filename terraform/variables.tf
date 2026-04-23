# =============================================================================
# vSphere Connection
# =============================================================================

variable "vsphere_server" {
  description = "vSphere/VCF server hostname or IP"
  type        = string
}

variable "vsphere_user" {
  description = "vSphere SSO username (e.g. administrator@vsphere.local)"
  type        = string
}

variable "vsphere_password" {
  description = "vSphere SSO password"
  type        = string
  sensitive   = true
}

variable "vsphere_datacenter" {
  description = "vSphere datacenter name"
  type        = string
}

variable "vsphere_cluster" {
  description = "vSphere cluster name"
  type        = string
}

variable "vsphere_datastore" {
  description = "vSphere datastore name for VM disks"
  type        = string
}

variable "vsphere_network" {
  description = "vSphere port group / network name"
  type        = string
  default     = "vm-network"
}

variable "vsphere_resource_pool" {
  description = "vSphere resource pool path (empty string uses cluster root)"
  type        = string
  default     = ""
}

# =============================================================================
# VM Template
# =============================================================================

variable "vm_template" {
  description = "Name of the VM template to clone (e.g. ubuntu-2404-lts-cloud)"
  type        = string
}

variable "vm_firmware" {
  description = "Firmware type for the VM (bios or efi)"
  type        = string
  default     = "efi"

  validation {
    condition     = contains(["bios", "efi"], var.vm_firmware)
    error_message = "vm_firmware must be 'bios' or 'efi'."
  }
}

# =============================================================================
# VM Specs
# =============================================================================

variable "vm_count" {
  description = "Number of VMs to provision"
  type        = number
  default     = 3
}

variable "vm_name_prefix" {
  description = "Prefix for VM names (e.g. rke2 produces rke2-1, rke2-2, ...)"
  type        = string
  default     = "rke2"
}

variable "vm_cpus" {
  description = "Number of vCPUs per VM"
  type        = number
  default     = 4
}

variable "vm_memory_mb" {
  description = "Memory in MB per VM"
  type        = number
  default     = 8192
}

variable "vm_disk_size_gb" {
  description = "OS disk size in GB per VM"
  type        = number
  default     = 100
}

# =============================================================================
# Networking
# =============================================================================

variable "vm_ips" {
  description = "List of static IPs for each VM (length must match vm_count)"
  type        = list(string)
  default     = ["10.0.1.10", "10.0.1.11", "10.0.1.12"]
}

variable "gateway" {
  description = "Default gateway IP"
  type        = string
}

variable "netmask" {
  description = "Subnet mask in CIDR prefix length (e.g. 24)"
  type        = number
  default     = 24
}

variable "dns_servers" {
  description = "List of DNS server IPs"
  type        = list(string)
  default     = ["8.8.8.8", "8.8.4.4"]
}

variable "domain" {
  description = "DNS search domain"
  type        = string
  default     = "example.com"
}

# =============================================================================
# OS Config
# =============================================================================

variable "ssh_user" {
  description = "Default SSH user created by cloud-init"
  type        = string
  default     = "rancher"
}

variable "ssh_public_key" {
  description = "SSH public key injected into the VM for the ssh_user"
  type        = string
}

variable "vm_hostname_prefix" {
  description = "Hostname prefix (defaults to vm_name_prefix if empty)"
  type        = string
  default     = ""
}

# =============================================================================
# Role Toggle
# =============================================================================

variable "is_rancher_node" {
  description = "When true, cloud-init includes RKE2 kernel prereqs (modules, sysctl, swap disable)"
  type        = bool
  default     = true
}

# =============================================================================
# Ansible Integration
# =============================================================================

variable "enable_ansible_inventory" {
  description = "Generate an Ansible inventory file from Terraform state"
  type        = bool
  default     = true
}

variable "ansible_hardening_playbook_path" {
  description = "Path to Ansible hardening playbook (relative or absolute)"
  type        = string
  default     = ""
}

variable "run_ansible_on_provision" {
  description = "Automatically run the Ansible hardening playbook after VM provisioning"
  type        = bool
  default     = false
}
