# HA Rancher on VKS: A Reference Architecture for VMware Cloud Foundation

> Deploying a production-grade, highly-available Rancher management cluster on top of
> VMware Cloud Foundation (VCF) using vSphere Kubernetes Service (VKS) VM Service,
> RKE2, and Kube-VIP.

![Status: Reference Architecture](https://img.shields.io/badge/status-reference%20architecture-blue)
![Platform: VCF + VKS](https://img.shields.io/badge/platform-VCF%20%2B%20VKS-success)
![Kubernetes: RKE2](https://img.shields.io/badge/kubernetes-RKE2-orange)

---

## TL;DR

VCF 9 ships with VKS (vSphere Kubernetes Service), which makes it trivial to stand
up workload Kubernetes clusters on top of vSphere. But running **Rancher** as a
multi-cluster management plane is a different problem: Rancher needs its own
dedicated, highly-available Kubernetes cluster, and on-prem environments don't
have a cloud load balancer sitting in front of the API server.

This repo documents a reference pattern I've used to solve that problem:

1. Provision three Linux VMs via **VKS VM Service** (declaratively, through the
   Supervisor Cluster).
2. Install a **3-node HA RKE2 cluster** on those VMs.
3. Use **Kube-VIP** to front the RKE2 API server with a virtual IP — no external
   load balancer required.
4. Install **Rancher** via Helm onto the RKE2 cluster as the multi-cluster
   management plane.

The Kube-VIP + RKE2 bootstrap portion is based on the excellent gist by
[@danieleagle](https://gist.github.com/danieleagle/5138a97ec08145ed52f5188f3a80a9ce)
(forked from [@bgulla](https://gist.github.com/bgulla/7a6a72bdc5df6febb1e22dbc32f0ca4f)).
Credit where it's due — this write-up extends that approach with VKS-native node
provisioning and the downstream Rancher install.

---

## Architecture

```
                       ┌───────────────────────────────────────────┐
                       │              VCF 9 / vSphere              │
                       │                                           │
                       │   ┌─────────────────────────────────────┐ │
                       │   │       VKS Supervisor Cluster        │ │
                       │   │  (VM Service + TKG Service)         │ │
                       │   └──────────────────┬──────────────────┘ │
                       │                      │                    │
                       │          ┌───────────┼───────────┐        │
                       │          │           │           │        │
                       │    ┌─────▼────┐ ┌────▼─────┐ ┌───▼─────┐  │
                       │    │ rke2-1   │ │ rke2-2   │ │ rke2-3  │  │
                       │    │ VM       │ │ VM       │ │ VM      │  │
                       │    │ Ubuntu   │ │ Ubuntu   │ │ Ubuntu  │  │
                       │    └─────┬────┘ └────┬─────┘ └───┬─────┘  │
                       │          │           │           │        │
                       └──────────┼───────────┼───────────┼────────┘
                                  │           │           │
                         ┌────────▼───────────▼───────────▼────────┐
                         │         RKE2 HA control plane           │
                         │  (etcd + kube-apiserver on all 3 nodes) │
                         └────────────────────┬────────────────────┘
                                              │
                                    ┌─────────▼──────────┐
                                    │     Kube-VIP       │
                                    │  VIP: 10.0.1.100   │
                                    └─────────┬──────────┘
                                              │
                                    ┌─────────▼──────────┐
                                    │      Rancher       │
                                    │   (cattle-system)  │
                                    └────────────────────┘
```

**What each component does:**

| Component | Role |
|---|---|
| **VCF 9 / vSphere** | Underlying hypervisor and infrastructure stack |
| **VKS Supervisor** | Provides the VM Service CRDs to declaratively provision VMs |
| **3x Ubuntu VMs** | RKE2 control-plane + etcd nodes |
| **RKE2** | CNCF-conformant Kubernetes distribution, production-ready out of the box |
| **Kube-VIP** | Runs as a static pod on each control-plane node, floats a VIP via leader election |
| **Rancher** | Multi-cluster management plane, installed via Helm |

---

## Why This Pattern?

A few natural questions about this architecture:

### "Why not just run Rancher on a VKS workload cluster?"

You can — Rancher happily runs on any CNCF-conformant cluster, including VKS/TKG.
But in practice, most operators running Rancher as a multi-cluster management
plane want the management cluster to be:

- **Independently upgradeable** from VKS/TKG lifecycle and VCF patch cycles
- **Portable** across vSphere versions and even off vSphere in the future
- **Decoupled** from Supervisor namespace quotas and policies
- **Self-contained** for DR — you can back up the RKE2 etcd snapshot and restore
  on any infrastructure

Running Rancher on RKE2 gives you that separation. The VKS-provisioned VMs give
you declarative provisioning *without* coupling the Rancher control plane to TKG
cluster lifecycle.

### "Why Kube-VIP instead of an external load balancer?"

The classic on-prem HA problem is chicken-and-egg: something has to load-balance
the API server before the cluster exists to schedule workloads. You can't use
MetalLB or an in-cluster NGINX for this, because those need the API server to be
reachable in the first place.

Kube-VIP solves this by running as a **static pod** (scheduled directly by the
kubelet, outside the scheduler's control) and using ARP or BGP to float a VIP
across the control-plane nodes via leader election. No external dependencies.

### "Why RKE2?"

- CIS-hardened by default (relevant if you're in a regulated environment)
- Single-binary install, systemd-managed
- Built-in etcd, embedded registry, SELinux-aware
- Rancher's recommended distro for the management cluster

---

## Prerequisites

Before you start, you need:

### VCF / VKS

- VCF 9.x with Workload Management enabled
- A **Supervisor Namespace** you have edit permissions on
- **VM Service** enabled on that namespace, with:
  - At least one VM Class available (recommend `best-effort-large` or larger — these nodes run etcd + kube-apiserver + Rancher)
  - A VM Image (Ubuntu 22.04 LTS or later) published to a Content Library attached to the namespace
  - A Storage Policy bound to the namespace

### Networking

- A routable subnet the VMs can attach to (e.g., `10.0.1.0/24`)
- **One reserved IP for the VIP** — not in your DHCP pool, not assigned to any VM
- DNS entries (or `/etc/hosts`) for:
  - Each node hostname (`rke2-1`, `rke2-2`, `rke2-3`)
  - The VIP hostname (`rancher.example.lan`)

### Tooling on your workstation

- `kubectl` with context pointed at the Supervisor Namespace
- `helm` 3.x
- `ssh` and `curl`

### Reference values used throughout this guide

| Item | Value |
|---|---|
| Node 1 | `rke2-1` — `10.0.1.11` |
| Node 2 | `rke2-2` — `10.0.1.12` |
| Node 3 | `rke2-3` — `10.0.1.13` |
| VIP | `10.0.1.100` |
| VIP hostname | `rancher.example.lan` |
| Domain | `example.lan` |

> Replace these with your own values. Every command below references these
> placeholders.

---

## Part 1: Provision the VMs via VKS VM Service

VKS exposes the VM Service through Kubernetes CRDs in the Supervisor Namespace.
We'll use three resources:

- `VirtualMachine` — declares the VM itself
- `VirtualMachineImage` — already exists in the namespace (read-only)
- `VirtualMachineClass` — already exists in the namespace (read-only)

### 1.1 — Verify available images and classes

```bash
# Switch to your Supervisor Namespace context
kubectl config use-context your-supervisor-namespace

# See what images are published to this namespace
kubectl get virtualmachineimages

# See what VM classes are bound
kubectl get virtualmachineclassbindings
```

Pick an Ubuntu 22.04 (or later) image name and a class name like
`best-effort-large` for the next step.

### 1.2 — Cloud-init bootstrap

We'll pass a cloud-init user-data document to each VM via a `Secret`. This
handles hostname setup, SSH key injection, and firewall disabling up front.

Save as `cloud-init-rke2-1.yaml`:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: rke2-1-cloud-init
  namespace: your-supervisor-namespace
stringData:
  user-data: |
    #cloud-config
    hostname: rke2-1
    fqdn: rke2-1.example.lan
    manage_etc_hosts: true
    users:
      - name: ubuntu
        sudo: ALL=(ALL) NOPASSWD:ALL
        groups: sudo
        shell: /bin/bash
        ssh_authorized_keys:
          - ssh-ed25519 AAAA...YOUR-KEY-HERE... user@workstation
    write_files:
      - path: /etc/hosts
        append: true
        content: |
          10.0.1.11  rke2-1 rke2-1.example.lan
          10.0.1.12  rke2-2 rke2-2.example.lan
          10.0.1.13  rke2-3 rke2-3.example.lan
          10.0.1.100 rancher.example.lan
    runcmd:
      - systemctl disable --now ufw || true
      - systemctl disable --now firewalld || true
      - swapoff -a
      - sed -i '/ swap / s/^/#/' /etc/fstab
      - modprobe br_netfilter
      - echo 'br_netfilter' > /etc/modules-load.d/br_netfilter.conf
      - echo 'net.ipv4.ip_forward=1' > /etc/sysctl.d/99-k8s.conf
      - sysctl --system
```

Create matching Secrets for `rke2-2` and `rke2-3`, changing only the hostname
and FQDN.

### 1.3 — Declare the VirtualMachine

Save as `vm-rke2-1.yaml`:

```yaml
apiVersion: vmoperator.vmware.com/v1alpha2
kind: VirtualMachine
metadata:
  name: rke2-1
  namespace: your-supervisor-namespace
  labels:
    role: rke2-control-plane
spec:
  imageName: ubuntu-22-04-lts-cloudimg   # substitute with your published image
  className: best-effort-large
  storageClass: vsan-default-storage-policy
  powerState: poweredOn
  networkInterfaces:
    - networkName: workload-network
  bootstrap:
    cloudInit:
      rawCloudConfig:
        name: rke2-1-cloud-init
        key: user-data
```

Repeat for `rke2-2` and `rke2-3`.

### 1.4 — Apply and validate

```bash
kubectl apply -f cloud-init-rke2-1.yaml -f cloud-init-rke2-2.yaml -f cloud-init-rke2-3.yaml
kubectl apply -f vm-rke2-1.yaml -f vm-rke2-2.yaml -f vm-rke2-3.yaml

# Watch VMs come up
kubectl get vm -w

# Grab the assigned IPs (reconcile them with your static assignments)
kubectl get vm -o custom-columns=NAME:.metadata.name,IP:.status.vmIp,POWER:.status.powerState
```

Once all three VMs are `poweredOn` and have reported IPs, SSH to each and
confirm `/etc/hosts` looks right and firewalls are off.

> **Note on IP assignment:** this guide assumes you have static or reserved
> DHCP assignments so the IPs match the table above. In production, use IP
> reservations in your DHCP scope or a vSphere Network Profile with static
> pools. Node IPs must be stable — RKE2 writes them into etcd.

---

## Part 2: Bootstrap RKE2 HA with Kube-VIP

This is the section that most closely follows
[@danieleagle's gist](https://gist.github.com/danieleagle/5138a97ec08145ed52f5188f3a80a9ce).
I've adapted it slightly for Ubuntu 22.04 on VKS and added the VIP hostname
handling that Rancher will need later.

### 2.1 — On `rke2-1` (the first control-plane node)

SSH to `rke2-1` and run:

```bash
# Pick the VIP you reserved earlier
export RKE2_VIP_IP=10.0.1.100
export PRIMARY_IFACE=$(ip -o -4 route show to default | awk '{print $5}')

# Drop the Kube-VIP manifest into RKE2's auto-deploy directory
sudo mkdir -p /var/lib/rancher/rke2/server/manifests/
curl -sL kube-vip.io/k3s \
  | vipAddress=${RKE2_VIP_IP} vipInterface=${PRIMARY_IFACE} sh \
  | sudo tee /var/lib/rancher/rke2/server/manifests/vip.yaml

# The Kube-VIP template targets k3s by default; rewrite it for RKE2
sudo sed -i 's/k3s/rke2/g' /var/lib/rancher/rke2/server/manifests/vip.yaml

# RKE2 config: tell it which hostnames the API cert should cover
sudo mkdir -p /etc/rancher/rke2
sudo tee /etc/rancher/rke2/config.yaml > /dev/null <<EOF
write-kubeconfig-mode: "0644"
tls-san:
  - rke2-1
  - rke2-1.example.lan
  - rke2-2
  - rke2-2.example.lan
  - rke2-3
  - rke2-3.example.lan
  - rancher.example.lan
  - 10.0.1.100
node-taint:
  - "CriticalAddonsOnly=true:NoExecute"
EOF
```

The `node-taint` keeps workloads off control-plane nodes. Later, if you want to
add dedicated worker nodes, provision more VMs and join them as `rke2-agent`.
For a 3-node management cluster hosting just Rancher, you can remove that taint
so Rancher pods schedule on these same nodes — see Part 3.

### 2.2 — Install and start RKE2 on the first node

```bash
curl -sfL https://get.rke2.io | sudo sh -
sudo systemctl enable rke2-server.service
sudo systemctl start rke2-server.service

# Give it ~2 minutes to initialize etcd and come fully up
sudo journalctl -u rke2-server -f
```

Set up `kubectl` on the node:

```bash
echo 'export KUBECONFIG=/etc/rancher/rke2/rke2.yaml' >> ~/.bashrc
echo 'export PATH=$PATH:/var/lib/rancher/rke2/bin' >> ~/.bashrc
source ~/.bashrc

kubectl get nodes -o wide
kubectl get pods -n kube-system | grep kube-vip
```

You should see `rke2-1` `Ready` and a `kube-vip-ds` pod running in
`kube-system`. The VIP `10.0.1.100` should now ARP on the primary interface
(verify with `ip addr show | grep 10.0.1.100` — it may be bound to a node
slightly differently depending on ARP vs BGP mode).

### 2.3 — Retrieve the node token

```bash
sudo cat /var/lib/rancher/rke2/server/node-token
```

Copy the full token string. You'll use it on the other two nodes.

### 2.4 — Join `rke2-2` and `rke2-3`

On each additional control-plane node, run:

```bash
export TOKEN="K10...YOUR-TOKEN-HERE...::server:..."

sudo mkdir -p /etc/rancher/rke2
sudo tee /etc/rancher/rke2/config.yaml > /dev/null <<EOF
token: ${TOKEN}
server: https://rancher.example.lan:9345
write-kubeconfig-mode: "0644"
tls-san:
  - rke2-1
  - rke2-1.example.lan
  - rke2-2
  - rke2-2.example.lan
  - rke2-3
  - rke2-3.example.lan
  - rancher.example.lan
  - 10.0.1.100
node-taint:
  - "CriticalAddonsOnly=true:NoExecute"
EOF

curl -sfL https://get.rke2.io | sudo sh -
sudo systemctl enable rke2-server.service
sudo systemctl start rke2-server.service
```

> **Key detail:** the `server:` URL points to the VIP hostname, not the IP of
> `rke2-1`. This is what makes the cluster tolerate the loss of any single
> control-plane node — including `rke2-1` itself.

After a couple of minutes, back on `rke2-1`:

```bash
kubectl get nodes -o wide
```

All three nodes should be `Ready` with role `control-plane,etcd,master`.

### 2.5 — Validate the VIP

From your workstation (not a node):

```bash
# Pull the kubeconfig from the cluster
scp ubuntu@rke2-1:/etc/rancher/rke2/rke2.yaml ./rke2.yaml

# Rewrite the server URL to use the VIP
sed -i 's|https://127.0.0.1:6443|https://rancher.example.lan:6443|' ./rke2.yaml

export KUBECONFIG=$PWD/rke2.yaml
kubectl get nodes
```

If this works, your API server is being served through the VIP — which is the
entire point of the exercise. Now cordon `rke2-1` and confirm you still get
responses:

```bash
kubectl cordon rke2-1
kubectl get nodes   # should still return
```

---

## Part 3: Install Rancher

With RKE2 up and a stable VIP in front of the API, installing Rancher is the
easy part.

### 3.1 — Install cert-manager

```bash
helm repo add jetstack https://charts.jetstack.io
helm repo update

kubectl create namespace cert-manager
helm install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --version v1.15.3 \
  --set crds.enabled=true

kubectl -n cert-manager rollout status deploy/cert-manager
```

### 3.2 — Install Rancher via Helm

```bash
helm repo add rancher-latest https://releases.rancher.com/server-charts/latest
helm repo update

kubectl create namespace cattle-system

helm install rancher rancher-latest/rancher \
  --namespace cattle-system \
  --set hostname=rancher.example.lan \
  --set bootstrapPassword='changeme-on-first-login' \
  --set replicas=3 \
  --set ingress.tls.source=rancher

kubectl -n cattle-system rollout status deploy/rancher
```

### 3.3 — Untaint the control-plane nodes (optional)

If this cluster exists *only* to run Rancher, you probably want Rancher pods
scheduling on the control-plane nodes rather than adding dedicated workers:

```bash
for node in rke2-1 rke2-2 rke2-3; do
  kubectl taint nodes $node CriticalAddonsOnly=true:NoExecute-
done
```

### 3.4 — Access the Rancher UI

Browse to `https://rancher.example.lan/` and log in with the bootstrap
password. Rancher will prompt you to rotate it on first login.

---

## Part 4: Day-2 Considerations

### Back up etcd

RKE2 takes automatic etcd snapshots. Configure S3 or a shared NFS target in
`/etc/rancher/rke2/config.yaml`:

```yaml
etcd-snapshot-schedule-cron: "0 */6 * * *"
etcd-snapshot-retention: 28
etcd-s3: true
etcd-s3-endpoint: s3.internal.lan
etcd-s3-bucket: rke2-backups
etcd-s3-access-key: ...
etcd-s3-secret-key: ...
```

### Upgrade path

- **VKS / VCF**: upgraded via SDDC Manager on its own cadence, independent of
  this cluster
- **RKE2**: upgrade with the
  [system-upgrade-controller](https://docs.rke2.io/upgrades/automated_upgrade)
  and `Plan` CRDs — or by `systemctl stop rke2-server && curl -sfL https://get.rke2.io | INSTALL_RKE2_VERSION=vX.Y.Z sh - && systemctl start rke2-server` one node at a time
- **Rancher**: standard Helm upgrade against the `rancher-latest` chart

### Adding downstream clusters

This is where the architecture pays off. From the Rancher UI, you can now:

- **Import** VKS/TKG workload clusters (Rancher will register them and take
  over RBAC, monitoring, policy)
- **Provision** net-new downstream RKE2 clusters on additional VMs
- **Provision** clusters in AWS/EKS, Azure/AKS, GCP/GKE from the same UI

The Rancher management plane sits above all of them.

### Observability

- Kube-VIP logs: `kubectl -n kube-system logs ds/kube-vip-ds`
- RKE2 logs: `journalctl -u rke2-server -f` on any node
- Rancher logs: `kubectl -n cattle-system logs deploy/rancher`

### Failure modes to test

Before you call this production-ready, actually exercise the HA:

1. **Single node loss** — `poweroff` one VM. Rancher UI should stay up. VIP
   should float within a few seconds.
2. **Rolling reboot** — reboot one node at a time, waiting for `Ready` between
   each.
3. **Network partition** — drop the management interface on one node. Cluster
   should maintain quorum with the other two.

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| VIP doesn't respond on node 1 | `vipInterface` wrong in `vip.yaml` | Edit manifest, restart `rke2-server` |
| Nodes 2/3 can't join | Firewall or `tls-san` missing VIP hostname | Disable ufw/firewalld; add VIP hostname to `tls-san` on node 1, restart, re-issue cert |
| `kubectl get nodes` hangs from workstation | DNS doesn't resolve VIP hostname | Add hostname to local `/etc/hosts` or site DNS |
| Rancher pods `CrashLoopBackOff` | cert-manager not ready | `kubectl -n cert-manager get pods`; wait for all 3 to be `Running` |
| `kube-vip` pod crash on node restart | Stale leader election | `kubectl -n kube-system rollout restart ds/kube-vip-ds` |

---

## References

- **Kube-VIP + RKE2 bootstrap pattern** —
  [@danieleagle's gist](https://gist.github.com/danieleagle/5138a97ec08145ed52f5188f3a80a9ce)
  (forked from [@bgulla](https://gist.github.com/bgulla/7a6a72bdc5df6febb1e22dbc32f0ca4f)) —
  the original basis for Part 2 of this guide
- [Kube-VIP documentation](https://kube-vip.io/)
- [Kube-VIP Control Plane mode](https://kube-vip.io/docs/usage/k3s/)
- [RKE2 documentation](https://docs.rke2.io/)
- [Rancher Helm chart](https://github.com/rancher/rancher/tree/main/chart)
- [VKS / VCF VM Service](https://techdocs.broadcom.com/us/en/vmware-cis/vcf.html)
- [VM Operator CRD reference](https://github.com/vmware-tanzu/vm-operator)

---

## License

This guide is released under the MIT License. Use it, fork it, improve it.

## Feedback

PRs and issues welcome. If you've run this in your own environment and hit
something I didn't document, open an issue — the troubleshooting table needs
more entries.
