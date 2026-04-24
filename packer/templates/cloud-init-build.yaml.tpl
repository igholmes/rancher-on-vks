#cloud-config
# Build-time cloud-init for the Packer VM. Applied ONCE during the build window.
# Final cleanup role wipes cloud-init state so clones re-seed from their own config.

hostname: ${hostname}
fqdn: ${hostname}${search_domain != "" ? ".${search_domain}" : ""}
manage_etc_hosts: true

users:
  - name: ${ssh_user}
    groups: [wheel]
    sudo: "ALL=(ALL) NOPASSWD:ALL"
    shell: /bin/bash
    lock_passwd: false
%{ if ssh_public_key != "" ~}
    ssh_authorized_keys:
      - ${ssh_public_key}
%{ endif ~}

ssh_pwauth: true
disable_root: true

write_files:
  - path: /etc/NetworkManager/system-connections/build-net.nmconnection
    permissions: "0600"
    owner: root:root
    content: |
      [connection]
      id=build-net
      type=ethernet
      autoconnect=true

      [ipv4]
      method=manual
      address1=${ip_address}/${netmask_cidr},${gateway}
%{ if length(dns_servers) > 0 ~}
      dns=${join(";", dns_servers)};
%{ endif ~}
%{ if search_domain != "" ~}
      dns-search=${search_domain};
%{ endif ~}
      may-fail=false

      [ipv6]
      method=disabled

runcmd:
  - nmcli connection reload
  - |
    iface=$(nmcli -t -f DEVICE,TYPE device | awk -F: '$2=="ethernet"{print $1; exit}')
    if [ -n "$iface" ]; then
      nmcli device disconnect "$iface" || true
      nmcli connection up build-net ifname "$iface" || true
    fi
