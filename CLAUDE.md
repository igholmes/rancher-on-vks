# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Infrastructure-as-Code project for deploying **Rancher** on **RKE2** running on **VMware vSphere Kubernetes Service (VKS)** virtual machines.

- **VKS**: VMware's enterprise Kubernetes platform integrated with vSphere (vCenter/ESX), using the VM Operator API (`vmoperator.vmware.com/v1alpha3`) to manage VMs declaratively
- **RKE2**: Rancher's FIPS-compliant Kubernetes distribution (also called "RKE Government")
- **Rancher**: Multi-cluster Kubernetes management platform providing centralized RBAC, monitoring, and application lifecycle management

## Architecture

The deployment flow is: **VKS VM Operator** provisions a VM → **cloud-init** configures the OS and kernel → **bootstrap script** installs RKE2 + Helm + cert-manager + Rancher.

| File | Purpose |
|---|---|
| `vm-rke2-1.yaml` | VKS `VirtualMachine` CR + `PersistentVolumeClaim` for the RKE2 server node (namespace: `ns-rancher`) |
| `cloud-init-rke2-1.yaml` | Kubernetes `Secret` containing cloud-init user-data (user setup, kernel modules, sysctl, swap disable, RKE2 config) |
| `bootstrap-primary.sh` | Executed by cloud-init `runcmd`; installs RKE2 server, Helm, cert-manager, and Rancher via Helm charts |
| `pre-install-rke2.sh` | Interactive pre-install: configures kube-vip, RKE2 config with TLS SANs, installs k9s, sets up shell environment |
| `import-tkg-cluster.sh` | Imports an existing VKS TKG cluster into Rancher management via the Rancher v3 API |
| `etcd-backup-restore-rke2.sh` | etcd backup/restore/health drill for RKE2 on VCF (`backup`, `restore`, `health` modes) |
| `rancher-rbac-multi-tenant.yaml` | RBAC patterns for multi-tenant K8s: GlobalRoles, ClusterRoleTemplates, per-tenant Roles, NetworkPolicies, ResourceQuotas |
| `ansible-patch-rhel-rancher/` | Ansible playbook for rolling RHEL patching of RKE2 nodes with HA (cordon → drain → patch → reboot → uncordon, one node at a time) |

## Deployment

```bash
# Apply to the VKS supervisor cluster
kubectl apply -f cloud-init-rke2-1.yaml
kubectl apply -f vm-rke2-1.yaml
```

The cloud-init secret must exist before the VM is created (it references the secret by name). The bootstrap script runs automatically on first boot.

## Key Configuration Points

- **VM class/image**: Set in `vm-rke2-1.yaml` (`spec.className`, `spec.imageName`)
- **Storage**: vSAN default policy, 100Gi PVC for RKE2 data
- **SSH access**: Replace the `ssh-rsa CHANGEME` key in `cloud-init-rke2-1.yaml`
- **Rancher hostname**: Set via `RANCHER_HOSTNAME` env var in `bootstrap-primary.sh` (default: `rancher.example.com`)
- **Versions**: `RKE2_VERSION`, `RANCHER_VERSION`, `CERT_MANAGER_VERSION` are configurable env vars at the top of `bootstrap-primary.sh`
- **TLS SANs**: Configured in the RKE2 config embedded in cloud-init
