%{ if is_rancher_node ~}
[rke2_servers]
%{ for i, name in vm_names ~}
${name} ansible_host=${vm_ips[i]}
%{ endfor ~}

[rke2_agents]

[rke2_cluster:children]
rke2_servers
rke2_agents

[rke2_cluster:vars]
ansible_user=${ssh_user}
ansible_become=true
ansible_become_method=sudo
rke2_service_server=rke2-server
rke2_service_agent=rke2-agent
kubeconfig_path=/etc/rancher/rke2/rke2.yaml
kubectl_bin=/var/lib/rancher/rke2/bin/kubectl
%{ else ~}
[servers]
%{ for i, name in vm_names ~}
${name} ansible_host=${vm_ips[i]}
%{ endfor ~}

[servers:vars]
ansible_user=${ssh_user}
ansible_become=true
ansible_become_method=sudo
%{ endif ~}
