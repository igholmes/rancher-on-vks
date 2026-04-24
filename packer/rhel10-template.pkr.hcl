packer {
  required_version = ">= 1.9.0"

  required_plugins {
    vsphere = {
      source  = "github.com/hashicorp/vsphere"
      version = ">= 1.3.0"
    }
    ansible = {
      source  = "github.com/hashicorp/ansible"
      version = ">= 1.1.1"
    }
  }
}

# =============================================================================
# Locals
# =============================================================================

locals {
  timestamp     = formatdate("YYYYMMDD-hhmmss", timestamp())
  build_vm_name = "${var.build_vm_name_prefix}-${local.timestamp}"

  cloud_init_user_data = templatefile("${path.root}/templates/cloud-init-build.yaml.tpl", {
    hostname       = local.build_vm_name
    ssh_user       = var.ssh_username
    ssh_public_key = var.ssh_public_key
    ip_address     = var.build_ip_address
    netmask_cidr   = var.build_netmask_cidr
    gateway        = var.build_gateway
    dns_servers    = var.build_dns_servers
    search_domain  = var.build_search_domain
  })

  cloud_init_metadata = jsonencode({
    "local-hostname" = local.build_vm_name
    "instance-id"    = local.build_vm_name
  })
}

# =============================================================================
# Source: clone from RHEL10-Gold-Current
# =============================================================================

source "vsphere-clone" "rhel10" {
  # Connection
  vcenter_server      = var.vsphere_server
  username            = var.vsphere_user
  password            = var.vsphere_password
  insecure_connection = var.vsphere_insecure_connection

  # Placement
  datacenter    = var.vsphere_datacenter
  cluster       = var.vsphere_cluster
  datastore     = var.vsphere_datastore
  folder        = var.vsphere_folder
  resource_pool = var.vsphere_resource_pool

  # Source & output
  template             = var.source_template
  vm_name              = local.build_vm_name
  convert_to_template  = true

  # Resources (override template defaults so the build VM is right-sized)
  CPUs      = var.build_vm_cpus
  RAM       = var.build_vm_memory_mb
  firmware  = var.build_vm_firmware

  disk_controller_type = ["pvscsi"]
  storage {
    disk_size             = var.build_vm_disk_size_gb * 1024
    disk_thin_provisioned = true
  }

  network_adapters {
    network      = var.vsphere_network
    network_card = "vmxnet3"
  }

  # Inject build-time static IP via cloud-init guestinfo
  configuration_parameters = {
    "guestinfo.userdata"          = base64encode(local.cloud_init_user_data)
    "guestinfo.userdata.encoding" = "base64"
    "guestinfo.metadata"          = base64encode(local.cloud_init_metadata)
    "guestinfo.metadata.encoding" = "base64"
  }

  # SSH
  communicator         = "ssh"
  ssh_username         = var.ssh_username
  ssh_password         = var.ssh_password
  ssh_private_key_file = var.ssh_private_key_file
  ssh_timeout          = var.ssh_timeout
  ssh_handshake_attempts = 100

  # Graceful shutdown before template conversion
  shutdown_command = "sudo /sbin/shutdown -P now"
  shutdown_timeout = "10m"
}

# =============================================================================
# Build
# =============================================================================

build {
  name    = "rhel10-hardened"
  sources = ["source.vsphere-clone.rhel10"]

  # Wait for cloud-init to finish before Ansible runs
  provisioner "shell" {
    inline = [
      "echo 'Waiting for cloud-init to finish...'",
      "sudo cloud-init status --wait || true",
    ]
  }

  # Ansible: subscription → hardening → security-tools → cleanup
  provisioner "ansible" {
    playbook_file = "${path.root}/ansible/site.yml"
    user          = var.ssh_username
    use_proxy     = false

    extra_arguments = [
      "--extra-vars", "register_to_satellite=${var.register_to_satellite}",
      "--extra-vars", "satellite_server_url=${var.satellite_server_url}",
      "--extra-vars", "satellite_organization=${var.satellite_organization}",
      "--extra-vars", "satellite_activation_key=${var.satellite_activation_key}",
      "--extra-vars", "satellite_ca_url=${var.satellite_ca_url}",
      "--extra-vars", "http_proxy=${var.http_proxy}",
      "--extra-vars", "https_proxy=${var.https_proxy}",
      "--extra-vars", "no_proxy_list=${var.no_proxy}",
      "--extra-vars", "enable_hardening=${var.enable_hardening}",
      "--extra-vars", "enable_security_tools=${var.enable_security_tools}",
      "--extra-vars", "security_agent_package_url=${var.security_agent_package_url}",
      "--extra-vars", "security_agent_token=${var.security_agent_token}",
      "--scp-extra-args", "'-O'",
    ]

    ansible_env_vars = [
      "ANSIBLE_HOST_KEY_CHECKING=False",
      "ANSIBLE_STDOUT_CALLBACK=yaml",
    ]
  }

  # Emit a manifest so downstream tooling can find the build output
  post-processor "manifest" {
    output     = "${path.root}/manifest.json"
    strip_path = true
    custom_data = {
      build_vm_name          = local.build_vm_name
      current_template_name  = var.current_template_name
      previous_template_name = var.previous_template_name
      source_template        = var.source_template
    }
  }

  # Rotate: delete Previous, Current→Previous, build→Current (only on success)
  post-processor "shell-local" {
    only = var.rotate_templates ? ["vsphere-clone.rhel10"] : []

    environment_vars = [
      "GOVC_URL=${var.vsphere_server}",
      "GOVC_USERNAME=${var.vsphere_user}",
      "GOVC_PASSWORD=${var.vsphere_password}",
      "GOVC_INSECURE=${var.vsphere_insecure_connection}",
      "GOVC_DATACENTER=${var.vsphere_datacenter}",
      "BUILD_TEMPLATE_NAME=${local.build_vm_name}",
      "CURRENT_TEMPLATE_NAME=${var.current_template_name}",
      "PREVIOUS_TEMPLATE_NAME=${var.previous_template_name}",
      "TEMPLATE_FOLDER=${var.vsphere_folder}",
      "GOVC_BIN=${var.govc_binary}",
    ]

    scripts = ["${path.root}/scripts/rotate-templates.sh"]
  }
}
