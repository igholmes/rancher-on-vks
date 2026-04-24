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

variable "vsphere_insecure_connection" {
  description = "Skip TLS verification when connecting to vSphere"
  type        = bool
  default     = true
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
  description = "vSphere datastore name for the build VM"
  type        = string
}

variable "vsphere_network" {
  description = "vSphere port group / network name for the build VM"
  type        = string
}

variable "vsphere_folder" {
  description = "VM/template folder path (e.g. 'Templates/Linux'). Empty uses the datacenter root."
  type        = string
  default     = ""
}

variable "vsphere_resource_pool" {
  description = "vSphere resource pool path. Empty uses the cluster root."
  type        = string
  default     = ""
}

# =============================================================================
# Source & Output Templates
# =============================================================================

variable "source_template" {
  description = "Existing gold template to clone for the build"
  type        = string
  default     = "RHEL10-Gold-Current"
}

variable "current_template_name" {
  description = "Final name of the newly hardened template (becomes 'Current' after rotation)"
  type        = string
  default     = "RHEL10-Gold-Current"
}

variable "previous_template_name" {
  description = "Name used for the rotated-out template"
  type        = string
  default     = "RHEL10-Gold-Previous"
}

variable "build_vm_name_prefix" {
  description = "Prefix for the temporary build VM/template name (a timestamp is appended)"
  type        = string
  default     = "rhel10-build"
}

# =============================================================================
# Build VM Specs
# =============================================================================

variable "build_vm_cpus" {
  description = "vCPUs for the build VM"
  type        = number
  default     = 2
}

variable "build_vm_memory_mb" {
  description = "Memory (MB) for the build VM"
  type        = number
  default     = 4096
}

variable "build_vm_disk_size_gb" {
  description = "OS disk size (GB) for the build VM. Must be >= source template disk."
  type        = number
  default     = 60
}

variable "build_vm_firmware" {
  description = "Firmware type: 'bios' or 'efi'"
  type        = string
  default     = "efi"
}

# =============================================================================
# Build-Time Networking (static — no DHCP in this environment)
# =============================================================================

variable "build_ip_address" {
  description = "Static IP assigned to the build VM during the Packer run"
  type        = string
}

variable "build_netmask_cidr" {
  description = "Subnet prefix length (e.g. 24)"
  type        = number
  default     = 24
}

variable "build_gateway" {
  description = "Default gateway for the build VM"
  type        = string
}

variable "build_dns_servers" {
  description = "DNS servers used during the build"
  type        = list(string)
  default     = []
}

variable "build_search_domain" {
  description = "DNS search domain for the build VM"
  type        = string
  default     = ""
}

# =============================================================================
# SSH (used by Packer to connect to the build VM and run Ansible)
# =============================================================================

variable "ssh_username" {
  description = "Username that exists in the gold template with sudo rights"
  type        = string
}

variable "ssh_password" {
  description = "Password for ssh_username (use password OR private key, not both)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "ssh_private_key_file" {
  description = "Path to SSH private key for ssh_username (leave empty to use password)"
  type        = string
  default     = ""
}

variable "ssh_public_key" {
  description = "Public key injected via cloud-init for ssh_username during the build"
  type        = string
  default     = ""
}

variable "ssh_timeout" {
  description = "How long Packer waits for SSH to come up after clone"
  type        = string
  default     = "20m"
}

# =============================================================================
# Red Hat Subscription (Satellite)
# =============================================================================

variable "register_to_satellite" {
  description = "Register the build VM to Satellite during the build (unregister at end)"
  type        = bool
  default     = true
}

variable "satellite_server_url" {
  description = "Satellite server URL (e.g. https://satellite.example.com)"
  type        = string
  default     = ""
}

variable "satellite_organization" {
  description = "Satellite organization label"
  type        = string
  default     = ""
}

variable "satellite_activation_key" {
  description = "Satellite activation key"
  type        = string
  default     = ""
  sensitive   = true
}

variable "satellite_ca_url" {
  description = "URL to the Satellite CA RPM (usually https://<satellite>/pub/katello-ca-consumer-latest.noarch.rpm)"
  type        = string
  default     = ""
}

# =============================================================================
# HTTP Proxy (placeholder — not used until filled in)
# =============================================================================

variable "http_proxy" {
  description = "HTTP proxy URL for dnf (e.g. http://proxy.example.com:3128). Empty disables."
  type        = string
  default     = ""
}

variable "https_proxy" {
  description = "HTTPS proxy URL for dnf. Empty disables."
  type        = string
  default     = ""
}

variable "no_proxy" {
  description = "Comma-separated hosts/domains to bypass the proxy"
  type        = string
  default     = ""
}

# =============================================================================
# Hardening / Security-Tools (placeholders)
# =============================================================================

variable "enable_hardening" {
  description = "Run the hardening role (CIS-style placeholder)"
  type        = bool
  default     = true
}

variable "enable_security_tools" {
  description = "Run the security-tools role (agent install placeholder)"
  type        = bool
  default     = true
}

variable "security_agent_package_url" {
  description = "URL to a security agent RPM (placeholder)"
  type        = string
  default     = ""
}

variable "security_agent_token" {
  description = "Enrollment token for the security agent (placeholder)"
  type        = string
  default     = ""
  sensitive   = true
}

# =============================================================================
# Rotation (post-build)
# =============================================================================

variable "rotate_templates" {
  description = "After a successful build, delete Previous, rename Current→Previous, rename build→Current"
  type        = bool
  default     = true
}

variable "govc_binary" {
  description = "Path to the govc binary used for rotation"
  type        = string
  default     = "govc"
}
