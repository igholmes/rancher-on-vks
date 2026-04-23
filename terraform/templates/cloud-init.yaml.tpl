#cloud-config

hostname: ${hostname}
fqdn: ${hostname}.${domain}
manage_etc_hosts: true

users:
  - name: ${ssh_user}
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
    lock_passwd: true
    ssh_authorized_keys:
      - ${ssh_public_key}

package_update: true
package_upgrade: true
packages:
  - curl
  - apt-transport-https
  - ca-certificates
  - open-iscsi
  - nfs-common
  - jq
  - gnupg
  - lsb-release

%{ if is_rancher_node ~}
write_files:
  - path: /etc/modules-load.d/kubernetes.conf
    content: |
      overlay
      br_netfilter
      ip_vs
      ip_vs_rr
      ip_vs_wrr
      ip_vs_sh
      nf_conntrack

  - path: /etc/sysctl.d/99-kubernetes.conf
    content: |
      net.bridge.bridge-nf-call-iptables  = 1
      net.bridge.bridge-nf-call-ip6tables = 1
      net.ipv4.ip_forward                 = 1
      net.ipv6.conf.all.forwarding        = 1
      fs.inotify.max_user_watches         = 524288
      fs.inotify.max_user_instances        = 512
%{ endif ~}

runcmd:
  - echo "${hostname}" > /etc/hostname
%{ if is_rancher_node ~}
  # Load kernel modules for Kubernetes/RKE2
  - modprobe overlay
  - modprobe br_netfilter
  - modprobe ip_vs
  - modprobe ip_vs_rr
  - modprobe ip_vs_wrr
  - modprobe ip_vs_sh
  - modprobe nf_conntrack
  - sysctl --system
  # Disable swap
  - swapoff -a
  - sed -i '/\sswap\s/d' /etc/fstab
%{ endif ~}
  # Signal cloud-init completion
  - touch /var/lib/cloud/instance/boot-finished-signal

# Static network configuration
network:
  version: 2
  ethernets:
    ens192:
      dhcp4: false
      addresses:
        - ${ip_address}/${netmask}
      gateway4: ${gateway}
      nameservers:
        addresses:
%{ for dns in dns_servers ~}
          - ${dns}
%{ endfor ~}
        search:
          - ${domain}
