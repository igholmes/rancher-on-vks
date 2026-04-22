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
